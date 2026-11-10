import XCTest
@testable import Dotphin

final class FileMetadataFormatterTests: XCTestCase {
    func test_folder_hasCarpetaKindAndDashSize() {
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/x"), name: "x", isDirectory: true, isSymbolicLink: false, size: nil, modificationDate: nil)
        let meta = FileMetadataFormatter().metadata(for: item)
        XCTAssertEqual(meta.kind, appText("Carpeta"))
        XCTAssertEqual(meta.sizeText, "—")
        XCTAssertEqual(meta.modifiedText, "—")
    }

    func test_fileWithExtension_usesExtensionAsKind() {
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/a.txt"), name: "a.txt", isDirectory: false, isSymbolicLink: false, size: 1234, modificationDate: Date())
        let meta = FileMetadataFormatter().metadata(for: item)
        XCTAssertEqual(meta.kind, "TXT")
        XCTAssertNotEqual(meta.sizeText, "—")
    }

    func test_fileWithoutExtension_usesDocumentoAsKind() {
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/README"), name: "README", isDirectory: false, isSymbolicLink: false, size: 10, modificationDate: nil)
        let meta = FileMetadataFormatter().metadata(for: item)
        XCTAssertEqual(meta.kind, appText("Documento"))
        XCTAssertEqual(meta.modifiedText, "—")
    }

    func test_contentSize_includesFilesInSubfolders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0, count: 50_000).write(to: nested.appendingPathComponent("big.bin"))

        let item = FileItem(url: root, name: root.lastPathComponent, isDirectory: true, isSymbolicLink: false, size: nil, modificationDate: Date())
        let formatter = FileMetadataFormatter()
        XCTAssertNil(formatter.cachedSizeDisplayText(for: item, directorySizeMode: .contentSize), "sin calcular no debe tocar el disco")

        let text = await formatter.computedSizeDisplayText(for: item, directorySizeMode: .contentSize)
        XCTAssertEqual(text, ByteCountFormatter.string(fromByteCount: 50_000, countStyle: .file), "el archivo de la subcarpeta debe contar")
        XCTAssertEqual(formatter.cachedSizeDisplayText(for: item, directorySizeMode: .contentSize), text)
    }
}
