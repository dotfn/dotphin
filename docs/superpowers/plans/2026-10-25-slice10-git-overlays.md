# Slice 10 — Overlays de control de versiones (git) — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Badges de estado de git (modificado/agregado/borrado/sin
seguimiento/renombrado) en las filas de archivos cuando la carpeta
actual está dentro de un repo git. Shell-out a `git status
--porcelain`, cacheado por carpeta (se calcula una vez por `load()`,
no en cada render).

**Alcance recortado (ponytail), documentado como diferido, no como
bug:** no hay refresco automático cuando el estado de git cambia por
fuera de la app (no hay file-watching, ya aceptado desde el slice 1) —
hay que navegar afuera y volver, o un refresh manual, para verlo
actualizado. Tampoco se distingue staged vs. unstaged con íconos
distintos, un solo badge por archivo.

**Arquitectura:** `GitStatusProvider` (sin estado) corre `git status
--porcelain=v1` vía `Process` y devuelve un diccionario
`[String: GitFileStatus]` keyeado por nombre de archivo dentro de la
carpeta pedida. Fuera de un repo git (o sin binario `git`), devuelve
`[:]` — nunca tira, un overlay ausente no es un error. `BrowserViewModel`
lo cachea en `gitStatuses`, recalculado en cada `load()`. Las 3 vistas
de listado reciben `gitStatuses` y dibujan un badge chico si hay
entrada para ese nombre.

**Tech Stack:** Swift 6.4, `Foundation.Process` (shell-out a `git`,
nativo del sistema, sin dependencias nuevas).

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`

## Global Constraints

- Mismas restricciones globales de los slices 1-9.
- `GitStatusProvider` nunca tira ni bloquea la UI por más de lo que
  tarda `git status` en un repo real (operación ya síncrona en el main
  actor, mismo precedente aceptado del slice 1 — si se vuelve
  perceptible en un repo gigante, se revisita).
- Si el binario `git` no está en el `PATH` del proceso, se degrada a
  "sin overlays", nunca crashea ni bloquea la navegación normal.

## Review Focus

- Carpeta que NO es un repo git → `gitStatuses` vacío, navegación y
  listado funcionan exactamente igual que antes de este slice.
- Un archivo sin seguimiento (`??` en porcelain) → badge de "sin
  seguimiento", no se confunde con "modificado".
- Un archivo borrado del working tree pero todavía en el índice → no
  debe crashear al no encontrarlo en `items` (el archivo borrado no
  aparece en el listado del slice 1, así que su entrada en
  `gitStatuses` simplemente no se usa — no debe intentar renderizar un
  `FileItem` que no existe).
- Un archivo modificado dentro de una subcarpeta (no directo en la
  carpeta actual) → la carpeta contenedora debe mostrar algún
  indicador agregado, no fallar en silencio ni intentar indexar un
  `FileItem` con un nombre que contiene "/".
- `git status` devolviendo un formato inesperado (binario de git roto,
  salida vacía, etc.) → debe tratarse como "sin overlays", no crashear
  el parseo.

---

## Task 1: `GitStatusProvider`

**Files:**
- Create: `Sources/DolphinForMacOS/Services/GitStatusProvider.swift`
- Test: `Tests/DolphinForMacOSTests/GitStatusProviderTests.swift`

**Interfaces:**
- Produce:
  ```swift
  enum GitFileStatus {
      case modified, added, deleted, untracked, renamed
  }

  struct GitStatusProvider {
      func statuses(in directory: URL) -> [String: GitFileStatus]
  }
  ```
  Corre `/usr/bin/env git -C <directory> status --porcelain=v1 --untracked-files=all`
  vía `Process`. Parsea cada línea `XY PATH` (o `XY PATH -> PATH2` para
  renombres, usar `PATH2`). Si `PATH` no contiene `/`, es un archivo
  directo de `directory`: key = `PATH`. Si contiene `/`, es algo dentro
  de una subcarpeta: key = el primer componente (nombre de la
  subcarpeta), valor `.modified` si no hay ya una entrada para esa key
  (agregado simple, no pisa un estado más específico ya puesto). Mapeo
  de código a estado: contiene `"?"` → `.untracked`; si no, contiene
  `"A"` → `.added`; si no, contiene `"D"` → `.deleted`; si no, contiene
  `"R"` → `.renamed`; si no, contiene `"M"` → `.modified`; cualquier
  otra cosa se ignora. Si el proceso falla (no es un repo, binario
  ausente, exit code != 0) o la salida no se puede parsear, devuelve
  `[:]`.

- [ ] **Step 1: Tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class GitStatusProviderTests: XCTestCase {
    private var repoDir: URL!

    override func setUpWithError() throws {
        repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try run("git", ["init", "-q"], in: repoDir)
        try run("git", ["config", "user.email", "test@example.com"], in: repoDir)
        try run("git", ["config", "user.name", "Test"], in: repoDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoDir)
    }

    private func run(_ bin: String, _ args: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [bin] + args
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
    }

    func test_statuses_onNonGitFolder_returnsEmpty() {
        let notARepo = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: notARepo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: notARepo) }
        XCTAssertEqual(GitStatusProvider().statuses(in: notARepo), [:])
    }

    func test_statuses_detectsUntrackedFile() throws {
        try "x".write(to: repoDir.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let statuses = GitStatusProvider().statuses(in: repoDir)
        XCTAssertEqual(statuses["new.txt"], .untracked)
    }

    func test_statuses_detectsModifiedTrackedFile() throws {
        let fileURL = repoDir.appendingPathComponent("tracked.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        try run("git", ["add", "."], in: repoDir)
        try run("git", ["commit", "-q", "-m", "initial"], in: repoDir)
        try "y".write(to: fileURL, atomically: true, encoding: .utf8)
        let statuses = GitStatusProvider().statuses(in: repoDir)
        XCTAssertEqual(statuses["tracked.txt"], .modified)
    }

    func test_statuses_aggregatesNestedChangeOnContainingFolder() throws {
        let sub = repoDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "x".write(to: sub.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)
        let statuses = GitStatusProvider().statuses(in: repoDir)
        XCTAssertEqual(statuses["sub"], .modified)
    }
}
```

