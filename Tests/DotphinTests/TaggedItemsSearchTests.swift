import XCTest
@testable import Dotphin

/// Barra lateral → Etiquetas: los archivos con una etiqueta salen de Spotlight.
///
/// Spotlight no indexa las carpetas temporales del sistema, así que el archivo
/// se crea en `~/Documents` (en una carpeta propia que se borra al terminar) y
/// se espera a que el índice lo vea.
@MainActor
final class TaggedItemsSearchTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        folder = documents.appendingPathComponent("DotphinTagTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func test_showingATag_listsTheFilesWithThatColor() async throws {
        let red = folder.appendingPathComponent("rojo.txt")
        let blue = folder.appendingPathComponent("azul.txt")
        try "r".write(to: red, atomically: true, encoding: .utf8)
        try "b".write(to: blue, atomically: true, encoding: .utf8)
        let service = FolderIconAndTagService()
        try service.setColorTag(.red, for: red)
        try service.setColorTag(.blue, for: blue)

        let viewModel = BrowserViewModel(startingAt: folder)
        var found: [String] = []
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            viewModel.showItems(taggedWith: .red)
            await viewModel.waitForBackgroundWork()
            found = viewModel.searchResults.filter { $0.url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL }.map(\.name)
            if !found.isEmpty { break }
            try await Task.sleep(for: .seconds(1))
        }
        XCTAssertEqual(found, ["rojo.txt"], "Spotlight devuelve solo el archivo rojo")
        XCTAssertEqual(viewModel.shownTag, .red)
        XCTAssertTrue(viewModel.isShowingResults)

        viewModel.navigate(to: folder)
        XCTAssertNil(viewModel.shownTag, "navegar vuelve a la carpeta")
        XCTAssertFalse(viewModel.isShowingResults)
    }
}
