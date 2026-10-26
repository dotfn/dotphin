# Slice 1 — Ventana + Sidebar de Places + Navegador central — Plan de implementación

> **Para ejecutores agénticos:** SUB-SKILL REQUERIDO: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea. Los pasos usan sintaxis de checkbox (`- [ ]`) para seguimiento.

**Objetivo:** Una app de macOS que abre con sidebar de Places (marcadores +
volúmenes montados reales) y un navegador central con breadcrumb editable y
lista de archivos, navegando el filesystem local real. Es el primer slice
vertical: tiene que compilar y poder probarse en la app real, no es un
prototipo de UI con datos falsos.

**Arquitectura:** SwiftUI puro. `NavigationSplitView` con sidebar
(`PlacesSidebarView`) y detalle (`BrowserView` = breadcrumb + lista). Un
único `BrowserViewModel` `@Observable` es la fuente de verdad de la
ubicación actual; los servicios (`DirectoryReader`, `PlacesProvider`) son
tipos sin estado que el view model usa.

**Tech Stack:** Swift 6.4, SwiftUI, Swift Package Manager (sin `.xcodeproj`).
Sin dependencias de terceros.

**Spec:** `docs/superpowers/specs/2026-10-25-dolphin-macos-design.md`
(ver también `docs/decisions.md` por las decisiones de toolchain tomadas al
preparar este plan).

## Global Constraints

- macOS mínimo: 27+ únicamente. `platforms: [.macOS(.v27)]` en Package.swift.
- `// swift-tools-version: 6.4` (requerido para `.v27`).
- Sin App Sandbox, sin entitlements. La app corre solo en esta Mac, lanzada
  desde Xcode (abrir `Package.swift` directamente, no crear `.xcodeproj`).
- TCC sigue activo aunque no haya sandbox: cualquier lectura de directorio
  que falle por permisos se trata como estado explícito de la UI, nunca
  como lista vacía silenciosa.
- Sin dependencias de terceros en este slice.
- Regla del usuario para todo el proyecto: antes de escribir código
  SwiftUI/macOS/de diseño en cualquier task, consultar el skill Axiom
  correspondiente (axiom-swiftui para vistas/estado, axiom-macos para
  `NavigationSplitView`/particularidades de macOS, axiom-design para
  nombres exactos de SF Symbols) — no solo cuando algo falla.
- Orden por defecto de archivos en una carpeta: directorios primero, luego
  case-insensitive por nombre ascendente. Fijo, no configurable en este
  slice.
- Archivos ocultos (nombre empieza con `.`): ocultos por defecto. No hay
  toggle en este slice.

## Review Focus

- Carpeta vacía → debe mostrarse como lista vacía, no como error.
- Carpeta sin permiso de lectura (TCC) → debe mostrar un estado explícito
  de "sin acceso" con forma de abrir Configuración del Sistema, nunca una
  lista vacía silenciosa.
- Symlink a una carpeta → debe listarse como su propio item (no seguirlo ni
  listar su contenido inline), para no arriesgar un loop si el symlink es
  circular.
- Archivos ocultos (dotfiles) → deben estar excluidos por defecto de forma
  determinística, no como efecto secundario del orden.
- Navegar a una ruta que deja de existir (carpeta borrada o volumen
  expulsado mientras se navega) → debe degradar a un estado de error, nunca
  crashear ni quedar en un estado inconsistente.

---

## Task 1: Scaffold del paquete + ventana mínima

**Files:**
- Create: `Package.swift`
- Create: `Sources/DolphinForMacOS/App/DolphinForMacOSApp.swift`
- Modify: `docs/decisions.md` (agregar entrada si surge algo no previsto)

**Interfaces:**
- Produce: el target ejecutable `DolphinForMacOS`, product name usado por
  Xcode para correr/debuggear la app.

- [ ] **Step 1: Crear `Package.swift`**

```swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "DolphinForMacOS",
    platforms: [.macOS(.v27)],
    targets: [
        .executableTarget(name: "DolphinForMacOS", path: "Sources/DolphinForMacOS"),
        .testTarget(name: "DolphinForMacOSTests", dependencies: ["DolphinForMacOS"], path: "Tests/DolphinForMacOSTests"),
    ]
)
```

- [ ] **Step 2: Crear `Sources/DolphinForMacOS/App/DolphinForMacOSApp.swift` con una ventana placeholder**

