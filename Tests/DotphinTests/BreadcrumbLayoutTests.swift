import AppKit
import SwiftUI
import XCTest
@testable import Dotphin

/// Las migas de la ruta solo se desplazan cuando de verdad no entran: si sobra
/// ancho, el último segmento no debe quedar cortado.
@MainActor
final class BreadcrumbLayoutTests: XCTestCase {
    private func scrollViews(in view: NSView) -> [NSScrollView] {
        let own: [NSScrollView] = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { scrollViews(in: $0) }
    }

    /// Anchos en los que las migas pasaron a la versión con desplazamiento.
    private func widthsThatScroll(url: URL, widths: [CGFloat]) -> [CGFloat] {
        let host = NSHostingView(rootView: BreadcrumbView(url: url, onNavigate: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        var scrolling: [CGFloat] = []
        for width in widths {
            window.setContentSize(NSSize(width: width, height: 40))
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            host.layoutSubtreeIfNeeded()
            if !scrollViews(in: host).isEmpty { scrolling.append(width) }
        }
        return scrolling
    }

    func test_shortPath_neverScrollsWhenThereIsRoomToSpare() {
        // "Macintosh HD › Users › <usuario>" mide unos 300 pt.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let widths = Array(stride(from: CGFloat(380), through: 1100, by: 15))
        XCTAssertEqual(widthsThatScroll(url: home, widths: widths), [])
    }

    func test_longPath_scrollsInANarrowSpace() {
        var deep = FileManager.default.temporaryDirectory
        for index in 0..<12 { deep.appendPathComponent("carpeta-con-nombre-largo-\(index)", isDirectory: true) }
        XCTAssertEqual(widthsThatScroll(url: deep, widths: [300]), [300])
    }

    func test_longPath_inANarrowSpace_showsTheCurrentFolder() throws {
        var deep = FileManager.default.temporaryDirectory
        for index in 0..<12 { deep.appendPathComponent("carpeta-con-nombre-largo-\(index)", isDirectory: true) }
        let host = NSHostingView(rootView: BreadcrumbView(url: deep, onNavigate: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(scrollViews(in: host).first)
        let document = try XCTUnwrap(scrollView.documentView)
        XCTAssertGreaterThan(document.frame.width, scrollView.contentView.bounds.width, "la ruta debería no entrar")
        // Al final de la ruta está la carpeta actual: tiene que quedar a la vista.
        XCTAssertEqual(scrollView.contentView.bounds.maxX, document.frame.maxX, accuracy: 2)
    }
}
