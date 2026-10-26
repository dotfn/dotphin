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