```swift
import SwiftUI

@main
struct DolphinForMacOSApp: App {
    var body: some Scene {
        WindowGroup {
            Text("DolphinForMacOS")
        }
    }
}
```

- [ ] **Step 3: Verificar que compila**

Run: `swift build`
Expected: `Build complete!` sin errores.

- [ ] **Step 4: Verificar que corre como app real**

Run: `swift run &` (o abrir `Package.swift` en Xcode y tocar Run), esperar
unos segundos, confirmar que el proceso sigue vivo (`ps aux | grep
DolphinForMacOS`) y luego matarlo. Esto ya se validó una vez a mano en el
scratchpad durante la preparación del plan; este paso lo repite dentro del
proyecto real.
Expected: el proceso aparece corriendo (no termina solo ni crashea).

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/DolphinForMacOS/App/DolphinForMacOSApp.swift
git commit -m "feat: scaffold de Package.swift con ventana placeholder"
```

---

## Task 2: `FileItem` + `DirectoryReader`

**Files:**
- Create: `Sources/DolphinForMacOS/Models/FileItem.swift`
- Create: `Sources/DolphinForMacOS/Services/DirectoryReader.swift`
- Test: `Tests/DolphinForMacOSTests/DirectoryReaderTests.swift`

**Interfaces:**
- Produce:
  ```swift
  struct FileItem: Identifiable, Hashable {
      let id: URL // == url
      let url: URL
      let name: String
      let isDirectory: Bool
      let isSymbolicLink: Bool
      let size: Int64?
      let modificationDate: Date?
  }

  enum DirectoryReadError: Error, Equatable {
      case permissionDenied(URL)
      case notFound(URL)
      case other(String)
  }

  struct DirectoryReader {
      var showsHiddenFiles: Bool = false
      func contents(of url: URL) throws -> [FileItem]
  }
  ```
  `contents(of:)` ordena directorios primero, luego nombre ascendente
  case-insensitive (`localizedStandardCompare` o equivalente). Oculta
  dotfiles cuando `showsHiddenFiles == false`. Un symlink se reporta como
  un único `FileItem` (no se sigue ni se expande su contenido).

- [ ] **Step 1: Escribir los tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class DirectoryReaderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_contentsOfEmptyDirectory_returnsEmptyArray() throws {
        let reader = DirectoryReader()
        XCTAssertEqual(try reader.contents(of: tempDir), [])
    }

    func test_contentsHidesDotfilesByDefault() throws {
        try "x".write(to: tempDir.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        let reader = DirectoryReader()
        let names = try reader.contents(of: tempDir).map(\.name)
        XCTAssertEqual(names, ["visible.txt"])
    }

    func test_contentsIncludesDotfilesWhenShowsHiddenFilesTrue() throws {
        try "x".write(to: tempDir.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        var reader = DirectoryReader()
        reader.showsHiddenFiles = true
        let names = try reader.contents(of: tempDir).map(\.name)
        XCTAssertTrue(names.contains(".hidden"))
    }

    func test_contentsOrdersDirectoriesFirstThenCaseInsensitiveName() throws {
        try "x".write(to: tempDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appendingPathComponent("A.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("zfolder"), withIntermediateDirectories: true)
        let reader = DirectoryReader()
        let names = try reader.contents(of: tempDir).map(\.name)
        XCTAssertEqual(names, ["zfolder", "A.txt", "b.txt"])
    }

    func test_contentsIncludesSymbolicLinkAsItsOwnItem_doesNotFollowIt() throws {
        let target = tempDir.appendingPathComponent("realFolder")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = tempDir.appendingPathComponent("linkToFolder")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let reader = DirectoryReader()
        let items = try reader.contents(of: tempDir)
        let linkItem = items.first { $0.name == "linkToFolder" }
        XCTAssertEqual(linkItem?.isSymbolicLink, true)
    }

    func test_contentsOfNonExistentDirectory_throwsNotFound() {
        let reader = DirectoryReader()
        let missing = tempDir.appendingPathComponent("doesNotExist")
        XCTAssertThrowsError(try reader.contents(of: missing)) { error in
            XCTAssertEqual(error as? DirectoryReadError, .notFound(missing))
        }
    }

    func test_contentsOfUnreadableDirectory_throwsPermissionDenied() throws {
        let locked = tempDir.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let reader = DirectoryReader()
        XCTAssertThrowsError(try reader.contents(of: locked)) { error in
            XCTAssertEqual(error as? DirectoryReadError, .permissionDenied(locked))
        }
    }
}
```

