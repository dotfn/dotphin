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

## 2026-10-26 — Slice 9: hallazgos de la revisión final de rama

Revisión final (Opus, fresh context) sobre la papelera navegable —
la única operación permanente de todo el proyecto. Tres "Important"
arreglados en el momento (ver commit `fix: Vaciar papelera nunca
apunta a otra carpeta, nunca falla en silencio`): la carpeta a vaciar
dependía solo de que la vista mostrara el botón (ahora el view model
tiene su propio guard), vaciar una papelera sin permiso de lectura
reportaba éxito sin borrar nada, y un fallo parcial dejaba la lista
mostrando ítems que ya se habían borrado de verdad. El resto queda
diferido:

- "Eliminar" (mover a la papelera) sigue disponible en el menú
  contextual y la toolbar mientras se navega la papelera misma — el
  wording del alert ("Se moverá a la Papelera") no tiene sentido para
  un ítem que ya está ahí. El plan pedía explícitamente dejar esos
  botones como están; queda como mejora de copy, no de lógica.
- `restoreSelected()` siempre mueve a Home, incluso si el ítem
  seleccionado es un resultado de búsqueda anidado dentro de una
  carpeta de la papelera (`~/.Trash/carpeta/sub/x.txt`) — restaura solo
  ese archivo, no la carpeta contenedora. No pierde datos, pero puede
  sorprender.
- El mensaje de fallo parcial de `emptyTrash` lista todos los nombres
  que fallaron en un solo string sin límite — con muchos fallos el
  alert puede crecer mucho. Candidato: "N ítems, p. ej. a, b, c…".
