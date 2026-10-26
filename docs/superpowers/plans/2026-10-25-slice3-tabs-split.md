# Slice 3 — Pestañas + split view — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Múltiples pestañas en la ventana, cada una con su propio
`BrowserViewModel`, y cada pestaña puede dividirse en dos paneles (split
view) — igual que `dolphintabwidget`/`tabpage` en Dolphin.

**Arquitectura:** `Tab` agrupa un `BrowserViewModel` primario y uno
secundario opcional (split) + qué panel está enfocado. `TabsViewModel` es
el nuevo dueño de la navegación de más alto nivel: lista de tabs, tab
seleccionado. La sidebar de Places pasa a navegar el panel enfocado del
tab seleccionado, no un `BrowserViewModel` único.

**Tech Stack:** Swift 6.4, SwiftUI (`HSplitView` nativo de macOS para el
split redimensionable).

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`

## Global Constraints

- Mismas restricciones globales de los slices 1-2.
- Cerrar la última pestaña no hace nada (no se puede llegar a cero
  pestañas en este slice) — evita el caso "ventana sin contenido", que no
  está en el alcance de este slice (cerrar la ventana entera cuando no
  quedan tabs es un comportamiento de gestión de ventanas que se deja para
  más adelante).
- Pestaña nueva abre en la misma carpeta que la pestaña actual (como
  Dolphin), no en Home.
- Split nuevo arranca mostrando la misma carpeta que el panel primario
  (como Dolphin), no en Home.

## Review Focus

- Cerrar la pestaña seleccionada → debe seleccionarse otra pestaña válida,
  nunca quedar con `selectedTabID` apuntando a un tab que ya no existe.
- Cerrar la única pestaña que queda → no debe hacer nada (no debe dejar 0
  tabs).
- Activar split y después desactivarlo → el panel enfocado debe volver a
  ser el primario si estaba enfocado el secundario (que ya no existe).
- Enfocar el panel secundario de un tab que no está en split → debe ser
  ignorado (no hay panel 1 si no hay split).
- Cambiar de pestaña seleccionada no debe afectar el estado (carpeta
  actual, view properties) de las demás pestañas.

---

## Task 1: `Tab` + `TabsViewModel`

**Files:**
- Create: `Sources/DolphinForMacOS/Models/Tab.swift`
- Create: `Sources/DolphinForMacOS/ViewModels/TabsViewModel.swift`
- Test: `Tests/DolphinForMacOSTests/TabsViewModelTests.swift`

**Interfaces:**
- Consume: `BrowserViewModel` (slice 1/2).
- Produce:
  ```swift
  struct Tab: Identifiable {
      let id: UUID
      var primary: BrowserViewModel
      var secondary: BrowserViewModel?
      var focusedPaneIndex: Int // 0 o 1

      var isSplit: Bool { secondary != nil }
      var focused: BrowserViewModel { focusedPaneIndex == 1 ? (secondary ?? primary) : primary }
  }

  @Observable
  final class TabsViewModel {
      private(set) var tabs: [Tab]
      private(set) var selectedTabID: Tab.ID

      init(startingAt url: URL)
      var selectedTab: Tab? { tabs.first { $0.id == selectedTabID } }

      func addTab(startingAt url: URL)
      func closeTab(_ id: Tab.ID)
      func selectTab(_ id: Tab.ID)
      func toggleSplit(for id: Tab.ID)
      func setFocusedPane(_ index: Int, for id: Tab.ID)
  }
  ```

- [ ] **Step 1: Escribir los tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class TabsViewModelTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_init_startsWithOneTabSelected() {
        let vm = TabsViewModel(startingAt: tempDir)
        XCTAssertEqual(vm.tabs.count, 1)
        XCTAssertEqual(vm.selectedTabID, vm.tabs[0].id)
        XCTAssertEqual(vm.selectedTab?.primary.currentURL, tempDir)
    }

    func test_addTab_appendsAndSelectsIt_atGivenURL() {
        let vm = TabsViewModel(startingAt: tempDir)
        let sub = tempDir.appendingPathComponent("sub")
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        vm.addTab(startingAt: sub)
        XCTAssertEqual(vm.tabs.count, 2)
        XCTAssertEqual(vm.selectedTabID, vm.tabs[1].id)
        XCTAssertEqual(vm.selectedTab?.primary.currentURL, sub)
    }

    func test_closeTab_removesItAndSelectsAnotherValidTab() {
        let vm = TabsViewModel(startingAt: tempDir)
        vm.addTab(startingAt: tempDir)
        let firstID = vm.tabs[0].id
        let secondID = vm.tabs[1].id
        vm.closeTab(secondID)
        XCTAssertEqual(vm.tabs.map(\.id), [firstID])
        XCTAssertEqual(vm.selectedTabID, firstID)
    }

    func test_closeTab_onLastRemainingTab_doesNothing() {
        let vm = TabsViewModel(startingAt: tempDir)
        let onlyID = vm.tabs[0].id
        vm.closeTab(onlyID)
        XCTAssertEqual(vm.tabs.count, 1)
        XCTAssertEqual(vm.tabs[0].id, onlyID)
    }

    func test_toggleSplit_addsSecondaryAtSamePrimaryURL_thenRemovesIt() {
        let vm = TabsViewModel(startingAt: tempDir)
        let id = vm.selectedTabID
        vm.toggleSplit(for: id)
        XCTAssertTrue(vm.selectedTab!.isSplit)
        XCTAssertEqual(vm.selectedTab!.secondary?.currentURL, tempDir)

        vm.setFocusedPane(1, for: id)
        vm.toggleSplit(for: id)
        XCTAssertFalse(vm.selectedTab!.isSplit)
        XCTAssertEqual(vm.selectedTab!.focusedPaneIndex, 0, "al perder el panel secundario, el foco vuelve al primario")
    }

    func test_setFocusedPane_ignoredWhenNotSplit() {
        let vm = TabsViewModel(startingAt: tempDir)
        let id = vm.selectedTabID
        vm.setFocusedPane(1, for: id)
        XCTAssertEqual(vm.selectedTab!.focusedPaneIndex, 0)
    }

    func test_selectingAnotherTab_doesNotAffectOtherTabsState() {
        let vm = TabsViewModel(startingAt: tempDir)
        let sub = tempDir.appendingPathComponent("sub")
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        vm.addTab(startingAt: sub)
        let firstID = vm.tabs[0].id
        vm.selectTab(firstID)
        XCTAssertEqual(vm.selectedTab?.primary.currentURL, tempDir)
        XCTAssertEqual(vm.tabs[1].primary.currentURL, sub, "la otra pestaña no debió cambiar")
    }
}
```

