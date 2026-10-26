# Slice 5 — Filtro en vivo + barra de estado — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Filtro de texto en vivo sobre la carpeta actual (por
nombre, case-insensitive) y una barra de estado con conteo de ítems y
espacio libre del volumen.

**Arquitectura:** `BrowserViewModel` gana `filterText` (stored) y
`filteredItems` (computed sobre `items`). Las 3 vistas de listado pasan
a recibir `filteredItems` en vez de `items`. `VolumeInfoProvider` es un
servicio sin estado para el espacio libre.

**Tech Stack:** Swift 6.4, SwiftUI, `URLResourceValues` nativo.

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`

## Global Constraints

- Mismas restricciones globales de los slices 1-4.
- El filtro no vuelve a leer el filesystem — filtra en memoria sobre
  `items` ya cargado (igual criterio que el cambio de modo de vista del
  slice 2).
- Navegar a otra carpeta limpia el filtro (si no, "ya no hay nada" puede
  confundirse con una carpeta vacía real).

## Review Focus

- Filtro que no matchea nada → la vista debe mostrar "sin resultados",
  nunca confundirse visualmente con una carpeta vacía real.
- Filtro con mayúsculas/minúsculas mezcladas → debe matchear
  case-insensitive.
- Navegar a otra carpeta con un filtro activo → el filtro se limpia, no
  se aplica silenciosamente a la carpeta nueva.
- Volumen cuyo espacio libre no se puede leer (por ejemplo, un volumen
  recién expulsado) → la barra de estado debe degradar a un placeholder,
  no crashear ni mostrar basura.
- El conteo de la barra de estado con filtro activo debe reflejar los
  ítems filtrados, no el total sin filtrar (para que tenga sentido con lo
  que se ve en pantalla).

---

## Task 1: `filterText` + `filteredItems` en `BrowserViewModel`

**Files:**
- Modify: `Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift`
- Modify: `Tests/DolphinForMacOSTests/BrowserViewModelTests.swift`

**Interfaces:**
- Produce:
  ```swift
  var filterText: String = ""
  var filteredItems: [FileItem] { /* items filtrado por filterText si no está vacío */ }
  ```
  `navigate(to:)` resetea `filterText = ""`.

- [ ] **Step 1: Tests que fallan**

```swift
func test_filteredItems_withEmptyFilter_returnsAllItems() throws {
    try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "x".write(to: tempDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)
    XCTAssertEqual(vm.filteredItems.count, 2)
}

func test_filteredItems_matchesCaseInsensitiveSubstring() throws {
    try "x".write(to: tempDir.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)
    try "x".write(to: tempDir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.filterText = "report"
    XCTAssertEqual(vm.filteredItems.map(\.name), ["Report.txt"])
}

func test_filteredItems_noMatch_returnsEmpty() throws {
    try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.filterText = "zzz"
    XCTAssertEqual(vm.filteredItems, [])
}

func test_navigate_clearsFilterText() throws {
    let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.filterText = "algo"
    vm.navigate(to: sub)
    XCTAssertEqual(vm.filterText, "")
}
```

- [ ] **Step 2:** `swift test --filter BrowserViewModelTests` → FAIL.
- [ ] **Step 3:** Implementar. `filteredItems` usa
  `items.filter { $0.name.localizedCaseInsensitiveContains(filterText) }`
  cuando `!filterText.isEmpty`, si no devuelve `items` tal cual.
- [ ] **Step 4:** PASS (todos, incluyendo slices 1-4).
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift Tests/DolphinForMacOSTests/BrowserViewModelTests.swift
git commit -m "feat: filtro en vivo (filterText/filteredItems) en BrowserViewModel"
```

---

## Task 2: `VolumeInfoProvider`

**Files:**
- Create: `Sources/DolphinForMacOS/Services/VolumeInfoProvider.swift`
- Test: `Tests/DolphinForMacOSTests/VolumeInfoProviderTests.swift`

**Interfaces:**
- Produce:
  ```swift
  struct VolumeInfoProvider {
      func availableCapacity(for url: URL) -> Int64?
  }
  ```

- [ ] **Step 1: Tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class VolumeInfoProviderTests: XCTestCase {
    func test_availableCapacity_forRealPath_returnsPositiveValue() {
        let provider = VolumeInfoProvider()
        let capacity = provider.availableCapacity(for: FileManager.default.temporaryDirectory)
        XCTAssertNotNil(capacity)
        XCTAssertTrue((capacity ?? 0) > 0)
    }

    func test_availableCapacity_forNonExistentPath_returnsNil() {
        let provider = VolumeInfoProvider()
        let missing = URL(fileURLWithPath: "/this/does/not/exist/at/all")
        XCTAssertNil(provider.availableCapacity(for: missing))
    }
}
```

- [ ] **Step 2:** `swift test --filter VolumeInfoProviderTests` → FAIL.
- [ ] **Step 3:** Implementar con
  `try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity.map(Int64.init)`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/VolumeInfoProvider.swift Tests/DolphinForMacOSTests/VolumeInfoProviderTests.swift
git commit -m "feat: VolumeInfoProvider"
```

---

## Task 3: `FilterBarView` + `StatusBarView` + wiring

**Files:**
- Create: `Sources/DolphinForMacOS/Views/FilterBarView.swift`
- Create: `Sources/DolphinForMacOS/Views/StatusBarView.swift`
- Modify: `Sources/DolphinForMacOS/Views/BrowserView.swift`

**Interfaces:**
- Consume: `VolumeInfoProvider` (Task 2), `BrowserViewModel.filterText/filteredItems` (Task 1).
- Produce:
  ```swift
  struct FilterBarView: View { @Binding var text: String }
  struct StatusBarView: View { let itemCount: Int; let totalCount: Int; let availableCapacity: Int64? }
  ```

- [ ] **Step 1: `FilterBarView`**

`TextField("Filtrar...", text: $text)` + botón "x" para limpiar
(visible solo si `!text.isEmpty`).

- [ ] **Step 2: `StatusBarView`**

Texto: `"\(itemCount) ítems"` si `itemCount == totalCount`, si no
`"\(itemCount) de \(totalCount) ítems"`. A la derecha, espacio libre
formateado con `ByteCountFormatter` si `availableCapacity != nil`, si no
`"—"`.

- [ ] **Step 3: Wiring en `BrowserView`**

Las 3 vistas de listado pasan a recibir `viewModel.filteredItems` en vez
de `viewModel.items`. Agregar `FilterBarView(text: Binding(get: {
viewModel.filterText }, set: { viewModel.filterText = $0 }))` debajo del
breadcrumb, y `StatusBarView(itemCount: viewModel.filteredItems.count,
totalCount: viewModel.items.count, availableCapacity:
VolumeInfoProvider().availableCapacity(for: viewModel.currentURL))` al
fondo de `BrowserView`. Si `filteredItems.isEmpty && !filterText.isEmpty`,
mostrar `Text("Sin resultados")` en vez de la lista vacía (para no
confundir con una carpeta realmente vacía).

- [ ] **Step 4:** `swift build` → `Build complete!`.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Views/FilterBarView.swift Sources/DolphinForMacOS/Views/StatusBarView.swift Sources/DolphinForMacOS/Views/BrowserView.swift
git commit -m "feat: FilterBarView y StatusBarView integrados en BrowserView"
```

---

## Task 4: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests de slices 1-5 en PASS.
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo, matarlo.
- [ ] **Step 3:** sin commit si no hay cambios pendientes.