- [ ] **Step 2: Correr los tests y confirmar que fallan**

Run: `swift test --filter DirectoryReaderTests`
Expected: FAIL — `FileItem`/`DirectoryReader` no existen todavía.

- [ ] **Step 3: Implementar `FileItem` en `Sources/DolphinForMacOS/Models/FileItem.swift`**

Struct de solo datos según la firma de arriba. `id` devuelve `url`.

- [ ] **Step 4: Implementar `DirectoryReader` en `Sources/DolphinForMacOS/Services/DirectoryReader.swift`**

Usar `FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys:options: [.skipsSubdirectoryDescendants]` no aplica aquí, no hace falta) con las keys `.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey`. Mapear
`NSError` con `NSFileReadNoPermissionError` a `.permissionDenied(url)`,
`NSFileReadNoSuchFileError` a `.notFound(url)`, cualquier otro a `.other`.
Filtrar dotfiles salvo `showsHiddenFiles`. Ordenar con
`sorted { ... }` directorios primero, después
`$0.name.localizedStandardCompare($1.name) == .orderedAscending`.

- [ ] **Step 5: Correr los tests y confirmar que pasan**

Run: `swift test --filter DirectoryReaderTests`
Expected: PASS, todos los casos.

- [ ] **Step 6: Commit**

```bash
git add Sources/DolphinForMacOS/Models/FileItem.swift Sources/DolphinForMacOS/Services/DirectoryReader.swift Tests/DolphinForMacOSTests/DirectoryReaderTests.swift
git commit -m "feat: FileItem y DirectoryReader con orden, dotfiles y symlinks"
```

---

## Task 3: `PlaceItem` + `PlacesProvider`

**Files:**
- Create: `Sources/DolphinForMacOS/Models/PlaceItem.swift`
- Create: `Sources/DolphinForMacOS/Services/PlacesProvider.swift`
- Test: `Tests/DolphinForMacOSTests/PlacesProviderTests.swift`

**Interfaces:**
- Consume: nada de tasks anteriores (independiente de `FileItem`).
- Produce:
  ```swift
  enum PlaceKind: Equatable {
      case bookmark
      case volume
  }

  struct PlaceItem: Identifiable, Hashable {
      let id: URL // == url
      let url: URL
      let name: String
      let systemImage: String
      let kind: PlaceKind
  }

  struct PlacesProvider {
      func staticBookmarks() -> [PlaceItem]
      func mountedVolumes() -> [PlaceItem]
      func allPlaces() -> [PlaceItem] // staticBookmarks() + mountedVolumes()
  }
  ```
  `staticBookmarks()` devuelve, en este orden: Home (`house`), Desktop
  (`desktopcomputer`), Documents (`doc.text`), Downloads
  (`arrow.down.circle`) — URLs vía
  `FileManager.default.homeDirectoryForCurrentUser` y
  `FileManager.default.urls(for:in:)`. Antes de fijar los nombres de SF
  Symbol definitivos, consultar `axiom-design` (sf-symbols-ref.md) por el
  nombre exacto — los de aquí son el default razonable si el skill no
  sugiere otra cosa.
  `mountedVolumes()` usa
  `FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeIsInternalKey], options: [.skipHiddenVolumes])`,
  `systemImage` es `"internaldrive"` si `volumeIsInternalKey` es true, si no
  `"externaldrive"`.

