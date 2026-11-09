import XCTest
@testable import Dotphin

final class FileHistoryAndCopyTests: XCTestCase {
    private var tempDir: URL!
    private let ops = FileOperationsService()

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String, in dir: URL? = nil) throws -> URL {
        let url = (dir ?? tempDir).appendingPathComponent(name)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeDir(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func test_copy_intoSameFolder_usesCopySuffix() throws {
        let source = try makeFile("a.txt")
        let first = try ops.copy(source, toDirectory: tempDir)
        let second = try ops.copy(source, toDirectory: tempDir)
        XCTAssertEqual(first.lastPathComponent, "a copy.txt")
        XCTAssertEqual(second.lastPathComponent, "a copy 2.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func test_copy_folderIntoItself_throws() throws {
        let folder = try makeDir("f")
        XCTAssertThrowsError(try ops.copy(folder, toDirectory: folder))
    }

    func test_undoRedo_move() throws {
        let source = try makeFile("a.txt")
        let target = try makeDir("t")
        let moved = try ops.move(source, toDirectory: target)
        var history = FileOperationHistory()
        history.record([.moved(from: source, to: moved)])

        try history.undo(using: ops)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertTrue(history.canRedo)

        try history.redo(using: ops)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
    }

    func test_undo_copy_removesCreatedCopy() throws {
        let source = try makeFile("a.txt")
        let created = try ops.copy(source, toDirectory: tempDir)
        var history = FileOperationHistory()
        history.record([.copied(source: source, to: created)])
        try history.undo(using: ops)
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func test_record_clearsRedoStack() throws {
        var history = FileOperationHistory()
        let folder = tempDir.appendingPathComponent("n", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        history.record([.createdFolder(folder)])
        try history.undo(using: ops)
        XCTAssertTrue(history.canRedo)
        history.record([.createdFolder(folder)])
        XCTAssertFalse(history.canRedo)
    }

    func test_locationParser_expandsTildeAndRejectsFiles() throws {
        XCTAssertNotNil(LocationParser.directoryURL(from: "~"))
        let file = try makeFile("a.txt")
        XCTAssertNil(LocationParser.directoryURL(from: file.path))
        XCTAssertNil(LocationParser.directoryURL(from: "relative/path"))
    }

    func test_locationParser_completesUniqueDirectory() throws {
        _ = try makeDir("Documentos")
        let completed = LocationParser.completed(tempDir.path + "/Doc")
        XCTAssertEqual(completed, tempDir.path + "/Documentos/")
    }
}
