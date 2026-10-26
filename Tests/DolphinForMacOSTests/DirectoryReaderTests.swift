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
