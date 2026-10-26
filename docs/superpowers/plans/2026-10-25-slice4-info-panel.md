# Slice 4 — Panel de información (metadata) — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Selección de un solo ítem (sin abrirlo) en cualquiera de las
3 vistas, y un panel de información dockable (vía `.inspector`, nativo de
macOS) que muestra metadata del ítem seleccionado del panel enfocado.

**Arquitectura:** `BrowserViewModel` gana `selectedItem`. Las 3 vistas de
listado ganan un callback `onSelect` separado de `onOpen` (click simple
vs. doble-click). `InfoPanelView` es una vista pura que renderiza
metadata ya formateada por `FileMetadataFormatter` (función pura,
testeable sin UI).

**Alcance recortado (ponytail):** preview real de thumbnail (QuickLook)
queda afuera de este slice — se usa el mismo ícono SF Symbol genérico que
ya usan las listas. Se documenta como diferido, no como bug.

**Tech Stack:** Swift 6.4, SwiftUI `.inspector()` (macOS nativo).

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`

## Global Constraints

- Mismas restricciones globales de los slices 1-3.
- Cambiar de carpeta (navigate) limpia la selección — no tiene sentido
  mostrar metadata de un ítem que ya no está en la vista actual.
- Cerrar/cambiar de pestaña o de panel enfocado no comparte selección
  entre paneles — cada `BrowserViewModel` tiene su propia `selectedItem`.

## Review Focus

- Navegar a otra carpeta con un ítem seleccionado → la selección debe
  limpiarse, no quedar "fantasma" apuntando a un ítem de la carpeta
  anterior.
- Ningún ítem seleccionado → el panel debe mostrar un estado vacío
  explícito, no crashear ni mostrar metadata basura.
- Formatear metadata de una carpeta (sin `size`) → no debe mostrar "0
  bytes" ni crashear, debe mostrar un placeholder razonable ("—" o vacío).
- Dos paneles (split) con selecciones distintas → el panel de info debe
  reflejar la selección del panel *enfocado*, no la del otro.
- Formatear un nombre de archivo sin extensión → el "tipo" no debe
  mostrar una extensión vacía ni crashear.

---

## Task 1: Selección en `BrowserViewModel`

**Files:**
- Modify: `Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift`
- Modify: `Tests/DolphinForMacOSTests/BrowserViewModelTests.swift`

**Interfaces:**
- Produce (agrega a la clase existente):
  ```swift
  private(set) var selectedItem: FileItem?
  func select(_ item: FileItem?)
  ```
  `navigate(to:)` limpia `selectedItem = nil` antes de cargar la nueva
  carpeta.

- [ ] **Step 1: Tests que fallan**

```swift
func test_select_setsSelectedItem() throws {
    try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)
    let item = vm.items[0]
    vm.select(item)
    XCTAssertEqual(vm.selectedItem, item)
}

func test_navigate_clearsSelection() throws {
    try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.select(vm.items[0])
    vm.navigate(to: sub)
    XCTAssertNil(vm.selectedItem)
}
```

- [ ] **Step 2:** `swift test --filter BrowserViewModelTests` → FAIL (no existe `selectedItem`/`select`).
- [ ] **Step 3:** Implementar. `select(_:)` solo asigna; `navigate(to:)` asigna `selectedItem = nil` al principio.
- [ ] **Step 4:** `swift test --filter BrowserViewModelTests` → PASS (todos, incluyendo los de slices 1-2).
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift Tests/DolphinForMacOSTests/BrowserViewModelTests.swift
git commit -m "feat: BrowserViewModel.selectedItem, se limpia al navegar"
```

---

## Task 2: `FileMetadataFormatter`

**Files:**
- Create: `Sources/DolphinForMacOS/Services/FileMetadataFormatter.swift`
- Test: `Tests/DolphinForMacOSTests/FileMetadataFormatterTests.swift`

**Interfaces:**
- Produce:
  ```swift
  struct FileMetadata {
      let kind: String
      let sizeText: String // "—" para carpetas
      let modifiedText: String // "—" si no hay fecha
  }

  struct FileMetadataFormatter {
      func metadata(for item: FileItem) -> FileMetadata
  }
  ```
  `kind`: "Carpeta" si `isDirectory`; si no, `pathExtension.uppercased()`
  si no está vacía, si no "Documento".