- [ ] **Step 1: Escribir los tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class PlacesProviderTests: XCTestCase {
    func test_staticBookmarks_returnsHomeDesktopDocumentsDownloadsInOrder() {
        let provider = PlacesProvider()
        let names = provider.staticBookmarks().map(\.name)
        XCTAssertEqual(names, ["Home", "Desktop", "Documents", "Downloads"])
    }

    func test_staticBookmarks_homeURLMatchesFileManager() {
        let provider = PlacesProvider()
        let home = provider.staticBookmarks().first { $0.name == "Home" }
        XCTAssertEqual(home?.url, FileManager.default.homeDirectoryForCurrentUser)
    }

    func test_mountedVolumes_includesBootVolume() {
        let provider = PlacesProvider()
        let volumes = provider.mountedVolumes()
        XCTAssertFalse(volumes.isEmpty, "debe incluir al menos el volumen de arranque")
    }

    func test_allPlaces_isBookmarksThenVolumes() {
        let provider = PlacesProvider()
        let all = provider.allPlaces()
        let bookmarks = provider.staticBookmarks()
        XCTAssertEqual(Array(all.prefix(bookmarks.count)), bookmarks)
    }
}
```

- [ ] **Step 2: Correr los tests y confirmar que fallan**

Run: `swift test --filter PlacesProviderTests`
Expected: FAIL — los tipos no existen.

- [ ] **Step 3: Implementar `PlaceItem`**

Struct de solo datos según la firma de arriba.

- [ ] **Step 4: Implementar `PlacesProvider`**

Según el comportamiento fijado arriba. `allPlaces()` es la concatenación
literal.

- [ ] **Step 5: Correr los tests y confirmar que pasan**

Run: `swift test --filter PlacesProviderTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/DolphinForMacOS/Models/PlaceItem.swift Sources/DolphinForMacOS/Services/PlacesProvider.swift Tests/DolphinForMacOSTests/PlacesProviderTests.swift
git commit -m "feat: PlaceItem y PlacesProvider (bookmarks + volúmenes montados)"
```

---

## Task 4: `BrowserViewModel`

**Files:**
- Create: `Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift`
- Test: `Tests/DolphinForMacOSTests/BrowserViewModelTests.swift`

**Interfaces:**
- Consume: `FileItem`, `DirectoryReadError`, `DirectoryReader.contents(of:)`
  (Task 2).
- Produce:
  ```swift
  @Observable
  final class BrowserViewModel {
      private(set) var currentURL: URL
      private(set) var items: [FileItem] = []
      private(set) var error: DirectoryReadError?

      init(startingAt url: URL, reader: DirectoryReader = DirectoryReader())
      func navigate(to url: URL)
      func goUp()
      func refresh()
  }
  ```
  `navigate(to:)` y `refresh()` llaman a `reader.contents(of:)`; si tira,
  `items = []` y `error` queda seteado; si no tira, `items` se llena y
  `error = nil`. `goUp()` navega a
  `currentURL.deletingLastPathComponent()` salvo que ya esté en `/`.

- [ ] **Step 1: Escribir los tests que fallan**

```swift
import XCTest
@testable import DolphinForMacOS

