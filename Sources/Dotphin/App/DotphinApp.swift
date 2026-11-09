import AppKit
import SwiftUI

extension Notification.Name {
    static let openToolbarConfiguration = Notification.Name("Dotphin.openToolbarConfiguration")
}

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
            FileEditCommands()
            CommandGroup(after: .appSettings) {
                Button("Configurar barras de herramientas…") {
                    NotificationCenter.default.post(name: .openToolbarConfiguration, object: nil)
                }
                Button("Mostrar todas las pestañas") {
                    NativeTabOverviewController.toggle()
                }
                .keyboardShortcut("\\", modifiers: [.command, .shift])
            }
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

/// Makes sure the app shows up in the Dock with its icon even when launched
/// as a bare SPM executable (`swift run`), where no app bundle exists.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DotphinApp.applyAppIcon()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
