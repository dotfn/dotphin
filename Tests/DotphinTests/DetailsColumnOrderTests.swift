import AppKit
import XCTest
@testable import Dotphin

/// Orden de las columnas de Detalles frente a lo que AppKit guarda (#14).
@MainActor
final class DetailsColumnOrderTests: XCTestCase {
    private var autosaveName = ""

    override func setUp() async throws {
        autosaveName = "DetailsColumnOrderTests.\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "NSTableView Columns v3 \(autosaveName)")
        UserDefaults.standard.removeObject(forKey: "NSTableView Sort Ordering v2 \(autosaveName)")
        UserDefaults.standard.removeObject(forKey: "NSTableView Supports v2 \(autosaveName)")
    }

    /// Una tabla con Nombre + `columns`, como la arma `rebuildColumns`.
    private func makeTable(_ columns: [DetailsColumn]) -> NSTableView {
        let tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: 900, height: 300))
        let identifiers = [DetailsTableView.Coordinator.nameColumnID]
            + columns.map { NSUserInterfaceItemIdentifier($0.rawValue) }
        for identifier in identifiers {
            let column = NSTableColumn(identifier: identifier)
            column.width = 120
            tableView.addTableColumn(column)
        }
        tableView.autosaveName = autosaveName
        tableView.autosaveTableColumns = true
        return tableView
    }

    private func order(of tableView: NSTableView) -> [String] {
        tableView.tableColumns.map(\.identifier.rawValue)
    }

    func test_columnShownAfterSaving_goesBackToItsCanonicalPlace() {
        // Se guarda con Tipo y Tamaño (cambiar un ancho dispara el guardado).
        let saved = makeTable([.type, .size])
        saved.tableColumns[1].width = 150

        // Después se muestra «Extensión», que va entre las dos.
        let columns: [DetailsColumn] = [.type, .extensionType, .size]
        let restored = makeTable(columns)
        // Acá AppKit ya restauró lo guardado y dejó «Extensión» al final:
        // name, type, size, extensionType.
        DetailsTableView.Coordinator.restoreCanonicalOrder(of: columns, in: restored)

        XCTAssertEqual(order(of: restored), ["name", "type", "extensionType", "size"])
        XCTAssertEqual(restored.tableColumns[1].width, 150, "los anchos guardados se conservan")
    }

    func test_canonicalOrder_fixesAnyShuffledOrder() {
        let columns: [DetailsColumn] = [.type, .extensionType, .size, .modificationDate]
        let tableView = makeTable(columns)
        tableView.moveColumn(4, toColumn: 1)
        tableView.moveColumn(0, toColumn: 3)

        DetailsTableView.Coordinator.restoreCanonicalOrder(of: columns, in: tableView)

        XCTAssertEqual(order(of: tableView), ["name", "type", "extensionType", "size", "modificationDate"])
    }
}
