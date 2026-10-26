# Dolphin para macOS — Documento de diseño

Estado: borrador para revisión
Fecha: 2026-10-25

## Intención y porqué

El usuario es usuario diario de Linux y de Dolphin (KDE), y considera que Finder es
un mal producto de forma transversal (navegación, paneles, opciones, comodidad).
El objetivo es construir una app nativa de macOS que replique a detalle las
funcionalidades de exploración de archivos de Dolphin — tanto en comportamiento
(navegación local y de dispositivos conectados) como en superficie visual —
adaptada al lenguaje de diseño de Apple (HIG, Liquid Glass) en lugar de clonar
literalmente la UI de KDE.

No es un side-project para probar una idea: es la herramienta que el usuario
quiere usar todos los días en vez de Finder. Por eso el desarrollo es
incremental y vertical — cada slice debe compilar y poder probarse en la app
real antes de pasar al siguiente, nunca "todo el diseño primero, todo el código
después".

## Objetivos

- Paridad funcional con Dolphin en exploración de archivos: navegación con
  breadcrumb editable, vistas de iconos/lista/detalles, pestañas, panel
  dividido (split view), panel de marcadores/dispositivos (Places), panel de
  carpetas (árbol), panel de información (metadata/preview), filtro en vivo,
  barra de estado, búsqueda, papelera, menú contextual con acciones de
  archivo, configuración persistente por carpeta de las "view properties".
- Verse y comportarse como una app nativa de macOS 26: SwiftUI, Liquid Glass,
  SF Symbols, tipografía del sistema — no una réplica pixel-a-pixel de KDE.
- Acceso real a volúmenes montados (discos externos, USB, SD) sin las
  limitaciones de un sandbox de App Store.
- Explorar dispositivos móviles conectados (iPhone, Android) como ubicaciones
  navegables, con el entendimiento de que el alcance real depende de lo que
  el sistema permite (ver Riesgos).
- Cada incremento vertical (slice) es compilable, ejecutable y probable por
  el usuario de inmediato — no hay fase de "solo backend" o "solo diseño".
- Cada decisión de arquitectura y de producto queda documentada a medida que
  se toma, no al final.

## No-objetivos

- No es compatible con App Store (ver Restricciones de distribución).
- No se busca compatibilidad con macOS anterior a 26 — no hay ramas
  `@available` para versiones viejas.
- No se replican partes de Dolphin ajenas a exploración de archivos y
  dispositivos (no hay plan de clonar, por ejemplo, integración con Baloo,
  feedback de usuario/telemetría de KDE, ni el sistema de paquetes de KDE).
- No se busca ser un file manager multiplataforma ni reusar código con Linux.

## Anti-objetivos

(Cosas que harían fracasar el proyecto aunque "funcione".)

- Que termine sintiéndose como un puerto de Qt/KDE en vez de una app de
  macOS — widgets, animaciones o jerarquía visual que no respeten HIG.
- Que el desarrollo se estanque meses en un slice "perfecto" antes de poder
  probarlo. El valor del enfoque vertical se pierde si un slice tarda
  semanas en ser ejecutable.
- Que por perseguir paridad total con Dolphin se termine copiando opciones o
  menús que Dolphin mismo consideraría "intrusivos" para el usuario promedio
  (ver la filosofía de Dolphin en su propio README: cada opción tiene costo).

## Restricciones

- **Plataforma objetivo:** solo la última versión de macOS. La intención del
  usuario era "la última, sin guards hacia atrás" — al verificar el
  toolchain real de esta máquina (`xcodebuild -version`) resultó ser Xcode
  27.1 / SDK macOS 27.0, no 26. Se fija en macOS 27+ en vez de 26 para ser
  consistente con la intención real. Ver `docs/decisions.md`.
- **Distribución:** la app corre solo en esta Mac, lanzada desde Xcode
  (ad-hoc/sin firmar), **sin** App Sandbox. No hay pipeline de Developer ID
  ni notarización mientras no haga falta mover la app a otra máquina o
  compartirla — se agrega después sin tocar código si llega ese caso. Sin
  sandbox sigue siendo necesario para listar `/Volumes`, leer/escribir sin
  bookmarks con scope de seguridad, montar/desmontar.
- **TCC (privacidad de macOS):** quitar el sandbox no quita las protecciones
  de TCC. Carpetas como Desktop/Documents/Downloads y el acceso a
  volúmenes removibles siguen disparando el diálogo de permiso del sistema
  la primera vez, y navegar fuera de eso en general requiere que el usuario
  otorgue Full Disk Access a la app en Configuración del Sistema. El slice 1
  tiene que asumir esto desde el día 1 (pedir el permiso o degradar con un
  estado claro si falta, no fallar en silencio con una carpeta vacía).
