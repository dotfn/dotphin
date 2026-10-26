# Slice 8 — Ventana de preferencias — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Una ventana de preferencias nativa de macOS (`Settings`
scene) con dos ajustes reales que hoy ya existen en el código pero sin
UI para cambiarlos: el modo de vista por defecto para carpetas nunca
visitadas, y si se muestran archivos ocultos por defecto.

**Alcance recortado (ponytail), documentado como diferido, no como
bug:** "inicio" (abrir en Home vs. la carpeta de la última sesión) y
ajustes de papelera quedan afuera — lo primero necesita persistir la
última ubicación visitada (una pieza de estado nueva sin dueño claro
todavía), lo segundo depende de que la papelera exista como feature
(slice 9, todavía no construido). Este slice se limita a ajustes que ya
tienen una contraparte real en el código (`ViewProperties.mode` por
defecto, `DirectoryReader.showsHiddenFiles`).

**Arquitectura:** `AppSettings` + `AppSettingsStore` (persistido en
`UserDefaults`, mismo patrón que `ViewPropertiesStore`). `ViewPropertiesStore`
pasa a usar `appSettingsStore.settings().defaultViewMode` como default en
vez del `ViewProperties()` hardcodeado cuando una carpeta nunca fue
visitada. `BrowserViewModel` lee `appSettingsStore.settings().showsHiddenFiles`
una vez al crearse para inicializar su `DirectoryReader`.

**Tech Stack:** Swift 6.4, SwiftUI `Settings` scene (nativo de macOS).

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`

## Global Constraints

- Mismas restricciones globales de los slices 1-7.
- Cambiar un ajuste en Preferencias aplica a carpetas/ventanas nuevas
  desde ese momento — no es retroactivo sobre ventanas ya abiertas (no
  hay observación en vivo entre `Settings` y los `BrowserViewModel` ya
  instanciados). Se documenta como diferido, no se finge que es
  instantáneo.

## Review Focus

- Abrir Preferencias sin haber cambiado nada antes → debe mostrar los
  valores por defecto reales (`list`, `showsHiddenFiles = false`), no
  un estado vacío ni crashear.
- Cambiar el modo de vista por defecto y después navegar a una carpeta
  nunca visitada → esa carpeta debe abrir en el modo elegido, no en
  `list` hardcodeado.
- Cambiar "mostrar ocultos" a activado y crear un `BrowserViewModel`
  nuevo → debe listar dotfiles sin tener que tocar código.
- Una carpeta que YA tiene `ViewProperties` guardadas (de un slice
  anterior) no debe verse afectada por cambiar el default — el default
  solo aplica a carpetas sin entrada todavía.
- `AppSettingsStore` con un valor corrupto en `UserDefaults` (JSON
  roto) → debe degradar a los defaults de `AppSettings`, no crashear la
  ventana de Preferencias ni la app entera.

---

## Task 1: `AppSettings` + `AppSettingsStore`

**Files:**
- Create: `Sources/DolphinForMacOS/Models/AppSettings.swift`
- Create: `Sources/DolphinForMacOS/Services/AppSettingsStore.swift`
- Test: `Tests/DolphinForMacOSTests/AppSettingsStoreTests.swift`

**Interfaces:**
- Consume: `ViewMode` (slice 2).
- Produce:
  ```swift
  struct AppSettings: Codable, Equatable {
      var defaultViewMode: ViewMode = .list
      var showsHiddenFiles: Bool = false
  }

  struct AppSettingsStore {
      init(defaults: UserDefaults = .standard)
      func settings() -> AppSettings
      func setSettings(_ settings: AppSettings)
  }
  ```
  Key fija `"appSettings"`, JSON-encoded, igual patrón que
  `ViewPropertiesStore`. Si falta la entrada o el decode falla,
  devuelve `AppSettings()`.

- [ ] **Step 1: Tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class AppSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_settings_withNoSavedEntry_returnsDefaults() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings(), AppSettings())
    }

    func test_setThenGet_roundTrips() {
        let store = AppSettingsStore(defaults: defaults)
        var settings = AppSettings()
        settings.defaultViewMode = .icons
        settings.showsHiddenFiles = true
        store.setSettings(settings)
        XCTAssertEqual(store.settings(), settings)
    }

    func test_settings_withCorruptData_returnsDefaults() {
        defaults.set("not valid json".data(using: .utf8), forKey: "appSettings")
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings(), AppSettings())
    }
}
```

