# Slice 2 — Vistas (iconos/lista/detalles) + zoom + orden + view properties — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Reemplazar la lista fija del slice 1 por tres modos de vista
(iconos, lista, detalles) con zoom y orden configurables, persistidos por
carpeta — igual que las "view properties" de Dolphin.

**Arquitectura:** Un `ViewProperties` (modo, campo de orden, ascendente,
nivel de zoom) por carpeta, persistido en `UserDefaults` keyeado por
`url.path`. `BrowserViewModel` expone `viewProperties` para la carpeta
actual y aplica orden/zoom antes de entregar `items` a la vista.
`FileListView` se reemplaza por un selector de 3 vistas.

**Tech Stack:** Swift 6.4, SwiftUI, `UserDefaults` (nativo, sin nueva
dependencia).

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`
**Decisiones previas:** `docs/decisions.md`

## Global Constraints

- Mismas restricciones globales del slice 1 (macOS 27+, sin sandbox, SwiftUI
  nativo, sin dependencias de terceros, consultar Axiom antes de código
  SwiftUI/macOS/diseño).
- Alcance deliberadamente recortado (ponytail): no hay agrupado
  (`grouping`) todavía, solo orden simple. Se difiere si se necesita.
- Persistencia vía `UserDefaults` (nativo) en vez de un store propio — es
  la opción más simple que cumple "persistido por carpeta"; si el volumen
  de carpetas visitadas se vuelve un problema real, se migra a un archivo
  JSON propio (no ahora, YAGNI).

## Review Focus

- Carpeta nunca visitada → debe tener view properties por defecto
  razonables (lista, orden por nombre ascendente, zoom medio), no crashear
  por falta de entrada en `UserDefaults`.
- Cambiar de modo/orden/zoom en una carpeta y volver a otra y de nuevo a la
  primera → debe recordar lo que se configuró, no resetear.
- Cambiar el modo de vista no debe perder la carpeta actual ni refrescar
  innecesariamente el filesystem (no debe re-leer el directorio solo por
  cambiar de modo).
- Orden por tamaño/fecha con carpetas mezcladas con archivos → las
  carpetas deben seguir yendo primero (ver slice 1), el criterio de orden
  dentro de cada grupo es el que cambia.
- Zoom en modo lista/detalles no debe romper el layout (texto cortado,
  filas superpuestas) en los extremos del rango.

---

## Task 1: `ViewProperties` + persistencia

**Files:**
- Create: `Sources/DolphinForMacOS/Models/ViewProperties.swift`
- Create: `Sources/DolphinForMacOS/Services/ViewPropertiesStore.swift`
- Test: `Tests/DolphinForMacOSTests/ViewPropertiesStoreTests.swift`

**Interfaces:**
- Produce:
  ```swift
  enum ViewMode: String, Codable { case icons, list, details }
  enum SortField: String, Codable { case name, size, modificationDate }

  struct ViewProperties: Codable, Equatable {
      var mode: ViewMode = .list
      var sortField: SortField = .name
      var ascending: Bool = true
      var zoomLevel: Double = 1.0 // 0.5...2.0
  }

  struct ViewPropertiesStore {
      private let defaults: UserDefaults
      init(defaults: UserDefaults = .standard)
      func properties(for url: URL) -> ViewProperties // default si no hay entrada
      func setProperties(_ properties: ViewProperties, for url: URL)
  }
  ```
  La key de `UserDefaults` es `"viewProperties.\(url.path)"`, valor
  codificado en JSON (`JSONEncoder`/`JSONDecoder`).

- [ ] **Step 1: Escribir los tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class ViewPropertiesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_propertiesForNeverVisitedFolder_returnsDefaults() {
        let store = ViewPropertiesStore(defaults: defaults)
        let props = store.properties(for: URL(fileURLWithPath: "/tmp/never-visited"))
        XCTAssertEqual(props, ViewProperties())
    }

    func test_setThenGet_roundTrips() {
        let store = ViewPropertiesStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/some-folder")
        var props = ViewProperties()
        props.mode = .icons
        props.sortField = .size
        props.ascending = false
        props.zoomLevel = 1.5
        store.setProperties(props, for: url)
        XCTAssertEqual(store.properties(for: url), props)
    }

    func test_differentFolders_haveIndependentProperties() {
        let store = ViewPropertiesStore(defaults: defaults)
        let a = URL(fileURLWithPath: "/tmp/a")
        let b = URL(fileURLWithPath: "/tmp/b")
        var propsA = ViewProperties()
        propsA.mode = .details
        store.setProperties(propsA, for: a)
        XCTAssertEqual(store.properties(for: b), ViewProperties())
        XCTAssertEqual(store.properties(for: a), propsA)
    }
}
```