- [ ] **Step 1: Tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class FileMetadataFormatterTests: XCTestCase {
    func test_folder_hasCarpetaKindAndDashSize() {
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/x"), name: "x", isDirectory: true, isSymbolicLink: false, size: nil, modificationDate: nil)
        let meta = FileMetadataFormatter().metadata(for: item)
        XCTAssertEqual(meta.kind, "Carpeta")
        XCTAssertEqual(meta.sizeText, "—")
        XCTAssertEqual(meta.modifiedText, "—")
    }

    func test_fileWithExtension_usesExtensionAsKind() {
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/a.txt"), name: "a.txt", isDirectory: false, isSymbolicLink: false, size: 1234, modificationDate: Date())
        let meta = FileMetadataFormatter().metadata(for: item)
        XCTAssertEqual(meta.kind, "TXT")
        XCTAssertNotEqual(meta.sizeText, "—")
    }

    func test_fileWithoutExtension_usesDocumentoAsKind() {
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/README"), name: "README", isDirectory: false, isSymbolicLink: false, size: 10, modificationDate: nil)
        let meta = FileMetadataFormatter().metadata(for: item)
        XCTAssertEqual(meta.kind, "Documento")
        XCTAssertEqual(meta.modifiedText, "—")
    }
}
```

- [ ] **Step 2:** `swift test --filter FileMetadataFormatterTests` → FAIL.
- [ ] **Step 3:** Implementar con `ByteCountFormatter` (`.countStyle = .file`) para `sizeText` y `Date.formatted(date: .abbreviated, time: .shortened)` para `modifiedText`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/FileMetadataFormatter.swift Tests/DolphinForMacOSTests/FileMetadataFormatterTests.swift
git commit -m "feat: FileMetadataFormatter"
```

---

## Task 3: `InfoPanelView` + selección de un click en las 3 vistas

**Files:**
- Create: `Sources/DolphinForMacOS/Views/InfoPanelView.swift`
- Modify: `Sources/DolphinForMacOS/Views/FileListView.swift`
- Modify: `Sources/DolphinForMacOS/Views/IconGridView.swift`
- Modify: `Sources/DolphinForMacOS/Views/DetailsListView.swift`
- Modify: `Sources/DolphinForMacOS/Views/BrowserView.swift`

**Interfaces:**
- Consume: `FileMetadataFormatter` (Task 2), `BrowserViewModel.selectedItem/select` (Task 1).
- Produce: `struct InfoPanelView: View { let item: FileItem? }`. Las 3
  vistas de listado ganan `let onSelect: (FileItem) -> Void` además de
  `onOpen`, y resaltan la fila/celda cuyo `id` coincide con el ítem
  seleccionado (que `BrowserView` les pasa como `selectedItem: FileItem?`
  nuevo parámetro).

Antes de implementar, consultar `axiom-macos` (swiftui-differences.md,
sección Inspector) — regla del proyecto.

- [ ] **Step 1: `InfoPanelView`**

Si `item == nil`, `Text("Nada seleccionado").foregroundStyle(.secondary)`.
Si no, ícono grande (mismo criterio que `IconGridView`) + `Text(item.name)`
+ filas con `FileMetadataFormatter().metadata(for: item)` (Tipo, Tamaño,
Modificado).

- [ ] **Step 2: Click simple en las 3 vistas**

`FileListView`/`IconGridView`/`DetailsListView` reciben `selectedItem:
FileItem?` y `onSelect: (FileItem) -> Void`. Un solo tap (no
`onTapGesture(count: 2)`, un tap normal con `.onTapGesture { onSelect(item) }`
antes del doble-click, o usar `.simultaneousGesture` para que no se pisen)
llama `onSelect`; fondo resaltado si `item.id == selectedItem?.id`.

- [ ] **Step 3: `BrowserView` + `.inspector`**

`BrowserView` agrega `.inspector(isPresented: $showsInfo) { InfoPanelView(item: viewModel.selectedItem) }` con un `@State private var showsInfo = false` y un botón en la toolbar existente (ícono `sidebar.right`) que la togglea. Pasa `onSelect: viewModel.select` y `selectedItem: viewModel.selectedItem` a las 3 vistas de listado.

- [ ] **Step 4:** `swift build` → `Build complete!`.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Views/InfoPanelView.swift Sources/DolphinForMacOS/Views/FileListView.swift Sources/DolphinForMacOS/Views/IconGridView.swift Sources/DolphinForMacOS/Views/DetailsListView.swift Sources/DolphinForMacOS/Views/BrowserView.swift
git commit -m "feat: InfoPanelView dockable + selección de un click"
```

---

## Task 4: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests de slices 1-4 en PASS.
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo, matarlo.
- [ ] **Step 3:** sin commit si no hay cambios pendientes.
