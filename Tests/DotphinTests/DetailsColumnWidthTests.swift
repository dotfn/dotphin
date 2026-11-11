import AppKit
import SwiftUI
import XCTest
@testable import Dotphin

/// Anchos de columna de Detalles: las columnas llenan el ancho visible, sin
/// hueco al final ni barra horizontal de más, aun con anchos guardados de
/// otra ventana u otro panel.
@MainActor
final class DetailsColumnWidthTests: XCTestCase {
    @Observable final class Columns {
        var visible: [DetailsColumn] = []
    }

    struct Host: View {
        let model: Columns

        var body: some View {
            DetailsTableView(
                rows: [], visibleColumns: model.visible, zoomLevel: 1, selection: .constant([]), gitStatuses: [:],
                expandableFolders: true, directorySizeMode: .contentCount, useRelativeDates: false,
                permissionsFormat: .symbolic, currentURL: URL(fileURLWithPath: NSTemporaryDirectory()),
                sortField: .name, ascending: true, onChangeSort: nil, onToggleColumn: nil, onOpen: { _ in },
                onToggleExpansion: { _ in }, onMoveDropped: { _, _ in }, menuForItems: { _, _ in nil }
            )
        }
    }

    private let defaultsKey = "NSTableView Columns v3 \(DetailsTableView.Coordinator.columnsAutosaveName)"
    private var savedDefaults: Any?
    private var windows: [NSWindow] = []

    override func setUp() async throws {
        savedDefaults = UserDefaults.standard.object(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        UserDefaults.standard.set(savedDefaults, forKey: defaultsKey)
    }

    private func spin() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    private func mount(width: CGFloat, _ columns: [DetailsColumn]) throws -> (Columns, NSWindow, NSScrollView, NSTableView) {
        let model = Columns()
        model.visible = columns
        let window = NSWindow(contentViewController: NSHostingController(rootView: Host(model: model)))
        window.setContentSize(NSSize(width: width, height: 400))
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        spin()
        func find(in view: NSView) -> NSScrollView? {
            if let match = view as? NSScrollView { return match }
            return view.subviews.lazy.compactMap(find).first
        }
        let scrollView = try XCTUnwrap(find(in: try XCTUnwrap(window.contentView)))
        let tableView = try XCTUnwrap(scrollView.documentView as? NSTableView)
        return (model, window, scrollView, tableView)
    }

    /// Hueco entre la última columna y el borde: 10 pt es el margen del estilo `.inset`.
    private func trailingGap(_ scrollView: NSScrollView, _ tableView: NSTableView) -> CGFloat {
        scrollView.contentView.bounds.width - tableView.rect(ofColumn: tableView.numberOfColumns - 1).maxX
    }

    func test_widthsSavedInAWiderWindow_stillFitANarrowerOne() throws {
        let columns: [DetailsColumn] = [.type, .size, .modificationDate]
        let (_, wide, _, wideTable) = try mount(width: 1200, columns)
        wideTable.tableColumns[0].width = 800
        spin()
        wide.close()

        let (_, _, scrollView, tableView) = try mount(width: 800, columns)
        XCTAssertEqual(tableView.frame.width, scrollView.contentView.bounds.width, "sin barra horizontal")
        XCTAssertEqual(trailingGap(scrollView, tableView), 10, accuracy: 1)
    }

    func test_widthsSavedInANarrowerPane_stillFillAWiderOne() throws {
        let (model, _, scrollView, tableView) = try mount(width: 1200, [.type, .size])

        // Otro panel, más angosto, guarda sus anchos…
        let (_, narrow, _, narrowTable) = try mount(width: 600, [.type, .size, .modificationDate])
        narrowTable.tableColumns[0].width = 200
        spin()
        narrow.close()

        // …y este, ya en pantalla, rearma sus columnas y los restaura.
        model.visible = [.type, .size, .modificationDate]
        spin()
        XCTAssertEqual(trailingGap(scrollView, tableView), 10, accuracy: 1, "sin hueco al final")
        XCTAssertEqual(tableView.frame.width, scrollView.contentView.bounds.width)
    }

    func test_resizing_keepsColumnsFitting_untilNameReachesItsMinimum() throws {
        let (_, window, scrollView, tableView) = try mount(width: 1000, [.type, .size, .modificationDate])
        for width in [600, 1200, 700] as [CGFloat] {
            window.setContentSize(NSSize(width: width, height: 400))
            spin()
            XCTAssertEqual(trailingGap(scrollView, tableView), 10, accuracy: 1, "ancho \(width)")
        }
        // Más angosto que el mínimo de Nombre más las demás: ahí sí hay barra.
        window.setContentSize(NSSize(width: 420, height: 400))
        spin()
        XCTAssertEqual(tableView.tableColumns[0].width, tableView.tableColumns[0].minWidth)
        XCTAssertGreaterThan(tableView.frame.width, scrollView.contentView.bounds.width)
    }
}