final class BrowserViewModelTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_init_loadsItemsForStartingURL() throws {
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        XCTAssertEqual(vm.items.map(\.name), ["a.txt"])
        XCTAssertNil(vm.error)
    }

    func test_navigateToSubfolder_updatesCurrentURLAndItems() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.navigate(to: sub)
        XCTAssertEqual(vm.currentURL, sub)
        XCTAssertEqual(vm.items, [])
    }

    func test_goUp_movesToParentDirectory() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let vm = BrowserViewModel(startingAt: sub)
        vm.goUp()
        XCTAssertEqual(vm.currentURL, tempDir)
    }

    func test_navigateToDeletedDirectory_setsNotFoundError_doesNotCrash() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let vm = BrowserViewModel(startingAt: tempDir)
        try FileManager.default.removeItem(at: sub)
        vm.navigate(to: sub)
        XCTAssertEqual(vm.error, .notFound(sub))
        XCTAssertEqual(vm.items, [])
    }
}
```

- [ ] **Step 2: Correr los tests y confirmar que fallan**

Run: `swift test --filter BrowserViewModelTests`
Expected: FAIL — `BrowserViewModel` no existe.

- [ ] **Step 3: Implementar `BrowserViewModel`**

Consultar `axiom-swiftui` por el patrón correcto de `@Observable` en una
clase que SwiftUI va a observar desde una vista (regla del proyecto: usar
Axiom antes de escribir código de estado/SwiftUI).

- [ ] **Step 4: Correr los tests y confirmar que pasan**

Run: `swift test --filter BrowserViewModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/ViewModels/BrowserViewModel.swift Tests/DolphinForMacOSTests/BrowserViewModelTests.swift
git commit -m "feat: BrowserViewModel con navigate/goUp/refresh y manejo de errores"
```

---

## Task 5: Vistas — sidebar, breadcrumb, lista, estado de permiso denegado

**Files:**
- Create: `Sources/DolphinForMacOS/Views/PlacesSidebarView.swift`
- Create: `Sources/DolphinForMacOS/Views/BreadcrumbView.swift`
- Create: `Sources/DolphinForMacOS/Views/FileListView.swift`
- Create: `Sources/DolphinForMacOS/Views/PermissionDeniedView.swift`
- Create: `Sources/DolphinForMacOS/Views/BrowserView.swift`

**Interfaces:**
- Consume: `PlaceItem`/`PlacesProvider` (Task 3), `FileItem` (Task 2),
  `BrowserViewModel` (Task 4).
- Produce:
  ```swift
  struct PlacesSidebarView: View {
      let places: [PlaceItem]
      let onSelect: (PlaceItem) -> Void
  }

  struct BreadcrumbView: View {
      let url: URL
      let onNavigate: (URL) -> Void
  }

  struct FileListView: View {
      let items: [FileItem]
      let onOpen: (FileItem) -> Void
  }

  struct PermissionDeniedView: View {
      let url: URL
  }

  struct BrowserView: View {
      let viewModel: BrowserViewModel
  }
  ```

Antes de escribir estas vistas, consultar `axiom-macos` (NavigationSplitView,
List/Table en macOS) y `axiom-design` (colores semánticos, SF Symbols,
tipografía) — regla del proyecto.

- [ ] **Step 1: Implementar `PlacesSidebarView`**

`List(places) { place in ... }` con `Label(place.name, systemImage:
place.systemImage)`, `.onTapGesture` o selección de `List` llama
`onSelect(place)`.

- [ ] **Step 2: Implementar `BreadcrumbView`**

Descompone `url` en sus `pathComponents`, un `Button` por componente que
llama `onNavigate` con la URL acumulada hasta ese punto.

- [ ] **Step 3: Implementar `FileListView`**

`List(items) { item in ... }`, ícono de carpeta/archivo según
`item.isDirectory`, doble click/doble tap sobre un directorio llama
`onOpen(item)` (sobre un archivo no hace nada en este slice).

- [ ] **Step 4: Implementar `PermissionDeniedView`**

Texto explicando que falta acceso a `url.path`, botón que abre
`NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)`.

- [ ] **Step 5: Implementar `BrowserView`**

`VStack { BreadcrumbView(url: viewModel.currentURL, onNavigate:
viewModel.navigate); if let error = viewModel.error { ... (mapear a
PermissionDeniedView si es .permissionDenied, un texto simple si no) }
else { FileListView(items: viewModel.items, onOpen: { if $0.isDirectory {
viewModel.navigate(to: $0.url) } }) } }`.

- [ ] **Step 6: Verificar que compila**

Run: `swift build`
Expected: `Build complete!` sin errores.

- [ ] **Step 7: Commit**

```bash
git add Sources/DolphinForMacOS/Views
git commit -m "feat: vistas de sidebar, breadcrumb, lista de archivos y permiso denegado"
```

---

## Task 6: Integración final — `ContentView` + `App`

**Files:**
- Create: `Sources/DolphinForMacOS/Views/ContentView.swift`
- Modify: `Sources/DolphinForMacOS/App/DolphinForMacOSApp.swift`

**Interfaces:**
- Consume: todo lo anterior.
- Produce: nada que otra task consuma — es el final del slice.

- [ ] **Step 1: Implementar `ContentView`**

```swift
struct ContentView: View {
    @State private var viewModel = BrowserViewModel(
        startingAt: FileManager.default.homeDirectoryForCurrentUser
    )
    private let places = PlacesProvider().allPlaces()

    var body: some View {
        NavigationSplitView {
            PlacesSidebarView(places: places) { place in
                viewModel.navigate(to: place.url)
            }
        } detail: {
            BrowserView(viewModel: viewModel)
        }
    }
}
```

- [ ] **Step 2: Reemplazar el placeholder en `DolphinForMacOSApp`**

`WindowGroup { ContentView() }` en vez del `Text` del Task 1.

- [ ] **Step 3: Correr toda la suite de tests**

Run: `swift test`
Expected: todos los tests de Tasks 2-4 en PASS.

- [ ] **Step 4: Correr la app y probar a mano**

Abrir `Package.swift` en Xcode, Run. Verificar: la sidebar muestra Home,
Desktop, Documents, Downloads y al menos el volumen de arranque; clickear
cada uno navega el panel central; doble-click en una carpeta navega hacia
adentro; el breadcrumb permite volver a cualquier ancestro; navegar a una
carpeta sin permiso (ej. la carpeta Trash de otro usuario, o
`~/Library/Application Support` de otra app) muestra el estado de permiso
denegado en vez de una lista vacía.

- [ ] **Step 5: Commit**

```bash
git add Sources/DolphinForMacOS/Views/ContentView.swift Sources/DolphinForMacOS/App/DolphinForMacOSApp.swift
git commit -m "feat: integra sidebar + navegador en ContentView — slice 1 completo"
```
