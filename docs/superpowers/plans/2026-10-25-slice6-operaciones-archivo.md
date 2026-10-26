# Slice 6 — Operaciones de archivo — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Renombrar, eliminar (a la papelera, con confirmación), y
crear carpeta nueva — con menú contextual. Es el único slice que toca
archivos reales de forma destructiva.

**Alcance recortado (ponytail), documentado como diferido, no como
bug:** copiar/mover por drag&drop o portapapeles, "Open With", y crear
archivo nuevo vacío quedan afuera de este slice. Son extensiones
naturales de la misma capa de servicio (`FileOperationsService`), no un
rediseño — se agregan cuando haga falta.

**Arquitectura:** `FileOperationsService` (sin estado, testeable) hace el
trabajo real sobre `FileManager`. `BrowserViewModel` expone métodos que
llaman al servicio y refrescan `items`/`selectedItem`. La UI pide
confirmación antes de cualquier operación destructiva (eliminar) y pide
el nombre antes de renombrar/crear carpeta — nunca ejecuta directo desde
un click de menú.

**Tech Stack:** Swift 6.4, SwiftUI, `FileManager` nativo (`trashItem`).

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`
(ver la entrada de Slice 6 en el documento de diseño: es el único slice
que exige tests además de prueba manual).

## Global Constraints

- Mismas restricciones globales de los slices 1-5.
- **Ninguna operación destructiva corre sin confirmación explícita del
  usuario** — eliminar pide confirmación siempre; renombrar/crear carpeta
  piden el nombre antes de ejecutar (no hay "deshacer" en este slice).
- Todo en `FileOperationsService` tiene test — no alcanza con "lo probé
  a mano" para esta capa (a diferencia de las vistas).

## Review Focus

- Renombrar a un nombre que ya existe en la misma carpeta → debe
  rechazarse con un error claro, nunca sobrescribir silenciosamente.
- Renombrar con nombre vacío o solo espacios → debe rechazarse, nunca
  crear un archivo sin nombre ni crashear.
- Eliminar el ítem que está seleccionado → la selección debe limpiarse
  después (ya no existe), no quedar apuntando a un `FileItem` fantasma.
- Crear una carpeta con un nombre que ya existe → debe rechazarse con el
  mismo error que renombrar, no crear una carpeta "Nueva carpeta (2)"
  automáticamente (eso es una mejora de UX para otro slice).
- Cualquier operación que falle (permisos, nombre invalido) → debe
  mostrarse al usuario de forma legible, nunca fallar en silencio ni
  crashear la app.

---

## Task 1: `FileOperationsService`

**Files:**
- Create: `Sources/DolphinForMacOS/Services/FileOperationsService.swift`
- Test: `Tests/DolphinForMacOSTests/FileOperationsServiceTests.swift`

**Interfaces:**
- Produce:
  ```swift
  enum FileOperationError: Error, Equatable {
      case nameAlreadyExists(URL)
      case invalidName
      case other(String)
  }

  struct FileOperationsService {
      func rename(_ item: FileItem, to newName: String) throws -> URL
      func moveToTrash(_ item: FileItem) throws
      func createFolder(in directory: URL, named name: String) throws -> URL
  }
  ```
  Nombre inválido: vacío o solo whitespace, o que contenga `/` (separador
  de ruta). `rename`/`createFolder` chequean colisión con
  `FileManager.default.fileExists(atPath:)` antes de actuar.

- [ ] **Step 1: Tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class FileOperationsServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String) throws -> FileItem {
        let url = tempDir.appendingPathComponent(name)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return FileItem(url: url, name: name, isDirectory: false, isSymbolicLink: false, size: 1, modificationDate: Date())
    }

    func test_rename_movesFileToNewName() throws {
        let item = try makeFile("a.txt")
        let newURL = try FileOperationsService().rename(item, to: "b.txt")
        XCTAssertEqual(newURL, tempDir.appendingPathComponent("b.txt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
    }

    func test_rename_toExistingName_throwsNameAlreadyExists() throws {
        let item = try makeFile("a.txt")
        _ = try makeFile("b.txt")
        XCTAssertThrowsError(try FileOperationsService().rename(item, to: "b.txt")) { error in
            XCTAssertEqual(error as? FileOperationError, .nameAlreadyExists(tempDir.appendingPathComponent("b.txt")))
        }
    }

    func test_rename_toEmptyOrWhitespaceName_throwsInvalidName() throws {
        let item = try makeFile("a.txt")
        XCTAssertThrowsError(try FileOperationsService().rename(item, to: "   ")) { error in
            XCTAssertEqual(error as? FileOperationError, .invalidName)
        }
    }

    func test_rename_nameContainingSlash_throwsInvalidName() throws {
        let item = try makeFile("a.txt")
        XCTAssertThrowsError(try FileOperationsService().rename(item, to: "b/c.txt")) { error in
            XCTAssertEqual(error as? FileOperationError, .invalidName)
        }
    }

    func test_moveToTrash_removesFileFromOriginalLocation() throws {
        let item = try makeFile("a.txt")
        try FileOperationsService().moveToTrash(item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.url.path))
    }

    func test_createFolder_createsDirectory() throws {
        let url = try FileOperationsService().createFolder(in: tempDir, named: "Nueva carpeta")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func test_createFolder_withExistingName_throwsNameAlreadyExists() throws {
        _ = try FileOperationsService().createFolder(in: tempDir, named: "Dup")
        XCTAssertThrowsError(try FileOperationsService().createFolder(in: tempDir, named: "Dup")) { error in
            XCTAssertEqual(error as? FileOperationError, .nameAlreadyExists(tempDir.appendingPathComponent("Dup")))
        }
    }
}
```

