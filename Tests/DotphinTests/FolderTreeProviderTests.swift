import XCTest
@testable import Dotphin

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
