# Log de decisiones

Log append-only. Cada entrada: fecha, decisión, motivo. No se reescribe el
pasado — si una decisión cambia, se agrega una entrada nueva que referencia
a la vieja.

## 2026-10-25 — Target macOS corregido de 26 a 27

`xcodebuild -version` en la máquina de desarrollo muestra Xcode 27.1, SDK
macOS 27.0 (`xcrun --sdk macosx --show-sdk-version` → 27.0). La intención
original del usuario era "solo la última versión, sin back-compat", no el
número 26 literal. Se fija el deployment target en macOS 27+.

## 2026-10-25 — Proyecto como Swift Package, no `.xcodeproj`

En vez de generar un `.xcodeproj` a mano (no hay forma oficial de hacerlo
por CLI sin plantillas de terceros), el proyecto es un `Package.swift` con
un `executableTarget` usando el lifecycle de App de SwiftUI
(`@main struct ... : App`). Xcode abre `Package.swift` directamente y
corre/debuggea el ejecutable como una app de ventana real — no hace falta
`.xcodeproj` para esto.

Verificado empíricamente antes de comprometerse: con
`// swift-tools-version: 6.4` y `platforms: [.macOS(.v27)]`, un target
ejecutable con `import SwiftUI` y `WindowGroup { NavigationSplitView {...} }`
compila (`swift build`) y al correrlo (`swift run`) queda un proceso vivo
con su run loop (no crashea ni termina solo) — confirma que el enfoque
funciona en este toolchain antes de construir el resto de la app sobre él.

`SupportedPlatform.MacOSVersion.v27` requiere
`swift-tools-version: 6.4` o superior (no existe en 6.0).

## 2026-10-25 — Sin sandbox, sin firma por ahora

Confirmado con el usuario: la app corre solo en esta Mac desde Xcode. No
hay entitlements de sandbox ni pipeline de notarización en este slice.

## 2026-10-25 — Slice 1: hallazgos de la revisión final de rama

Revisión final (subagente fresco, Opus) sobre el rango completo del
slice 1. Dos hallazgos "Important" se arreglaron en el momento (ver
commit `fix: symlinks a carpetas se pueden abrir, sidebar siempre
renavega`). El resto queda acá como decisión diferida, no como bug
pendiente sin dueño:

- **Breadcrumb no es editable (sin campo de texto).** El objetivo del
  spec dice "breadcrumb editable" pero la Task 5 del plan solo
  especificó botones por componente de ruta, que es lo que se construyó.
  Se difiere un campo de texto tipeable a un slice posterior (candidato:
  slice 2, junto con el resto de pulido de navegación) en vez de
  agregarlo fuera de plan en este fix pass.