- Sin test para "emptyTrash con un `trashURL` real que coincide pero
  sin permiso de lectura" más allá del caso ya cubierto con `chmod
  000` directo — cubierto en la práctica, no hay un test narrado
  específicamente como "simulación de falta de Full Disk Access".

## 2026-10-26 — Slice 10: hallazgos de la revisión final de rama

Revisión final (Opus, fresh context) sobre los overlays de git. Dos
"Critical" y dos "Important" arreglados en el mismo pase (ver commit
`fix: GitStatusProvider ya no cuelga la app ni calcula mal debajo de
la raíz`): un deadlock real de pipe que colgaba la app
permanentemente, badges mal calculados en cualquier subcarpeta del
repo, nombres con espacios/no-ASCII que nunca hacían match, y los
resultados de búsqueda mostrando los badges de la carpeta equivocada.
El resto queda diferido:

- **Diálogo de "instalar herramientas de línea de comandos" en una Mac
  sin Xcode/CLT:** `/usr/bin/env git` podría resolver al shim de
  `xcode-select` en una máquina sin CLT instalado, lo que
  potencialmente dispara un diálogo del sistema (y, peor, podría ser
  OTRA forma de colgar la navegación si el diálogo bloquea el proceso).
  No se pudo verificar en este entorno (tiene Xcode instalado). Queda
  como riesgo documentado, no como fix a ciegas — no hay forma
  confiable de detectar "es el shim" sin invocarlo, que es justo lo que
  se quiere evitar. Revisar en una Mac limpia antes de distribuir fuera
  de esta máquina de desarrollo.
- **Costo de la suite de tests:** cada test de `BrowserViewModel`/
  `TabsViewModel` ahora dispara dos procesos `git` (`rev-parse
  --show-prefix` + `status`) en `load()`, aunque la carpeta de test no
  sea un repo. La suite completa pasó de ~0.06s a ~9.8s con este
  slice. Es tolerable hoy, pero crece linealmente con cada test nuevo
  de view model. Candidato: hacer `GitStatusProvider` inyectable vía
  protocolo/closure e inyectar un no-op en los tests existentes que no
  prueban nada relacionado a git — no se hizo en este fix pass porque
  es un cambio de forma (afecta la firma pública de
  `BrowserViewModel.init`), no un bug puntual.
- Códigos de conflicto de merge (`UU`, `AA`, `DU`) caen en `.added`/
  `.deleted` o se ignoran según el caso; no hay un estado dedicado a
  "en conflicto".
- Una carpeta con cambios mezclados (algo untracked y algo modificado
  adentro) muestra el primer estado que se encuentra, no una
  combinación — detalle menor de agregación.
- `GitStatusBadge` es solo un punto de color sin `.help`/accessibility
  label — mismo gap de accesibilidad en íconos que otros slices.
- Sin test para una salida de `git` grande (el caso que gatilla el
  deadlock original) — se verificó a mano con un script aparte (4000
  archivos, ~67KB, termina en 1s) en vez de un test permanente, por el
  costo de generar ese fixture en cada corrida de la suite.

## 2026-10-26 — Slice 11: hallazgos de la revisión final de rama

Revisión final (Opus, fresh context) sobre volúmenes externos. Dos
"Important" arreglados en el momento (ver commit `fix: el error de
expulsión llega al usuario, y el disco de arranque no ofrece
Expulsar`): el mensaje de error del sistema no llegaba al usuario
(faltaba `LocalizedError`), y "Expulsar" aparecía sobre el disco de
arranque. El resto queda diferido:

- Expulsar corre síncrono en el main thread — un volumen de red lento
  puede trabar la ventana unos segundos. Mismo tipo de concesión ya
  aceptada para la consulta de espacio libre del slice 5.
- El alert de error de expulsión se dispara desde dentro del botón del
  alert de confirmación — en teoría SwiftUI encola el segundo alert
  después de que cierra el primero, pero no se verificó a mano (ni se
  puede, sin una imagen de disco de prueba montada en este entorno).
  Revisar al hacer la verificación manual pendiente del slice.
- "Información" sobre un volumen que se desmontó en el ínterin muestra
  "—" en los tres campos en vez de un mensaje explícito tipo "el
  volumen ya no está disponible".
- La info del volumen se vuelve a leer en cada re-render mientras el
  alert está abierto — barato para un volumen local, podría trabar con
  un volumen de red colgado (mismo tipo de concesión del slice 5).
- `pendingEject` no se limpia después de cerrarse el alert (inocuo,
  la presentación depende de `showsEjectConfirmation`, no de
  `pendingEject != nil`).
- El volumen sigue en la sidebar después de expulsarlo con éxito hasta
  que se reinicia la app (ya aceptado — no hay observación de
  mount/unmount en vivo, decisión del slice 1/5).

## 2026-10-26 — Slice 12: spike de dispositivos móviles — conclusión: no se implementa

Tal como pedía el roadmap ("empieza con un spike de investigación de
alcance real antes de comprometer diseño"), este slice es el spike en
sí — no hay código que mergear. Investigación:

**iPhone.** La única superficie pública para que una app de terceros en
macOS acceda a contenido de un iPhone es `ImageCaptureCore`
(`ICDeviceBrowser`/`ICCameraDevice`) — lo mismo que usa Image
Capture.app. Está acotada a fotos/videos (estilo DCIM), no es un
filesystem general. `ICCameraItem` es un modelo de objetos aparte, no
basado en `URL`/`FileManager` — no encaja con `FileItem`/
`DirectoryReader`/`BrowserViewModel`, la arquitectura entera de esta
app, sin un camino paralelo de UI (otro modelo de datos, otro flujo de
carga, descubrimiento de dispositivo asíncrono vía delegate, y el
usuario tiene que "confiar" en la computadora desde el teléfono — un
flujo que no existe en ningún otro lado de la app). Lo que Finder
muestra bajo "Archivos" para apps de iOS con `UIFileSharingEnabled` usa
una ruta distinta (`MobileDevice.framework`/`AMDevice`) que no es
pública — es la misma API no documentada que usa `libimobiledevice`
(ingeniería inversa). Usarla significa frameworks privados, lo que va
en contra de la postura de este proyecto (Direct Distribution con
APIs públicas, nada que arriesgue notarización o que dependa de una
API que Apple puede cerrar en cualquier punto).

**Android.** macOS no tiene ningún framework nativo de MTP (a
diferencia de Windows). La única forma de hablar MTP es manejar el
stack USB vía IOKit directamente e implementar el protocolo
PTP/MTP desde cero, o traer una librería de terceros (p. ej. libmtp).
Ambas opciones violan la regla del proyecto de "sin dependencias
nuevas, preferir nativo" — y la primera es, en sí misma, un proyecto
del tamaño de esta app entera, no "unas líneas más".

**Decisión: slice 12 queda diferido indefinidamente, sin código.** No
es un recorte de alcance por pereza — está respaldado por
restricciones reales de la plataforma, la misma categoría de
restricción que el documento de diseño ya anticipaba en su sección de
Riesgos antes de escribir una sola línea de código. Si en el futuro
Apple publica una API soportada para esto, o si "ver la cámara de
fotos del iPhone" sin edición de archivos alcanza como alcance
reducido, se puede reabrir como un slice nuevo con su propio
diseño — no como una extensión de `BrowserViewModel`.

## 2026-10-26 — Slice 13 (terminal): review y rulings

Review de branch completo (fresh Opus, base a80042f..49b1c74). Veredicto:
"Ready to merge con fixes". Hallazgos y resolución:

- **Important (fixed):** `TerminalLauncher.openTerminal` solo lanzaba si
  `/usr/bin/open` no podía ejecutarse — si `open` arrancaba pero fallaba
  (Terminal.app ausente, o la carpeta actual fue borrada/no existe), el
  proceso salía con código distinto de 0 y stderr tenía el mensaje real,
  pero la función devolvía éxito igual y el usuario no veía ninguna
  alerta. Esto rompía exactamente el caso que el plan pedía cubrir. Fix:
  leer stderr (antes de `waitUntilExit`, por la lección del slice 10) y
  chequear `terminationStatus` antes de retornar sin error.
- **Minor (fixed):** el botón de terminal no tenía `.help`. Se agregó —
  mismo patrón que el resto de los íconos del toolbar, varios de los
  cuales siguen sin tooltip; ver el barrido de accesibilidad planeado
  para el slice 14.
- **Minor (fixed por la corrección de arriba):** "no hay test del path de
  error" — el nuevo test (`test_openTerminal_throwsWhenPathDoesNotExist`)
  cubre esto apuntando a una carpeta inexistente, que falla dentro de
  `open` antes de intentar abrir una ventana real — no rompe el
  precedente de no lanzar una Terminal real en los tests.
- **Ruling:** la corrección del texto del plan original que decía
  `try?` para la llamada — la implementación real usa `do`/`catch` desde
  el principio (correcto, el plan tenía un error); no requiere ninguna
  acción de código, solo se deja constancia aquí.
- Todo lo demás señalado por el reviewer como "declined to judge"
  (sin test de lanzamiento real, sin click-through de GUI, `open -a
  Terminal` en vez de emulador embebido, sin soporte de terminal
  alternativa) son límites de alcance ya aceptados en el spec/plan, no
  hallazgos nuevos.

105/105 tests en verde tras el fix. Listo para mergear a main.

## 2026-10-26 — Slice 14 (pulido): chequeo de adopción de Liquid Glass

Según `axiom-design` (skills/liquid-glass-ref.md): "la mayoría de los
componentes estándar de SwiftUI/UIKit adoptan Liquid Glass
automáticamente". Se grepeó todo `Sources/` buscando
`.ultraThinMaterial`, `NSVisualEffectView`, `.blur(`, `.regularMaterial`,
`.thinMaterial` y `glassEffect` — cero resultados. Toda la app usa
controles stock de SwiftUI sobre macOS 27
(`NavigationSplitView`/`List`/`Table`/`Menu`/`Button`/`TextField`/
`.alert`/`.inspector`/`TabView` propio hecho a mano con `HStack`, no un
material custom). Conclusión: no hay nada que migrar ni override que
corregir — la adopción es automática por construcción. No se agregó
código por agregar.

## 2026-10-26 — Slice 14 (pulido): review y rulings

Review de branch completo (fresh Opus, base 75dddda..d4e507f). Veredicto:
"Ready to merge después de arreglar el Important #1". Hallazgos y
resolución:

- **Important (fixed):** en `InfoPanelView`, el continuation de
  `QLThumbnailGenerator` no tiene punto de cancelación cooperativa — al
  cambiar de selección, SwiftUI cancela el `Task` viejo pero la llamada
  suspendida igual reanuda cuando Quick Look termina. Sin chequear
  `Task.isCancelled` después del `await`, el thumbnail del ítem anterior
  pisaba el del ítem nuevo de forma persistente (ej: seleccionar un video
  grande y cambiar rápido a una carpeta — la carpeta terminaba mostrando
  el thumbnail del video en vez del ícono azul). Fix: `guard
  !Task.isCancelled else { return }` antes de asignar `thumbnail`.
- **Minor (deferred):** un frame de thumbnail viejo puede verse antes de
  que `.task(id:)` corra y limpie el estado al cambiar de selección —
  cosmético, un solo frame, no se mergea una solución más compleja
  (key del estado por URL) para esto ahora.
- **Minor (deferred):** el barrido de accesibilidad del slice 14 no
  cubrió `ViewModePicker` (los 3 segmentos son solo `Image(systemName:)`
  sin `.help`/`.accessibilityLabel`) ni el `Slider` de zoom en
  `BrowserView` — ambos están en archivos que sí se tocaron en este
  slice, así que el alcance planeado quedó corto. Se deja como deuda
  explícita para una próxima pasada, junto con `GitStatusBadge` (un
  punto de color sin alternativa accesible — fuera del alcance original
  del slice 14, detectado por el reviewer de todas formas).
- **Minor (deferred):** el test de `ThumbnailLoader` depende del
  servicio XPC de Quick Look estando disponible — podría ser flaky en
  CI sandboxeado; no es un problema en el setup actual (local, sin CI).
- Todo lo demás señalado por el reviewer como "declined to judge"
  (qué tan probable es el bug en la práctica sin correr la GUI,
  comportamiento exacto de `QLThumbnailGenerator.cancel`, qué lee
  VoiceOver de un SF Symbol sin más contexto) son límites de verificación
  de este entorno, no hallazgos nuevos.

107/107 tests en verde tras el fix. Listo para mergear a main — cierra
el roadmap original de 14 slices (con drag & drop explícitamente
diferido, documentado arriba en la entrada del slice 14).

## 2026-10-26 — Slice 14b (deuda de accesibilidad): review y rulings

Review de branch completo (fresh Opus, base 95a4782..e400308). Veredicto:
"Ready to merge" — sin Critical ni Important. Minors (deferred, no se
fixean en este pass):

- `GitStatusBadge` se anuncia como elemento separado de VoiceOver, sin
  agrupar con el nombre del archivo en `IconGridView`/`DetailsListView`
  (ej: VoiceOver dice "Modificado" sin contexto). Candidato a
  `.accessibilityElement(children: .combine)` en la fila completa en
  una futura pasada.
- El `Slider` de zoom tiene label pero no `.accessibilityValue`, así que
  VoiceOver lee el rango 0.5...2.0 como porcentaje crudo en vez de un
  valor de zoom legible.
- Dudas abiertas que el reviewer marcó como no verificables sin GUI/
  VoiceOver real: si el `.help` por segmento del `Picker` segmentado
  realmente muestra tooltip (podría ser un no-op inofensivo en AppKit),
  y si VoiceOver lee el `.accessibilityLabel` del segmento o el nombre
  del SF Symbol. Si una revisión con VoiceOver real muestra que lee el
  símbolo, el fallback documentado es `Label(...)` +
  `.labelStyle(.iconOnly)` en vez de `Image` desnuda.

108/108 tests en verde. Listo para mergear a main.

## 2026-10-26 — Slice 15 (drag & drop): review y rulings

Review de branch completo (fresh Opus, base d27ed2f..623384e, con una
sonda real contra el SDK y el filesystem para verificar el formato de
Transferable de `URL` y los guards de `move`). Veredicto: "Ready to
merge con fixes". Ningún hallazgo de pérdida de datos. Hallazgos y
resolución:

- **Important (fixed):** soltar sobre una fila de ARCHIVO se rechazaba
  (`return false`) en vez de caer al comportamiento de "soltar en el
  fondo" — en una lista llena, la mayoría del área visible son filas de
  archivo, así que la mayoría de los drops no hacían nada. Fix: enrutar
  a `currentURL` cuando `!item.isDirectory`, en las 3 vistas de listado.
- **Important (fixed):** en modo búsqueda, soltar sobre el fondo de la
  lista movía el archivo a la carpeta que se está navegando, no a donde
  realmente vive — un movimiento no pedido, aunque sin pérdida de datos.
  `FileListView.currentURL` ahora es `URL?`; en búsqueda se pasa `nil` y
  ese drop de fondo queda deshabilitado (soltar sobre una fila de
  carpeta puntual sigue funcionando siempre, sin ambigüedad).
- **Important (fixed):** arrastrar una carpeta y soltarla sobre sí misma
  (no un descendiente — ella misma) no estaba cubierto por ningún guard
  de `FileOperationsService.move` — el árbol quedaba intacto, pero el
  usuario veía un error de "no se pudo mover" por una acción que debería
  ser un no-op silencioso, como en Finder. Nuevo guard de igualdad +
  test (`test_move_folderDroppedOntoItself_isNoOp`).
- **Important (fixed):** "entre paneles" no refrescaba el pane que NO
  originó el drop — quedaba desactualizado hasta navegar o refrescar a
  mano, lo cual es el título mismo de este slice. `BrowserView` ganó un
  callback opcional `onFilesMoved`; `SplitBrowserView` lo usa para
  refrescar el pane sin tocar.
- **Important (corrección de premisa del plan, sin fix de código):**
  el plan afirma que `Table` no tiene un contenedor de "fila completa"
  expuesto en SwiftUI, así que el drag/drop de `DetailsListView` se
  limitó a la celda de la columna "Nombre". El reviewer encontró que
  esto es **objetivamente falso**: el SDK tiene `TableRowContent.draggable(_:)`
  y `.dropDestination(for:action:)` desde macOS 14, usando la sintaxis
  `Table(of:selection:) { } rows: { ForEach(items) { TableRow($0)... } }`
  en vez de la sintaxis de `TableColumn` por closure que usa este
  archivo. No se migra ahora — el reviewer también señaló un riesgo no
  verificado de conflicto de gestos entre `.draggable` en una celda y la
  selección nativa de fila en `List`/`Table` (ambos corren sobre
  `NSTableView`), y hacer este cambio sin poder clickear la GUI real es
  más riesgo que valor a esta altura. Queda como el único "fix" de este
  review que se decide NO aplicar ahora — ruling explícito, no omisión:
  **antes de confiar en el drag/drop de `DetailsListView` en uso real,
  alguien con la GUI a mano debe: (1) confirmar que un solo click sigue
  seleccionando la fila y el doble click sigue abriendo, en la columna
  Nombre; (2) si hay conflicto, migrar a `TableRow.draggable`/
  `.dropDestination`, que de paso elimina la limitación de "solo
  Nombre".**
- **Minor (deferred):** el no-op de "soltar sobre la propia carpeta" no
  cubre alias por symlink (`/tmp` vs `/private/tmp`) ni diferencias de
  mayúsculas/minúsculas en el path — en esos casos rarísimos termina en
  un error de "ya existe" en vez de un no-op silencioso. Sin riesgo de
  datos (el guard de `fileExists` sigue protegiendo contra sobrescribir).
- **Minor (deferred):** cuando `FileOperationsService.move` falla por un
  motivo específico (ej. "no se puede mover una carpeta dentro de sí
  misma"), `moveDroppedItems` descarta ese mensaje y solo reporta el
  nombre del archivo en el error agregado — el mensaje claro que pide el
  plan no llega al usuario en el caso de fallos parciales.
- **Minor (deferred):** mover entre volúmenes distintos copia+borra de
  forma síncrona en el main actor (comportamiento normal de
  `FileManager.moveItem`, no es un bug nuevo de este slice) — sin
  riesgo de pérdida de datos, pero es la primera operación de archivo
  potencialmente larga de la app corriendo en el hilo principal.
- Confirmado con una sonda real contra el SDK: una `URL` de tipo
  `file://` exporta tanto `public.url` como `public.file-url` vía su
  conformance built-in de `Transferable` — Finder recibe `public.file-url`
  como un archivo real (no un webloc), confirmando la premisa
  arquitectónica del plan sobre arrastrar hacia Finder.
- Todo lo demás señalado por el reviewer como "declined to judge"
  (comportamiento real de ruteo de drop anidado y gestos en macOS 27 sin
  poder correr la GUI, qué operación exacta —copiar o mover— ofrece
  `.draggable` hacia Finder, soltar en la vista de Papelera) son límites
  de verificación de este entorno, no hallazgos nuevos.

115/115 tests en verde tras los fixes. Listo para mergear a main — cierra
el roadmap completo de 15 slices (14 originales + el ítem de drag & drop
que se había diferido explícitamente del slice 14).

## 2026-10-26 — Recorte del slice 13 (terminal embebido): se mantiene, no se revierte

Repregunta explícita sobre si el recorte del slice 13 (de "terminal
embebido" a `open -a Terminal`) debería revertirse ahora que hay
presión por cerrar todos los recortes de alcance del proyecto. Se
decide NO revertirlo, por motivos distintos a los de "inicio"
(slice 17, arriba) o "papelera" — ahí no había nada bloqueando excepto
que no se le había prestado atención; acá sí hay un bloqueo real:

- Un terminal embebido de verdad requiere un emulador de terminal real
  (parseo de secuencias VT100/ANSI, manejo de PTY, teclado) — no es un
  recorte de alcance menor, es un subsistema entero. La opción
  conocida y madura es SwiftTerm, una dependencia de terceros. Eso
  choca directo con la regla explícita del proyecto "sin dependencias
  de terceros por default" (ver `project_dolphin_macos.md`).
- Escribir un emulador de terminal desde cero (sin SwiftTerm) es un
  proyecto de varias semanas en cualquier equipo real, no algo para
  forzar al final de una sesión larga sin poder probarlo interactivamente.
- A diferencia del slice 16 (fotos de iPhone), donde había hardware
  real para verificar, un emulador de terminal embebido necesitaría
  probarse exhaustivamente a mano (resize, colores, programas
  interactivos como vim/less, señales) — no hay forma de dar por
  verificado algo así sin uso real sostenido.

Conclusión: el recorte del slice 13 queda como está, documentado como
una decisión de ingeniería permanente (evitar una dependencia grande o
reinventar un emulador de terminal), no como una tarea pendiente. Si
en el futuro se decide agregar SwiftTerm como excepción explícita a la
regla de "sin dependencias de terceros", eso es una decisión que le
corresponde al usuario, no algo para asumir de forma autónoma.

## 2026-10-26 — Slice 17 (ubicación de inicio): review y rulings

Review de branch completo (fresh Opus, base 7b40eb9..73ff74e, con
verificación real compilando y decodificando un blob de prueba, no
solo lectura de código). Veredicto inicial: "No listo para mergear" —
Important real confirmado. Hallazgos y resolución:

- **Important (fixed):** `AppSettings` tiene `var` con valores default
  (`= .home`, `= false`, etc.), pero el `Decodable` sintetizado por
  Swift exige la key en el JSON de todas formas — el default solo
  sirve para `AppSettings()` en memoria, nunca para decodificar un
  blob que no tiene esa key. Como `AppSettingsStore.settings()` usa
  `try?` y cae a `AppSettings()` completo ante cualquier error, un
  usuario con settings guardados ANTES de este slice perdía
  silenciosamente `defaultViewMode` y `showsHiddenFiles` también (no
  solo los 2 campos nuevos) la primera vez que la app arrancaba con
  este código. El reviewer lo confirmó compilando y decodificando un
  blob real de 2 keys, no especulando. Fix: `init(from:)` a mano con
  `decodeIfPresent(...) ?? default` por campo + test de regresión que
  decodifica ese mismo blob viejo.
- **Minor (fixed):** el chequeo de "Carpeta personalizada" aceptaba
  cualquier ítem del filesystem con `fileExists(atPath:)`, incluyendo
  un archivo regular si reemplazaba a la carpeta elegida. Ahora exige
  `isDirectory` explícitamente.
- **Minor (deferred):** `.desktop` nunca verifica que `~/Desktop` en
  verdad exista — en macOS casi siempre existe, no se agrega el check.
- **Aclaración, no código:** cambiar la ubicación de inicio en
  Settings con la app corriendo no mueve la ventana ya abierta —
  `@State private var tabsViewModel` se evalúa una sola vez por
  instancia de `ContentView`; una ventana nueva (Cmd-N) sí usa el
  valor nuevo, una ya abierta nunca se reubica. Confirmado por el
  reviewer leyendo el ciclo de vida de SwiftUI, no asumido.
- Todo lo demás señalado como "declined to judge" (la interacción real
  de `NSOpenPanel`, qué pasa si la carpeta de inicio se borra en el
  instante exacto entre el chequeo y la navegación, si versiones
  previas del proyecto ya tenían este mismo bug con
  `showsHiddenFiles`) son límites de verificación de este entorno o
  preguntas fuera del diff de este slice, no hallazgos nuevos.

121/121 tests en verde tras el fix. Listo para mergear a main.

## 2026-11-09 — Funcionalidad no documentada que entró con el commit de rename

El gap-analysis contra KDE Dolphin encontró que el commit `4716ba4`
("rename: Dolphin for macOS -> Dotphin") no fue solo un rename: trajo
sin entradas en este log gran parte de lo que hoy cubre
`DolphinFullParityTests.swift` (22 categorías: agrupado, selección por
patrón, búsquedas guardadas, checksums, comparación, git stage/commit,
terminal embebido con buffer propio, plantillas fijas de "Crear nuevo",
permisos editables, etc.). No se reconstruye retroactivamente; se deja
asentado para que nadie asuma que este log describe todo lo que existe.
Consecuencia práctica: antes de declarar un hueco de paridad, leer el
código (el primer análisis de este slice sobreestimó 3 de 4 huecos por
confiar en grep y en este log).

## 2026-11-09 — Slice 18 (permisos recursivos, plantillas, montar imagen, deuda de slice 15): review y rulings

Alcance real (confirmado con el usuario tras corregir el análisis): permisos
recursivos, plantillas de `~/Templates`, acción explícita "Montar imagen de
disco", y los 3 Minor diferidos del review de slice 15. Protocolos remotos
(smb/sftp/ftp) quedan fuera por decisión del usuario, por ahora.

Review de branch completo (fresh agent, base fc30f96..fc8cb1f, con sondas
reales: matriz de symlinks, chmod sobre árboles reales, `hdiutil attach`
real sobre un dmg de 200 MB, y ruteo de drag/drop de `Table` en un
`NSHostingView` offscreen). Veredicto: "Ready with fixes". Resolución:

- **Critical (fixed):** el chmod recursivo seguía symlinks — un enlace
  dentro de la carpeta a un archivo de afuera (ej. `~/.ssh/id_rsa`) recibía
  el modo nuevo. Ahora se saltean symlinks. Test de regresión.
- **Important (fixed):** el chmod recursivo quedaba a medias y reportaba
  éxito: el enumerator no tenía `errorHandler` y cada carpeta se cambiaba
  antes de entrar, así que quitar "x" dejaba el resto del árbol intacto con
  0 fallos. Ahora se lista todo primero, se aplica de lo más profundo hacia
  arriba con la raíz al final, y lo que no se pudo listar cuenta como
  fallo. Tests: quitar x llega al fondo; subcarpeta ilegible = fallo.
- **Important (fixed):** el fix D2 (`resolvingSymlinksInPath()`) también
  resolvía el último componente, así que mover un SYMLINK se evaluaba como
  su destino (falsos "dentro de sí misma", no-ops silenciosos que en
  cortar/pegar vaciaban el portapapeles sin mover nada). Ahora solo se
  resuelven las carpetas padre. Tests con los 2 casos reproducidos.
- **Important (fixed):** `hdiutil attach` verifica la imagen antes de
  montar (3,1 s medidos con 200 MB) y corría en el main actor. Ahora corre
  en `Task.detached`; stdout va a `/dev/null` (era un `Pipe()` sin drenar,
  la misma clase de deadlock que el slice 10).
- **Minor (fixed):** el aviso de deprecación que hdiutil escribe siempre en
  stderr en macOS 27 se filtra del mensaje al usuario.
- **Minor (fixed):** si la plantilla desaparece entre abrir el menú y
  pulsar Crear, se muestra un error en vez de crear en silencio un archivo
  con el contenido por defecto de esa extensión.
- **D3 (pendiente de GUI, posible regresión):** la sonda del reviewer
  indica que con `TableRow.dropDestination` el outline view registra
  `public.file-url` y tapa el `.dropDestination` a nivel de `Table` —
  soltar en el área vacía DEBAJO de las filas podría no hacer nada (antes
  movía a la carpeta actual). Soltar sobre filas (carpeta → dentro; archivo
  → carpeta actual) sí funciona según la sonda. No se "arregla" a ciegas;
  no se mergea a main hasta que el usuario verifique a mano: click fuera de
  "Nombre" selecciona, doble click abre, menú contextual en fila vs. vacío,
  arrastrar desde otra columna, arrastrar varias filas, soltar debajo de
  las filas, soltar entre filas.
- **D3 resuelto de otra forma (al mergear, 2026-11-09):** la migración a
  `Table(of:) { } rows: { TableRow… }` se descartó en el merge. Detalles
  ya corre sobre `NSTableView` (`DetailsTableView`, ver más abajo), donde
  soltar debajo de las filas cae en la carpeta actual
  (`setDropRow(-1, dropOperation: .on)`) y arrastre/selección ya fueron
  verificados a mano. El resto del slice (chmod recursivo, plantillas,
  montar imagen de disco) entra tal cual.

194/194 tests en verde tras los fixes.

## 2026-11-09 — Rendimiento: trabajo pesado fuera del main actor + arrastre múltiple en Lista

Rama `fix/rendimiento-y-seleccion-lista`. Consultado axiom-concurrency
(`@concurrent` para forzar segundo plano, cancelación cooperativa) y
axiom-swiftui 26-ref (`dragContainer`) antes de escribir el código.

- `BrowserViewModel` y `TabsViewModel` pasan a `@MainActor` (antes sin
  aislamiento): requisito para lanzar `Task`s que escriben estado sin
  carreras. Los tests que los usan quedan también `@MainActor`.
- **Búsqueda** (`performSearch`): ahora es una `Task` cancelable que corre
  `SearchService.results` (`@concurrent`). Cada llamada cancela la anterior
  y el recorrido chequea `Task.isCancelled` por entrada. Antes, alcance
  "en todas partes" o modo contenido congelaba la app hasta terminar.
  `isSearching` muestra progreso en vez de "sin resultados" mientras corre.
  Los tests esperan con `waitForBackgroundWork()`.
- **Navegación** (`load`): `git status` + rama pasan a segundo plano
  (`GitStatusProvider.snapshot`, `@concurrent`); el resultado se descarta
  si mientras tanto se navegó. Detectar el repo sigue síncrono (caminata
  por `.git`, sin proceso). **No se movió** la lectura del directorio:
  buena parte de los tests y la UI asumen `items` listo tras `navigate`; queda como deuda.
- **Tamaño de carpetas** en Lista/Detalles: nueva `DirectorySizeText` con
  `.task(id:)`; el `body` solo lee el caché. Bug corregido: el modo
  "tamaño del contenido" sumaba solo el primer nivel, ahora es recursivo.
  El tooltip de carpetas ya no cuenta ítems en el `body` (usa el caché y
  no cachea el tooltip incompleto).
- `filteredItems` se memoiza por (versión de `items`, texto, modo, facetas).
- `setSelection` resolvía symlinks de todos los ítems en cada clic (un
  syscall por ítem); ahora solo si llega un ID desconocido.
- **Lista**: `.draggable(url)` por fila → `.draggable(containerItemID:)`
  + `.dragContainer(for: URL.self, itemID: \.self)` +
  `.dragContainerSelection`, para que arrastrar una fila seleccionada
  arrastre toda la selección. **Sin verificación de GUI todavía**: este
  entorno no tiene permisos de Accesibilidad / Grabación de pantalla.

## 2026-11-09 — Lista y Detalles sobre `NSTableView` nativo (selección y arrastre como Finder)

Consultado axiom-macos (`appkit-interop`: coordinator con binding fresco en
cada update, sin `NSHostingView` por celda) antes de escribir el código.

- **Lista** (`FileTableView`) y **Detalles** (`DetailsTableView`, nuevo)
  dejan `List`/`Table` de SwiftUI. Con `.draggable` en la celda, el clic
  sobre el nombre no seleccionaba de inmediato, no viajaba toda la
  selección y el arrastre se confundía con selección. Ahora clic/⌘/⇧,
  arrastre múltiple y drop por fila son los de AppKit.
- `FileNSTableView.canDragRows`: el arrastre de archivos solo arranca sobre
  ícono + nombre; desde el resto de la fila arrastrar extiende la
  selección (equivalente al recuadro de Finder en vista de lista).
- Detalles: los encabezados de columna ahora ordenan (`onChangeSort`, que
  antes se pasaba pero no se usaba). Los grupos pasan a filas de
  encabezado, igual que en Lista. `DetailsListView` conserva su firma y el
  estado de carpetas expandidas.
- Selección y arrastre confirmados a mano por el usuario.

## 2026-11-09 — Chequeo de "no nativo": teclado, menús, grillas, divisores y toolbar

Misma rama. Consultado axiom-macos (`appkit-interop`, `menus-and-commands`:
focused values en vez de notificaciones; `swiftui-differences`: inspector,
toolbars) antes de escribir el código. Se reemplazó todo lo que forzaba a
mano algo que AppKit/SwiftUI ya resuelven:

- **Teclado**: se eliminó el monitor global de `keyDown`
  (`QuickLookKeyMonitorView`). Espacio/Intro/Esc van en el `keyDown` de
  `FileNSTableView` / `FileNSCollectionView`; flechas, ⇧+flechas y búsqueda
  al tipear son las de AppKit (`typeSelectStringFor`). Con Quick Look al
  frente, las flechas se reenvían a la vista de archivos.
- **Menú Edición**: vuelve a ser el estándar (se quitaron los
  `CommandGroup(replacing: .undoRedo / .pasteboard)` y los `NSApp.sendAction`
  condicionados a "hay un campo de texto"). Cortar/Copiar/Pegar/Eliminar/
  Seleccionar todo llegan por responder chain a `AppDelegate`, que actúa
  sobre el panel activo de la ventana clave. Deshacer/Rehacer usan el
  `UndoManager` de la ventana (`BrowserViewModel.record` registra cada lote).
- **Comandos de menú**: 33 notificaciones globales → `WindowCommands`, un
  objeto por ventana publicado con `focusedSceneValue`. Con varias ventanas,
  cada comando actúa solo en la activa.
- **Renombrar**: edición en línea (Intro / F2 / menú contextual), nombre
  sin extensión seleccionado, Esc cancela, clic afuera confirma. Se fueron
  los `alert` con `TextField`.
- **Quick Look**: anima desde el rect real del ícono
  (`QuickLookSourceProviding`). La extensión de `NSWindow` que acepta el
  control del panel queda como respaldo para cuando el foco está en el
  panel lateral.
- **Iconos y Compacta**: `FileCollectionView` (`NSCollectionView`) con
  recuadro de selección, arrastre de toda la selección y drop sobre
  carpetas. Las celdas siguen siendo las de SwiftUI dentro de un
  `NSHostingView` por celda (se crea una vez, cambia `rootView`).
- **Divisores**: `HSplitView` (vista dividida y panel de información) y
  `VSplitView` (terminal). **`.inspector` descartado**: junto a la barra de
  ubicación entraba en bucle de "Update Constraints" al redimensionar
  (reproducido en test). De paso se corrigió la barra de ubicación, que
  tenía el mismo problema latente (`ScrollView` horizontal con `fixedSize`
  → `ViewThatFits`). Se pierden: doble clic en el divisor para 50/50 y el
  botón de expandir la terminal (no hay API para fijar la posición).
- **Toolbar**: `BrowserToolbar` con `.toolbar(id:)` + `.searchable`. El
  sistema agrupa, desborda y personaliza. Se borraron
  `CustomizableToolbarView`, `ToolbarConfigurationSheetView`, la pestaña de
  Ajustes y `WindowToolbarEnforcer`. **Quedan sin uso** (pero con tests):
  `ToolbarLayoutEngine` y los campos `toolbar*` de `AppSettings`.
- **Ajustes**: `AppSettingsModel` (`@Observable`, compartido) en vez de
  copias `@State` + decodificar `UserDefaults` en cada `body`.
- **Terminal externa**: `NSWorkspace.open` en vez de `/usr/bin/open`.

Verificación: `FileViewInteractionTests` monta las vistas en una ventana
real y las maneja con eventos sintéticos (flechas, Intro, renombrar,
deshacer, modo selección, doble clic). Lo que no se puede probar así: la
selección por clic y el recuadro de `NSCollectionView` (dependen del estado
real del mouse), el arrastre, y el aspecto de la toolbar nativa.
192 tests en verde.

## 2026-11-09 — Slice 19: copiar y mover en segundo plano, con progreso y conflictos

Consultado axiom-concurrency (`@concurrent` para sacar el trabajo del main
actor, continuación para esperar la respuesta del usuario).

- `FileTransferService.run` (`@concurrent`) copia o mueve un lote ítem por
  ítem. Lo usan pegar, copiar/mover al otro panel, soltar y duplicar, que
  antes corrían en el main actor y congelaban la ventana.
- **Conflicto de nombre**: diálogo Reemplazar / Conservar ambos / Omitir /
  Detener, con "Aplicar a todos" (`dialogSuppressionToggle`). Reemplazar
  manda el existente a la Papelera antes de poner el nuevo, así queda en el
  mismo lote de deshacer. Copiar dentro de la misma carpeta sigue siendo
  "duplicar" y no pregunta.
- **Sin vista que pregunte** (`presentsConflictPrompts == false`, p. ej. en
  tests): se conserva el comportamiento anterior — copiar deja ambos, mover
  informa "Ya existe un ítem con ese nombre".
- **Progreso**: barra inferior solo si la operación pasa los 400 ms, con
  botón Detener. Dos operaciones seguidas se encolan.
- Al terminar se refrescan también los otros paneles que muestran una
  carpeta afectada (registro débil de view models). Es provisorio: el
  observador de carpetas del slice 20 lo reemplaza.
- **Límites aceptados**: el avance es por ítem, no por bytes, y la
  cancelación es entre ítems (`FileManager.copyItem` no se puede cortar a la
  mitad): un único archivo enorme muestra "1 de 1" hasta terminar. Si se
  cierra la pestaña con el diálogo de conflicto abierto, esa operación
  queda esperando.
- Tests que llamaban a estas operaciones ahora esperan con
  `waitForBackgroundWork()`. 227 tests en verde.

## 2026-11-09 — Slice 20: carpetas y volúmenes en vivo

- `DirectoryWatcher` (FSEvents, como Finder): `BrowserViewModel` vuelve a
  leer la carpeta actual cuando cambia en disco, venga el cambio de esta
  app o de otra. Solo cambios directos de la carpeta, no de sus
  subcarpetas. Se prende con `watchesCurrentDirectory`, que activa la vista
  (los view models sueltos de los tests no abren streams).
- Trampa encontrada: FSEvents informa rutas reales (`/private/var/…`) y
  `resolvingSymlinksInPath()` le quita justamente el `/private`. Hay que
  comparar contra `realpath`.
- El aviso de disco relee la carpeta pero no relanza una búsqueda activa.
- **Lugares**: se actualiza al montar, expulsar o renombrar un volumen
  (`NSWorkspace` notifica). Los paneles que estaban dentro de un disco
  expulsado vuelven a la carpeta personal. Cierra la deuda del slice 1.
- Queda pendiente (deuda previa): la lectura del directorio sigue siendo
  síncrona en el main actor; con el observador ahora se relee más seguido.
  233 tests en verde.

## 2026-11-09 — Slice 21: arrastre completo (copiar/mover como Finder, carpetas con resorte)

- `FileDropPolicy`: mismo volumen → mover, otro volumen → copiar, ⌥ fuerza
  copiar, ⌘ fuerza mover. Se apoya en `draggingSourceOperationMask`, que
  AppKit ya ajusta según las teclas; al devolver `.copy` el cursor muestra
  el "+" verde del sistema.
- ⌥ + soltar en la misma carpeta ahora duplica (antes el drop se rechazaba).
- `FileDropController` unifica validación y aceptación del drop para la
  tabla (Lista/Detalles) y la grilla (Iconos/Compacta); antes estaba
  copiada tres veces.
- **Carpetas con resorte** (`SpringLoadingTimer`): un arrastre quieto 1 s
  sobre una carpeta la abre. No "vuelve" sola si el arrastre sale, a
  diferencia de Finder.
- No se hizo el menú "Mover aquí / Copiar aquí / Enlazar aquí" de Dolphin:
  en macOS esa elección va por teclas modificadoras.
- **Sin verificación de GUI**: las reglas, el destino del drop y el reloj
  del resorte tienen tests; el arrastre real (cursor, apertura de la
  carpeta en pleno arrastre) hay que probarlo a mano. 241 tests en verde.

## 2026-11-09 — Detalles finos: ⌘F, Compartir, columnas de Detalles y código muerto

- **⌘F** ("Ir → Buscar…") lleva el foco al campo de búsqueda nativo
  (`searchable(isPresented:)`).
- **Compartir**: ítem de toolbar con `ShareLink` (menú del sistema). No se
  agregó al menú contextual: los menús son `NSHostingMenu` y no se pudo
  verificar a ciegas que `ShareLink` funcione ahí.
- **Columnas de Detalles**: clic derecho en el encabezado muestra u oculta
  columnas, y AppKit recuerda los anchos (`autosaveTableColumns`). Hay que
  reactivar el autosave cada vez que se rearman las columnas para que
  aplique lo guardado; el criterio de orden lo sigue mandando el modelo, no
  lo que guarda la tabla.
- **Código muerto borrado**: `ToolbarLayoutEngine`, `ToolbarConfigEntry`,
  `ToolbarTextPosition`, `ToolbarDropTarget` y los campos `toolbar*` de
  `AppSettings`, con sus tests. Los ajustes guardados que todavía traen
  esas claves se decodifican igual (hay test).
- Queda sin hacer del relevamiento: sección Recientes en Lugares, stash de
  la vista dividida, separar un panel a ventana nueva y actuar como
  administrador. 238 tests en verde.

## 2026-11-10 — Inglés y español (localización)

Consultado axiom-integration (`localization`: String Catalogs, `#bundle` en
paquetes) y probado con un paquete de prueba antes de tocar la app.

- **Catálogo** `Resources/Localizable.xcstrings` (~630 claves). Las claves
  son los textos en español del código; cada una tiene valor explícito en
  inglés y en español. **Inglés es el idioma de respaldo**
  (`defaultLocalization: "en"`): quien no tenga ni inglés ni español ve inglés.
- **Todo texto busca en el bundle del paquete** (`bundle: #bundle`, ~830
  lugares). Al correr como ejecutable suelto (Xcode, `swift run`) el bundle
  principal no tiene traducciones: sin esto la app quedaba siempre en español.
  Los literales de SwiftUI se pasaron a `String(localized: …, bundle: #bundle)`
  (mismas claves). Un test falla si aparece un `String(localized:)` sin bundle.
- **`Support/Info.plist` incrustado en el binario** (`-sectcreate __TEXT
  __info_plist`, ruta absoluta desde `#filePath`). Sin él, macOS no sabe qué
  idiomas tiene un ejecutable suelto y siempre elige el de respaldo: ni
  `-AppleLanguages (es)` lograba español. **No lleva `CFBundleIdentifier`**: el
  dominio de UserDefaults cambiaría y se perderían los ajustes guardados.
  El `.app` de `scripts/build_app_bundle.sh` declara lo mismo en su Info.plist.
- Frases armadas con pedazos traducidos ("No se puede \(verbo)…", la barra de
  estado, la barra de progreso) pasaron a frases completas: el orden cambia
  entre idiomas.
- Enums cuyo `rawValue` se mostraba en pantalla (pestañas de Propiedades y de
  Git, estados de la comparación) ahora tienen un `title` localizado; el
  `rawValue` queda fijo.
- **Tests**: el idioma del proceso de tests es el del sistema. Las aserciones
  sobre textos visibles comparan contra `appText(clave)` (la traducción en el
  idioma en curso) en vez de un texto fijo en español.
- **No traducido a propósito**: nombres de archivo que crea la app (" copy",
  " enlace"), el registro de depuración y los nombres de Lugares guardados.
- **Verificado** con el binario real y `-AppleLanguages`: en → inglés,
  es / es-AR → español, fr → inglés, "fr, es" → español. Sin verificar a la
  vista (sin acceso a pantalla): textos que no entren en su lugar en inglés.
  242 tests en verde.

## 2026-11-10 — Barra de pestañas con una sola pestaña, menú Visualización duplicado y marcas de menú nativas

Reportado por el usuario al probar.

- **Barra de pestañas**: se mostraba también con una sola pestaña si había
  pestañas cerradas recientemente (para dar acceso a "reabrir"). Ahora, como
  Safari, solo aparece con dos o más pestañas o con el ajuste "Mostrar
  siempre". Reabrir sigue en Archivo y con ⇧⌘T.
- **Dos menús "View"**: no era un texto hardcodeado. macOS pone siempre su
  menú Visualización (pantalla completa, barra lateral, toolbar) y la app
  agregaba otro propio "Ver"; en inglés los dos se llamaban "View". Las
  opciones propias pasan a `CommandGroup(before: .sidebar)`, dentro del menú
  del sistema, como Finder.
- **Marcas de menú**: 14 opciones ponían "✓" en el título y 7 menús dibujaban
  un ícono `checkmark` al lado del texto. La "✓" del título quedaba sin
  traducir (así se descubrió) y ninguna de las dos la anuncia VoiceOver como
  estado. Pasan a `Toggle` (sí/no) y `Picker` en línea (una entre varias:
  agrupar por, orden, dirección, modo de vista, etiqueta de color, filtros de
  búsqueda, estilo de la barra de estado, subcarpetas de la barra de
  ubicación). "Agrupar por" se modela con `GroupByChoice`.
- Efecto menor aceptado: en "Ordenar por" del menú contextual, volver a
  elegir el mismo campo ya no invierte la dirección; la dirección es una
  elección aparte (como en Finder). En las subcarpetas de la barra de
  ubicación, elegir la marcada no hace nada (ya es la siguiente miga).
- Verificado con el binario real volcando el menú: un solo "View" /
  "Visualización", todo traducido, marcas en el estado correcto. Un test
  impide volver a escribir "✓" o el ícono `checkmark` a mano. 243 tests.

## 2026-11-10 — Distribución por Homebrew (0.1.0-beta)

- El repo `dotfn/dotphin` pasa a público: un cask baja la app de una URL
  pública y los adjuntos de releases de un repo privado piden login. Antes se
  revisó el historial: sin secretos, emails ni rutas personales.
- Cask `dotphin` en `dotfn/homebrew-tap`, con el mismo estilo que `brewmenu`:
  zip del release de GitHub, `depends_on macos: :golden_gate` (macOS 27) y
  `arch: :arm64` (el binario es solo arm64), `postflight_steps` que quita la
  quarantine porque no hay Developer ID ni notarización (la firma es ad-hoc).
- El release no se marca como pre-release aunque la versión sea `-beta`:
  `brew audit --strict` rechaza pre-releases y `:github_latest` los ignora.
  La regex de livecheck acepta el sufijo (`v0.1.0-beta`).
- `CFBundleShortVersionString` solo admite números: el bundle dice `0.1.0`,
  el tag y el cask dicen `0.1.0-beta`. `LSMinimumSystemVersion` sube a 27.0
  para coincidir con el paquete.
- Release nuevo: `scripts/make_release.sh <versión>` → tag `v<versión>` →
  `gh release create` con el zip → actualizar `version` y `sha256` del cask.
- Verificado: `brew style`, `brew audit --cask --strict --online`,
  `brew livecheck`, y `brew install --cask dotfn/tap/dotphin` real; la app
  instalada abre con `open`.

## 2026-11-10 — Ícono nativo de macOS 26+ (Icon Composer)

- El ícono aparecía dentro de un cuadrado gris. Desde macOS 26, un `.icns`
  suelto que no sigue la forma del sistema queda encerrado así. El
  `AppIcon.icon` de Icon Composer estaba en el repo pero nunca se compilaba.
- `build_app_bundle.sh` corre `actool` sobre `AppIcon.icon`: genera
  `Assets.car` (el ícono que usa macOS, con la forma, sombra y brillo del
  sistema) y `AppIcon.icns` de respaldo, y el Info.plist declara
  `CFBundleIconName`.
- El dibujo traía un fondo redondeado propio, no cuadrado, con bordes
  transparentes. Se rehízo a sangre completa (fondo claro hasta el borde, la
  carpeta al 80% del lienzo) para que el sistema le aplique su forma.
- `applyAppIcon()` solo pone el ícono a mano en `swift run`, sin `.app`.
  Dentro del `.app` reemplazaba el de Assets.car por el `.icns` y volvía a
  aparecer el cuadrado gris en el Dock.
- Se borran `Assets.xcassets` y `scripts/make_icons.swift`: eran el sistema
  viejo de imágenes con margen y sombra propios. El README usa `docs/icon.png`.
- Verificado pidiendo a macOS el ícono como lo dibuja Finder
  (`NSWorkspace.icon(forFile:)`): antes, el cuadrado gris; ahora, la forma del
  sistema.

## 2026-11-10 — Terminal integrada sobre SwiftTerm (slice 22)

- El panel F4 tenía un emulador propio (`TerminalScreenBuffer`) que tiraba los
  colores, no tenía pantalla alterna (`vim`, `less`, `htop` no andaban), fijaba
  220 columnas y escribía en un `TextField` aparte (sin Tab ni Ctrl+R). Se
  reemplaza por SwiftTerm (MIT, `from: "1.99.3"`), la primera dependencia
  externa del paquete, elegida por el usuario. Descartados: libghostty (API de
  embebido no estable, build con Zig), xterm.js en WKWebView (no nativo).
- Axiom consultado: `axiom-macos` → `appkit-interop.md`.
- `EmbeddedTerminalSession` es dueña de la `DotphinTerminalView`
  (`LocalProcessTerminalView`): la shell sobrevive a ocultar el panel. Si la
  shell termina, una barra ofrece "Reiniciar", que crea una vista nueva.
- El `keyDown` de SwiftTerm no se puede sobrescribir desde otro módulo: un
  monitor local de teclado, activo solo con la terminal enfocada, le da F4/⇧F4
  al menú y marca el Intro como "el usuario ejecutó un comando".
- Shell → Dotphin: `proc_pidinfo` tras cada lote de salida (a lo sumo una
  consulta pendiente a la vez) y OSC 7 si la shell lo emite. Se compara con
  `realpath`, así una carpeta vista por un enlace (`/tmp`) no rebota como otra
  (`/private/tmp`).
- `optionAsMetaKey = false`: Option compone caracteres (la @ en teclados
  latinoamericanos), como en Terminal.app.
- Ya no se fuerzan `PROMPT`, `PROMPT_EOL_MARK` ni `nopromptsp`: eran parches
  para el emulador viejo; ahora se ve el prompt propio del usuario. `COLUMNS` y
  `LINES` se quitan del entorno para que mande el tamaño real del pty.
- Revisión independiente, corregido:
  - Rebote: con un comando ya ejecutado, cada `cd` de Dotphin hacía volver a
    la carpeta anterior (zsh escribe antes de cambiar de carpeta). Ahora se
    ignora lo que informe la shell hasta que llega al `cd` pendiente (o 3 s).
    El bug venía del emulador viejo.
  - El `cd` automático ya no se escribe dentro de `vim`, `less` o un servidor:
    solo si la shell es el grupo de primer plano (`tcgetpgrp`); si no, queda
    diferido y se manda al volver el prompt.
  - `stop()` manda SIGHUP (zsh interactivo ignora SIGTERM) y llama a
    `updateUiClosed()`; cerrar la ventana llama a `stop()`.
  - Cada panel tiene su contenedor y le presta la vista de la terminal, para
    que un F4 F4 rápido no la deje fuera.
  - OSC 7 de otro equipo (`ssh`) se ignora; `LANG` sale del idioma del
    usuario; se quitan `TERM_PROGRAM`/`ITERM_*` heredados; Intro que confirma
    texto de un método de entrada no cuenta como comando.
- Verificado con tests de la shell real, con un `ZDOTDIR` vacío para no
  depender del `~/.zshrc` del usuario: arranca en la carpeta, sigue a Dotphin
  sin rebotar (el test falla sin la corrección), espera a que termine un
  programa, `stop()` mata la shell, F4 e Intro por `NSApp.sendEvent`.
  No verificado a mano: el aspecto de colores, `vim` y el mouse en pantalla
  (este entorno no puede mirar la pantalla).

## 2026-11-11 — Relecturas en ráfaga y carga al arrancar (slice 23, issue #2)

- Registro del usuario: al arrancar, `contentsOfDirectory` de la carpeta
  personal tardó 3 s en el hilo principal; después, cientos de relecturas
  por "cambio en disco".
- Las relecturas repetidas eran varias pestañas abiertas en la carpeta
  personal: cada una seguía observando su carpeta aunque no se viera
  (`watchesCurrentDirectory` se prendía y nunca se apagaba). Ahora
  `BrowserView` lo apaga al desaparecer; al volver, la pestaña relee una vez.
- Lo que disparaba los cambios eran archivos ocultos que otras apps reescriben
  (`~/.claude.json`, con un temporal y un renombre). FSEvents pasa a eventos
  por archivo y se ignora la tanda si solo cambiaron ocultos que no se
  muestran (`.hidden` sí cuenta). Una subcarpeta "modificada" tampoco cuenta:
  es un cambio adentro de ella.
- Navegar lee en segundo plano (`DirectoryLoadRequest.runInBackground`,
  `@concurrent`; Axiom `axiom-concurrency`). Cada carga se numera y un
  resultado viejo se descarta. Mientras carga, la lista queda vacía (no se
  puede actuar sobre ítems de la carpeta anterior) y se ve "Cargando carpeta…".
  Navegar y seleccionar (carpeta contenedora, destino de un enlace,
  propiedades) usa `navigate(to:selecting:)`.
- Solo los view models de la app (`TabsViewModel`) cargan en segundo plano;
  uno suelto (tests) sigue sincrónico. `refresh()` tras una operación propia
  sigue sincrónico, para seleccionar enseguida lo recién creado.
- Descartado después de medir:
  - Evitar reasignar `items`/`error`/etc. iguales para no redibujar: con este
    Swift, `@Observable` ya no avisa si el valor es igual (verificado con
    `withObservationTracking`). Solo se conserva el chequeo de `items`,
    porque su `didSet` invalida la caché de `filteredItems`.
  - Agrupar avisos con una espera propia: los 0,3 s de `latency` de FSEvents
    ya juntan una ráfaga (el test pasa igual sin la espera).
- Los bloqueos de 400–900 ms del registro no venían de las relecturas: también
  aparecen sin ninguna cerca y coinciden con compilaciones en la máquina. Al
  arrancar queda uno de ~900 ms que ya no es de leer carpetas (la lectura en
  segundo plano tarda 8 ms); falta perfilarlo.
- Revisión independiente, corregido:
  - Al abrir o cerrar la vista dividida (o mover el panel a otra pestaña),
    SwiftUI llama al `onAppear` de la vista nueva antes que al `onDisappear`
    de la vieja: con un booleano el panel visible dejaba de observar. Ahora
    se cuentan las vistas visibles (`viewDidAppear`/`viewDidDisappear`); un
    test montado lo prueba y falla con el booleano.
  - Los eventos por archivo de todo el árbol (en `~`: cachés, navegadores)
    llegaban al hilo principal. Se filtran en una cola propia; al main actor
    solo llegan las entradas directas.
  - El indicador "Cargando carpeta…" aparece recién a los 200 ms; volver a la
    misma carpeta no vacía la lista.
  - Etiquetas, Finder info y dueño de una subcarpeta sí provocan relectura.
  - Sin relectura extra al arrancar; contadores de tests solo en DEBUG.

## 2026-11-11 — Bordes de la ventana y migas de la ruta

- Vista dividida en ventanas angostas (840–975 pt): el `HSplitView` de los
  paneles no repartía el ancho y quedaba una franja vacía a la derecha (772 pt
  en 840). Con un tamaño exacto (`fillingAvailableSpaceExactly()`, un
  `GeometryReader`) sí lo hace. No se aplica al divisor exterior: ahí el
  tamaño exacto en alto tapaba la barra de estado.
- Con el panel de información abierto el contenido necesitaba ~920 pt y en
  840 se cortaba en los dos bordes (SwiftUI lo centra). Los mínimos de los
  paneles dentro de los divisores no llegan al mínimo de la ventana, así que
  el mínimo sube a 1000 pt mientras el panel está abierto (`contentMinSize`
  agranda la ventana sola).
- Migas: `.layoutPriority(1)` (el arreglo anterior) hacía que el panel
  exigiera su ancho; ahora las migas son lo único flexible de la fila y el
  espacio clicable va de fondo. Si no entran, el desplazamiento arranca al
  final (`defaultScrollAnchor(.trailing)`) para que se vea la carpeta actual.
- Tests montados que los reproducen; la ventana restaura la sesión guardada,
  así que el test divide solo si hace falta (antes `toggleSplit` a veces
  cerraba una división restaurada y la medición salía distinta).

## 2026-11-11 — Íconos en los menús contextuales

- Pedido del usuario: íconos donde hacen falta y una opción para apagarlos,
  como Dolphin. Axiom (`axiom-design` → `liquid-glass-ref.md`): en macOS 26
  los menús muestran el ícono a la izquierda cuando el ítem usa `Label`, y
  las acciones estándar usan los símbolos del sistema (tijeras, `doc.on.doc`,
  `doc.on.clipboard`, papelera).
- `MenuItemLabel` + `Button(_:menuIcon:)` / `Menu(_:menuIcon:)` leen
  `AppSettings.showsMenuIcons` (activado; las configuraciones guardadas antes
  también lo traen activado). Opción en Configuración → Menú contextual.
- Llevan ícono las acciones de los menús contextuales de archivos, fondo de
  carpeta, ruta, barra lateral, árbol, pestañas y barra de estado. No llevan:
  casillas (`Toggle`, la marca ya es su ícono), ítems dinámicos (destinos,
  plantillas, apps de "Abrir con") ni botones de diálogos. Los íconos del
  menú "Icono de carpeta" se ven siempre: son el contenido.
- Un test comprueba que cada `menuIcon:` del código es un SF Symbol real.
- Después, a pedido del usuario, también la barra de menús (Archivo, Edición,
  Visualización, Ir, Marcadores, Acerca de): mismos símbolos que la barra de
  herramientas. La opción pasa a "Comportamiento de visualización", porque ya
  no es solo del menú contextual. Duplicar (archivo o pestaña) usa
  `square.on.square`; "pestaña nueva", `plus.square.on.square`. Los ítems
  estándar del sistema (Cortar, Copiar, Pegar…) los pone macOS y no dependen
  de esta opción.
- Los íconos no se veían: en macOS 27 AppKit oculta por defecto las imágenes
  de los ítems de menú (`preferredImageVisibility = .automatic`; ver
  `NSMenuItem.h` del SDK 27). Los ítems tenían la imagen, pero no se dibujaba.
  `MenuImageVisibility` (instalado al arrancar) escucha `didAddItem` /
  `didChangeItem` de cualquier menú de la app y pone `.visible` u `.hidden`
  según la opción; con la opción apagada también oculta los íconos que pone
  el sistema. SwiftUI no tiene modificador para esto. El test falla sin el
  coordinador (todos los ítems quedan en "automático").

## 2026-11-11 — Compartir y fila de colores en el menú contextual (como Finder)

- Pedido del usuario (y issue #6): «Compartir…» con AirDrop, Mail, Mensajes,
  y la fila de círculos de colores de Finder.
- Compartir: `ShareLink(items:)` dentro del menú; `NSHostingMenu` lo convierte
  en el ítem estándar del sistema (`_performStandardShareMenuItem`), el mismo
  de Finder. Sirve para varios archivos.
- Colores: `Picker` con `.pickerStyle(.palette)` → submenú con
  `presentationStyle = .palette`, que AppKit dibuja como la fila en línea.
  Orden de Finder (rojo… gris). Los círculos van como `Label(...).tint(color)`:
  con `foregroundStyle` el menú los convierte en plantilla y salen grises (un
  test dibuja cada círculo y mide su color). Reemplaza al submenú «Etiqueta de
  color». Volver a elegir el color actual lo quita (`tagToApply`); además, si
  hay etiqueta, una ✕ para quitarla.
- `MenuImageVisibility` deja siempre visibles las imágenes de una paleta: son
  el contenido, no un adorno, aunque se apaguen los íconos de los menús.
- No se pudo automatizar el clic: `performActionForItem` no dispara los ítems
  de `NSHostingMenu` fuera de un menú abierto de verdad.
- Carpetas etiquetadas: se ven del color de su etiqueta, como el color de
  carpeta de Dolphin (`ThumbnailLoader.icon(for:)`). El ícono del sistema se
  tiñe con mezcla "color" recortada a su silueta: conserva relieve y dibujos.
  Solo en Dotphin (no cambia el ícono en el disco). Falta en el árbol de la
  barra lateral y en la ruta: ahí solo hay URL, no `FileItem`.
- «Compartir…» pasa de `ShareLink` a `NSSharingServicePicker` abierto junto al
  ícono del archivo que se tocó (`ShareAnchor`, lo arma la vista al hacer clic
  derecho), del lado izquierdo y apuntándolo, como Finder. Sin ancla, junto
  al puntero. Se abre en el turno siguiente, con el menú ya cerrado.

## 2026-11-11 — Gesto de deslizar para el historial (como Safari)

- Las tres vistas de archivos usan `SwipeNavigationScrollView` (subclase de
  `NSScrollView`). La navegación les llega por el entorno
  (`\.swipeNavigation`, lo pone `BrowserView`), sin sumar parámetros.
- Dos dedos: `trackSwipeEvent` del sistema (rebote y animación nativos), solo
  si `NSEvent.isSwipeTrackingFromScrollEventsEnabled` (Ajustes → Trackpad →
  «Deslizar entre páginas»), el gesto empieza horizontal, sin inercia, y el
  contenido no puede desplazarse más hacia ese lado (Detalles con columnas
  anchas se desplaza primero). Hacia un lado sin historial, rebota.
- Tres dedos: `swipe(with:)`. Signos como WebKit/Safari: `deltaX` y
  `gestureAmount` positivos = atrás (la documentación y otras fuentes no
  coinciden en la dirección física; queda para verificar en el trackpad).
- Indicador: flecha en el borde que entra con el gesto y se pinta con el
  color de acento cuando soltar ya navega.
- `NSEvent.isTouchSwipeNavigationEnabled` (macOS 27) es para pantallas
  táctiles, no para el trackpad.

## 2026-11-11 — Auditoría de APIs nativas: ocultos, tipo, paquetes y sesión

Salió de una auditoría de lo que la app hacía a mano teniendo API del sistema
(issues #15 a #34). Acá, los cuatro que eran bugs.

- Ocultos (#15): `DirectoryReader` y `FolderTreeProvider` leen `isHiddenKey`.
  Además de los nombres con punto y `.hidden`, queda oculto lo que lleva la
  marca del sistema (`~/Library`, `/usr`…). El conteo de ítems de una carpeta
  usa `.skipsHiddenFiles`. El autocompletado de la barra de ubicación sigue
  mirando solo el punto: `~/Lib` + Tab tiene que completar `Library`.
- Tipo (#16): `localizedTypeDescriptionKey`, guardado en
  `FileItem.typeDescription`; `kindDescription` cae a la extensión si no se
  leyó (ítems armados a mano en los tests). Medido: ~15 ms más en `/usr/bin`
  (932 entradas).
- Paquetes (#17): `isPackageKey`. `FileItem.opensAsFolder` (carpeta que no es
  paquete) decide abrir, ordenar con las carpetas, desplegar en Detalles y los
  ítems de menú de carpeta; «Mostrar contenido del paquete» entra igual. La
  búsqueda no baja a los paquetes (`.skipsPackageDescendants`). Queda como
  carpeta para soltar, pegar adentro y «Abrir terminal aquí».
- Sesión de pestañas (#18): `TabSessionStore` guarda una sesión por ventana
  (`tabsSessions.v2`, las 12 más recientes). La ventana se identifica con
  `@SceneStorage("tabSessionID")`: si el sistema la restaura, vuelve con su
  id y sus pestañas. Sin restauración, solo la primera ventana del proceso
  retoma la última sesión usada (`claimLaunchSession`); las de ⌘N empiezan
  de cero. No se guardan las pestañas en `@SceneStorage` porque, con «Cerrar
  ventanas al salir de una app» (el valor por defecto), macOS lo descarta al
  salir y se perdería "recordar pestañas". La clave vieja
  (`tabsSessionSnapshot.v1`) se sigue leyendo como sesión inicial.
- `ArchiveService.runProcess` leía stderr después de `waitUntilExit()`: mismo
  bloqueo que el del slice 10. La salida que nadie lee va a `/dev/null`.
- Sin verificar en la app real: la restauración de varias ventanas por el
  sistema (los tests cubren `TabSessionStore` y `beginSession`, no el enganche
  con `@SceneStorage`).
