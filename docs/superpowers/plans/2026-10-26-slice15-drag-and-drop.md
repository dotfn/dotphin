# Slice 15 — Drag & drop entre paneles y con Finder — Plan

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Cerrar el único punto del roadmap original de 14 slices que
quedó deliberadamente afuera del slice 14 (polish pass): drag & drop de
archivos/carpetas entre los paneles de la app, hacia carpetas dentro de
la misma vista, y hacia/desde Finder.

**Arquitectura:** `URL` ya conforma a `Transferable` sin código
adicional (confirmado en axiom-swift `transferable-ref.md`: "Built-in
Transferable Types ... `URL`"), así que no se necesita un tipo
`Transferable` custom ni `FileRepresentation`. Cada fila de archivo se
vuelve arrastrable con `.draggable(item.url)`; cada fila de carpeta y
el fondo de cada vista de listado aceptan el drop con
`.dropDestination(for: URL.self)`. El movimiento real de archivos se
hace con un método nuevo en `FileOperationsService` (mismo patrón que
`rename`/`restore`: valida, mueve con `FileManager`, traduce errores a
`FileOperationError`), invocado desde un método nuevo en
`BrowserViewModel` que sigue el patrón ya establecido de
`operationError` + `refresh()` (igual que `delete`/`createFolder`).

Una nota importante sobre direcciones de arrastre: como la app no usa
sandbox, arrastrar un archivo hacia Finder entrega la URL real del
archivo (no una promesa de archivo tipo `NSFilePromiseProvider`) — eso
es suficiente para que Finder la trate como una copia real del archivo,
que es el comportamiento estándar al arrastrar desde una app que no es
Finder. No se implementa "mover" hacia Finder (eso requeriría negociar
la máscara de operación o usar promised files) — queda documentado como
limitación aceptada, no como bug.

**Tech Stack:** Swift 6.4, SwiftUI `.draggable`/`.dropDestination` +
`Transferable` nativo de `URL`. Sin dependencias nuevas.

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`

## Global Constraints

- Mismas restricciones globales de los slices anteriores.
- El movimiento de archivos usa `FileManager.moveItem`, igual que
  `rename`/`restore` — nunca copia+borra manual.
- Ningún drop debe poder borrar datos silenciosamente: un conflicto de
  nombre en el destino SIEMPRE debe terminar en `FileOperationError` (el
  mismo `.alert` de "No se pudo completar la operación" que ya existe),
  nunca sobrescribir.
- `DetailsListView` usa `Table`, que no tiene un contenedor de "fila
  completa" expuesto en SwiftUI — el drag/drop ahí queda limitado a la
  celda de la columna "Nombre" (agarrar y soltar desde "Tamaño" o
  "Modificado" no inicia/acepta un drag). Limitación de `Table`
  documentada, no se busca una solución alternativa para esto.
- No hay feedback visual de "drop target resaltado" (`isTargeted:`) en
  este slice — es una mejora de pulido, no funcional, y se deja afuera
  para no inflar el alcance.
- No se implementa arrastre de selección múltiple coordinado (arrastrar
  uno de varios ítems seleccionados y que todos se muevan) — cada drag
  mueve solo el ítem que se agarró. Soltar SÍ soporta múltiples URLs a
  la vez (por ejemplo, arrastrar 3 archivos desde Finder), porque
  `.dropDestination(for: URL.self)` ya entrega `[URL]` sin código
  extra — ese caso se prueba.
- No hay drop target en la sidebar de Places ni en el árbol de carpetas
  (`FolderTreeRow`) — solo en las 3 vistas de listado del panel
  principal. Queda documentado como extensión futura, no como bug.

## Review Focus

- Soltar un archivo sobre la carpeta que ya lo contiene (drop sobre el
  fondo de la vista que muestra esa misma carpeta, o sobre sí mismo) no
  debe mostrar un error de "ya existe un ítem con ese nombre" — debe ser
  un no-op silencioso, como en Finder.
- Arrastrar una carpeta y soltarla dentro de una de sus propias
  subcarpetas (o sobre sí misma) debe fallar con un mensaje claro, nunca
  corromper el árbol de archivos ni colgar la app.
- Soltar varios archivos a la vez donde algunos tienen conflicto de
  nombre en el destino y otros no: los que no tienen conflicto deben
  moverse igual, y el error debe mencionar solo los que fallaron (mismo
  patrón que `emptyTrash`).
- Un drop exactamente sobre una fila de carpeta (dentro de una lista que
  también tiene un `dropDestination` de fondo) debe mover el ítem DENTRO
  de esa carpeta, no a la carpeta que se está viendo — verificar que el
  `dropDestination` de la fila realmente intercepta el drop antes de que
  llegue al de la lista completa (son dos `dropDestination` anidados,
  uno más específico que el otro).

---

## Task 1: `FileOperationsService.move(_:toDirectory:)`

**Files:**
- Modify: `Sources/DolphinForMacOS/Services/FileOperationsService.swift`
- Test: `Tests/DolphinForMacOSTests/FileOperationsServiceTests.swift`

**Interfaces:**
- Produce: `func move(_ sourceURL: URL, toDirectory destinationDirectory: URL) throws -> URL`
  (reutiliza `FileOperationError` ya existente: `.nameAlreadyExists`, `.other`)

- [ ] **Step 1: Tests que fallan**

```swift
func test_move_relocatesFileIntoDestinationDirectory() throws {
    let source = tempDir.appendingPathComponent("a.txt")
    try "x".write(to: source, atomically: true, encoding: .utf8)
    let destDir = tempDir.appendingPathComponent("dest", isDirectory: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    let result = try FileOperationsService().move(source, toDirectory: destDir)

    XCTAssertEqual(result, destDir.appendingPathComponent("a.txt"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
}

func test_move_droppedOnOwnContainingDirectory_isNoOp() throws {
    let source = tempDir.appendingPathComponent("a.txt")
    try "x".write(to: source, atomically: true, encoding: .utf8)

    let result = try FileOperationsService().move(source, toDirectory: tempDir)

    XCTAssertEqual(result, source)
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
}

func test_move_intoOwnDescendant_throws() throws {
    let folder = tempDir.appendingPathComponent("folder", isDirectory: true)
    let sub = folder.appendingPathComponent("sub", isDirectory: true)
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

    XCTAssertThrowsError(try FileOperationsService().move(folder, toDirectory: sub))
}

func test_move_whenDestinationNameExists_throwsNameAlreadyExists() throws {
    let source = tempDir.appendingPathComponent("a.txt")
    try "x".write(to: source, atomically: true, encoding: .utf8)
    let destDir = tempDir.appendingPathComponent("dest", isDirectory: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    try "y".write(to: destDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

    XCTAssertThrowsError(try FileOperationsService().move(source, toDirectory: destDir)) { error in
        guard case FileOperationError.nameAlreadyExists = error else {
            XCTFail("esperaba nameAlreadyExists, fue \(error)")
            return
        }
    }
}
```

- [ ] **Step 2:** `swift test --filter FileOperationsServiceTests` → FAIL (no existe `move`).
- [ ] **Step 3: Implementar**

```swift
func move(_ sourceURL: URL, toDirectory destinationDirectory: URL) throws -> URL {
    let destination = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
    let sourcePath = sourceURL.standardizedFileURL.path
    let destinationPath = destination.standardizedFileURL.path
    guard destinationPath != sourcePath else {
        return sourceURL
    }
    guard !destinationDirectory.standardizedFileURL.path.hasPrefix(sourcePath + "/") else {
        throw FileOperationError.other("No se puede mover una carpeta dentro de sí misma.")
    }
    guard !FileManager.default.fileExists(atPath: destinationPath) else {
        throw FileOperationError.nameAlreadyExists(destination)
    }
    do {
        try FileManager.default.moveItem(at: sourceURL, to: destination)
    } catch {
        throw FileOperationError.other(error.localizedDescription)
    }
    return destination
}
```

- [ ] **Step 4:** `swift test --filter FileOperationsServiceTests` → PASS (4 nuevos + los existentes).
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/FileOperationsService.swift Tests/DolphinForMacOSTests/FileOperationsServiceTests.swift
git commit -m "feat: FileOperationsService.move (soporte de movimiento para drag & drop)"
```

---

## Task 2: `BrowserViewModel.moveDroppedItems(_:into:)`

**Files:**
- Modify: `Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift`
- Test: `Tests/DolphinForMacOSTests/BrowserViewModelTests.swift`

**Interfaces:**
- Consume: `FileOperationsService.move(_:toDirectory:)` (Task 1)
- Produce: `func moveDroppedItems(_ urls: [URL], into directory: URL)` — sin
  retorno; en éxito llama `refresh()`; en fallo parcial o total, puebla
  `operationError` con `.other("No se pudieron mover: <nombres>")`
  (mismo patrón que `emptyTrash`).

- [ ] **Step 1: Tests que fallan**

```swift
func test_moveDroppedItems_movesFileIntoTargetDirectory() throws {
    let fileURL = tempDir.appendingPathComponent("a.txt")
    try "x".write(to: fileURL, atomically: true, encoding: .utf8)
    let destDir = tempDir.appendingPathComponent("dest", isDirectory: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    let vm = BrowserViewModel(startingAt: tempDir)

    vm.moveDroppedItems([fileURL], into: destDir)

    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("a.txt").path))
    XCTAssertNil(vm.operationError)
}

func test_moveDroppedItems_whenOneFails_reportsErrorButMovesTheRest() throws {
    let okFile = tempDir.appendingPathComponent("ok.txt")
    try "x".write(to: okFile, atomically: true, encoding: .utf8)
    let conflictFile = tempDir.appendingPathComponent("conflict.txt")
    try "x".write(to: conflictFile, atomically: true, encoding: .utf8)
    let destDir = tempDir.appendingPathComponent("dest", isDirectory: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
    try "y".write(to: destDir.appendingPathComponent("conflict.txt"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)

    vm.moveDroppedItems([okFile, conflictFile], into: destDir)

    XCTAssertFalse(FileManager.default.fileExists(atPath: okFile.path), "el que no tenía conflicto se movió igual")
    XCTAssertTrue(FileManager.default.fileExists(atPath: conflictFile.path), "el que tenía conflicto se quedó donde estaba")
    XCTAssertNotNil(vm.operationError)
}
```

- [ ] **Step 2:** `swift test --filter BrowserViewModelTests` → FAIL (no existe `moveDroppedItems`).
- [ ] **Step 3: Implementar**

```swift
func moveDroppedItems(_ urls: [URL], into directory: URL) {
    defer { refresh() }
    var failures: [String] = []
    for url in urls {
        do {
            _ = try operations.move(url, toDirectory: directory)
        } catch {
            failures.append(url.lastPathComponent)
        }
    }
    if !failures.isEmpty {
        operationError = .other("No se pudieron mover: \(failures.joined(separator: ", "))")
    }
}
```

- [ ] **Step 4:** `swift test --filter BrowserViewModelTests` → PASS.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift Tests/DolphinForMacOSTests/BrowserViewModelTests.swift
git commit -m "feat: BrowserViewModel.moveDroppedItems"
```

---

## Task 3: Wiring en `IconGridView` y `FileListView` (draggable + dropDestination)

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/IconGridView.swift`
- Modify: `Sources/DolphinForMacOS/Views/FileListView.swift`

**Interfaces:**
- Consume: `BrowserViewModel.moveDroppedItems(_:into:)` (Task 2), pasado
  como closure `onMoveDropped: ([URL], URL) -> Void` desde `BrowserView`.
- Ambas vistas ganan un parámetro nuevo `currentURL: URL` y
  `onMoveDropped: ([URL], URL) -> Void`.

Antes de implementar, consultar `axiom-swift` (`transferable-ref.md`,
ya leído en este slice) para el patrón exacto de `.draggable` +
`.dropDestination` anidado y el gotcha de hit-testing — regla del
proyecto de usar Axiom antes de código SwiftUI.

- [ ] **Step 1: `IconGridView`** — en el `VStack` de cada ítem (ya tiene
  `.contentShape(Rectangle())`), agregar:

```swift
.draggable(item.url)
.dropDestination(for: URL.self) { urls, _ in
    guard item.isDirectory else { return false }
    onMoveDropped(urls, item.url)
    return true
}
```

  Y en el `ScrollView` exterior (fondo de la grilla = soltar en espacio
  vacío mueve al `currentURL` que se está viendo):

```swift
.dropDestination(for: URL.self) { urls, _ in
    onMoveDropped(urls, currentURL)
    return true
}
```

- [ ] **Step 2: `FileListView`** — en el `HStack` de cada fila, agregar
  `.contentShape(Rectangle())` (asegura que toda la fila sea
  arrastrable/soltable, no solo el ancho intrínseco del `Label`) +
  `.draggable(item.url)` + el mismo `.dropDestination` condicional a
  `item.isDirectory` que en `IconGridView`. En el `List` exterior,
  agregar el `.dropDestination` de fondo apuntando a `currentURL`.
- [ ] **Step 3:** `swift build` → `Build complete!`.
- [ ] **Step 4: Commit**

```bash
git add Sources/DolphinForMacOS/Views/IconGridView.swift Sources/DolphinForMacOS/Views/FileListView.swift
git commit -m "feat: drag & drop en IconGridView y FileListView"
```

---

## Task 4: Wiring en `DetailsListView` (limitado a la columna "Nombre")

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/DetailsListView.swift`

**Interfaces:**
- Mismos parámetros nuevos que Task 3: `currentURL: URL`,
  `onMoveDropped: ([URL], URL) -> Void`.

- [ ] **Step 1:** En el `HStack` del `TableColumn("Nombre")`, agregar
  `.contentShape(Rectangle())` + `.draggable(item.url)` + el mismo
  `.dropDestination` condicional a `item.isDirectory` que en las otras
  dos vistas. En el `Table` exterior, agregar el `.dropDestination` de
  fondo apuntando a `currentURL`.
- [ ] **Step 2:** `swift build` → `Build complete!`.
- [ ] **Step 3: Commit**

```bash
git add Sources/DolphinForMacOS/Views/DetailsListView.swift
git commit -m "feat: drag & drop en DetailsListView (columna Nombre)"
```

---

## Task 5: Wiring final en `BrowserView`

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/BrowserView.swift`

**Interfaces:**
- Consume: `IconGridView`/`FileListView`/`DetailsListView` con los
  nuevos parámetros (Tasks 3-4); `viewModel.moveDroppedItems` (Task 2).

- [ ] **Step 1:** En los 4 call sites de `FileListView`/`IconGridView`/
  `DetailsListView` dentro de `BrowserView.body` (los resultados de
  búsqueda y los 3 modos de vista), pasar:

```swift
currentURL: viewModel.currentURL,
onMoveDropped: { urls, directory in viewModel.moveDroppedItems(urls, into: directory) }
```

- [ ] **Step 2:** `swift build` → `Build complete!` (sin test
  automático para el wiring de vista en sí — mismo motivo que el resto
  de los modificadores de vista de este proyecto: no hay infraestructura
  de UI testing para arrastrar y soltar de verdad).
- [ ] **Step 3: Commit**

```bash
git add Sources/DolphinForMacOS/Views/BrowserView.swift
git commit -m "feat: drag & drop — wiring final en BrowserView, slice 15 completo"
```

---

## Task 6: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests en PASS (incluyendo los
  6 nuevos de Tasks 1-2).
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo,
  matarlo.