- **La lista de volúmenes en Places es una foto fija al abrir la app**
  (no escucha montar/desmontar). Es exactamente lo que pedía la Task 3
  del plan. Vive mejor en el slice 11 ("soporte más profundo de
  volúmenes externos"), que ya es donde el roadmap preveía esto.
- **Hidden files = prefijo `.` únicamente**, no respeta la BSD hidden
  flag de macOS (por eso `~/Library` y `/usr` se ven). Es el
  comportamiento de Dolphin/Linux a propósito, tal como lo fijó el plan.
  Queda explícito acá para que no se lea como un bug no documentado.
- **Symlinks no se siguen para listar contenido inline** (sí se pueden
  abrir desde slice 1 ya arreglado arriba). Evita el riesgo de loop con
  un symlink circular.
- **Patrón de la sidebar:** un `Button` por fila en vez de
  `List(selection:)`, para que cada click llame `onSelect` sin depender
  de que el valor de selección haya cambiado. El resaltado se deriva
  comparando `place.url == currentURL`, no de estado propio.
- **Gap de verificación manual:** el click-through real (clicks,
  doble-click, breadcrumb, vista de permiso denegado) no lo verificó el
  implementador — no hay herramienta de automatización de UI para una
  ventana nativa de macOS en este entorno. Queda para que el usuario lo
  pruebe a mano.

Diferidos sin acción (quedan en el reporte de revisión, no se repiten
acá en detalle): mensaje de "sin acceso" no distingue TCC/EPERM de un
EACCES de permisos Unix comunes; doble-click solo hit-testea el
ícono+texto de la fila, no la fila completa, y no hay selección de fila
ni abrir con Return; no hay botón de refresh/subir en la UI; la lectura
de directorio es síncrona en el main actor (puede trabar la ventana con
una carpeta enorme o una red lenta — aceptable para este slice, revisar
si se vuelve perceptible); un ítem individual que falle al leer sus
resourceValues puede tirar toda la lectura de la carpeta en vez de
saltear solo ese ítem.

## 2026-10-26 — Slice 2: hallazgos de la revisión final de rama

Revisión final (Opus, fresh context) sobre vistas/zoom/orden/view
properties. Dos "Important" arreglados en el momento (comparador de
orden con empates no determinísticos + descendente roto; overlap en la
grilla de iconos en cualquier zoom, no solo en los extremos). El resto
queda diferido, sin acción en este slice:

- El menú de orden no muestra visualmente cuál es el campo/dirección
  activa (sin checkmark). Candidato: reemplazar por `Picker` + `Toggle`
  dentro del `Menu`.
- El slider de zoom persiste en cada tick de arrastre (un JSON
  encode + write por tick) en vez de solo al soltar.
- `DetailsListView` (modo detalles) tiene la misma limitación de
  doble-click que el modo lista del slice 1 (solo ícono+texto, sin
  selección de fila ni Return). Tampoco tiene click-en-columna para
  ordenar (`Table` lo soporta nativo vía `sortOrder`, no se usó para no
  duplicar el control de orden — ver decisión del slice 2 sobre el Menu).
- El texto de la celda en modo iconos no escala con el zoom (ilegible en
  el extremo bajo, chico bajo un ícono grande en el extremo alto).
- Las claves de `ViewPropertiesStore` usan `url.path` crudo — `/tmp/x` y
  `/private/tmp/x` (o la misma carpeta vista por symlink) cuentan como
  carpetas distintas. Candidato: normalizar con
  `.resolvingSymlinksInPath().standardizedFileURL` antes de armar la key.
- `zoomLevel` leído de `UserDefaults` no se clampea a 0.5...2.0 — solo
  alcanzable con un valor corrupto editado a mano, no desde la UI.
- Varios tests de `BrowserViewModelTests` usan `UserDefaults.standard` o
  suites de `UserDefaults(suiteName:)` que nunca se limpian — dejan
  entradas sueltas en las preferencias reales de quien corre los tests.
  Candidato: inyectar siempre una suite descartable y limpiarla en
  `tearDown`, como ya hace `ViewPropertiesStoreTests`.

## 2026-10-26 — Slice 3: hallazgos de la revisión final de rama

Revisión final (Opus, fresh context) sobre pestañas/split view. Dos
"Important" arreglados en el momento (foco de panel que casi nunca se
activaba por perder contra los gestos hijos; estado de vista filtrándose
entre pestañas por falta de `.id`). El resto queda diferido:

- **Elección de pestaña al cerrar la seleccionada:** el código selecciona
  la vecina de la derecha (la que cae en el mismo índice tras remover),
  no la de la izquierda como describía el plan literalmente. Ambos
  comportamientos son razonables (Dolphin también usa la derecha) — se
  deja así, el plan queda corregido de hecho por esta decisión.
- `setFocusedPane` acepta cualquier entero una vez que el tab está en
  split (no valida que sea 0 o 1) — solo alcanzable con una llamada mal
  formada desde código nuevo, no desde la UI actual.
- El botón "+" abre la pestaña nueva en la carpeta del panel primario,
  no del panel enfocado — coincide con lo que pedía el plan
  literalmente, aunque Dolphin usa el panel activo. Queda así por ahora.
- Activar split no mueve el foco al panel nuevo (se queda en el
  primario).
- Las pestañas no seleccionadas solo reciben el click sobre su texto
  (fondo transparente no es "clickeable" visualmente), y no hay
  `ScrollView` si hay muchas pestañas.
- Los paneles de split no tienen `minWidth` — se pueden arrastrar a
  ancho cero.
- Sin tooltips/accesibilidad en los botones de ícono (cerrar, nueva
  pestaña, split).

## 2026-10-26 — Slice 4: hallazgos de la revisión final de rama

Revisión final (Opus, fresh context) sobre selección + panel de
información. Dos "Important" arreglados en el momento (el inspector
seguía a un panel fijo en vez del enfocado, y perdía su estado
abierto/cerrado al splitear o cambiar de tab — ambos se resolvían
subiendo el estado de `BrowserView` a `ContentView`).

- **Ruling: selección por gesto custom en vez de `List`/`Table`
  `selection:` nativo.** El revisor recomendó migrar a selección nativa
  (`List(items, selection:)`/`Table(items, selection:)` +
  `contextMenu(forSelectionType:primaryAction:)`) ya en este slice,
  porque es la base correcta para el menú contextual del slice 6 y
  resuelve de una vez el retraso del tap exclusivo y el área de click
  angosta (ya logueada en slices 1-3). No se hizo en este fix pass:
  es un cambio de forma, no un bug puntual, y tocar las 3 vistas de
  listado ahora + rehacer el plan ya escrito del slice 6 alrededor de
  esto es más alcance del que un fix pass de revisión debería asumir.
  Queda como candidato fuerte para hacerse *como parte* del slice 6
  (menú contextual), no después. Costo si sigue así: la selección
  tarda ~el intervalo de doble-click del sistema en reaccionar, y en
  modo lista/detalles solo el ícono+texto de la fila es clickeable (el
  resaltado es de fila completa, así que lo que se ve no coincide con
  lo que se puede clickear).
- Doble-click sobre un archivo (no carpeta) no selecciona nada — el
  `exclusively` suprime el select en favor de un `onOpen` que es no-op
  para archivos. Queda sin arreglar hasta la migración a selección
  nativa de arriba.
- No hay forma de deseleccionar clickeando un espacio vacío (lo nativo
  lo da gratis).
- `FileMetadataFormatter` crea un `ByteCountFormatter` nuevo por llamada
  en vez de cachearlo (regresión menor de performance vs. el `static
  let` que tenía `DetailsListView` antes de este slice) — no se
  cachea porque un `static let` de un tipo no-Sendable crasheaba el
  compilador en un `struct` plano usado desde tests (ver ledger del
  Task 2); en una `View` (como lo tenía `DetailsListView`) sí compila,
  así que el riesgo es específico al contexto de uso, no al tipo.
- Un archivo (no carpeta) con `size == nil` muestra "Zero KB" en vez de
  un placeholder — el mismo problema que el plan quería evitar para
  carpetas, pero no cubierto por sus tests (que solo prueban carpetas
  sin tamaño). Candidato: `item.size.map(formatter.string(fromByteCount:)) ?? "—"`.
- El ícono por tipo (carpeta/documento) está duplicado entre
  `InfoPanelView`, `IconGridView` y `FileListView` — candidato a una
  propiedad `FileItem.symbolName` compartida.
- Botón del panel de información (`sidebar.right`) sin tooltip/label de
  accesibilidad — mismo gap que los botones de pestañas del slice 3.

## 2026-10-26 — Slice 5: hallazgos de la revisión final de rama

Revisión final (Opus, fresh context) sobre filtro + barra de estado. Un
"Important" arreglado en el momento (el filtro no limpiaba la selección
si ocultaba el ítem seleccionado — el panel de información seguía
mostrando metadata de algo invisible). El resto queda diferido:

- El espacio libre se consulta en cada render de `BrowserView`
  (incluye cada tecla tipeada en el filtro) en vez de una vez en
  `load(_:)`. Barato en disco local, puede trabar con un volumen de red
  lento. Candidato: moverlo a estado del view model.
- Se usa `.volumeAvailableCapacityKey` en vez de
  `.volumeAvailableCapacityForImportantUsageKey` — Finder usa la
  segunda (excluye espacio purgeable), así que el número puede no
  coincidir con "Acerca de esta Mac". El spec nombra la key literal
  usada; cambiarla es una decisión de producto, no un bug.
- La barra de estado muestra "0 ítems" también cuando hay un error
  (permiso denegado / no encontrado), lo que puede leerse como "carpeta
  vacía". Candidato: ocultar el conteo o mostrar "—" si `viewModel.error != nil`.
- Sin pluralización ("1 ítems" en vez de "1 ítem").
- El estado "Sin resultados" se decide en la vista (`BrowserView`), no
  en el view model — no hay un test directo de ese caso a nivel de VM,
  solo indirectamente vía `filteredItems`/`filterText`.
- Un filtro de solo espacios (`"   "`) cuenta como activo (matchea
  cualquier nombre con un espacio) — candidato: trim antes del check de
  vacío.
- El botón de limpiar el filtro no tiene tooltip/accesibilidad — mismo
  gap que otros botones de ícono de slices anteriores.

## 2026-10-26 — Slice 6: hallazgos de la revisión final de rama

Revisión final (Opus, fresh context) sobre operaciones de archivo — la
única que toca archivos reales. Sin "Critical": ninguna ruta borra o
renombra algo distinto del ítem seleccionado, y borrar siempre va a la
Papelera (recuperable). Tres "Important" arreglados en el momento:
selección fantasma tras renombrar (y, de forma genérica, tras cualquier
refresh), el alert de borrado no nombraba ni fijaba su objetivo hasta
confirmar, y renombrar a un nombre que empieza con "." hacía
desaparecer el ítem sin forma de recuperarlo (no hay toggle de
"mostrar ocultos" todavía). El resto queda diferido:

- Nombres compuestos solo de salto de línea pasan la validación
  (`validate` usa `.whitespaces`, no `.whitespacesAndNewlines`).
- Renombrar solo cambiando mayúsculas/minúsculas (`a.txt` → `A.txt`) en
  un volumen case-insensitive (APFS por defecto) falla con "ya existe"
  en vez de aceptarse — igual que confirmar "Renombrar" sin cambiar el
  nombre. Candidato: comparar por identidad del recurso, no por
  `fileExists` crudo, o salir temprano si `newName == item.name`.
- Renombrar a "." o ".." da el error genérico de "ya existe" en vez de
  un mensaje específico (ambos quedan cubiertos por el rechazo de
  nombres que empiezan con "." agregado en este fix pass, pero el
  mensaje que ve el usuario sigue siendo "nombre inválido" genérico,
  no algo como "nombre reservado").
- Falta test de que `moveToTrash` sobre un ítem que ya no existe tira
  (no se traga el error).
- Con dos paneles de split mostrando la misma carpeta, la identidad por
  path puede quedar stale en el panel no enfocado si el otro panel
  renombra/borra — mitigado por el mismo mecanismo de reconciliación en
  `load(_:)` la próxima vez que ese panel refresque, pero no hay
  notificación entre paneles (no hay file-watching, ya logueado en
  slice 1).

## 2026-10-26 — Slice 7: hallazgos de la revisión final de rama

Revisión final (Opus, fresh context) sobre árbol de carpetas + búsqueda.
Confirmado empíricamente: ni el árbol ni la búsqueda hacen loop con un
symlink circular (el enumerator no sigue symlinks a directorios por
default), y ambos degradan a vacío/salteado ante una carpeta sin
permiso, sin crashear. Tres "Important" arreglados en el momento (ver
el commit `fix: debounce de búsqueda, resultados se refrescan al
borrar, selección en modo búsqueda`). El resto queda diferido:

- El árbol de carpetas nunca vuelve a leer un nodo ya expandido
  (`children == nil` es la única condición) — una carpeta creada,
  renombrada o borrada por el slice 6 no aparece/desaparece del árbol
  hasta reiniciar la app. Candidato: sacar la condición `children ==
  nil` para que cada expand vuelva a leer.
- La búsqueda usa `.skipsHiddenFiles` (respeta el flag `UF_HIDDEN` del
  sistema), mientras que el resto de la app define "oculto" solo como
  prefijo `.` (decisión del slice 1) — una carpeta marcada con el flag
  de sistema (no muy común, pero existe) se salta en la búsqueda y se
  ve en el navegador normal. Inconsistencia menor, no un bug de
  seguridad.
- Las carpetas vía symlink no aparecen en el árbol en absoluto (en vez
  de aparecer como hoja no expandible) — el plan pedía "listado, no
  seguido"; quedó como "ni listado". No hay riesgo de loop en ningún
  caso.
- Abrir un resultado de búsqueda que es una carpeta navega a su
  carpeta contenedora (como pedía el plan), no entra a la carpeta — un
  usuario que hace doble-click en una carpeta en los resultados
  probablemente espera entrar, no ver el padre. Documentado como
  tensión conocida, no se resuelve en este slice.
- Los resultados de búsqueda no muestran la ruta/carpeta contenedora —
  dos archivos con el mismo nombre en carpetas distintas se ven
  idénticos en la lista.
- La barra de estado sigue contando los ítems de la carpeta actual
  durante una búsqueda activa, no los resultados.
- El filtro de texto y la búsqueda pueden estar "activos" los dos a la
  vez sin que la UI avise cuál gana (gana la búsqueda, por orden en
  `BrowserView`) — no hay nada que le diga esto al usuario.
- Un query de búsqueda de solo espacios dispara un recorrido completo
  igual — mismo tipo de hueco que el filtro del slice 5.
- Cada fila del árbol muestra una flecha de disclosure aunque sea una
  hoja o una carpeta sin permiso (expande a nada, sin indicador), y el
  árbol no resalta ni sigue la carpeta actualmente abierta.
- Faltan tests directos de `SearchService` para symlink circular y
  carpeta sin permiso (el comportamiento correcto está confirmado por
  el revisor con un script aparte, pero no está fijado en la suite).

## 2026-10-26 — Slice 8: hallazgos de la revisión final de rama

Revisión final (Opus, fresh context) sobre la ventana de preferencias.
Sin hallazgos Critical ni Important — las 5 garantías del Review Focus
se sostienen y los 79 tests pasan. Sin fixes en este pase. Queda
documentado:

- **Alcance reducido respecto al roadmap:** el ítem 8 del diseño dice
  "vistas, inicio, papelera" — este slice solo implementa "vistas"
  (modo de vista por defecto) y, además, "mostrar ocultos" (que no
  estaba en el roadmap original pero ya existía en el código sin UI).
  "Inicio" y "papelera" quedan afuera — "inicio" necesita persistir la
  última ubicación visitada (sin dueño claro todavía) y "papelera"
  depende del slice 9, que recién se está planeando.
- **Los dos ajustes no tienen el mismo alcance de "cuándo aplican".**
  El modo de vista por defecto aplica en la próxima navegación de
  *cualquier* panel ya abierto a una carpeta sin `ViewProperties`
  guardadas (no hace falta una pestaña nueva) — más inmediato de lo
  que el plan prometía. "Mostrar ocultos" solo aplica a
  `BrowserViewModel`s nuevos (pestaña nueva, split nuevo), porque se
  lee una sola vez al construir el `DirectoryReader` por defecto. Esto
  puede dar un tab con dos paneles en split mostrando ocultos distinto
  si se activa el ajuste entre la creación de cada panel — es
  consistente con la regla del plan de "no retroactivo", pero vale
  tenerlo escrito.
- `ViewPropertiesStore(defaults: suite)` sin pasar `appSettingsStore:`
  sigue leyendo el fallback de modo desde `UserDefaults.standard`, no
  desde la suite inyectada — filtra estado global a tests que ya eran
  "aislados" antes de este slice (pasa hoy solo porque el dominio de
  `xctest` no tiene la key `appSettings`). Candidato:
  `appSettingsStore: AppSettingsStore? = nil` con fallback a
  `AppSettingsStore(defaults: defaults)` cuando es `nil`, para que lea
  de la misma suite.
- `AppSettings` (como `ViewProperties`) decodifica con `Codable`
  sintetizado, que no usa los valores default de las properties si
  falta un campo en el JSON guardado — si un slice futuro le agrega un
  campo (inicio, papelera), un `AppSettings` guardado con el esquema
  viejo falla el decode completo y vuelve a todos los defaults,
  perdiendo silenciosamente lo que el usuario ya había elegido.
  Candidato: `init(from:)` manual con `decodeIfPresent ?? default`
  cuando se agregue el próximo campo.