- [ ] **Step 2: Correr y confirmar que fallan**

Run: `swift test --filter ViewPropertiesStoreTests`
Expected: FAIL — los tipos no existen.

- [ ] **Step 3: Implementar `ViewProperties`**

Struct `Codable`/`Equatable` con los defaults de la firma.

- [ ] **Step 4: Implementar `ViewPropertiesStore`**

JSON-encode/decode contra `UserDefaults`, key `"viewProperties.\(url.path)"`.
Si falta la entrada o falla el decode, devolver `ViewProperties()`.

- [ ] **Step 5: Correr y confirmar que pasan**

Run: `swift test --filter ViewPropertiesStoreTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/DolphinForMacOS/Models/ViewProperties.swift Sources/DolphinForMacOS/Services/ViewPropertiesStore.swift Tests/DolphinForMacOSTests/ViewPropertiesStoreTests.swift
git commit -m "feat: ViewProperties y ViewPropertiesStore persistido por carpeta"
```

---

## Task 2: Orden en `DirectoryReader` parametrizable

**Files:**
- Modify: `Sources/DolphinForMacOS/Services/DirectoryReader.swift`
- Modify: `Tests/DolphinForMacOSTests/DirectoryReaderTests.swift`

**Interfaces:**
- Consume: `SortField` (Task 1).
- Produce: `DirectoryReader.contents(of:sortField:ascending:) throws -> [FileItem]`
  (nueva sobrecarga; la firma vieja `contents(of:)` queda como
  conveniencia que llama a la nueva con `sortField: .name, ascending: true`
  para no romper los tests del slice 1).
  Las carpetas siguen yendo primero siempre (invariante del slice 1); el
  criterio de `sortField`/`ascending` solo decide el orden dentro de cada
  grupo (carpetas entre sí, archivos entre sí).

- [ ] **Step 1: Escribir los tests que fallan**

```swift
func test_contentsSortedBySizeDescending_foldersStillFirst() throws {
    try "12345".write(to: tempDir.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)
    try "1234567890".write(to: tempDir.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("zfolder"), withIntermediateDirectories: true)
    let reader = DirectoryReader()
    let names = try reader.contents(of: tempDir, sortField: .size, ascending: false).map(\.name)
    XCTAssertEqual(names, ["zfolder", "big.txt", "small.txt"])
}

func test_contentsSortedByModificationDateAscending() throws {
    let older = tempDir.appendingPathComponent("older.txt")
    let newer = tempDir.appendingPathComponent("newer.txt")
    try "x".write(to: older, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)], ofItemAtPath: older.path)
    try "x".write(to: newer, atomically: true, encoding: .utf8)
    let reader = DirectoryReader()
    let names = try reader.contents(of: tempDir, sortField: .modificationDate, ascending: true).map(\.name)
    XCTAssertEqual(names, ["older.txt", "newer.txt"])
}
```
(Agregar estos dos tests al archivo existente, dentro de la clase
`DirectoryReaderTests`.)

- [ ] **Step 2: Correr y confirmar que fallan**

Run: `swift test --filter DirectoryReaderTests`
Expected: FAIL — la sobrecarga no existe.

- [ ] **Step 3: Implementar la sobrecarga parametrizada**

Mover la lógica de `.sorted` a la nueva firma; dentro de cada grupo
(directorio/archivo) comparar por el campo pedido
(`name`: `localizedStandardCompare`; `size`: `Int64` con `nil` tratado como
`0`; `modificationDate`: `Date` con `nil` tratado como `.distantPast`),
invirtiendo si `ascending == false`. La firma vieja `contents(of:)` queda
como conveniencia.

- [ ] **Step 4: Correr toda la suite de `DirectoryReaderTests`**

