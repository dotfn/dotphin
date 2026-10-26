import XCTest
@testable import DolphinForMacOS

final class FileOperationsServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String) throws -> FileItem {
        let url = tempDir.appendingPathComponent(name)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return FileItem(url: url, name: name, isDirectory: false, isSymbolicLink: false, size: 1, modificationDate: Date())
    }

    func test_rename_movesFileToNewName() throws {
        let item = try makeFile("a.txt")
        let newURL = try FileOperationsService().rename(item, to: "b.txt")
        XCTAssertEqual(newURL, tempDir.appendingPathComponent("b.txt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
    }

    func test_rename_toExistingName_throwsNameAlreadyExists() throws {
        let item = try makeFile("a.txt")
        _ = try makeFile("b.txt")
        XCTAssertThrowsError(try FileOperationsService().rename(item, to: "b.txt")) { error in
            XCTAssertEqual(error as? FileOperationError, .nameAlreadyExists(tempDir.appendingPathComponent("b.txt")))
        }
    }

    func test_rename_toEmptyOrWhitespaceName_throwsInvalidName() throws {
        let item = try makeFile("a.txt")
        XCTAssertThrowsError(try FileOperationsService().rename(item, to: "   ")) { error in
            XCTAssertEqual(error as? FileOperationError, .invalidName)
        }
    }

    func test_rename_nameContainingSlash_throwsInvalidName() throws {
        let item = try makeFile("a.txt")
        XCTAssertThrowsError(try FileOperationsService().rename(item, to: "b/c.txt")) { error in
            XCTAssertEqual(error as? FileOperationError, .invalidName)
        }
    }

    func test_moveToTrash_removesFileFromOriginalLocation() throws {
        let item = try makeFile("a.txt")
        try FileOperationsService().moveToTrash(item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.url.path))
    }

    func test_createFolder_createsDirectory() throws {
        let url = try FileOperationsService().createFolder(in: tempDir, named: "Nueva carpeta")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func test_createFolder_withExistingName_throwsNameAlreadyExists() throws {
        _ = try FileOperationsService().createFolder(in: tempDir, named: "Dup")
        XCTAssertThrowsError(try FileOperationsService().createFolder(in: tempDir, named: "Dup")) { error in
            XCTAssertEqual(error as? FileOperationError, .nameAlreadyExists(tempDir.appendingPathComponent("Dup")))
        }
    }
}
