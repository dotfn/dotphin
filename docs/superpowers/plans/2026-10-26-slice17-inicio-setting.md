# Slice 17 — Setting de ubicación de inicio ("inicio") — Plan

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Cerrar la parte de "inicio" que el slice 8 dejó afuera al
recortar el alcance original de "vistas, inicio, papelera" a solo
"vistas" (en ese momento no había ningún feature al que atar la
ubicación de inicio). Ahora sí hay uno obvio: dónde abre la app al
lanzarla. "Papelera" como setting queda fuera de este slice — se
reconsidera y se concluye en Review Focus/decisions.md, no se agrega
una casilla sin un comportamiento real detrás.

**Arquitectura:** `AppSettings` gana `startupLocation: StartupLocation`
(enum: `.home`, `.desktop`, `.custom`) + `customStartupPath: String?`.
Una extensión computa `startupURL: URL` resolviendo el enum a una URL
real, con fallback seguro a home si la carpeta personalizada no existe
o es nil — esta es la única lógica real de este slice y la que se
testea. `ContentView` usa `AppSettingsStore().settings().startupURL`
en vez de `FileManager.default.homeDirectoryForCurrentUser` al crear
el `TabsViewModel` inicial. `SettingsView` gana un `Picker` de 3
opciones + un botón "Elegir carpeta…" (con `NSOpenPanel`, sin test
automático — interacción de UI del sistema, mismo precedente que el
resto de este proyecto) que solo se habilita cuando la opción es
"Carpeta personalizada".

**Tech Stack:** Swift 6.4, SwiftUI + AppKit (`NSOpenPanel`). Sin
dependencias nuevas.

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`;
`docs/decisions.md` (entrada del slice 8, que dejó "inicio" pendiente).

## Global Constraints

- Mismas restricciones globales de los slices anteriores.
- El fallback a home debe ser total: una ruta personalizada borrada,
  inaccesible, o nunca configurada nunca debe dejar la app sin abrir
  o abrir en un error — siempre hay una URL válida.
- No se agrega ningún setting de "papelera" en este slice — se
  concluye explícitamente en decisions.md por qué no hay nada
  significativo que agregar ahí todavía (la confirmación antes de
  vaciar ya es incondicional, y volverla opcional sería debilitar una
  protección contra pérdida de datos, no un setting neutral).

## Review Focus

- Carpeta personalizada configurada y luego borrada del disco antes de
  reabrir la app: debe caer a home sin crashear ni mostrar un folder
  roto.
- Cambiar la ubicación de inicio en Settings NO debe mover la pestaña
  ya abierta — solo afecta el próximo lanzamiento de la app (esto ya
  es el comportamiento implícito al no re-crear `tabsViewModel`
  dinámicamente, pero conviene que el reviewer lo confirme explícito).

---

## Task 1: `AppSettings.startupURL` (lógica pura, testeable)

**Files:**
- Modify: `Sources/DolphinForMacOS/Models/AppSettings.swift`
- Test: `Tests/DolphinForMacOSTests/AppSettingsStoreTests.swift`

**Interfaces:**
- Produce:
  ```swift
  enum StartupLocation: String, Codable, CaseIterable {
      case home, desktop, custom
  }
  extension AppSettings {
      var startupURL: URL
  }
  ```

- [ ] **Step 1: Tests que fallan**

```swift
func test_startupURL_home_isHomeDirectory() {
    var settings = AppSettings()
    settings.startupLocation = .home
    XCTAssertEqual(settings.startupURL, FileManager.default.homeDirectoryForCurrentUser)
}

func test_startupURL_desktop_isDesktopFolder() {
    var settings = AppSettings()
    settings.startupLocation = .desktop
    XCTAssertEqual(
        settings.startupURL,
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    )
}

func test_startupURL_customExistingPath_usesThatPath() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    var settings = AppSettings()
    settings.startupLocation = .custom
    settings.customStartupPath = tempDir.path

    XCTAssertEqual(settings.startupURL.standardizedFileURL.path, tempDir.standardizedFileURL.path)
}

func test_startupURL_customMissingPath_fallsBackToHome() {
    var settings = AppSettings()
    settings.startupLocation = .custom
    settings.customStartupPath = "/no/existe/esta/carpeta/\(UUID().uuidString)"

    XCTAssertEqual(settings.startupURL, FileManager.default.homeDirectoryForCurrentUser)
}

func test_startupURL_customWithNilPath_fallsBackToHome() {
    var settings = AppSettings()
    settings.startupLocation = .custom
    settings.customStartupPath = nil

    XCTAssertEqual(settings.startupURL, FileManager.default.homeDirectoryForCurrentUser)
}
```

- [ ] **Step 2:** `swift test --filter AppSettingsStoreTests` → FAIL.
- [ ] **Step 3:** Implementar `StartupLocation`, los dos campos nuevos
  en `AppSettings` (con default `.home`/`nil` para no romper la
  decodificación de settings ya guardados — `Codable` con valores
  default en `struct` ya maneja esto si los campos nuevos tienen
  `init` por defecto, confirmar con el test de decodificación legacy
  si el existente no lo cubre ya).
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Models/AppSettings.swift Tests/DolphinForMacOSTests/AppSettingsStoreTests.swift
git commit -m "feat: AppSettings.startupURL (ubicación de inicio configurable)"
```

---

## Task 2: Wiring en `ContentView` + UI en `SettingsView`

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/ContentView.swift`
- Modify: `Sources/DolphinForMacOS/Views/SettingsView.swift`

**Interfaces:**
- Consume: `AppSettings.startupURL` (Task 1).

- [ ] **Step 1:** En `ContentView`, cambiar el `startingAt:` del
  `TabsViewModel` inicial de `FileManager.default.homeDirectoryForCurrentUser`
  a `AppSettingsStore().settings().startupURL`.
- [ ] **Step 2:** En `SettingsView`, agregar un `Picker` de
  `StartupLocation` ("Inicio", "Escritorio", "Carpeta personalizada") y,
  cuando la selección es `.custom`, un botón "Elegir carpeta…" que abre
  un `NSOpenPanel` (`canChooseDirectories = true`,
  `canChooseFiles = false`) y guarda `customStartupPath` al elegir.
- [ ] **Step 3:** `swift build` → `Build complete!` (sin test
  automático para el `NSOpenPanel` — interacción real del sistema,
  mismo precedente que el resto del proyecto).
- [ ] **Step 4: Commit**

```bash
git add Sources/DolphinForMacOS/Views/ContentView.swift Sources/DolphinForMacOS/Views/SettingsView.swift
git commit -m "feat: UI de ubicación de inicio en Settings + wiring — slice 17 completo"
```

---

## Task 3: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests en PASS.
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo,
  matarlo.
