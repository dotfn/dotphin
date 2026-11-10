import AppKit

enum TerminalLauncherError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

struct TerminalLauncher {
    static let terminalBundleIdentifier = "com.apple.Terminal"

    /// Abre Terminal en `url` con `NSWorkspace` (antes lanzaba `/usr/bin/open`).
    func openTerminal(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TerminalLauncherError.failed(String(localized: "No existe «\(url.path)».", bundle: #bundle))
        }
        guard let terminalURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.terminalBundleIdentifier
        ) else {
            throw TerminalLauncherError.failed(String(localized: "No se encontró la app Terminal.", bundle: #bundle))
        }
        NSWorkspace.shared.open([url], withApplicationAt: terminalURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
