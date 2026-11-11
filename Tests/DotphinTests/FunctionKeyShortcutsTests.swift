import AppKit
import XCTest
@testable import Dotphin

/// Atajos del menú y teclas F de respaldo: que cada tecla F caiga en un atajo
/// que de verdad existe en el menú, y que no vuelvan los que macOS se queda.
@MainActor
final class FunctionKeyShortcutsTests: XCTestCase {
    private func key(_ chars: String, code: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: chars,
            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code
        ))
    }

    private func fKey(_ code: Int) -> String {
        String(Character(UnicodeScalar(code)!))
    }

    private func commandsSource() throws -> String {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Dotphin/App/FileEditCommands.swift")
        return try String(contentsOf: file, encoding: .utf8)
    }

    /// (carácter, modificadores) de cada `.keyboardShortcut("x", modifiers: …)` del menú.
    private func menuShortcuts() throws -> [(String, NSEvent.ModifierFlags)] {
        let source = try commandsSource()
        let regex = try NSRegularExpression(pattern: #"\.keyboardShortcut\("((?:\\\\|[^"\\])+)", modifiers: ([^)]+)\)"#)
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match in
            guard let keyRange = Range(match.range(at: 1), in: source),
                  let modsRange = Range(match.range(at: 2), in: source) else { return nil }
            let key = source[keyRange] == #"\\"# ? "\\" : String(source[keyRange])
            let mods = source[modsRange]
            var flags: NSEvent.ModifierFlags = []
            if mods.contains(".command") { flags.insert(.command) }
            if mods.contains(".shift") { flags.insert(.shift) }
            if mods.contains(".option") { flags.insert(.option) }
            if mods.contains(".control") { flags.insert(.control) }
            return (key, flags)
        }
    }

    func test_everyFallbackLandsOnAShortcutTheMenuHas() throws {
        let menu = try menuShortcuts()
        XCTAssertGreaterThan(menu.count, 30, "no se leyeron los atajos del menú")
        for alias in FunctionKeyShortcuts.aliases {
            let target = alias.target
            XCTAssertTrue(
                menu.contains { $0.0 == target.characters && $0.1 == target.modifiers },
                "la tecla de respaldo apunta a \(target) y el menú no lo tiene"
            )
        }
    }

    func test_translatedEvent_firesTheMatchingMenuItem() throws {
        final class Target: NSObject {
            var fired: [String] = []
            @objc func hit(_ sender: NSMenuItem) { fired.append(sender.title) }
        }
        let target = Target()
        let menu = NSMenu()
        for alias in FunctionKeyShortcuts.aliases {
            let item = NSMenuItem(title: alias.target.characters, action: #selector(Target.hit(_:)), keyEquivalent: alias.target.characters)
            item.keyEquivalentModifierMask = alias.target.modifiers
            item.target = target
            menu.addItem(item)
        }

        let f3 = try key(fKey(NSF3FunctionKey), code: 99, flags: [.function])
        let shortcut = try XCTUnwrap(FunctionKeyShortcuts.menuShortcut(for: f3))
        XCTAssertTrue(menu.performKeyEquivalent(with: try XCTUnwrap(FunctionKeyShortcuts.translatedEvent(f3, to: shortcut))))

        let shiftF4 = try key(fKey(NSF4FunctionKey), code: 118, flags: [.function, .shift])
        let terminal = try XCTUnwrap(FunctionKeyShortcuts.menuShortcut(for: shiftF4))
        XCTAssertTrue(menu.performKeyEquivalent(with: try XCTUnwrap(FunctionKeyShortcuts.translatedEvent(shiftF4, to: terminal))))

        XCTAssertEqual(target.fired, ["\\", "`"])
    }

    func test_keysMacOSKeepsForItself_areNotUsed() throws {
        // F11 = Mostrar escritorio, ⌃F3 = foco al Dock: nunca llegan a la app.
        XCTAssertNil(FunctionKeyShortcuts.menuShortcut(for: try key(fKey(NSF11FunctionKey), code: 103, flags: [.function])))
        XCTAssertNil(FunctionKeyShortcuts.menuShortcut(for: try key(fKey(NSF3FunctionKey), code: 99, flags: [.function, .control])))
        let source = try commandsSource()
        XCTAssertFalse(source.contains("NSF11FunctionKey"))
        XCTAssertFalse(source.contains("NSF3FunctionKey), modifiers: [.control])"))
        // ⇧⌘⌫ es Vaciar Papelera en Finder; eliminar al instante es ⌥⌘⌫.
        XCTAssertFalse(source.contains(".keyboardShortcut(.delete, modifiers: [.command, .shift])"))
    }

    func test_plainKeysAndUnknownCombos_passThrough() throws {
        XCTAssertNil(FunctionKeyShortcuts.menuShortcut(for: try key("a", code: 0)))
        XCTAssertNil(FunctionKeyShortcuts.menuShortcut(for: try key(fKey(NSF5FunctionKey), code: 96, flags: [.function, .command])))
        XCTAssertEqual(
            FunctionKeyShortcuts.menuShortcut(for: try key("=", code: 24, flags: [.command])),
            .init(characters: "+", keyCode: 24, modifiers: .command)
        )
    }
}
