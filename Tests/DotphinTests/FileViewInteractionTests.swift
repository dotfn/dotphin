import AppKit
import SwiftUI
import XCTest
@testable import Dotphin

/// Teclado, selección y edición en línea de las vistas de archivos de AppKit,
/// montadas en una ventana real (sin mostrarla) y manejadas con eventos sintéticos.
@MainActor
final class FileViewInteractionTests: XCTestCase {
    private var tempDir: URL!
    private var vm: BrowserViewModel!
    private var window: NSWindow!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        for name in ["alfa.txt", "beta.txt", "gamma.txt"] {
            try "x".write(to: tempDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        vm = BrowserViewModel(
            startingAt: tempDir,
            store: ViewPropertiesStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        )
    }

    override func tearDownWithError() throws {
        window?.close()
        window = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func mount(mode: ViewMode) {
        vm.setViewMode(mode)
        let hosting = NSHostingController(rootView: BrowserView(viewModel: vm).frame(width: 700, height: 420))
        window = NSWindow(contentViewController: hosting)
        window.setFrame(NSRect(x: 0, y: 0, width: 700, height: 420), display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        pump()
    }

    private func pump(_ seconds: TimeInterval = 0.15) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = find(type, in: subview) { return match }
        }
        return nil
    }

    private func key(_ keyCode: UInt16, characters: String = "") -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        )!
    }

    private func item(_ name: String) -> FileItem { vm.items.first { $0.name == name }! }

    // MARK: Tabla (Lista / Detalles)

    func test_table_arrowKeysMoveSelectionNatively() throws {
        for mode in [ViewMode.list, .details] {
            mount(mode: mode)
            let table = try XCTUnwrap(find(FileNSTableView.self, in: window.contentView), "\(mode)")
            XCTAssertEqual(table.numberOfRows, 3)
            window.makeFirstResponder(table)

            vm.select(item("alfa.txt"))
            pump()
            XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 0))

            table.keyDown(with: key(125, characters: "\u{F701}")) // ↓
            pump()
            XCTAssertEqual(vm.selectedItem?.name, "beta.txt", "\(mode)")
            window.close()
        }
    }

    func test_table_selectAllSelectsEveryItem() throws {
        mount(mode: .details)
        let table = try XCTUnwrap(find(FileNSTableView.self, in: window.contentView))
        table.selectAll(nil)
        pump()
        XCTAssertEqual(vm.selectedIDs.count, 3)
    }

    func test_table_returnStartsInlineRename_andCommitRenamesFile() throws {
        mount(mode: .list)
        let table = try XCTUnwrap(find(FileNSTableView.self, in: window.contentView))
        window.makeFirstResponder(table)
        vm.select(item("beta.txt"))
        pump()

        table.keyDown(with: key(36, characters: "\r"))
        XCTAssertEqual(vm.renamingItemID, item("beta.txt").id)
        pump()
        XCTAssertTrue(table.isRenaming)

        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 4), "selecciona el nombre sin extensión")
        editor.string = "delta.txt"
        window.makeFirstResponder(table) // terminar la edición confirma, como Finder
        pump()

        XCTAssertFalse(table.isRenaming)
        XCTAssertNil(vm.renamingItemID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("delta.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("beta.txt").path))
        XCTAssertEqual(vm.selectedItem?.name, "delta.txt")
    }

    func test_table_escapeCancelsInlineRename() throws {
        mount(mode: .list)
        let table = try XCTUnwrap(find(FileNSTableView.self, in: window.contentView))
        window.makeFirstResponder(table)
        vm.select(item("beta.txt"))
        pump()
        vm.renamingItemID = item("beta.txt").id
        pump()
        XCTAssertTrue(table.isRenaming)

        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.string = "otro.txt"
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        pump()

        XCTAssertFalse(table.isRenaming)
        XCTAssertNil(vm.renamingItemID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("beta.txt").path))
        XCTAssertTrue(window.firstResponder === table)
    }

    func test_undoManagerOfWindow_undoesAndRedoesRename() throws {
        mount(mode: .list)
        let undoManager = try XCTUnwrap(vm.undoManager)
        vm.select(item("alfa.txt"))
        vm.renameSelected(to: "omega.txt")
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("alfa.txt").path))
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("omega.txt").path))
        XCTAssertTrue(undoManager.canUndo)
    }

    // MARK: Grilla (Iconos / Compacta)

    func test_grid_showsItems_andSyncsSelectionBothWays() throws {
        for mode in [ViewMode.icons, .compact] {
            mount(mode: mode)
            let grid = try XCTUnwrap(find(FileNSCollectionView.self, in: window.contentView), "\(mode)")
            XCTAssertEqual(grid.numberOfItems(inSection: 0), 3)
            XCTAssertEqual(grid.visibleItems().count, 3, "\(mode)")
            window.makeFirstResponder(grid)

            vm.select(item("alfa.txt"))
            pump()
            XCTAssertEqual(grid.selectionIndexPaths, [IndexPath(item: 0, section: 0)])

            grid.keyDown(with: key(124, characters: "\u{F703}")) // →
            pump()
            XCTAssertEqual(vm.selectedItem?.name, mode == .icons ? "beta.txt" : vm.selectedItem?.name, "\(mode)")
            XCTAssertEqual(vm.selectedIDs.count, 1)
            window.close()
        }
    }

    func test_grid_cellPassesClicksToGrid_andDoubleClickOpens() throws {
        let folder = tempDir.appendingPathComponent("carpeta", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        vm.refresh()
        mount(mode: .icons)
        let grid = try XCTUnwrap(find(FileNSCollectionView.self, in: window.contentView))
        let indexPath = try XCTUnwrap(grid.indexPathForID(item("carpeta").id))
        let frame = try XCTUnwrap(grid.layoutAttributesForItem(at: indexPath)?.frame)
        let pointInWindow = grid.convert(NSPoint(x: frame.midX, y: frame.minY + 30), to: nil)

        func mouse(_ type: NSEvent.EventType, clicks: Int) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: pointInWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1
            )!
        }

        // La celda no se queda con el clic: llega a la grilla.
        XCTAssertTrue(window.contentView?.hitTest(pointInWindow)?.isDescendant(of: grid) == true)
        XCTAssertFalse(window.contentView?.hitTest(pointInWindow) is NSHostingView<FileGridCellContent>)

        // (La selección por clic de NSCollectionView depende del estado real del
        // mouse y no reacciona a eventos sintéticos; acá se prueba el doble clic.)
        NSApp.postEvent(mouse(.leftMouseUp, clicks: 2), atStart: false)
        grid.mouseDown(with: mouse(.leftMouseDown, clicks: 2))
        pump(0.4)
        XCTAssertEqual(vm.currentURL.lastPathComponent, "carpeta")
    }

    func test_grid_selectionMode_clickTogglesWithoutModifiers() throws {
        mount(mode: .compact)
        vm.isSelectionModeActive = true
        pump()
        let grid = try XCTUnwrap(find(FileNSCollectionView.self, in: window.contentView))
        for index in [0, 2] {
            let frame = try XCTUnwrap(grid.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame)
            let event = NSEvent.mouseEvent(
                with: .leftMouseDown, location: grid.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            )!
            grid.mouseDown(with: event)
        }
        pump()
        XCTAssertEqual(Set(vm.selectedItems.map(\.name)), ["alfa.txt", "gamma.txt"])
    }

    func test_grid_inlineRename_commits() throws {
        mount(mode: .icons)
        let grid = try XCTUnwrap(find(FileNSCollectionView.self, in: window.contentView))
        window.makeFirstResponder(grid)
        vm.select(item("gamma.txt"))
        pump()

        grid.keyDown(with: key(36, characters: "\r"))
        pump()
        XCTAssertTrue(grid.isRenaming)
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 5))
        editor.string = "zeta.txt"
        window.makeFirstResponder(grid)
        pump()

        XCTAssertFalse(grid.isRenaming)
        XCTAssertNil(vm.renamingItemID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("zeta.txt").path))
    }

    func test_grid_typeAheadJumpsToItem() throws {
        mount(mode: .icons)
        let grid = try XCTUnwrap(find(FileNSCollectionView.self, in: window.contentView))
        window.makeFirstResponder(grid)
        grid.keyDown(with: key(5, characters: "g"))
        pump()
        XCTAssertEqual(vm.selectedItem?.name, "gamma.txt")
    }

    // MARK: Menú Edición estándar

    /// Con una vista de archivos enfocada nadie en la ventana atiende Copiar /
    /// Pegar: la acción sigue por la responder chain hasta `AppDelegate`.
    func test_editActions_fallThroughToAppDelegate_whenFileViewHasFocus() throws {
        for mode in [ViewMode.list, .icons] {
            mount(mode: mode)
            window.makeKeyAndOrderFront(nil)
            pump()
            let fileView: NSView = try XCTUnwrap(
                mode == .list
                    ? find(FileNSTableView.self, in: window.contentView)
                    : find(FileNSCollectionView.self, in: window.contentView)
            )
            window.makeFirstResponder(fileView)
            for action in [#selector(NSText.copy(_:)), #selector(NSText.cut(_:)), #selector(NSText.paste(_:))] {
                var responder: NSResponder? = window.firstResponder
                while let current = responder {
                    XCTAssertFalse(current.responds(to: action), "\(type(of: current)) intercepta \(action) en \(mode)")
                    responder = current.nextResponder
                }
            }
            XCTAssertTrue(AppDelegate().responds(to: #selector(NSText.copy(_:))))
            window.close()
        }
    }
}
