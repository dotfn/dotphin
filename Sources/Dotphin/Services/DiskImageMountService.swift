import Foundation

enum DiskImageMountError: LocalizedError, Equatable {
    case notADiskImage
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notADiskImage: return "No es una imagen de disco."
        case .failed(let message): return message
        }
    }
}

/// Mounts `.iso`/`.dmg`/`.cdr`/`.img` disk images via `hdiutil attach`, mirroring Dolphin's
/// explicit "Mount" context-menu action for disk images (`mountisoaction.cpp`).
struct DiskImageMountService {
    static let supportedExtensions: Set<String> = ["iso", "dmg", "cdr", "img"]

    static func isDiskImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    func mount(_ url: URL) throws {
        guard Self.isDiskImage(url) else {
            throw DiskImageMountError.notADiskImage
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", url.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            throw DiskImageMountError.failed(error.localizedDescription)
        }
        // Leer el pipe antes de waitUntilExit (lección del slice 10: al revés, deadlock).
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DiskImageMountError.failed(
                message?.isEmpty == false ? message! : "hdiutil terminó con código \(process.terminationStatus)."
            )
        }
    }
}
