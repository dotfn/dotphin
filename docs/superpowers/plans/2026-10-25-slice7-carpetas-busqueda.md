# Slice 7 — Panel de carpetas (árbol) + búsqueda — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea.

**Objetivo:** Panel de árbol de carpetas (expandible, carga perezosa) y
un campo de búsqueda por nombre dentro de la carpeta actual (recursivo).

**Alcance recortado (ponytail), documentado como diferido, no como
bug:** búsqueda indexada vía Spotlight (`NSMetadataQuery`) queda afuera
de este slice — es una integración async con su propio ciclo de vida
(notificaciones, lifecycle de la query) que amerita su propio slice. Este
slice usa un recorrido recursivo simple con `FileManager.enumerator`,
acotado a un máximo de resultados.

**Arquitectura:** `FolderTreeProvider` (sin estado) lista solo
subcarpetas de una carpeta dada. `FolderTreeRow` es una vista recursiva
que carga sus hijos perezosamente la primera vez que se expande (no se
escanea todo el filesystem de entrada). `SearchService` (sin estado)
hace la búsqueda recursiva acotada. `BrowserViewModel` gana
`searchQuery`/`searchResults`/`performSearch()`.

**Tech Stack:** Swift 6.4, SwiftUI (`DisclosureGroup` recursivo),
`FileManager.enumerator` nativo.

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`

## Global Constraints

- Mismas restricciones globales de los slices 1-6.
- La búsqueda nunca escanea más de `maxResults` (200) — evita que una
  búsqueda en `/` o `~` cuelgue la app. Se marca con un comentario
  `ponytail:` el límite y el camino de mejora (Spotlight/NSMetadataQuery).
- El árbol de carpetas nunca escanea subcarpetas que el usuario no
  expandió — carga perezosa real, no una ilusión de carga perezosa sobre
  datos ya cargados.

## Review Focus

- Expandir un nodo del árbol sin permiso de lectura → debe mostrarse
  vacío o con un indicador de error, nunca crashear ni tirar la carpeta
  entera.
- Buscar con la carpeta actual conteniendo más de `maxResults`
  coincidencias → debe cortar en el límite, no colgarse ni devolver todo.
- Buscar con un término vacío → no debe iniciar un recorrido completo del
  filesystem (eso sería carísimo), debe devolver vacío de inmediato.
- Un symlink circular dentro del árbol de carpetas → no debe causar un
  loop infinito al expandir.
- Click en un resultado de búsqueda → debe navegar a la carpeta que
  contiene ese archivo (no "abrir" el archivo en sí), consistente con
  cómo Dolphin presenta resultados de búsqueda.

---

## Task 1: `FolderTreeProvider`

**Files:**
- Create: `Sources/DolphinForMacOS/Services/FolderTreeProvider.swift`
- Test: `Tests/DolphinForMacOSTests/FolderTreeProviderTests.swift`

**Interfaces:**
- Produce:
  ```swift
  struct FolderTreeProvider {
      func subdirectories(of url: URL) -> [URL]
  }
  ```
  Solo directorios (no archivos), sin ocultos (prefijo `.`), sin seguir
  symlinks (si un symlink apunta a una carpeta, no se expande como tal
  en este nivel — se trata igual que `DirectoryReader` del slice 1:
  listado, no seguido). Ordenado por nombre (`localizedStandardCompare`).
  Nunca tira: si la carpeta no se puede leer, devuelve `[]`.

- [ ] **Step 1: Tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class FolderTreeProviderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_subdirectories_returnsOnlyDirectoriesSortedByName() throws {
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("b"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("a"), withIntermediateDirectories: true)
        try "x".write(to: tempDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let names = FolderTreeProvider().subdirectories(of: tempDir).map(\.lastPathComponent)
        XCTAssertEqual(names, ["a", "b"])
    }

    func test_subdirectories_excludesHidden() throws {
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("visible"), withIntermediateDirectories: true)
        let names = FolderTreeProvider().subdirectories(of: tempDir).map(\.lastPathComponent)
        XCTAssertEqual(names, ["visible"])
    }

    func test_subdirectories_ofUnreadableFolder_returnsEmptyArray_doesNotThrow() {
        let missing = tempDir.appendingPathComponent("doesNotExist")
        XCTAssertEqual(FolderTreeProvider().subdirectories(of: missing), [])
    }
}
```