- [ ] **Step 2: Correr y confirmar que fallan**

Run: `swift test --filter TabsViewModelTests`
Expected: FAIL — los tipos no existen.

- [ ] **Step 3: Implementar `Tab`**

Struct con los campos de la firma. `focused` como propiedad computada.

- [ ] **Step 4: Implementar `TabsViewModel`**

`addTab(startingAt:)` crea `Tab(id: UUID(), primary: BrowserViewModel(startingAt: url), secondary: nil, focusedPaneIndex: 0)`, lo agrega y lo selecciona. `closeTab` no hace nada si `tabs.count == 1`; si no, remueve y selecciona el tab que queda en el índice anterior (o el primero si era el índice 0). `toggleSplit` crea `secondary = BrowserViewModel(startingAt: tab.primary.currentURL)` si no hay, o lo pone en `nil` si ya hay (y fuerza `focusedPaneIndex = 0`). `setFocusedPane` solo acepta `1` si `isSplit`, si no lo ignora.

- [ ] **Step 5: Correr y confirmar que pasan**

Run: `swift test --filter TabsViewModelTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/DolphinForMacOS/Models/Tab.swift Sources/DolphinForMacOS/ViewModels/TabsViewModel.swift Tests/DolphinForMacOSTests/TabsViewModelTests.swift
git commit -m "feat: Tab y TabsViewModel (pestañas + split, sin UI todavía)"
```