Run: `swift test --filter DirectoryReaderTests`
Expected: PASS, incluyendo los 9 tests del slice 1.

- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/DirectoryReader.swift Tests/DolphinForMacOSTests/DirectoryReaderTests.swift
git commit -m "feat: DirectoryReader soporta orden por nombre/tamaño/fecha"
```

---

## Task 3: `BrowserViewModel` expone y aplica `ViewProperties`

**Files:**
- Modify: `Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift`
- Modify: `Tests/DolphinForMacOSTests/BrowserViewModelTests.swift`

**Interfaces:**
- Consume: `ViewPropertiesStore`, `ViewProperties` (Task 1),
  `DirectoryReader.contents(of:sortField:ascending:)` (Task 2).
- Produce (agrega a la clase existente, no rompe lo del slice 1):
  ```swift
  private(set) var viewProperties: ViewProperties

  init(startingAt url: URL, reader: DirectoryReader = DirectoryReader(), store: ViewPropertiesStore = ViewPropertiesStore())

  func setViewMode(_ mode: ViewMode)
  func setSort(field: SortField, ascending: Bool)
  func setZoomLevel(_ level: Double)
  ```
  Cambiar modo de vista NO vuelve a leer el filesystem (solo cambia
  `viewProperties.mode` y persiste); cambiar orden sí vuelve a pedir
  `items` con el nuevo criterio sin volver a golpear disco si ya se tienen
  los `FileItem` en memoria — basta con reordenar el array ya cargado, no
  hace falta un segundo `reader.contents(of:)`. `navigate(to:)` carga
  `viewProperties` de la nueva carpeta desde el store antes de leer.

- [ ] **Step 1: Escribir los tests que fallan**

```swift
func test_init_loadsViewPropertiesForStartingFolder() throws {
    let store = ViewPropertiesStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    var saved = ViewProperties()
    saved.mode = .icons
    store.setProperties(saved, for: tempDir)
    let vm = BrowserViewModel(startingAt: tempDir, store: store)
    XCTAssertEqual(vm.viewProperties.mode, .icons)
}

func test_setViewMode_persistsAndDoesNotRereadDisk() throws {
    try "a".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let store = ViewPropertiesStore(defaults: suite)
    let vm = BrowserViewModel(startingAt: tempDir, store: store)
    try FileManager.default.removeItem(at: tempDir.appendingPathComponent("a.txt"))
    vm.setViewMode(.icons)
    XCTAssertEqual(vm.viewProperties.mode, .icons)
    XCTAssertEqual(vm.items.map(\.name), ["a.txt"], "no debió re-leer el disco al cambiar el modo")
    XCTAssertEqual(store.properties(for: tempDir).mode, .icons)
}

