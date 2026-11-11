import AppKit
import SwiftUI
import XCTest
@testable import Dotphin

/// "Compartir…" (AirDrop, Mail…) y la fila de colores de Finder en el menú
/// contextual de archivos, probados sobre el `NSMenu` real que arma la app.
@MainActor
final class ShareAndColorTagMenuTests: XCTestCase {
    private var dir: URL!
    private var file: URL!
    private var vm: BrowserViewModel!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("nota.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        vm = BrowserViewModel(startingAt: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func itemMenu() throws -> NSMenu {
        let actions = BrowserContextMenuActions(
            viewModel: vm, onOpen: { _ in }, onOpenInNewTab: nil, onNewFolderPrompt: {}, onNewFilePrompt: { _ in },
            onRename: { _ in }, onBatchRename: {}, onDelete: { _ in }, onDeleteSelection: {},
            onShowProperties: { _ in }, onOpenTerminal: nil
        )
        let menu = try XCTUnwrap(makeFileItemsMenu(for: vm.items, actions: actions, onRename: nil, onBatchRename: nil, onDelete: { _ in }, onDeleteSelection: {}))
        menu.update()
        return menu
    }

    private func paletteItem(in menu: NSMenu) throws -> NSMenuItem {
        try XCTUnwrap(menu.items.first { $0.submenu?.presentationStyle == .palette }, "no hay fila de colores")
    }

    private func labelNumber() -> Int {
        let values = try? file.resourceValues(forKeys: [.labelNumberKey])
        return values?.labelNumber ?? 0
    }

    /// Color del centro de la imagen, ya dibujada.
    private func centerColor(of image: NSImage) throws -> NSColor {
        let size = NSSize(width: 32, height: 32)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.colorAt(x: 16, y: 16)?.usingColorSpace(.sRGB))
    }

    func test_shareItem_isInTheMenu() throws {
        let titles = try itemMenu().items.map(\.title)
        XCTAssertTrue(titles.contains { $0 == "Share…" || $0 == "Compartir…" }, "falta Compartir: \(titles)")
    }

    func test_palette_showsTheSevenFinderColors_inOrder_andInColor() throws {
        let palette = try XCTUnwrap(paletteItem(in: itemMenu()).submenu)
        XCTAssertEqual(palette.items.count, 7, "sin etiqueta no se ofrece quitarla")
        for (item, tag) in zip(palette.items, FinderColorTag.finderPaletteOrder) {
            let image = try XCTUnwrap(item.image, "\(tag) sin imagen")
            XCTAssertFalse(image.isTemplate, "\(tag): una imagen plantilla se dibuja gris")
            let drawn = try centerColor(of: image)
            let expected = try XCTUnwrap(tag.nsColor?.usingColorSpace(.sRGB))
            let distance = abs(drawn.redComponent - expected.redComponent)
                + abs(drawn.greenComponent - expected.greenComponent)
                + abs(drawn.blueComponent - expected.blueComponent)
            XCTAssertLessThan(distance, 0.35, "\(tag): se dibujó \(drawn) en vez de \(expected)")
        }
    }

    func test_taggedFile_marksItsColor_andOffersToRemoveIt() throws {
        try FolderIconAndTagService().setColorTag(.blue, for: file)
        vm.refresh()
        let palette = try XCTUnwrap(paletteItem(in: itemMenu()).submenu)
        let blue = try XCTUnwrap(FinderColorTag.finderPaletteOrder.firstIndex(of: .blue))
        XCTAssertEqual(palette.items.count, 8, "con etiqueta se ofrece quitarla")
        XCTAssertEqual(palette.items[blue].state, .on)
        XCTAssertEqual(palette.items.filter { $0.state == .on }.count, 1)
    }

    func test_choosingTheCurrentColorAgain_removesIt_likeFinder() {
        XCTAssertEqual(FinderColorTag.tagToApply(choosing: .red, current: FinderColorTag.none), .red)
        XCTAssertEqual(FinderColorTag.tagToApply(choosing: .red, current: .blue), .red)
        XCTAssertEqual(FinderColorTag.tagToApply(choosing: .blue, current: .blue), FinderColorTag.none)
        XCTAssertEqual(FinderColorTag.tagToApply(choosing: FinderColorTag.none, current: .blue), FinderColorTag.none)
        // Varios ítems: no hay color "actual", elegir uno los etiqueta a todos.
        XCTAssertEqual(FinderColorTag.tagToApply(choosing: .green, current: nil), .green)
    }

    func test_paletteStaysVisible_evenWithMenuIconsTurnedOff() throws {
        MenuImageVisibility.shared.install()
        let settings = AppSettingsModel.shared
        let original = settings.settings.showsMenuIcons
        defer { settings.settings.showsMenuIcons = original }
        settings.settings.showsMenuIcons = false

        let palette = try XCTUnwrap(paletteItem(in: itemMenu()).submenu)
        XCTAssertEqual(palette.items.filter { $0.preferredImageVisibility != .visible }.count, 0)
    }
}

/// Compartir se abre apuntando al ícono del archivo que se tocó, como Finder.
@MainActor
final class ShareAnchorTests: XCTestCase {
    private final class Source: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        func numberOfRows(in tableView: NSTableView) -> Int { 5 }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cell = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            let icon = NSImageView(frame: NSRect(x: 20, y: 4, width: 16, height: 16))
            icon.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
            cell.addSubview(icon)
            return cell
        }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 24 }
    }

    func test_anchor_isTheIconOfTheClickedRow() throws {
        let source = Source()
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        table.addTableColumn(NSTableColumn(identifier: .init("nombre")))
        table.tableColumns[0].width = 300
        table.dataSource = source
        table.delegate = source
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = table
        defer { window.close() }
        table.reloadData()
        table.layoutSubtreeIfNeeded()

        let anchor = try XCTUnwrap(ShareAnchor.forRow(2, in: table))
        XCTAssertTrue(anchor.view === table)
        let rowRect = table.rect(ofRow: 2)
        XCTAssertTrue(rowRect.contains(anchor.rect), "el ancla no está en la fila tocada")
        XCTAssertEqual(anchor.rect.width, 16, accuracy: 0.5, "debería ser el ícono, no toda la fila")
        XCTAssertNil(ShareAnchor.forRow(9, in: table))
    }
}
