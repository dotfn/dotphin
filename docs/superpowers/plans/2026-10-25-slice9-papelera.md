# Slice 9 — Papelera como ubicación navegable — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** La papelera (`~/.Trash`) aparece como un Place navegable
normal (se obtiene gratis, es una carpeta real), más "Vaciar papelera"
(borrado permanente, con confirmación) y "Restaurar" (mover el ítem
seleccionado afuera de la papelera).

**Alcance recortado (ponytail), documentado como diferido, no como
bug:** "Restaurar" en Dolphin devuelve el ítem a su ubicación original
usando metadata que el spec de trash de Linux guarda (`.trashinfo`).
macOS no expone esa metadata a apps de terceros vía API pública — no
hay forma de saber de dónde vino un ítem que ya está en `~/.Trash` si
no fuimos nosotros los que lo mandamos ahí. Este slice define
"Restaurar" como mover el ítem a Home, no a su carpeta original. Es
una limitación real de la plataforma, no una simplificación arbitraria.
Elegir destino de restauración (en vez de Home fijo) también queda
afuera.

**Arquitectura:** Se agregan `restore`/`emptyTrash` a
`FileOperationsService` (misma capa que rename/delete/createFolder del
slice 6, mismo manejo de errores). `PlacesProvider` agrega Trash como
bookmark. `BrowserView` detecta si `currentURL` es la papelera y
agrega dos botones (Vaciar, Restaurar) — todo lo demás (navegar,
listar, ordenar, filtrar, buscar) ya funciona porque la papelera es una
carpeta real y el resto de la app no distingue carpetas especiales.

