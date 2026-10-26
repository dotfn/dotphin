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

    func test_rename_toHiddenName_throwsInvalidName() throws {
        let item = try makeFile("a.txt")
        XCTAssertThrowsError(try FileOperationsService().rename(item, to: ".a.txt")) { error in
            XCTAssertEqual(error as? FileOperationError, .invalidName)
        }
    }

    func test_restore_movesItemToDestination() throws {
        let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let destDir = tempDir.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let itemURL = trashDir.appendingPathComponent("a.txt")
        try "x".write(to: itemURL, atomically: true, encoding: .utf8)
        let item = FileItem(url: itemURL, name: "a.txt", isDirectory: false, isSymbolicLink: false, size: 1, modificationDate: Date())

        let newURL = try FileOperationsService().restore(item, to: destDir)
        XCTAssertEqual(newURL, destDir.appendingPathComponent("a.txt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
    }

    func test_restore_toDestinationWithExistingName_throwsNameAlreadyExists() throws {
        let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let destDir = tempDir.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try "x".write(to: destDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let itemURL = trashDir.appendingPathComponent("a.txt")
        try "y".write(to: itemURL, atomically: true, encoding: .utf8)
        let item = FileItem(url: itemURL, name: "a.txt", isDirectory: false, isSymbolicLink: false, size: 1, modificationDate: Date())

        XCTAssertThrowsError(try FileOperationsService().restore(item, to: destDir)) { error in
            XCTAssertEqual(error as? FileOperationError, .nameAlreadyExists(destDir.appendingPathComponent("a.txt")))
        }
        XCTAssertEqual(try? String(contentsOf: destDir.appendingPathComponent("a.txt"), encoding: .utf8), "x", "no debió sobrescribirse")
    }

    func test_restore_movesFolderWithContents() throws {
        let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let destDir = tempDir.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let folderURL = trashDir.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "x".write(to: folderURL.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)
        let item = FileItem(url: folderURL, name: "folder", isDirectory: true, isSymbolicLink: false, size: nil, modificationDate: Date())

        let newURL = try FileOperationsService().restore(item, to: destDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.appendingPathComponent("inside.txt").path))
    }

    func test_emptyTrash_onEmptyFolder_succeedsWithoutError() throws {
        let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        XCTAssertNoThrow(try FileOperationsService().emptyTrash(at: trashDir))
    }

    func test_emptyTrash_removesAllContents() throws {
        let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        try "x".write(to: trashDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: trashDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try FileOperationsService().emptyTrash(at: trashDir)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trashDir.path), [])
    }

    func test_emptyTrash_withOneUndeletableItem_removesTheRestAndReportsFailure() throws {
        let trashDir = tempDir.appendingPathComponent("trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        try "x".write(to: trashDir.appendingPathComponent("ok.txt"), atomically: true, encoding: .utf8)
        let locked = trashDir.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try "x".write(to: locked.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        XCTAssertThrowsError(try FileOperationsService().emptyTrash(at: trashDir))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashDir.appendingPathComponent("ok.txt").path), "el que sí se pudo borrar debe haberse borrado igual")
    }

    func test_emptyTrash_onUnreadableFolder_throws_doesNotReportFalseSuccess() throws {
        let locked = tempDir.appendingPathComponent("locked-trash", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        XCTAssertThrowsError(try FileOperationsService().emptyTrash(at: locked))
    }

    func test_move_relocatesFileIntoDestinationDirectory() throws {
        let source = tempDir.appendingPathComponent("a.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        let destDir = tempDir.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let result = try FileOperationsService().move(source, toDirectory: destDir)

        XCTAssertEqual(result, destDir.appendingPathComponent("a.txt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }

    func test_move_droppedOnOwnContainingDirectory_isNoOp() throws {
        let source = tempDir.appendingPathComponent("a.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)

        let result = try FileOperationsService().move(source, toDirectory: tempDir)

        XCTAssertEqual(result, source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func test_move_intoOwnDescendant_throws() throws {
        let folder = tempDir.appendingPathComponent("folder", isDirectory: true)
        let sub = folder.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        XCTAssertThrowsError(try FileOperationsService().move(folder, toDirectory: sub))
    }

    func test_move_whenDestinationNameExists_throwsNameAlreadyExists() throws {
        let source = tempDir.appendingPathComponent("a.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        let destDir = tempDir.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try "y".write(to: destDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try FileOperationsService().move(source, toDirectory: destDir)) { error in
            guard case FileOperationError.nameAlreadyExists = error else {
                XCTFail("esperaba nameAlreadyExists, fue \(error)")
                return
            }
        }
    }
}