- [ ] **Step 2:** `swift test --filter FileOperationsServiceTests` → FAIL.
- [ ] **Step 3:** Implementar. Validar nombre primero (vacío/whitespace-only vía
  `trimmingCharacters(in: .whitespaces).isEmpty`, o que contenga "/").
  Luego chequear colisión. `moveToTrash` usa
  `FileManager.default.trashItem(at:resultingItemURL:)`. Mapear cualquier
  otro error de `FileManager` a `.other(...)`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/FileOperationsService.swift Tests/DolphinForMacOSTests/FileOperationsServiceTests.swift
git commit -m "feat: FileOperationsService (rename, moveToTrash, createFolder)"
```

---

## Task 2: Wiring en `BrowserViewModel`

**Files:**
- Modify: `Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift`
- Modify: `Tests/DolphinForMacOSTests/BrowserViewModelTests.swift`

**Interfaces:**
- Consume: `FileOperationsService`, `FileOperationError` (Task 1).
- Produce:
  ```swift
  private(set) var operationError: FileOperationError?

  func renameSelected(to newName: String)
  func deleteSelected()
  func createFolder(named name: String)
  func clearOperationError()
  ```
  Las tres operan sobre `selectedItem` cuando aplica (`renameSelected`/
  `deleteSelected` no hacen nada si `selectedItem == nil`). Todas llaman
  `refresh()` después de una operación exitosa. Si la operación tira,
  `operationError` queda seteado y no se refresca. `deleteSelected`
  limpia `selectedItem = nil` después de un delete exitoso.

- [ ] **Step 1: Tests que fallan**

```swift
func test_renameSelected_renamesAndRefreshes() throws {
    try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.select(vm.items[0])
    vm.renameSelected(to: "b.txt")
    XCTAssertEqual(vm.items.map(\.name), ["b.txt"])
    XCTAssertNil(vm.operationError)
}

