import AppKit
import SwiftUI

@main
struct DotphinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            // Visualización → "Personalizar barra de herramientas…" del sistema.
            ToolbarCommands()
            FileEditCommands()
            AppSettingsCommands()
        }
        Settings {
            SettingsView()
        }
    }

    /// Safely resolves `AppIcon.icns` from either an `.app` bundle or the SPM resource bundle
    /// without invoking `Bundle.module`'s `fatalError` if the bundle was relocated.
    fileprivate static func applyAppIcon() {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            Bundle.main.resourceURL?
                .appendingPathComponent("Dotphin_Dotphin.bundle")
                .appendingPathComponent("AppIcon.icns"),
            Bundle.main.bundleURL
                .appendingPathComponent("Dotphin_Dotphin.bundle")
                .appendingPathComponent("AppIcon.icns"),
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: candidate.path),
               let image = NSImage(contentsOf: candidate) {
                NSApplication.shared.applicationIconImage = image
                return
            }
        }
    }
}

private struct AppSettingsCommands: Commands {
    @FocusedValue(\.windowCommands) private var commands

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Mostrar todas las pestañas") {
                commands?.perform(.toggleTabOverview)
            }
            .keyboardShortcut("\\", modifiers: [.command, .shift])
            DebugEventsToggle()
        }
    }
}

/// Prende/apaga `DebugEventLog` desde el menú de la app.
private struct DebugEventsToggle: View {
    @State private var isEnabled = DebugEventLog.isEnabled

    var body: some View {
        Toggle("Registrar eventos de depuración", isOn: $isEnabled)
            .onChange(of: isEnabled) { _, newValue in
                DebugEventLog.setEnabled(newValue)
            }
    }
}

/// Makes sure the app shows up in the Dock with its icon even when launched
/// as a bare SPM executable (`swift run`), where no app bundle exists.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        DebugEventLog.configureFromEnvironment()
        DebugEventLog.installEventMonitor()
        DebugEventLog.installMainThreadWatchdog()
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DotphinApp.applyAppIcon()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: Menú Edición estándar → archivos
    //
    // El delegate de la app es el último eslabón de la responder chain. Si el
    // foco está en un campo de texto, lo atiende el campo y esto ni se entera;
    // si no, Cortar/Copiar/Pegar/Eliminar actúan sobre el panel activo de la
    // ventana, tenga el foco la vista de archivos o el panel lateral.

    private var activeViewModel: BrowserViewModel? {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        return WindowCommands.commands(for: window)?.focusedViewModel()
    }

    @objc func copy(_ sender: Any?) {
        activeViewModel?.copySelected()
    }

    @objc func cut(_ sender: Any?) {
        activeViewModel?.cutSelected()
    }

    @objc func paste(_ sender: Any?) {
        activeViewModel?.paste()
    }

    @objc func delete(_ sender: Any?) {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        WindowCommands.commands(for: window)?.perform(.deleteSelectedFiles)
    }

    @objc func selectAll(_ sender: Any?) {
        activeViewModel?.selectAll()
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let viewModel = activeViewModel else { return false }
        switch menuItem.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)):
            return !viewModel.selectedIDs.isEmpty
        case #selector(paste(_:)):
            return viewModel.canPaste
        default:
            return true
        }
    }
}
