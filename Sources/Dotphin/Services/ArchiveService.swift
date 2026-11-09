import Foundation

/// Represents a single entry inside an archive (`.zip`, `.tar`, `.tar.gz`, etc.).
struct ArchiveEntryItem: Identifiable, Equatable, Sendable {
    let path: String
    let isDirectory: Bool

    var id: String { path }

    var displayName: String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let name = (trimmed as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    var depth: Int {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return max(0, trimmed.split(separator: "/").count - 1)
    }
}

/// Compresses and extracts archives using native macOS system tools (`/usr/bin/ditto` and `/usr/bin/tar`),
/// mirroring KDE Dolphin's Ark context-menu actions ("Comprimir en ZIP", "Extraer archivo aquí")
/// and `browseThroughArchives` (`DolphinView::openItemAsFolderUrl`).
struct ArchiveService {
    private static let supportedExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz"
    ]

    static func isArchive(_ url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tar.xz") {
            return true
        }
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func archiveBaseName(for url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        for compound in [".tar.gz", ".tar.bz2", ".tar.xz"] where lower.hasSuffix(compound) {
            return String(name.dropLast(compound.count))
        }
        let base = (name as NSString).deletingPathExtension
        return base.isEmpty ? "Extraído" : base
    }

    /// Compresses `urls` into a `.zip` file inside `directory`.
    func compress(_ urls: [URL], in directory: URL, archiveName: String? = nil) throws -> URL {
        guard !urls.isEmpty else {
            throw FileOperationError.invalidName
        }

        let defaultBase: String
        if let archiveName, !archiveName.trimmingCharacters(in: .whitespaces).isEmpty {
            defaultBase = (archiveName as NSString).deletingPathExtension
        } else if urls.count == 1 {
            let single = urls[0]
            defaultBase = single.isFileURL
                ? (single.lastPathComponent as NSString).deletingPathExtension
                : "Archivo"
        } else {
            defaultBase = "Archivo comprimido"
        }

        let cleanBase = defaultBase.isEmpty ? "Archivo" : defaultBase
        let destination = FileOperationsService().uniqueDestination(
            for: "\(cleanBase).zip",
            in: directory
        )

        if urls.count == 1 {
            try runProcess(
                executable: "/usr/bin/ditto",
                arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, destination.path]
            )
        } else {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("dolphin-zip-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }

            for url in urls {
                let target = staging.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: target)
            }
            try runProcess(
                executable: "/usr/bin/ditto",
                arguments: ["-c", "-k", "--sequesterRsrc", staging.path, destination.path]
            )
        }

        return destination
    }

    /// Extracts `archiveURL` into a new subfolder inside `directory`.
    func extract(_ archiveURL: URL, in directory: URL) throws -> URL {
        let baseName = Self.archiveBaseName(for: archiveURL)
        let destination = FileOperationsService().uniqueDestination(for: baseName, in: directory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let ext = archiveURL.pathExtension.lowercased()
        do {
            if ext == "zip" {
                try runProcess(
                    executable: "/usr/bin/ditto",
                    arguments: ["-x", "-k", archiveURL.path, destination.path]
                )
            } else {
                try runProcess(
                    executable: "/usr/bin/tar",
                    arguments: ["-xf", archiveURL.path, "-C", destination.path]
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        return destination
    }

    /// Lists entries inside `archiveURL` without modifying disk, supporting `.zip` (`zipinfo -1` / `tar -tf`) and `.tar*` (`tar -tf`).
    func listEntries(of archiveURL: URL) -> [ArchiveEntryItem] {
        let ext = archiveURL.pathExtension.lowercased()
        let output: String
        if ext == "zip" {
            output = runCaptureOutput(executable: "/usr/bin/zipinfo", arguments: ["-1", archiveURL.path])
                ?? runCaptureOutput(executable: "/usr/bin/tar", arguments: ["-tf", archiveURL.path])
                ?? ""
        } else {
            output = runCaptureOutput(executable: "/usr/bin/tar", arguments: ["-tf", archiveURL.path]) ?? ""
        }
        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("__MACOSX/") }
            .map { line in
                ArchiveEntryItem(path: line, isDirectory: line.hasSuffix("/"))
            }
    }

    private func runCaptureOutput(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw FileOperationError.other(
                (message?.isEmpty == false) ? message! : "Error al procesar el archivo comprimido."
            )
        }
    }
}