**Tech Stack:** Swift 6.4, SwiftUI, `FileManager` nativo.

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`

## Global Constraints

- Mismas restricciones globales de los slices 1-8.
- Vaciar la papelera es **permanente** (no hay otra papelera detrás) —
  pide confirmación explícita igual que cualquier operación destructiva
  del slice 6, con wording que diga "permanente", no "mover a la
  papelera".
- Restaurar a Home con colisión de nombre se rechaza con el mismo error
  que renombrar/crear carpeta (`nameAlreadyExists`) — nunca sobrescribe.

## Review Focus

- Vaciar una papelera vacía → debe completarse sin error, no tratar
  "nada que borrar" como una falla.
- Vaciar la papelera con un ítem que no se puede borrar (permisos) →
  debe borrar los que sí se pueden y reportar cuáles fallaron, nunca
  fallar en silencio ni abortar sin borrar nada.
- Restaurar a Home cuando ya existe un archivo con ese nombre → debe
  rechazarse, nunca sobrescribir.
- Restaurar una carpeta (no un archivo) → debe moverse completa con su
  contenido, no aplanarse ni perder archivos.
- Navegar a la papelera y usar filtro/orden/búsqueda → debe comportarse
  igual que en cualquier otra carpeta, sin casos especiales rotos.

---

## Task 1: `restore`/`emptyTrash` en `FileOperationsService`

**Files:**
- Modify: `Sources/DolphinForMacOS/Services/FileOperationsService.swift`
- Modify: `Tests/DolphinForMacOSTests/FileOperationsServiceTests.swift`

**Interfaces:**
- Produce (agrega a la struct existente):
  ```swift
  func restore(_ item: FileItem, to destinationDirectory: URL) throws -> URL
  func emptyTrash(at trashURL: URL) throws
  ```
  `restore` chequea colisión igual que `rename`/`createFolder`
  (`.nameAlreadyExists`) antes de `FileManager.default.moveItem`.
  `emptyTrash` enumera el contenido directo de `trashURL` y borra cada
  uno con `FileManager.default.removeItem`; sigue con los demás si uno
  falla, y al final tira `.other(...)` listando los nombres que
  fallaron si hubo alguno (no aborta en el primer error, no se traga
  ninguno).

- [ ] **Step 1: Tests que fallan**

```swift
func test_restore_movesItemToDestination() throws {
    let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
    try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
    let destDir = tempDir.appendingPathComponent("home", isDirectory: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    let itemURL = trashDir.appendingPathComponent("a.txt")
    try "x".write(to: itemURL, atomically: true, encoding: .utf8)
    let item = FileItem(url: itemURL, name: "a.txt", isDirectory: false, isSymbolicLink: false, size: 1, modificationDate: Date())

    let newURL = try FileOperationsService().restore(item, to: destDir)
    XCTAssertEqual(newURL, destDir.appendingPathComponent("a.txt"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: itemURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
}

func test_restore_toDestinationWithExistingName_throwsNameAlreadyExists() throws {
    let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
    try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
    let destDir = tempDir.appendingPathComponent("home", isDirectory: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    try "x".write(to: destDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let itemURL = trashDir.appendingPathComponent("a.txt")
    try "y".write(to: itemURL, atomically: true, encoding: .utf8)
    let item = FileItem(url: itemURL, name: "a.txt", isDirectory: false, isSymbolicLink: false, size: 1, modificationDate: Date())

    XCTAssertThrowsError(try FileOperationsService().restore(item, to: destDir)) { error in
        XCTAssertEqual(error as? FileOperationError, .nameAlreadyExists(destDir.appendingPathComponent("a.txt")))
    }
    XCTAssertEqual(try? String(contentsOf: destDir.appendingPathComponent("a.txt"), encoding: .utf8), "x", "no debió sobrescribirse")
}

func test_restore_movesFolderWithContents() throws {
    let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
    try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
    let destDir = tempDir.appendingPathComponent("home", isDirectory: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    let folderURL = trashDir.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    try "x".write(to: folderURL.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)
    let item = FileItem(url: folderURL, name: "folder", isDirectory: true, isSymbolicLink: false, size: nil, modificationDate: Date())

    let newURL = try FileOperationsService().restore(item, to: destDir)
    XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.appendingPathComponent("inside.txt").path))
}

func test_emptyTrash_onEmptyFolder_succeedsWithoutError() throws {
    let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
    try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
    XCTAssertNoThrow(try FileOperationsService().emptyTrash(at: trashDir))
}

func test_emptyTrash_removesAllContents() throws {
    let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
    try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
    try "x".write(to: trashDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "x".write(to: trashDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    try FileOperationsService().emptyTrash(at: trashDir)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trashDir.path), [])
}

func test_emptyTrash_withOneUndeletableItem_removesTheRestAndReportsFailure() throws {
    let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
    try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
    try "x".write(to: trashDir.appendingPathComponent("ok.txt"), atomically: true, encoding: .utf8)
    let locked = trashDir.appendingPathComponent("locked", isDirectory: true)
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    try "x".write(to: locked.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

    XCTAssertThrowsError(try FileOperationsService().emptyTrash(at: trashDir))
    XCTAssertFalse(FileManager.default.fileExists(atPath: trashDir.appendingPathComponent("ok.txt").path), "el que sí se pudo borrar debe haberse borrado igual")
}
```

- [ ] **Step 2:** `swift test --filter FileOperationsServiceTests` → FAIL.
- [ ] **Step 3:** Implementar según lo descrito arriba.
- [ ] **Step 4:** PASS (todos, incluyendo slices 1-8).
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/FileOperationsService.swift Tests/DolphinForMacOSTests/FileOperationsServiceTests.swift
git commit -m "feat: FileOperationsService.restore y emptyTrash"
```

---

## Task 2: Trash como Place + wiring en `BrowserViewModel`

**Files:**
- Modify: `Sources/DolphinForMacOS/Services/PlacesProvider.swift`
- Modify: `Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift`
- Modify: `Tests/DolphinForMacOSTests/PlacesProviderTests.swift`
- Modify: `Tests/DolphinForMacOSTests/BrowserViewModelTests.swift`

**Interfaces:**
- Produce:
  - `PlacesProvider.staticBookmarks()` agrega un quinto ítem: Trash
    (`FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)`,
    ícono `"trash"`, kind `.bookmark`), al final de la lista existente.
  - `BrowserViewModel`:
    ```swift
    func emptyTrash()
    func restoreSelected()
    ```
    `emptyTrash()` llama `operations.emptyTrash(at: currentURL)` y
    `refresh()` si no tira; si tira, `operationError`. `restoreSelected()`
    opera sobre `selectedItem` (no-op si es `nil`), restaura a
    `FileManager.default.homeDirectoryForCurrentUser`, limpia selección
    y refresca si tiene éxito; si tira, `operationError`.

- [ ] **Step 1: Tests que fallan**

```swift
// PlacesProviderTests
func test_staticBookmarks_includesTrashAtTheEnd() {
    let provider = PlacesProvider()
    let names = provider.staticBookmarks().map(\.name)
    XCTAssertEqual(names.last, "Trash")
}

// BrowserViewModelTests
func test_emptyTrash_removesItemsAndRefreshes() throws {
    try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.emptyTrash()
    XCTAssertEqual(vm.items, [])
    XCTAssertNil(vm.operationError)
}

func test_restoreSelected_movesToHomeAndClearsSelection() throws {
    try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.select(vm.items[0])
    vm.restoreSelected()
    XCTAssertNil(vm.selectedItem)
    XCTAssertEqual(vm.items, [])
    let restoredPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("a.txt").path
    XCTAssertTrue(FileManager.default.fileExists(atPath: restoredPath))
    try? FileManager.default.removeItem(atPath: restoredPath) // limpieza del test
}
```

- [ ] **Step 2:** `swift test --filter "PlacesProviderTests|BrowserViewModelTests"` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** PASS (todos, incluyendo slices 1-8).
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/PlacesProvider.swift Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift Tests/DolphinForMacOSTests/PlacesProviderTests.swift Tests/DolphinForMacOSTests/BrowserViewModelTests.swift
git commit -m "feat: Trash como Place, BrowserViewModel.emptyTrash/restoreSelected"
```

---

## Task 3: Botones "Vaciar papelera" / "Restaurar" en `BrowserView`

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/BrowserView.swift`

**Interfaces:**
- Consume: `BrowserViewModel.emptyTrash/restoreSelected` (Task 2).

- [ ] **Step 1: Implementar**

```swift
private var trashURL: URL? {
    try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
}

private var isBrowsingTrash: Bool {
    trashURL?.standardizedFileURL.path == viewModel.currentURL.standardizedFileURL.path
}
```
En la toolbar, si `isBrowsingTrash`: un botón "Restaurar" (habilitado
solo con `viewModel.selectedItem != nil`) que llama
`viewModel.restoreSelected()` directo (no es destructivo, no necesita
confirmación), y un botón "Vaciar papelera" con su propio `.alert` de
confirmación — texto explícito: "Esto borra el contenido de la papelera
de forma permanente. No se puede deshacer." — que llama
`viewModel.emptyTrash()`. Los botones existentes (Nueva carpeta,
Renombrar, Eliminar) se quedan como están, visibles siempre — no hace
falta ocultarlos para este slice.

- [ ] **Step 2:** `swift build` → `Build complete!`.
- [ ] **Step 3: Commit**

```bash
git add Sources/DolphinForMacOS/Views/BrowserView.swift
git commit -m "feat: botones de Vaciar papelera y Restaurar — slice 9 completo"
```

---

## Task 4: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests de slices 1-9 en PASS.
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo, matarlo.
- [ ] **Step 3:** sin commit si no hay cambios pendientes.
