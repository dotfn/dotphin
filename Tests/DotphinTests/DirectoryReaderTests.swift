import XCTest
@testable import Dotphin

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

    func test_contentsSortedBySizeDescending_foldersStillFirst() throws {
        try "12345".write(to: tempDir.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)
        try "1234567890".write(to: tempDir.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("zfolder"), withIntermediateDirectories: true)
        let reader = DirectoryReader()
        let names = try reader.contents(of: tempDir, sortField: .size, ascending: false).map(\.name)
        XCTAssertEqual(names, ["zfolder", "big.txt", "small.txt"])
    }

    func test_contentsSortedBySizeDescending_tiesBreakByNameAscending() throws {
        // Varios archivos del mismo tamaño creados en orden inverso al alfabético:
        // con un comparador roto para empates, el orden que sale no es "a","b","c"...
        let names = ["j", "i", "h", "g", "f", "e", "d", "c", "b", "a"]
        for name in names {
            try "x".write(to: tempDir.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
        }
        let reader = DirectoryReader()
        let result = try reader.contents(of: tempDir, sortField: .size, ascending: false).map(\.name)
        XCTAssertEqual(result, names.sorted().map { "\($0).txt" }, "tamaños iguales deben desambiguar por nombre, no quedar en orden arbitrario")
    }

    func test_contentsSortedByModificationDateAscending() throws {
        let older = tempDir.appendingPathComponent("older.txt")
        let newer = tempDir.appendingPathComponent("newer.txt")
        try "x".write(to: older, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)], ofItemAtPath: older.path)
        try "x".write(to: newer, atomically: true, encoding: .utf8)
        let reader = DirectoryReader()
        let names = try reader.contents(of: tempDir, sortField: .modificationDate, ascending: true).map(\.name)
        XCTAssertEqual(names, ["older.txt", "newer.txt"])
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

    func test_contentsOfSymlinkToFolder_reportsAsDirectory_sameAnItemCanBeOpened() throws {
        let target = tempDir.appendingPathComponent("realFolder")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = tempDir.appendingPathComponent("linkToFolder")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let reader = DirectoryReader()
        let items = try reader.contents(of: tempDir)
        let linkItem = items.first { $0.name == "linkToFolder" }
        XCTAssertEqual(linkItem?.isDirectory, true, "un symlink a una carpeta debe poder abrirse como carpeta")
    }

    func test_contentsOfDanglingSymlink_doesNotThrow_reportsNotDirectory() throws {
        let link = tempDir.appendingPathComponent("brokenLink")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: tempDir.appendingPathComponent("doesNotExist")
        )
        let reader = DirectoryReader()
        let items = try reader.contents(of: tempDir)
        let linkItem = items.first { $0.name == "brokenLink" }
        XCTAssertEqual(linkItem?.isSymbolicLink, true)
        XCTAssertEqual(linkItem?.isDirectory, false)
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

    // MARK: Ocultos por marca, paquetes y tipo (APIs del sistema)

    /// Marca un ítem como oculto sin cambiarle el nombre (lo que tiene `~/Library`).
    private func setHiddenFlag(on url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isHidden = true
        try url.setResourceValues(values)
    }

    func test_contentsHidesItemsWithTheHiddenFlag() throws {
        let flagged = tempDir.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: flagged, withIntermediateDirectories: true)
        try setHiddenFlag(on: flagged)
        try "x".write(to: tempDir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)

        XCTAssertEqual(try DirectoryReader().contents(of: tempDir).map(\.name), ["visible.txt"])

        let all = try DirectoryReader(showsHiddenFiles: true).contents(of: tempDir)
        let library = try XCTUnwrap(all.first { $0.name == "Library" })
        XCTAssertTrue(library.isHiddenByFlag)
        XCTAssertTrue(library.isHiddenItem, "con ocultos a la vista, igual cuenta como oculto (se atenúa y va al final)")
    }

    func test_folderTreeSkipsFlagHiddenFoldersAndPackages() throws {
        let flagged = tempDir.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: flagged, withIntermediateDirectories: true)
        try setHiddenFlag(on: flagged)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("Demo.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("normal"), withIntermediateDirectories: true)

        let tree = FolderTreeProvider(showsHiddenFiles: false).subdirectories(of: tempDir).map(\.lastPathComponent)
        XCTAssertEqual(tree, ["normal"])
        let withHidden = FolderTreeProvider(showsHiddenFiles: true).subdirectories(of: tempDir).map(\.lastPathComponent)
        XCTAssertEqual(withHidden, ["Library", "normal"])
    }

    func test_packageIsReadAsPackageAndSortsWithFiles() throws {
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("Demo.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("zfolder"), withIntermediateDirectories: true)
        try "x".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let items = try DirectoryReader().contents(of: tempDir)
        XCTAssertEqual(items.map(\.name), ["zfolder", "a.txt", "Demo.app"], "un paquete va con los archivos, no con las carpetas")
        let app = try XCTUnwrap(items.first { $0.name == "Demo.app" })
        XCTAssertTrue(app.isDirectory)
        XCTAssertTrue(app.isPackage)
        XCTAssertFalse(app.opensAsFolder, "abrirlo no debe navegar adentro")
        let folder = try XCTUnwrap(items.first { $0.name == "zfolder" })
        XCTAssertFalse(folder.isPackage)
        XCTAssertTrue(folder.opensAsFolder)
    }

    func test_kindIsTheSystemTypeDescription() throws {
        let file = tempDir.appendingPathComponent("nota.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let expected = try XCTUnwrap(file.resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription)

        let item = try XCTUnwrap(DirectoryReader().contents(of: tempDir).first)
        XCTAssertEqual(item.typeDescription, expected)
        XCTAssertEqual(FileMetadataFormatter().metadata(for: item).kind, expected)
        XCTAssertNotEqual(item.kindDescription, "TXT", "ya no es la extensión en mayúsculas")
    }
}