- [ ] **Step 2:** `swift test --filter FolderTreeProviderTests` → FAIL.
- [ ] **Step 3:** Implementar con `FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys:[.isDirectoryKey])`, filtrando `isDirectory == true` y nombre sin prefijo `.`, envuelto en `try?` (si tira, `[]`).
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/FolderTreeProvider.swift Tests/DolphinForMacOSTests/FolderTreeProviderTests.swift
git commit -m "feat: FolderTreeProvider"
```

---

## Task 2: `FolderTreeRow` + panel en la sidebar

**Files:**
- Create: `Sources/DolphinForMacOS/Views/FolderTreeRow.swift`
- Modify: `Sources/DolphinForMacOS/Views/ContentView.swift`

**Interfaces:**
- Consume: `FolderTreeProvider` (Task 1).
- Produce: `struct FolderTreeRow: View { let url: URL; let onSelect: (URL) -> Void }`

Antes de implementar, consultar `axiom-swiftui` (`DisclosureGroup`,
`OutlineGroup`) — regla del proyecto. Si `OutlineGroup` no soporta carga
perezosa real con el patrón de children opcional disponible, usar
`DisclosureGroup` recursivo (ver Step 1).

- [ ] **Step 1: `FolderTreeRow`**

```swift
struct FolderTreeRow: View {
    let url: URL
    let onSelect: (URL) -> Void
    @State private var children: [URL]?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let children {
                ForEach(children, id: \.self) { child in
                    FolderTreeRow(url: child, onSelect: onSelect)
                }
            }
        } label: {
            Label(url.lastPathComponent, systemImage: "folder")
                .onTapGesture { onSelect(url) }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded && children == nil {
                children = FolderTreeProvider().subdirectories(of: url)
            }
        }
    }
}
```

- [ ] **Step 2: Agregar el panel a la sidebar en `ContentView`**

Debajo de `PlacesSidebarView`, dentro del mismo `List`/columna de
sidebar (o en una segunda `Section` del mismo `List` si `PlacesSidebarView`
se aplana ahí — lo que compile más simple sin romper la interfaz de
`PlacesSidebarView` del slice 1): una fila `FolderTreeRow(url:
FileManager.default.homeDirectoryForCurrentUser, onSelect: { url in
tabsViewModel.selectedTab?.focused.navigate(to: url) })`.

- [ ] **Step 3:** `swift build` → `Build complete!`.
- [ ] **Step 4: Commit**

```bash
git add Sources/DolphinForMacOS/Views/FolderTreeRow.swift Sources/DolphinForMacOS/Views/ContentView.swift
git commit -m "feat: FolderTreeRow con carga perezosa, agregado a la sidebar"
```

---

## Task 3: `SearchService`

**Files:**
- Create: `Sources/DolphinForMacOS/Services/SearchService.swift`
- Test: `Tests/DolphinForMacOSTests/SearchServiceTests.swift`

**Interfaces:**
- Produce:
  ```swift
  struct SearchService {
      func search(for query: String, in directory: URL, maxResults: Int = 200) -> [FileItem]
  }
  ```
  Si `query` está vacío, devuelve `[]` sin recorrer nada. Recorre
  recursivamente con `FileManager.default.enumerator(at:includingPropertiesForKeys:options: [.skipsHiddenFiles])`,
  matchea nombre case-insensitive substring, corta en `maxResults`.
  // ponytail: recorrido recursivo simple, no indexado — si se necesita
  // escalar a carpetas con millones de archivos, migrar a
  // NSMetadataQuery (Spotlight).

- [ ] **Step 1: Tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class SearchServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_search_withEmptyQuery_returnsEmptyWithoutScanning() {
        XCTAssertEqual(SearchService().search(for: "", in: tempDir), [])
    }

    func test_search_findsMatchInNestedSubfolder() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "x".write(to: sub.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)
        let results = SearchService().search(for: "report", in: tempDir)
        XCTAssertEqual(results.map(\.name), ["Report.txt"])
    }

    func test_search_capsAtMaxResults() throws {
        for i in 0..<10 {
            try "x".write(to: tempDir.appendingPathComponent("match\(i).txt"), atomically: true, encoding: .utf8)
        }
        let results = SearchService().search(for: "match", in: tempDir, maxResults: 3)
        XCTAssertEqual(results.count, 3)
    }
}
```