func test_renameSelected_toExistingName_setsOperationError_doesNotRefresh() throws {
    try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "x".write(to: tempDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.select(vm.items[0]) // a.txt
    vm.renameSelected(to: "b.txt")
    XCTAssertNotNil(vm.operationError)
    XCTAssertEqual(vm.items.map(\.name).sorted(), ["a.txt", "b.txt"])
}

func test_deleteSelected_removesItemAndClearsSelection() throws {
    try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.select(vm.items[0])
    vm.deleteSelected()
    XCTAssertEqual(vm.items, [])
    XCTAssertNil(vm.selectedItem)
}

func test_createFolder_addsNewFolderToItems() throws {
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.createFolder(named: "Nueva carpeta")
    XCTAssertEqual(vm.items.map(\.name), ["Nueva carpeta"])
}
```

- [ ] **Step 2:** `swift test --filter BrowserViewModelTests` → FAIL.
- [ ] **Step 3:** Implementar usando una instancia de `FileOperationsService()` como
  dependencia (agregar parámetro `operations: FileOperationsService =
  FileOperationsService()` al `init`, igual patrón que `reader`/`store`).
- [ ] **Step 4:** PASS (todos, incluyendo slices 1-5).
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift Tests/DolphinForMacOSTests/BrowserViewModelTests.swift
git commit -m "feat: BrowserViewModel.renameSelected/deleteSelected/createFolder"
```

---

## Task 3: Selección nativa de `List`/`Table` + menú contextual + confirmación + prompts de nombre

**Decisión tomada en la revisión final del slice 4 (ver `docs/decisions.md`):**
en vez de agregar el menú contextual sobre el gesto custom
(`exclusively(before:)`) que ya tienen `FileListView`/`DetailsListView`,
se migra esas dos vistas a la selección nativa de SwiftUI
(`List(selection:)`/`Table(selection:)` + `contextMenu(forSelectionType:
primaryAction:)`). Esto de paso resuelve, sin trabajo extra: el retraso
del tap exclusivo, el área de click angosta, y que doble-click sobre un
archivo no seleccionaba nada (bugs ya logueados en slices 1-4).
`IconGridView` (un `LazyVGrid`, no un `List`/`Table`) no tiene selección
nativa — se queda con el gesto custom del slice 4, pero se le agrega
`.contentShape(Rectangle())` para que el área clickeable cubra toda la
celda, no solo el ícono+texto.

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/FileListView.swift`
- Modify: `Sources/DolphinForMacOS/Views/DetailsListView.swift`
- Modify: `Sources/DolphinForMacOS/Views/IconGridView.swift`
- Modify: `Sources/DolphinForMacOS/Views/BrowserView.swift`

**Interfaces:**
- Consume: `BrowserViewModel.renameSelected/deleteSelected/createFolder`
  (Task 2).
- Produce:
  ```swift
  struct FileListView: View {
      let items: [FileItem]
      @Binding var selectedID: FileItem.ID?
      let onOpen: (FileItem) -> Void
      let onDelete: (FileItem) -> Void
  }

  struct DetailsListView: View {
      let items: [FileItem]
      @Binding var selectedID: FileItem.ID?
      let onOpen: (FileItem) -> Void
      let onDelete: (FileItem) -> Void
  }

  struct IconGridView: View {
      // firma igual al slice 4 (selectedItem/onSelect/onOpen), + onDelete
      let onDelete: (FileItem) -> Void
  }
  ```

Antes de implementar, consultar `axiom-swiftui` (`contextMenu(forSelectionType:)`,
`.alert` con `TextField` para pedir un nombre) — regla del proyecto.

- [ ] **Step 1: `FileListView` con selección nativa**

```swift
List(items, selection: $selectedID) { item in
    Label(item.name, systemImage: item.isDirectory ? "folder" : "doc")
}
.contextMenu(forSelectionType: FileItem.ID.self) { ids in
    if let id = ids.first, let item = items.first(where: { $0.id == id }) {
        Button("Eliminar", role: .destructive) { onDelete(item) }
    }
} primaryAction: { ids in
    if let id = ids.first, let item = items.first(where: { $0.id == id }) {
        onOpen(item)
    }
}
```

- [ ] **Step 2: `DetailsListView` con selección nativa**

Mismo patrón que el Step 1 pero sobre `Table(items, selection: $selectedID) { TableColumn... }` en vez de `List`. Las columnas quedan igual que en el slice 4 (usan `FileMetadataFormatter`).

- [ ] **Step 3: `IconGridView` — `.contentShape` + menú contextual**

Agregar `.contentShape(Rectangle())` antes del `.gesture(...)` existente
del slice 4 (que se mantiene tal cual, con `selectedItem`/`onSelect`/
`onOpen`), y `.contextMenu { Button("Eliminar", role: .destructive) { onDelete(item) } }` a la celda.

- [ ] **Step 4: Wiring en `BrowserView`**

```swift
@State private var showsDeleteConfirmation = false
@State private var showsRenamePrompt = false
@State private var showsNewFolderPrompt = false
@State private var nameInput = ""

private var selectedID: Binding<FileItem.ID?> {
    Binding(
        get: { viewModel.selectedItem?.id },
        set: { id in viewModel.select(viewModel.items.first { $0.id == id }) }
    )
}
```
`onDelete` (pasado a las 3 vistas) selecciona el ítem y pone
`showsDeleteConfirmation = true`; el borrado real solo ocurre en el botón
"Eliminar" del `.alert` (`role: .destructive`), nunca directo desde el
menú contextual. Un botón "Renombrar" (habilitado solo con
`viewModel.selectedItem != nil`) pone `nameInput =
viewModel.selectedItem?.name ?? ""` y `showsRenamePrompt = true`. Un
botón "Nueva carpeta" en la toolbar pone `nameInput = "Nueva carpeta"` y
`showsNewFolderPrompt = true`. Los tres `.alert` siguen el patrón ya
descrito (confirmación destructiva para eliminar, `TextField` + botón de
acción para renombrar/crear carpeta). Si `viewModel.operationError !=
nil`, un `.alert` de error simple ("OK") que llama
`viewModel.clearOperationError()` al cerrarse.

- [ ] **Step 5:** `swift build` → `Build complete!`.
- [ ] **Step 6: Commit**

```bash
git add Sources/DolphinForMacOS/Views/FileListView.swift Sources/DolphinForMacOS/Views/DetailsListView.swift Sources/DolphinForMacOS/Views/IconGridView.swift Sources/DolphinForMacOS/Views/BrowserView.swift
git commit -m "feat: selección nativa List/Table, menú contextual, confirmación de borrado y prompts de nombre"
```

---

## Task 4: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests de slices 1-6 en PASS.
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo, matarlo.
- [ ] **Step 3:** sin commit si no hay cambios pendientes.
