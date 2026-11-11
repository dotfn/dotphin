import Foundation
import XCTest
@testable import Dotphin

@MainActor
final class ArchiveAndSearchFilterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dolphin-archive-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func test_compressAndExtract_roundTripsFilesWithUndo() throws {
        let fileA = tempDir.appendingPathComponent("hola.txt")
        let fileB = tempDir.appendingPathComponent("notas.md")
        try Data("contenido A".utf8).write(to: fileA)
        try Data("# titulo".utf8).write(to: fileB)

        let vm = BrowserViewModel(startingAt: tempDir)
        vm.selectAll()
        XCTAssertEqual(vm.selectedItems.count, 2)

        vm.compressSelected(archiveName: "paquete")
        let zipURL = tempDir.appendingPathComponent("paquete.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))
        XCTAssertTrue(ArchiveService.isArchive(zipURL))

        guard let zipItem = vm.items.first(where: { $0.name == "paquete.zip" }) else {
            XCTFail("Expected paquete.zip in BrowserViewModel.items")
            return
        }

        vm.extractArchive(zipItem)
        let extractedDir = tempDir.appendingPathComponent("paquete")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedDir.appendingPathComponent("hola.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedDir.appendingPathComponent("notas.md").path))
    }

    func test_searchTypeFilter_matchesExpectedCategories() throws {
        let folder = FileItem(
            url: tempDir.appendingPathComponent("Subcarpeta"),
            name: "Subcarpeta",
            isDirectory: true,
            isSymbolicLink: false,
            size: nil,
            modificationDate: nil
        )
        let image = FileItem(
            url: tempDir.appendingPathComponent("foto.png"),
            name: "foto.png",
            isDirectory: false,
            isSymbolicLink: false,
            size: 120,
            modificationDate: nil
        )
        let code = FileItem(
            url: tempDir.appendingPathComponent("main.swift"),
            name: "main.swift",
            isDirectory: false,
            isSymbolicLink: false,
            size: 64,
            modificationDate: nil
        )
        let doc = FileItem(
            url: tempDir.appendingPathComponent("manual.pdf"),
            name: "manual.pdf",
            isDirectory: false,
            isSymbolicLink: false,
            size: 1024,
            modificationDate: nil
        )

        XCTAssertTrue(SearchTypeFilter.folders.matches(folder))
        XCTAssertFalse(SearchTypeFilter.folders.matches(image))

        XCTAssertTrue(SearchTypeFilter.images.matches(image))
        XCTAssertFalse(SearchTypeFilter.images.matches(code))

        XCTAssertTrue(SearchTypeFilter.code.matches(code))
        XCTAssertFalse(SearchTypeFilter.code.matches(doc))

        XCTAssertTrue(SearchTypeFilter.documents.matches(doc))
        XCTAssertFalse(SearchTypeFilter.documents.matches(image))
    }

    func test_embeddedTerminal_quotesPathsForTheShell() {
        let quoted = EmbeddedTerminalSession.shellSingleQuoted("/Users/test/Carpeta con 'comillas'")
        XCTAssertEqual(quoted, "'/Users/test/Carpeta con '\\''comillas'\\'''")
    }
}
