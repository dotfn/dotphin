import AppKit
import SwiftUI

/// Comandos de menú que necesitan estado de la ventana (hojas, alertas, pestañas).
enum WindowCommand {
    case renameSelectedFiles
    case createNewFolder
    case moveToNewFolder
    case selectByPattern
    case deleteSelectedFiles
    case permanentDeleteSelectedFiles
    case quickLookSelectedFiles
    case showProperties
    case showViewPropertiesDialog
    case showDiskUsageAnalyzer
    case addTab
    case duplicateTab
    case closeTab
    case closeOtherTabs
    case reopenClosedTab
    case selectNextTab
    case selectPrevTab
    case toggleSplit
    case focusOtherSplitPane
    case moveSplitToTabs
    case swapSplitPanes
    case copyToOtherSplitPane
    case moveToOtherSplitPane
    case compareFiles
    case toggleInfoPanel
    case toggleFilterBar
    case toggleEmbeddedTerminal
    case openTerminal
    case bookmarkAllTabs
    case editBookmarks
    case openAllBookmarksInTabs
    case editLocationBar
    case toggleTabOverview
}

/// Destino de los comandos de menú de UNA ventana. `ContentView` lo publica con
/// `focusedSceneValue`, así el menú actúa solo sobre la ventana activa (antes
/// eran notificaciones globales que recibían todas las ventanas a la vez).
///
/// También queda asociado a su `NSWindow` para que `AppDelegate` — último
/// eslabón de la responder chain — atienda Copiar/Cortar/Pegar del menú Edición
/// estándar cuando el foco no está en un campo de texto.
@MainActor
final class WindowCommands {
    var handler: (WindowCommand) -> Void = { _ in }
    var focusedViewModel: () -> BrowserViewModel? = { nil }

    func perform(_ command: WindowCommand) {
        handler(command)
    }

    private static let byWindow = NSMapTable<NSWindow, WindowCommands>.weakToWeakObjects()

    static func commands(for window: NSWindow?) -> WindowCommands? {
        guard let window else { return nil }
        return byWindow.object(forKey: window)
    }

    func attach(to window: NSWindow) {
        Self.byWindow.setObject(self, forKey: window)
    }
}

private struct WindowCommandsFocusedKey: FocusedValueKey {
    typealias Value = WindowCommands
}

extension FocusedValues {
    var windowCommands: WindowCommands? {
        get { self[WindowCommandsFocusedKey.self] }
        set { self[WindowCommandsFocusedKey.self] = newValue }
    }
}

/// Asocia `WindowCommands` con la `NSWindow` que contiene a la vista.
struct WindowCommandsRegistrar: NSViewRepresentable {
    let commands: WindowCommands

    func makeNSView(context: Context) -> RegistrarView {
        let view = RegistrarView()
        view.commands = commands
        return view
    }

    func updateNSView(_ nsView: RegistrarView, context: Context) {
        nsView.commands = commands
        nsView.register()
    }

    final class RegistrarView: NSView {
        var commands: WindowCommands?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            register()
        }

        func register() {
            guard let window, let commands else { return }
            commands.attach(to: window)
        }
    }
}

/// Pedido de "Editar ubicación…" (⌘L): un contador que sube con cada pedido.
private struct LocationEditRequestKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var locationEditRequest: Int {
        get { self[LocationEditRequestKey.self] }
        set { self[LocationEditRequestKey.self] = newValue }
    }
}
