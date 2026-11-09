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
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            throw TerminalLauncherError.failed(error.localizedDescription)
        }
        // Leer el pipe antes de waitUntilExit (lección del slice 10: al revés, deadlock).
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TerminalLauncherError.failed(message?.isEmpty == false ? message! : "No se pudo abrir Terminal.")
        }
    }
}
