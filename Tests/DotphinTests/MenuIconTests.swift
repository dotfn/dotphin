import AppKit
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
}