---

## Task 2: Barra de pestañas (`TabBarView`)

**Files:**
- Create: `Sources/DolphinForMacOS/Views/TabBarView.swift`

**Interfaces:**
- Consume: `TabsViewModel`, `Tab` (Task 1).
- Produce: `struct TabBarView: View { let viewModel: TabsViewModel }`

Antes de implementar, consultar `axiom-macos` (menus-and-commands.md /
swiftui-differences.md) por el patrón de una barra de pestañas custom en
macOS — regla del proyecto.

- [ ] **Step 1: Implementar `TabBarView`**

`HStack` con un botón por tab (título = `tab.primary.currentURL.lastPathComponent`,
o `tab.focused.currentURL.lastPathComponent` para reflejar el panel
enfocado si está en split), resaltado si es el seleccionado, con una "x"
para cerrar (`viewModel.closeTab`) y un botón "+" al final
(`viewModel.addTab(startingAt: viewModel.selectedTab!.primary.currentURL)`).
Click en un tab llama `viewModel.selectTab`.

- [ ] **Step 2: Verificar que compila**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/DolphinForMacOS/Views/TabBarView.swift
git commit -m "feat: TabBarView"
```

---

## Task 3: Split view por pestaña (`SplitBrowserView`)

**Files:**
- Create: `Sources/DolphinForMacOS/Views/SplitBrowserView.swift`

**Interfaces:**
- Consume: `Tab`, `BrowserView` (slice 1/2).
- Produce: `struct SplitBrowserView: View { let tab: Tab; let onFocusPane: (Int) -> Void }`

- [ ] **Step 1: Implementar**

Si `tab.isSplit`, `HSplitView { BrowserView(viewModel: tab.primary).onTapGesture { onFocusPane(0) }; BrowserView(viewModel: tab.secondary!).onTapGesture { onFocusPane(1) } }`. Si no, `BrowserView(viewModel: tab.primary)` solo. Un borde de acento en el panel enfocado (`.border(tab.focusedPaneIndex == i ? Color.accentColor : .clear)`) para que se note cuál está activo.

- [ ] **Step 2: Verificar que compila**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/DolphinForMacOS/Views/SplitBrowserView.swift
git commit -m "feat: SplitBrowserView con HSplitView"
```

---

## Task 4: Integrar en `ContentView` + botón de split

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/ContentView.swift`

**Interfaces:**
- Consume: todo lo anterior.

- [ ] **Step 1: Reemplazar `BrowserViewModel` por `TabsViewModel` en `ContentView`**

`@State private var tabsViewModel = TabsViewModel(startingAt: FileManager.default.homeDirectoryForCurrentUser)`.
La sidebar de Places navega
`tabsViewModel.selectedTab?.focused` (vía `onSelect` llamando
`.navigate(to:)` sobre ese view model). El detalle de `NavigationSplitView`
pasa a ser `VStack { TabBarView(viewModel: tabsViewModel); if let tab = tabsViewModel.selectedTab { HStack { Button("Split") { tabsViewModel.toggleSplit(for: tab.id) }; Spacer() }; SplitBrowserView(tab: tab, onFocusPane: { tabsViewModel.setFocusedPane($0, for: tab.id) }) } }`.
El botón de split vive en `ContentView` (no en `BrowserView`) porque
`BrowserView` no conoce `Tab` y no hace falta romper su interfaz actual.

- [ ] **Step 2: Verificar que compila**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Correr toda la suite**

Run: `swift test`
Expected: todos los tests de slices 1-3 en PASS.

- [ ] **Step 4: Smoke run**

Run: `swift build && swift run &`, confirmar que el proceso queda vivo,
matarlo.

- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Views/ContentView.swift
git commit -m "feat: integra pestañas y split view en ContentView — slice 3 completo"
```
