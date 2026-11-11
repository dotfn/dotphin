import AppKit
import XCTest
@testable import Dotphin

/// Una carpeta con etiqueta de color se ve de ese color (como el color de
/// carpeta de Dolphin); los archivos y las carpetas sin etiqueta no cambian.
@MainActor
final class FolderTagTintTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func item(_ name: String, directory: Bool, tag: FinderColorTag) throws -> FileItem {
        let url = dir.appendingPathComponent(name, isDirectory: directory)
        if directory {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try "x".write(to: url, atomically: true, encoding: .utf8)
        }
        return FileItem(url: url, name: name, isDirectory: directory, isSymbolicLink: false, size: nil, modificationDate: nil, labelNumber: tag.rawValue)
    }

    /// Promedio de color de los píxeles opacos (el cuerpo de la carpeta).
    private func averageColor(of image: NSImage) throws -> (hue: CGFloat, saturation: CGFloat, opaqueFraction: CGFloat) {
        let side = 64
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        var r = 0.0, g = 0.0, b = 0.0, count = 0.0
        for x in 0..<side { for y in 0..<side {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.9 else { continue }
            r += c.redComponent; g += c.greenComponent; b += c.blueComponent; count += 1
        } }
        let average = NSColor(srgbRed: r / count, green: g / count, blue: b / count, alpha: 1)
        return (average.hueComponent, average.saturationComponent, count / Double(side * side))
    }

    func test_taggedFolder_isTintedWithItsColor_keepingTheFolderShape() throws {
        let plain = try item("sin", directory: true, tag: .none)
        let red = try item("roja", directory: true, tag: .red)
        let plainLook = try averageColor(of: ThumbnailLoader.icon(for: plain))
        let redLook = try averageColor(of: ThumbnailLoader.icon(for: red))

        // La carpeta común de macOS es azulada; la etiquetada en rojo, rojiza.
        XCTAssertTrue(redLook.hue < 0.08 || redLook.hue > 0.92, "tono \(redLook.hue) no es rojo")
        XCTAssertGreaterThan(redLook.saturation, 0.2)
        XCTAssertEqual(redLook.opaqueFraction, plainLook.opaqueFraction, accuracy: 0.02, "el tinte cambió la forma del ícono")
    }

    func test_untaggedFolder_andTaggedFile_keepTheSystemIcon() throws {
        let plain = try item("sin", directory: true, tag: .none)
        let file = try item("nota.txt", directory: false, tag: .green)
        XCTAssertTrue(ThumbnailLoader.icon(for: plain) === ThumbnailLoader.icon(forFile: plain.url.path))
        XCTAssertTrue(ThumbnailLoader.icon(for: file) === ThumbnailLoader.icon(forFile: file.url.path))
    }
}
