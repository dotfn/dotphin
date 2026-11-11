import AppKit

/// Atajos de respaldo estilo Dolphin. El menú muestra el atajo de macOS; estas
/// teclas (F3, F4, F5…) siguen andando cuando llegan a la app, es decir con fn o
/// con "Usar F1, F2, etc. como teclas de función estándar". Cada una se traduce
/// al atajo del menú, así no hay dos caminos para la misma acción.
///
/// F11 (Mostrar escritorio) y ⌃F3 (foco al Dock) no figuran: macOS se los
/// queda antes de que lleguen a la app.
enum FunctionKeyShortcuts {
    struct Shortcut: Equatable {
        let characters: String
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
    }

    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    private static func fKey(_ code: Int) -> String {
        String(Character(UnicodeScalar(code)!))
    }

    /// (tecla, modificadores) → atajo del menú.
    static let aliases: [(key: String, modifiers: NSEvent.ModifierFlags, target: Shortcut)] = [
        (fKey(NSF3FunctionKey), [], Shortcut(characters: "\\", keyCode: 42, modifiers: .command)),
        (fKey(NSF4FunctionKey), [], Shortcut(characters: "`", keyCode: 50, modifiers: .control)),
        (fKey(NSF4FunctionKey), .shift, Shortcut(characters: "`", keyCode: 50, modifiers: [.control, .shift])),
        (fKey(NSF5FunctionKey), [], Shortcut(characters: "r", keyCode: 15, modifiers: .command)),
        (fKey(NSF5FunctionKey), .shift, Shortcut(characters: "c", keyCode: 8, modifiers: [.command, .control])),
        (fKey(NSF6FunctionKey), .shift, Shortcut(characters: "m", keyCode: 46, modifiers: [.command, .control])),
        (fKey(NSF12FunctionKey), [], Shortcut(characters: "p", keyCode: 35, modifiers: [.command, .shift])),
        // ⌘= como ⌘+: en un teclado inglés "+" pide ⇧.
        ("=", .command, Shortcut(characters: "+", keyCode: 24, modifiers: .command)),
    ]

    /// El atajo del menú que corresponde a `event`, o `nil` si no es una tecla de respaldo.
    static func menuShortcut(for event: NSEvent) -> Shortcut? {
        guard event.type == .keyDown, let key = event.charactersIgnoringModifiers else { return nil }
        let modifiers = event.modifierFlags.intersection(relevantModifiers)
        return aliases.first { $0.key == key && $0.modifiers == modifiers }?.target
    }

    /// Mismo evento, con la tecla y los modificadores del atajo del menú.
    static func translatedEvent(_ event: NSEvent, to shortcut: Shortcut) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: event.locationInWindow, modifierFlags: shortcut.modifiers,
            timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
            characters: shortcut.characters, charactersIgnoringModifiers: shortcut.characters,
            isARepeat: event.isARepeat, keyCode: shortcut.keyCode
        )
    }

    private nonisolated(unsafe) static var monitor: Any?

    /// Va antes que la vista con foco (también la terminal) para que la tecla
    /// no termine escrita en la shell.
    @MainActor
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handledByMenu = MainActor.assumeIsolated { () -> Bool in
                guard let shortcut = menuShortcut(for: event),
                      let translated = translatedEvent(event, to: shortcut)
                else { return false }
                return NSApp.mainMenu?.performKeyEquivalent(with: translated) == true
            }
            return handledByMenu ? nil : event
        }
    }
}
