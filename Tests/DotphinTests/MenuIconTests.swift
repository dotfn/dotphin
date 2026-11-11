import AppKit
import SwiftUI
import XCTest
@testable import Dotphin

/// Íconos de los menús contextuales: que cada símbolo exista (si no, el ítem
/// queda con un hueco) y que la opción para apagarlos se guarde.
final class MenuIconTests: XCTestCase {
    private func menuIconNames() throws -> Set<String> {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Dotphin")
        let regex = try NSRegularExpression(pattern: #"menuIcon: "([^"]+)""#)
        var names = Set<String>()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { names.insert(String(text[range])) }
            }
        }
        return names
    }

    func test_everyMenuIconIsARealSFSymbol() throws {
        let names = try menuIconNames()
        XCTAssertGreaterThan(names.count, 30, "no se encontraron los íconos de los menús")
        let missing = names.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }.sorted()
        XCTAssertEqual(missing, [], "símbolos que no existen")
    }

    func test_menuIcons_areOnByDefault_evenForSettingsSavedBeforeTheOption() throws {
        XCTAssertTrue(AppSettings().showsMenuIcons)
        let old = Data(#"{"showsHiddenFiles": true}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertTrue(decoded.showsMenuIcons)
        XCTAssertTrue(decoded.showsHiddenFiles)
    }

    func test_turningMenuIconsOff_survivesSaving() throws {
        var settings = AppSettings()
        settings.showsMenuIcons = false
        let roundTrip = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(roundTrip.showsMenuIcons)
    }

    /// El menú contextual de las vistas de AppKit sale de SwiftUI vía
    /// `NSHostingMenu`: los ítems tienen que llegar al `NSMenu` con su imagen.
    @MainActor
    func test_fileContextMenu_itemsCarryTheirIcons_andLoseThemWhenTurnedOff() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let vm = BrowserViewModel(startingAt: dir)
        let actions = BrowserContextMenuActions(
            viewModel: vm, onOpen: { _ in }, onOpenInNewTab: nil, onNewFolderPrompt: {}, onNewFilePrompt: { _ in },
            onRename: { _ in }, onBatchRename: {}, onDelete: { _ in }, onDeleteSelection: {},
            onShowProperties: { _ in }, onOpenTerminal: nil
        )
        func menuImages() throws -> [String: Bool] {
            let menu = try XCTUnwrap(makeFileItemsMenu(for: vm.items, actions: actions, onRename: nil, onBatchRename: nil, onDelete: { _ in }, onDeleteSelection: {}))
            menu.update()
            return Dictionary(menu.items.filter { !$0.isSeparatorItem }.map { ($0.title, $0.image != nil) }, uniquingKeysWith: { $0 || $1 })
        }

        let settings = AppSettingsModel.shared
        let original = settings.settings.showsMenuIcons
        defer { settings.settings.showsMenuIcons = original }

        settings.settings.showsMenuIcons = true
        let withIcons = try menuImages()
        let cut = appText("Cortar")
        XCTAssertEqual(withIcons[cut], true, "«\(cut)» sin ícono: \(withIcons)")
        XCTAssertGreaterThan(withIcons.values.filter { $0 }.count, 8)

        settings.settings.showsMenuIcons = false
        let withoutIcons = try menuImages()
        XCTAssertEqual(withoutIcons.values.filter { $0 }.count, 0, "con la opción apagada no debe haber íconos: \(withoutIcons)")
    }
}