func test_setSort_reordersWithoutError() throws {
    try "12345".write(to: tempDir.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)
    try "1234567890".write(to: tempDir.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.setSort(field: .size, ascending: false)
    XCTAssertEqual(vm.items.map(\.name), ["big.txt", "small.txt"])
}

func test_setZoomLevel_persists() throws {
    let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let store = ViewPropertiesStore(defaults: suite)
    let vm = BrowserViewModel(startingAt: tempDir, store: store)
    vm.setZoomLevel(1.8)
    XCTAssertEqual(vm.viewProperties.zoomLevel, 1.8)
    XCTAssertEqual(store.properties(for: tempDir).zoomLevel, 1.8)
}
```

- [ ] **Step 2: Correr y confirmar que fallan**

Run: `swift test --filter BrowserViewModelTests`
Expected: FAIL.

- [ ] **Step 3: Implementar**

`load(_:)` pasa a tomar `viewProperties.sortField`/`ascending` al llamar
al reader. `navigate(to:)` hace `viewProperties = store.properties(for: url)`
antes de `load`. `setViewMode` solo actualiza+persiste, no llama a
`load`/`reader`. `setSort` actualiza+persiste y reordena `items` en
memoria con la misma función de comparación que usa `DirectoryReader`
(extraer un comparador compartido si hace falta para no duplicar lógica —
ver Task 2). `setZoomLevel` solo actualiza+persiste.

- [ ] **Step 4: Correr y confirmar que pasan**

Run: `swift test --filter BrowserViewModelTests`
Expected: PASS, incluyendo los 4 tests del slice 1.

- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift Tests/DolphinForMacOSTests/BrowserViewModelTests.swift
git commit -m "feat: BrowserViewModel aplica y persiste ViewProperties"
```

---

## Task 4: Vistas de iconos y detalles + selector de modo + zoom

**Files:**
- Create: `Sources/DolphinForMacOS/Views/IconGridView.swift`
- Create: `Sources/DolphinForMacOS/Views/DetailsListView.swift`
- Create: `Sources/DolphinForMacOS/Views/ViewModePicker.swift`
- Modify: `Sources/DolphinForMacOS/Views/BrowserView.swift`

**Interfaces:**
- Consume: `FileItem` (slice 1), `ViewProperties`/`ViewMode` (Task 1),
  `BrowserViewModel` (Task 3).
- Produce:
  ```swift
  struct IconGridView: View {
      let items: [FileItem]
      let zoomLevel: Double
      let onOpen: (FileItem) -> Void
  }

  struct DetailsListView: View {
      let items: [FileItem]
      let onOpen: (FileItem) -> Void
  }

  struct ViewModePicker: View {
      @Binding var mode: ViewMode
  }
  ```

Antes de implementar, consultar `axiom-swiftui` (containers-ref.md, grids
y `Table`) y `axiom-macos` (Table en macOS) — regla del proyecto.

- [ ] **Step 1: Implementar `IconGridView`**

`LazyVGrid` con columnas de ancho adaptativo escaladas por `zoomLevel`
(`GridItem(.adaptive(minimum: 64 * zoomLevel))`), ícono grande (SF Symbol
`folder.fill`/`doc.fill`) + nombre debajo, `.onTapGesture(count: 2)` llama
`onOpen`.

- [ ] **Step 2: Implementar `DetailsListView`**

`Table(items)` (macOS) con columnas Nombre, Tamaño (formateado con
`ByteCountFormatter`, vacío para carpetas), Modificado (formateado con
`DateFormatter`/`Date.formatted()`). Doble-click en una fila llama
`onOpen` (usar `.contextMenu(forSelectionType:menu:primaryAction:)` o un
`onTapGesture(count: 2)` sobre la fila, lo que compile más simple con
`Table`).

- [ ] **Step 3: Implementar `ViewModePicker`**

`Picker("Vista", selection: $mode) { ... }.pickerStyle(.segmented)` con un
ícono por modo (`square.grid.2x2` iconos, `list.bullet` lista,
`tablecells` detalles).

- [ ] **Step 4: Integrar en `BrowserView`**

Agregar `ViewModePicker` y un `Slider` de zoom (rango 0.5...2.0) a la
barra superior (junto al breadcrumb). Según `viewModel.viewProperties.mode`,
mostrar `IconGridView`, `FileListView` (la del slice 1, sigue siendo el
modo "list") o `DetailsListView` — el `onOpen` de los tres sigue siendo
"si `isDirectory`, `viewModel.navigate(to:)`". El `Slider` de zoom solo se
muestra en modo iconos (no aplica a lista/detalles en este slice).

- [ ] **Step 5: Verificar que compila**

Run: `swift build`
Expected: `Build complete!` sin errores.

- [ ] **Step 6: Commit**

```bash
git add Sources/DolphinForMacOS/Views/IconGridView.swift Sources/DolphinForMacOS/Views/DetailsListView.swift Sources/DolphinForMacOS/Views/ViewModePicker.swift Sources/DolphinForMacOS/Views/BrowserView.swift
git commit -m "feat: vistas de iconos y detalles, selector de modo y zoom"
```

---

## Task 5: Suite completa + verificación manual

**Files:** ninguno nuevo — solo verificación.

- [ ] **Step 1: Correr toda la suite**

Run: `swift test`
Expected: todos los tests de slice 1 + slice 2 en PASS.

- [ ] **Step 2: Build y smoke run**

Run: `swift build && swift run &` (matar el proceso después de confirmar
que levanta sin crashear).
Expected: build limpio, proceso vivo.

- [ ] **Step 3: Commit si algo quedó pendiente**

Si no hay cambios pendientes, no hace falta commit — este task es solo
verificación de cierre de slice.
