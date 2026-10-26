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

    func test_init_loadsViewPropertiesForStartingFolder() throws {
        let store = ViewPropertiesStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        var saved = ViewProperties()
        saved.mode = .icons
        store.setProperties(saved, for: tempDir)
        let vm = BrowserViewModel(startingAt: tempDir, store: store)
        XCTAssertEqual(vm.viewProperties.mode, .icons)
    }

    func test_setViewMode_persistsAndDoesNotRereadDisk() throws {
        try "a".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = ViewPropertiesStore(defaults: suite)
        let vm = BrowserViewModel(startingAt: tempDir, store: store)
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("a.txt"))
        vm.setViewMode(.icons)
        XCTAssertEqual(vm.viewProperties.mode, .icons)
        XCTAssertEqual(vm.items.map(\.name), ["a.txt"], "no debió re-leer el disco al cambiar el modo")
        XCTAssertEqual(store.properties(for: tempDir).mode, .icons)
    }

    func test_setSort_reordersWithoutError() throws {
        try "12345".write(to: tempDir.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)
        try "1234567890".write(to: tempDir.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: tempDir)
        vm.setSort(field: .size, ascending: false)
        XCTAssertEqual(vm.items.map(\.name), ["big.txt", "small.txt"])
    }

    func test_setZoomLevel_persists() throws {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = ViewPropertiesStore(defaults: suite)
        let vm = BrowserViewModel(startingAt: tempDir, store: store)
        vm.setZoomLevel(1.8)
        XCTAssertEqual(vm.viewProperties.zoomLevel, 1.8)
        XCTAssertEqual(store.properties(for: tempDir).zoomLevel, 1.8)
    }
}