- [ ] **Step 2:** `swift test --filter GitStatusProviderTests` → FAIL.
- [ ] **Step 3:** Implementar según lo descrito arriba.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/GitStatusProvider.swift Tests/DolphinForMacOSTests/GitStatusProviderTests.swift
git commit -m "feat: GitStatusProvider (shell-out a git status --porcelain)"
```

---

## Task 2: Cache en `BrowserViewModel`

**Files:**
- Modify: `Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift`
- Modify: `Tests/DolphinForMacOSTests/BrowserViewModelTests.swift`

**Interfaces:**
- Consume: `GitStatusProvider`, `GitFileStatus` (Task 1).
- Produce:
  ```swift
  private(set) var gitStatuses: [String: GitFileStatus] = [:]
  // init gana: gitStatus: GitStatusProvider = GitStatusProvider()
  ```
  Se recalcula en cada `load(_:)`, igual momento que `items`.

- [ ] **Step 1: Test que falla**

```swift
func test_load_populatesGitStatusesForGitRepo() throws {
    // reutiliza el helper de GitStatusProviderTests si está disponible,
    // o corre `git init -q` directo sobre tempDir con Process.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "init", "-q"]
    process.currentDirectoryURL = tempDir
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()

    try "x".write(to: tempDir.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)
    XCTAssertEqual(vm.gitStatuses["new.txt"], .untracked)
}
```

- [ ] **Step 2:** `swift test --filter test_load_populatesGitStatusesForGitRepo` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** PASS (todos, incluyendo slices 1-9).
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift Tests/DolphinForMacOSTests/BrowserViewModelTests.swift
git commit -m "feat: BrowserViewModel cachea gitStatuses por carpeta"
```

---

## Task 3: Badges en las 3 vistas de listado

**Files:**
- Modify: `Sources/DolphinForMacOS/Views/FileListView.swift`
- Modify: `Sources/DolphinForMacOS/Views/IconGridView.swift`
- Modify: `Sources/DolphinForMacOS/Views/DetailsListView.swift`
- Modify: `Sources/DolphinForMacOS/Views/BrowserView.swift`

**Interfaces:**
- Consume: `GitFileStatus`, `BrowserViewModel.gitStatuses` (Task 2).
- Produce: las 3 vistas ganan `let gitStatuses: [String: GitFileStatus]`.

Antes de implementar, consultar `axiom-design` (sf-symbols.md, color
por estado) — regla del proyecto.

- [ ] **Step 1: Badge compartido**

Un pequeño `Circle().fill(color).frame(width: 6, height: 6)` (o un SF
Symbol chico) al lado del nombre, color según `GitFileStatus`:
`.modified` → naranja, `.added` → verde, `.deleted` → rojo,
`.untracked` → gris, `.renamed` → azul. `nil` (sin entrada en el
diccionario) → nada, ni espacio reservado que desalinee la fila.

- [ ] **Step 2: Wiring en las 3 vistas + `BrowserView`**

Cada fila consulta `gitStatuses[item.name]` y dibuja el badge si no es
`nil`. `BrowserView` pasa `viewModel.gitStatuses` a las tres.

- [ ] **Step 3:** `swift build` → `Build complete!`.
- [ ] **Step 4: Commit**

```bash
git add Sources/DolphinForMacOS/Views/FileListView.swift Sources/DolphinForMacOS/Views/IconGridView.swift Sources/DolphinForMacOS/Views/DetailsListView.swift Sources/DolphinForMacOS/Views/BrowserView.swift
git commit -m "feat: badges de estado de git en las vistas de listado — slice 10 completo"
```

---

## Task 4: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests de slices 1-10 en PASS.
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo, matarlo.
- [ ] **Step 3:** sin commit si no hay cambios pendientes.
