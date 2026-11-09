import XCTest
@testable import Dotphin

final class PlacesProviderTests: XCTestCase {
    func test_staticBookmarks_returnsHomeDesktopDocumentsDownloadsTrashInOrder() {
        let provider = PlacesProvider()
        let names = provider.staticBookmarks().map(\.name)
        XCTAssertEqual(names, ["Home", "Desktop", "Documents", "Downloads", "Trash"])
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

    func test_mountedVolumes_bootVolumeIsNotEjectable() {
        let provider = PlacesProvider()
        let bootVolume = provider.mountedVolumes().first { $0.url.path == "/" }
        XCTAssertEqual(bootVolume?.isEjectable, false, "el disco de arranque no debe ofrecer Expulsar")
    }

    func test_allPlaces_isBookmarksThenVolumes() {
        let provider = PlacesProvider()
        let all = provider.allPlaces()
        let bookmarks = provider.staticBookmarks()
        XCTAssertEqual(Array(all.prefix(bookmarks.count)), bookmarks)
    }
}