- [ ] **Step 2:** `swift test --filter AppSettingsStoreTests` → FAIL.
- [ ] **Step 3:** Implementar (idéntico patrón a `ViewPropertiesStore`, key fija en vez de por-URL).
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Models/AppSettings.swift Sources/DolphinForMacOS/Services/AppSettingsStore.swift Tests/DolphinForMacOSTests/AppSettingsStoreTests.swift
git commit -m "feat: AppSettings y AppSettingsStore"
```

---

## Task 2: Wiring en `ViewPropertiesStore` y `BrowserViewModel`

**Files:**
- Modify: `Sources/DolphinForMacOS/Services/ViewPropertiesStore.swift`
- Modify: `Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift`
- Modify: `Tests/DolphinForMacOSTests/ViewPropertiesStoreTests.swift`
- Modify: `Tests/DolphinForMacOSTests/BrowserViewModelTests.swift`

**Interfaces:**
- Consume: `AppSettingsStore`, `AppSettings` (Task 1).
- Produce:
  ```swift
  // ViewPropertiesStore
  init(defaults: UserDefaults = .standard, appSettingsStore: AppSettingsStore = AppSettingsStore())
  // properties(for:) sin entrada guardada devuelve
  // ViewProperties(mode: appSettingsStore.settings().defaultViewMode)
  // en vez de ViewProperties() a secas.
  ```
  `BrowserViewModel.init` construye su `DirectoryReader` por defecto con
  `showsHiddenFiles: AppSettingsStore().settings().showsHiddenFiles`
  cuando no se inyecta uno explícito (el parámetro `reader:` sigue
  existiendo para tests, que pueden seguir pasando uno propio sin tocar
  `AppSettingsStore`).

- [ ] **Step 1: Tests que fallan**

```swift
// En ViewPropertiesStoreTests:
func test_propertiesForNeverVisitedFolder_usesAppSettingsDefaultViewMode() {
    let appSettingsStore = AppSettingsStore(defaults: defaults)
    var settings = AppSettings()
    settings.defaultViewMode = .icons
    appSettingsStore.setSettings(settings)
    let store = ViewPropertiesStore(defaults: defaults, appSettingsStore: appSettingsStore)
    XCTAssertEqual(store.properties(for: URL(fileURLWithPath: "/tmp/never-visited")).mode, .icons)
}

func test_propertiesForAlreadyVisitedFolder_ignoresAppSettingsDefault() {
    let appSettingsStore = AppSettingsStore(defaults: defaults)
    let store = ViewPropertiesStore(defaults: defaults, appSettingsStore: appSettingsStore)
    let url = URL(fileURLWithPath: "/tmp/already-visited")
    var saved = ViewProperties()
    saved.mode = .details
    store.setProperties(saved, for: url)

    var settings = AppSettings()
    settings.defaultViewMode = .icons
    appSettingsStore.setSettings(settings)

    XCTAssertEqual(store.properties(for: url).mode, .details, "no debe pisar una carpeta ya visitada")
}
```

- [ ] **Step 2:** `swift test --filter ViewPropertiesStoreTests` → FAIL.
- [ ] **Step 3:** Implementar. `BrowserViewModel` no necesita un test nuevo
  dedicado (ya cubierto indirectamente por los tests existentes que usan
  el `reader:` default — agregar solo si al implementar se nota un hueco
  real).
- [ ] **Step 4:** PASS (todos, incluyendo slices 1-7).
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/ViewPropertiesStore.swift Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift Tests/DolphinForMacOSTests/ViewPropertiesStoreTests.swift
git commit -m "feat: ViewPropertiesStore y BrowserViewModel usan AppSettings como default"
```

---

## Task 3: Ventana de preferencias (`SettingsView`)

**Files:**
- Create: `Sources/DolphinForMacOS/Views/SettingsView.swift`
- Modify: `Sources/DolphinForMacOS/App/DolphinForMacOSApp.swift`

**Interfaces:**
- Consume: `AppSettings`, `AppSettingsStore` (Task 1).
- Produce: `struct SettingsView: View` (sin parámetros, lee/escribe su
  propio `AppSettingsStore()` internamente — es una vista de nivel de
  app, no recibe nada de afuera).

Antes de implementar, consultar `axiom-macos` (`windows.md`, `Settings`
scene) — regla del proyecto.

- [ ] **Step 1: Implementar `SettingsView`**

```swift
struct SettingsView: View {
    @State private var settings = AppSettingsStore().settings()
    private let store = AppSettingsStore()

    var body: some View {
        Form {
            Picker("Vista por defecto", selection: $settings.defaultViewMode) {
                Text("Iconos").tag(ViewMode.icons)
                Text("Lista").tag(ViewMode.list)
                Text("Detalles").tag(ViewMode.details)
            }
            Toggle("Mostrar archivos ocultos", isOn: $settings.showsHiddenFiles)
        }
        .padding(20)
        .frame(width: 350)
        .onChange(of: settings) { _, newValue in
            store.setSettings(newValue)
        }
    }
}
```

- [ ] **Step 2: Agregar la escena en `DolphinForMacOSApp`**

```swift
var body: some Scene {
    WindowGroup { ContentView() }
    Settings { SettingsView() }
}
```

- [ ] **Step 3:** `swift build` → `Build complete!`.
- [ ] **Step 4: Commit**

```bash
git add Sources/DolphinForMacOS/Views/SettingsView.swift Sources/DolphinForMacOS/App/DolphinForMacOSApp.swift
git commit -m "feat: ventana de preferencias (vista por defecto, mostrar ocultos)"
```

---

## Task 4: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests de slices 1-8 en PASS.
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo, matarlo.
- [ ] **Step 3:** sin commit si no hay cambios pendientes.
