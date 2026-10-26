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