- [ ] **Step 2:** `swift test --filter SearchServiceTests` → FAIL.
- [ ] **Step 3:** Implementar. El `enumerator` con `includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]`; parar de iterar en cuanto se llega a `maxResults`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Services/SearchService.swift Tests/DolphinForMacOSTests/SearchServiceTests.swift
git commit -m "feat: SearchService (recorrido recursivo acotado, no indexado)"
```

---

## Task 4: Wiring de búsqueda en `BrowserViewModel` + UI

**Files:**
- Modify: `Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift`
- Modify: `Tests/DolphinForMacOSTests/BrowserViewModelTests.swift`
- Modify: `Sources/DolphinForMacOS/Views/BrowserView.swift`

**Interfaces:**
- Consume: `SearchService` (Task 3).
- Produce:
  ```swift
  var searchQuery: String = ""
  private(set) var searchResults: [FileItem] = []

  func performSearch()
  ```
  `navigate(to:)` limpia `searchQuery`/`searchResults`. `performSearch()`
  no hace nada si `searchQuery` está vacío (deja `searchResults = []`).

- [ ] **Step 1: Tests que fallan**

```swift
func test_performSearch_findsNestedMatch() throws {
    let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try "x".write(to: sub.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.searchQuery = "report"
    vm.performSearch()
    XCTAssertEqual(vm.searchResults.map(\.name), ["Report.txt"])
}

func test_navigate_clearsSearch() throws {
    let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let vm = BrowserViewModel(startingAt: tempDir)
    vm.searchQuery = "algo"
    vm.performSearch()
    vm.navigate(to: sub)
    XCTAssertEqual(vm.searchQuery, "")
    XCTAssertEqual(vm.searchResults, [])
}
```

- [ ] **Step 2:** `swift test --filter BrowserViewModelTests` → FAIL.
- [ ] **Step 3:** Implementar (agregar `search: SearchService = SearchService()` al `init`, mismo patrón que `reader`/`store`/`operations`).
- [ ] **Step 4:** PASS (todos, incluyendo slices 1-6).
- [ ] **Step 5: UI en `BrowserView`**

Un `TextField` de búsqueda junto al de filtro (o un toggle entre
"Filtrar" y "Buscar", lo que sea más simple de cablear sin romper
`FilterBarView`), que llama `viewModel.performSearch()` en
`.onSubmit` o en cada cambio de `searchQuery`. Cuando
`!viewModel.searchResults.isEmpty`, la lista principal muestra
`searchResults` en vez de `filteredItems`, y el `onOpen` de los
resultados navega a `item.url.deletingLastPathComponent()` (la carpeta
contenedora), no abre el archivo.

- [ ] **Step 6:** `swift build` → `Build complete!`.
- [ ] **Step 7: Commit**

```bash
git add Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift Tests/DolphinForMacOSTests/BrowserViewModelTests.swift Sources/DolphinForMacOS/Views/BrowserView.swift
git commit -m "feat: búsqueda recursiva acotada integrada en BrowserViewModel y BrowserView"
```

---

## Task 5: Suite completa + smoke run

- [ ] **Step 1:** `swift test` → todos los tests de slices 1-7 en PASS.
- [ ] **Step 2:** `swift build && swift run &`, confirmar proceso vivo, matarlo.
- [ ] **Step 3:** sin commit si no hay cambios pendientes.
