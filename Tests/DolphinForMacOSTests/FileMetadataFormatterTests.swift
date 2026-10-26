import XCTest
@testable import DolphinForMacOS

final class FileMetadataFormatterTests: XCTestCase {
    func test_folder_hasCarpetaKindAndDashSize() {
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/x"), name: "x", isDirectory: true, isSymbolicLink: false, size: nil, modificationDate: nil)
        let meta = FileMetadataFormatter().metadata(for: item)
        XCTAssertEqual(meta.kind, "Carpeta")
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
        XCTAssertEqual(meta.kind, "Documento")
        XCTAssertEqual(meta.modifiedText, "—")
    }
}
