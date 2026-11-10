import XCTest
@testable import Dotphin

final class TemplateProviderTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_customTemplates_whenDirectoryMissing_returnsEmptyWithoutCreatingIt() {
        let missingDir = tempDir.appendingPathComponent("Templates", isDirectory: true)

        let result = TemplateProvider().customTemplates(in: missingDir)

        XCTAssertEqual(result, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingDir.path))
    }

    func test_customTemplates_listsOnlyRegularFilesIgnoringSubfoldersAndDotfiles() throws {
        try "a".write(to: tempDir.appendingPathComponent("Informe.docx"), atomically: true, encoding: .utf8)
        try "b".write(to: tempDir.appendingPathComponent("Nota.md"), atomically: true, encoding: .utf8)
        try "c".write(to: tempDir.appendingPathComponent(".oculto.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("Subcarpeta", isDirectory: true),
            withIntermediateDirectories: true
        )

        let result = TemplateProvider().customTemplates(in: tempDir)

        XCTAssertEqual(result.map(\.lastPathComponent), ["Informe.docx", "Nota.md"])
    }
}
