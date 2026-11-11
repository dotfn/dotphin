import AppKit
import SwiftUI
import XCTest
@testable import Dotphin

/// La barra lateral usa la selección nativa de la lista (para poder arrastrar
/// Favoritos); la fila elegida sale de la carpeta que se está viendo.
@MainActor
final class SidebarSelectionTests: XCTestCase {
    final class Navigation { var selected: [PlaceItem] = [] }

    private func mount(currentURL: URL, navigation: Navigation) throws -> (NSWindow, NSOutlineView, SidebarPlaces) {
        let sidebar = PlacesProvider().sidebarPlaces()
        let view = PlacesSidebarView(sidebar: sidebar, currentURL: currentURL, onSelect: { navigation.selected.append($0) })
            .frame(width: 240, height: 700)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        func find(_ view: NSView) -> NSOutlineView? { (view as? NSOutlineView) ?? view.subviews.lazy.compactMap(find).first }
        return (window, try XCTUnwrap(find(try XCTUnwrap(window.contentView))), sidebar)
    }

    func test_theFolderBeingViewed_isTheSelectedRow() throws {
        let desktop = try XCTUnwrap(PlacesProvider().favorites().first { $0.name == "Desktop" })
        let (window, outline, _) = try mount(currentURL: desktop.url, navigation: Navigation())
        defer { window.close() }
        XCTAssertGreaterThanOrEqual(outline.selectedRow, 0, "Escritorio aparece elegido")
    }

    func test_aFolderOutsideTheSidebar_selectsNothing() throws {
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let (window, outline, _) = try mount(currentURL: elsewhere, navigation: Navigation())
        defer { window.close() }
        XCTAssertEqual(outline.selectedRow, -1)
    }

    func test_choosingARow_navigatesThere() throws {
        let navigation = Navigation()
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let (window, outline, sidebar) = try mount(currentURL: elsewhere, navigation: navigation)
        defer { window.close() }
        // La primera fila después del encabezado de Favoritos.
        let row = try XCTUnwrap((0..<outline.numberOfRows).first { outline.isRowSelectable($0) })
        outline.selectRowIndexes([row], byExtendingSelection: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(navigation.selected.map(\.url), [sidebar.favorites[0].url])
    }
}

private extension NSOutlineView {
    func isRowSelectable(_ row: Int) -> Bool {
        guard let item = item(atRow: row) else { return false }
        return delegate?.outlineView?(self, shouldSelectItem: item) ?? true
    }
}
