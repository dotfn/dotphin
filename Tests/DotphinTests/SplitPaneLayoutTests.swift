import AppKit
import SwiftUI
import XCTest
@testable import Dotphin

/// La vista dividida llena el ancho de la ventana: con un `HSplitView` suelto,
/// en ventanas angostas los paneles terminaban antes del borde derecho.
@MainActor
final class SplitPaneLayoutTests: XCTestCase {
    private func all<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, in: $0) }
    }

    /// Borde derecho de las vistas de archivos (tablas y grillas), en coordenadas de la ventana.
    private func fileViewsMaxX(in content: NSView) -> [CGFloat] {
        let views: [NSView] = all(NSTableView.self, in: content) + all(NSCollectionView.self, in: content)
        return views.compactMap { $0.enclosingScrollView }.map { $0.convert($0.bounds, to: content).maxX }
    }

    func test_splitPanes_reachTheRightEdgeAtEveryWidth() throws {
        try checkRightEdge(withPanels: false)
    }

    func test_withInfoPanelAndTerminal_windowGrowsAndNothingOverflows() throws {
        try checkRightEdge(withPanels: true)
    }

    private func checkRightEdge(withPanels: Bool) throws {
        let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView()))
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "SplitPaneLayoutTests")
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        func settle(_ seconds: TimeInterval = 0.2) {
            content.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }

        var deadline = Date().addingTimeInterval(3)
        while WindowCommands.commands(for: window) == nil, Date() < deadline { settle(0.05) }
        // La ventana restaura la sesión guardada (puede venir ya dividida):
        // se divide solo si hace falta. Dos paneles + el árbol de la barra lateral.
        settle(0.3)
        if fileViewsMaxX(in: content).count < 3 {
            WindowCommands.commands(for: window)?.perform(.toggleSplit)
        }
        deadline = Date().addingTimeInterval(4)
        while fileViewsMaxX(in: content).count < 3, Date() < deadline { settle(0.05) }
        XCTAssertGreaterThanOrEqual(fileViewsMaxX(in: content).count, 3, "no se montó la vista dividida")
        if withPanels {
            window.setContentSize(NSSize(width: ContentView.minimumWidth, height: 600))
            settle()
            WindowCommands.commands(for: window)?.perform(.toggleInfoPanel)
            WindowCommands.commands(for: window)?.perform(.toggleEmbeddedTerminal)
            settle(0.5)
            XCTAssertGreaterThanOrEqual(content.bounds.width, ContentView.minimumWidthWithInfoPanel - 1, "abrir el panel de información en una ventana angosta debe agrandarla")
        }

        let widths: [CGFloat] = withPanels ? [1000, 1100, 1300, 1000] : [840, 900, 1000, 1300, 900, 840]
        for width in widths {
            window.setContentSize(NSSize(width: width, height: 600))
            settle()
            let rightEdge = fileViewsMaxX(in: content).max() ?? 0
            if withPanels {
                // La ventana no se deja achicar por debajo del mínimo con el panel
                // de información abierto; dentro de ese mínimo nada se sale.
                XCTAssertGreaterThanOrEqual(window.contentMinSize.width, ContentView.minimumWidthWithInfoPanel - 1)
                if width >= ContentView.minimumWidthWithInfoPanel {
                    for split in all(NSSplitView.self, in: content) {
                        let frame = split.convert(split.bounds, to: content)
                        XCTAssertGreaterThanOrEqual(frame.minX, -1, "ancho \(width): un divisor se sale por la izquierda")
                        XCTAssertLessThanOrEqual(frame.maxX, content.bounds.width + 1, "ancho \(width): un divisor se sale por la derecha")
                    }
                }
            } else {
                XCTAssertEqual(rightEdge, content.bounds.width, accuracy: 1, "ancho \(width): los paneles no llegan al borde")
            }
        }
    }
}