- **Dependencias de terceros:** se evita agregar una por defecto. Se prefiere
  el framework nativo de Apple aunque entregue una versión más chica de la
  feature (ej. lanzar Terminal.app en vez de embeber un emulador de
  terminal). Una dependencia de terceros solo entra si, llegado ese slice,
  no hay forma razonable de lograrlo con frameworks nativos — se documenta
  el motivo en `docs/decisions.md` en ese momento.
- **Stack de UI:** SwiftUI nativo como default. Se cae a AppKit
  (`NSViewRepresentable`/`NSHostingView`) solo en puntos puntuales donde
  SwiftUI no alcanza en rendimiento o control (ej. posiblemente la vista de
  iconos con carpetas de decenas de miles de archivos, o drag & drop
  avanzado). Cada caída a AppKit se documenta en el log de decisiones con el
  motivo.
- **Un solo desarrollador, desarrollo incremental:** el orden de los slices
  prioriza "algo que se pueda abrir y tocar" sobre completitud de cualquier
  pieza individual.

## Riesgos / cosas que no están garantizadas

- **Exploración de iPhone:** iOS no expone un filesystem genérico a apps de
  terceros en macOS. Lo que es viable de forma oficial es: fotos vía
  `ImageCaptureCore` (igual que la app Image Capture), y carpetas de "File
  Sharing" expuestas explícitamente por apps de terceros instaladas en el
  iPhone (lo que Finder muestra bajo "Files"). Un árbol de archivos completo
  del iPhone como lo tendría una carpeta local **no es posible** sin APIs
  privadas. Esto se trata como un slice tardío y acotado a lo que es
  oficialmente posible, no como "explorar el iPhone como si fuera un disco".
- **Exploración de Android (MTP):** macOS no tiene soporte nativo de MTP.
  Implementarlo requiere hablar USB/MTP a bajo nivel (no hay framework de
  Apple para esto) o depender de una librería de terceros. Antes de
  comprometerse a este slice hace falta un spike de investigación dedicado;
  se marca en el roadmap como "spike primero, feature después".
- **Terminal embebido:** macOS no tiene un framework de emulación de
  terminal del sistema como VTE en Linux. La opción realista es una librería
  de terceros (ej. SwiftTerm, open source) o lanzar Terminal.app apuntando
  al directorio actual. Se decide en el momento de abordar ese slice, no
  ahora.

## Decisiones ya tomadas

| Decisión | Elegido | Motivo |
|---|---|---|
| macOS mínimo | 27+ únicamente (corregido de 26 al verificar el toolchain real) | Simplicidad, Liquid Glass completo desde el día 1, es herramienta personal |
| Distribución | Solo esta Mac, desde Xcode, sin sandbox | Un file manager serio necesita acceso real al filesystem; sin otra máquina de por medio, notarización no aporta nada todavía |
| UI stack | SwiftUI nativo, AppKit puntual | Balance entre velocidad de desarrollo y control cuando se necesite |
| Dispositivos en Places | Volúmenes locales/USB + móviles (iPhone/Android, con las limitaciones de Riesgos) | Pedido explícito del usuario |
| Primer slice vertical | Ventana con sidebar de Places + navegador central desde el inicio | Pedido explícito del usuario — no arrancar sin sidebar |

## Mapa de referencia: módulos de Dolphin → equivalente en macOS

Extraído de leer el código fuente real de Dolphin (`src/`), no de memoria.
Sirve como mapa de qué construir en cada slice, no es parte del compromiso
de alcance de este documento.

