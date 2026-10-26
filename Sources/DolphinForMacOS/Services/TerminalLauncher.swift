import Foundation

enum TerminalLauncherError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

struct TerminalLauncher {
    func launchArguments(for url: URL) -> [String] {
        ["-a", "Terminal", url.path]
    }

    func openTerminal(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = launchArguments(for: url)
        do {
            try process.run()
        } catch {
            throw TerminalLauncherError.failed(error.localizedDescription)
        }
    }
}
