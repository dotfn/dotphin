import AppKit
import SwiftUI
import XCTest
@testable import Dotphin

/// Barra de herramientas: disposición por defecto y buscador.
///
/// La persistencia de la personalización no se puede probar acá: estas
/// ventanas no son las de `WindowGroup` (no tienen el espacio flexible ni el
/// botón de la barra lateral) y SwiftUI se comporta distinto. Se verificó con
/// la app real escribiendo la configuración en sus preferencias (ver
/// docs/decisions.md).
@MainActor
final class ToolbarCustomizationTests: XCTestCase {
    private func openWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView()))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        return window
    }

    /// SwiftUI descarta la personalización guardada si tiene más copias de un
    /// espaciador que la barra por defecto: con este espacio flexible (que
    /// además lleva el buscador al borde) se pueden usar dos.
    func test_defaultToolbar_hasAFlexibleSpaceBeforeSearch() throws {
        let window = openWindow()
        defer { window.close() }
        let identifiers = try XCTUnwrap(window.toolbar).items.map(\.itemIdentifier.rawValue)
        XCTAssertEqual(Array(identifiers.suffix(2)), [NSToolbarItem.Identifier.flexibleSpace.rawValue, "com.apple.SwiftUI.search"])
    }

    /// ⌘F (Ir → Buscar…) pone el foco en el campo de búsqueda de la barra.
    func test_findCommand_focusesTheToolbarSearchField() throws {
        let window = openWindow()
        defer { window.close() }
        let search = try XCTUnwrap(window.toolbar?.items.compactMap { $0 as? NSSearchToolbarItem }.first)
        WindowCommands.commands(for: window)?.perform(.focusSearch)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let editor = window.firstResponder as? NSText
        XCTAssertTrue(editor?.delegate === search.searchField, "el foco queda en el buscador")
    }
}