| Módulo Dolphin (KDE) | Qué hace | Equivalente en macOS |
|---|---|---|
| `dolphinmainwindow` + `dolphintabwidget/tabpage/tabbar` | Ventana con pestañas, cada pestaña con split view | `WindowGroup`/`NavigationSplitView` + modelo de pestañas propio |
| `DolphinViewContainer` + `DolphinUrlNavigator` | Panel con breadcrumb editable | Vista propia de breadcrumb (SwiftUI) + path field editable |
| `DolphinView` + `kitemviews` | Vistas icono/lista/detalles, zoom, orden, agrupado, view properties por carpeta | `LazyVGrid` (iconos), `Table`/`List` (detalles), persistidas vía `FileManager` extended attributes o un store propio |
| `panels/places` | Marcadores + volúmenes montados | Sidebar con `FileManager`/`NSWorkspace` para volúmenes, store propio para marcadores |
| `panels/folders` | Árbol de carpetas | `List` con `OutlineGroup` |
| `panels/information` | Metadata/preview del seleccionado | `QuickLookThumbnailing` + metadata vía `FileManager`/`URLResourceValues` |
| `panels/terminal` | Terminal embebido | Ver Riesgos — decisión diferida |
| `filterbar` | Filtro en vivo | `TextField` + filtrado del modelo en memoria |
| `statusbar` | Conteo, espacio libre, zoom | Vista propia con `URLResourceValues.volumeAvailableCapacityKey` |
| `itemactions` + menú contextual | Acciones de archivo, servicios de terceros | `Menu`/`ContextMenu` + `NSWorkspace` para "Open With", `NSSharingService` |
| `search` (Baloo) | Búsqueda indexada | `NSMetadataQuery` (Spotlight) |
| `trash` | Papelera como ubicación | `FileManager.trashItem` + enumerar `~/.Trash` |
| versioncontrol (git overlay) | Badges de estado git | Shell-out a `git status --porcelain`, cacheado por carpeta |
| `settings` (kcfg) | Ventana de preferencias | `Settings` scene de SwiftUI + `@AppStorage`/store propio |

## Proceso de desarrollo y documentación

Pedido explícito del usuario: no esperar a tener todo decidido para poder
compilar y probar, y dejar constancia de las decisiones a medida que se
toman. Esto se resuelve con:

- `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md` (este archivo):
  el diseño aprobado, no cambia salvo que el alcance cambie de verdad.
- `docs/decisions.md`: log append-only. Cada vez que se tome una decisión no
  trivial durante un slice (una librería, una caída a AppKit, un cambio de
  alcance) se agrega una entrada con fecha, decisión y motivo. Se crea junto
  con el primer slice.
- Cada slice se implementa con su propio plan corto (vía
  `superpowers:writing-plans`) y termina en un estado compilable y probable
  en la app real antes de pasar al siguiente.
- Commits de git por slice, no por archivo.

## Roadmap de slices verticales (orden, no estimación de tiempo)

1. Ventana principal + sidebar de Places (marcadores estáticos + volúmenes
   montados reales) + navegador central de un solo panel (breadcrumb
   editable + vista de lista/iconos) sobre el filesystem local real.
2. Vistas: iconos/lista/detalles completas, zoom, orden, agrupado, "view
   properties" persistidas por carpeta.
3. Pestañas + split view (dos paneles por pestaña).
4. Panel de información (preview + metadata) dockable.
5. Filtro en vivo + barra de estado.
6. Operaciones de archivo: copiar/mover/renombrar/eliminar (a papelera),
   nuevo archivo/carpeta, menú contextual, "Open With". Es el único slice
   que toca archivos reales de forma destructiva: lleva confirmación antes
   de borrar/mover y un test unitario mínimo de la capa de operaciones
   (no alcanza con "lo probé a mano" como en los slices de navegación/UI).
7. Panel de carpetas (árbol) + búsqueda (Spotlight).
8. Ventana de preferencias (vistas, inicio, papelera).
9. Papelera como ubicación navegable (ver, restaurar, vaciar).
10. Overlays de control de versiones (git).
11. Soporte más profundo de volúmenes externos (expulsar, info de disco).
12. Dispositivos móviles — empieza con un spike de investigación de alcance
    real (ver Riesgos) antes de comprometer diseño. **Hecho
    (2026-10-26): spike completo, sin código.** Conclusión en
    `docs/decisions.md` — ni iPhone (solo fotos vía ImageCaptureCore, un
    modelo de datos aparte de `FileItem`; "Archivos" de Finder usa APIs
    privadas) ni Android (sin framework de MTP nativo en macOS) encajan
    en la arquitectura de esta app sin APIs privadas o una dependencia
    de terceros. Diferido indefinidamente, no es un bug ni una feature
    pendiente.
13. Terminal embebido — decisión de enfoque en el momento, ver Riesgos.
14. Pasada de pulido: adopción de Liquid Glass, accesibilidad, Quick Look,
    drag & drop entre paneles y con Finder.

## Lo que queda a criterio del builder

- Estructura exacta de archivos/paquetes del proyecto Xcode.
- Nombre de producto y bundle identifier definitivos (se parte de un
  placeholder, el usuario lo cambia cuando quiera en Signing & Capabilities).
- Diseño concreto de cada vista SwiftUI dentro de cada slice (se decide con
  `axiom-swiftui`/`axiom-macos`/`axiom-design` al momento de construir cada
  slice, no de antemano).
- Modelo de datos interno para representar archivos/carpetas/volúmenes.
- Elección final de librería para terminal embebido, si se llega a ese
  slice.
- Cualquier decisión marcada explícitamente como diferida en la sección de
  Riesgos.
