import XCTest
@testable import Dotphin

final class ThumbnailLoaderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_thumbnail_forExistingFile_returnsAnImage() async throws {
        let fileURL = tempDir.appendingPathComponent("doc.txt")
        try "contenido de prueba".write(to: fileURL, atomically: true, encoding: .utf8)
        let image = await ThumbnailLoader().thumbnail(for: fileURL, size: CGSize(width: 64, height: 64))
        XCTAssertNotNil(image)
    }

    func test_thumbnail_forNonExistentFile_returnsNil() async {
        let missing = tempDir.appendingPathComponent("doesNotExist.txt")
        let image = await ThumbnailLoader().thumbnail(for: missing, size: CGSize(width: 64, height: 64))
        XCTAssertNil(image)
    }
}
