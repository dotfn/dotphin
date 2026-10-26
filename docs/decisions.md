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
