import AppKit
import XCTest
@testable import Dotphin

/// Barra lateral al estilo Finder: Favoritos (orden propio) y Ubicaciones,
/// con elementos que se ocultan y vuelven desde Ajustes.
final class SidebarPlacesTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var provider: PlacesProvider!
    private var tempDir: URL!

    override func setUpWithError() throws {
        suiteName = "test.sidebar.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        provider = PlacesProvider(defaults: defaults)
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("Proyectos"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func names(_ places: [PlaceItem]) -> [String] {
        places.map(\.name)
    }

    func test_favorites_startLikeFinder_thenTheUserBookmarks() {
        provider.addBookmark(for: tempDir.appendingPathComponent("Proyectos"))
        XCTAssertEqual(names(provider.favorites()), ["Desktop", "Documents", "Downloads", "Applications", "Proyectos"])
    }

    func test_movingAFavorite_isKept() {
        provider.addBookmark(for: tempDir.appendingPathComponent("Proyectos"))
        provider.moveFavorites(fromOffsets: [4], toOffset: 0)
        XCTAssertEqual(names(provider.favorites()), ["Proyectos", "Desktop", "Documents", "Downloads", "Applications"])
        XCTAssertEqual(names(PlacesProvider(defaults: defaults).favorites()), names(provider.favorites()), "se guarda")
    }

    func test_movingWithHiddenFavorites_keepsTheHiddenOnesInPlace() throws {
        let documents = try XCTUnwrap(provider.favorites().first { $0.name == "Documents" })
        provider.setHiddenInSidebar(true, for: documents)
        // Visibles: Desktop, Downloads, Applications. Applications pasa al principio.
        provider.moveFavorites(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(names(provider.favorites()), ["Applications", "Desktop", "Downloads"])
        provider.setHiddenInSidebar(false, for: documents)
        XCTAssertEqual(names(provider.favorites()), ["Applications", "Desktop", "Documents", "Downloads"])
    }

    func test_hidingAndShowing_aBuiltInFavorite() throws {
        let downloads = try XCTUnwrap(provider.favorites().first { $0.name == "Downloads" })
        provider.removeFromSidebar(downloads)
        XCTAssertFalse(names(provider.favorites()).contains("Downloads"))
        XCTAssertTrue(names(provider.favorites(includingHidden: true)).contains("Downloads"), "sigue disponible en Ajustes")
        provider.setHiddenInSidebar(false, for: downloads)
        XCTAssertTrue(names(provider.favorites()).contains("Downloads"))
    }

    func test_removingAUserBookmark_deletesIt() throws {
        provider.addBookmark(for: tempDir.appendingPathComponent("Proyectos"))
        let bookmark = try XCTUnwrap(provider.favorites().first { $0.name == "Proyectos" })
        provider.removeFromSidebar(bookmark)
        XCTAssertFalse(names(provider.favorites(includingHidden: true)).contains("Proyectos"))
        XCTAssertTrue(provider.customBookmarks().isEmpty)
    }

    func test_locations_homeThenStartupDiskFirst_andTrashLast() throws {
        let locations = provider.locations()
        XCTAssertEqual(locations.first?.url, FileManager.default.homeDirectoryForCurrentUser)
        XCTAssertEqual(locations.first?.localizedDisplayName, FileManager.default.homeDirectoryForCurrentUser.lastPathComponent, "como Finder: el nombre de usuario")
        XCTAssertEqual(locations.dropFirst().first?.url.path, "/")
        XCTAssertEqual(locations.last?.name, "Trash")
        let trash = try XCTUnwrap(locations.last)
        provider.setHiddenInSidebar(true, for: trash)
        XCTAssertNotEqual(provider.locations().last?.name, "Trash")
    }

    func test_symbols_matchFinderSidebar() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func symbol(_ url: URL, kind: PlaceKind = .customBookmark, name: String? = nil) -> String {
            PlaceItem(url: url, name: name ?? url.lastPathComponent, systemImage: "", kind: kind).sidebarSymbol
        }
        XCTAssertEqual(symbol(home.appendingPathComponent("Developer")), "hammer")
        XCTAssertEqual(symbol(URL(fileURLWithPath: "/Applications"), kind: .bookmark), "a.circle")
        XCTAssertEqual(symbol(home, kind: .bookmark), "house")
        XCTAssertEqual(symbol(URL(fileURLWithPath: "/"), kind: .volume), "internaldrive")
        XCTAssertEqual(symbol(home.appendingPathComponent(".Trash"), kind: .bookmark, name: "Trash"), "trash")
        XCTAssertEqual(symbol(tempDir.appendingPathComponent("Proyectos")), "folder")
        XCTAssertEqual(symbol(tempDir.appendingPathComponent("Developer")), "folder", "solo la Developer de la carpeta personal")
        for place in provider.favorites() + provider.locations() {
            XCTAssertNotNil(NSImage(systemSymbolName: place.sidebarSymbol, accessibilityDescription: nil), place.sidebarSymbol)
        }
    }

    func test_tags_comeInFinderOrder_andCanBeHidden() {
        XCTAssertEqual(provider.sidebarTags(), [.red, .orange, .yellow, .green, .blue, .purple, .gray])
        provider.setTagHiddenInSidebar(true, for: .gray)
        XCTAssertFalse(provider.sidebarTags().contains(.gray))
        XCTAssertTrue(provider.sidebarTags(includingHidden: true).contains(.gray), "vuelve desde Ajustes")
        XCTAssertEqual(provider.sidebarPlaces().tags.count, 6)
    }

    func test_changingTheIcon_isKept_andResetGoesBackToFinders() throws {
        let documents = try XCTUnwrap(provider.favorites().first { $0.name == "Documents" })
        provider.setSidebarSymbol("star", for: documents)
        XCTAssertEqual(PlacesProvider(defaults: defaults).favorites().first { $0.name == "Documents" }?.sidebarSymbol, "star")
        provider.setSidebarSymbol(nil, for: documents)
        XCTAssertEqual(provider.favorites().first { $0.name == "Documents" }?.sidebarSymbol, "doc")

        let home = try XCTUnwrap(provider.locations().first)
        provider.setSidebarSymbol("heart", for: home)
        XCTAssertEqual(provider.locations().first?.sidebarSymbol, "heart", "también en Ubicaciones")
    }

    func test_movingStillWorks_withAChangedIcon() throws {
        let downloads = try XCTUnwrap(provider.favorites().first { $0.name == "Downloads" })
        provider.setSidebarSymbol("star", for: downloads)
        provider.moveFavorites(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(names(provider.favorites()), ["Downloads", "Desktop", "Documents", "Applications"])
    }

    func test_everySymbolChoiceExists() {
        for symbol in PlacesProvider.symbolChoices {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), symbol)
        }
        XCTAssertEqual(Set(PlacesProvider.symbolChoices).count, PlacesProvider.symbolChoices.count, "sin repetidos")
    }

    func test_droppingAFolder_addsItWhereItWasDropped() throws {
        provider.insertFavorites([tempDir.appendingPathComponent("Proyectos")], at: 1)
        XCTAssertEqual(names(provider.favorites()), ["Desktop", "Proyectos", "Documents", "Downloads", "Applications"])
    }

    func test_droppingAnExistingFavorite_onlyMovesIt() throws {
        let downloads = try XCTUnwrap(provider.favorites().first { $0.name == "Downloads" })
        provider.insertFavorites([downloads.url], at: 0)
        XCTAssertEqual(names(provider.favorites()), ["Downloads", "Desktop", "Documents", "Applications"])
    }

    func test_droppingAFile_isIgnored() throws {
        let file = tempDir.appendingPathComponent("nota.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        provider.insertFavorites([file], at: 0)
        XCTAssertEqual(names(provider.favorites()), ["Desktop", "Documents", "Downloads", "Applications"])
    }
}

/// Cambiar el ícono de una carpeta se ve enseguida en la lista.
@MainActor
final class FolderIconRefreshTests: XCTestCase {
    func test_changingAFolderIcon_dropsTheCachedIcon() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let before = ThumbnailLoader.icon(forFile: folder.path)
        XCTAssertTrue(ThumbnailLoader.icon(forFile: folder.path) === before, "queda en caché")

        let viewModel = BrowserViewModel(startingAt: folder.deletingLastPathComponent())
        viewModel.setFolderIcon(.allCases.first { $0.badgeSymbol != nil } ?? .allCases[0], for: folder)

        XCTAssertFalse(ThumbnailLoader.icon(forFile: folder.path) === before, "se vuelve a pedir al sistema")
    }
}
