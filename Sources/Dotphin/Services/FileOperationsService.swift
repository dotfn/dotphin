import Foundation

enum FileOperationError: Error, Equatable, Sendable {
    case nameAlreadyExists(URL)
    case invalidName
    case other(String)

    var message: String {
        switch self {
        case .nameAlreadyExists:
            return "Ya existe un ítem con ese nombre."
        case .invalidName:
            return "El nombre no es válido."
        case .other(let message):
            return message
        }
    }
}

struct FileOperationsService: Sendable {
    private func validate(_ name: String) throws {
        if name.trimmingCharacters(in: .whitespaces).isEmpty || name.contains("/") || name.hasPrefix(".") {
            throw FileOperationError.invalidName
        }
    }

    func rename(_ item: FileItem, to newName: String) throws -> URL {
        try validate(newName)
        let destination = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileOperationError.nameAlreadyExists(destination)
        }
        do {
            try FileManager.default.moveItem(at: item.url, to: destination)
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
        return destination
    }

    @discardableResult
    func moveToTrash(_ item: FileItem) throws -> URL? {
        try trash(item.url)
    }

    @discardableResult
    func trash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
        return resulting as URL?
    }

    /// Permanently deletes `url` bypassing the Trash (`KStandardAction::deleteFile` / `Shift+Delete`).
    func deletePermanently(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
    }

    /// Dolphin/Finder-style non-clobbering name: `a.txt` → `a copy.txt` → `a copy 2.txt`.
    func uniqueDestination(for name: String, in directory: URL) -> URL {
        let fm = FileManager.default
        let first = directory.appendingPathComponent(name)
        guard fm.fileExists(atPath: first.path) else { return first }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var counter = 1
        while true {
            let suffix = counter == 1 ? " copy" : " copy \(counter)"
            let candidateName = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    func copy(_ sourceURL: URL, toDirectory destinationDirectory: URL) throws -> URL {
        let destination = uniqueDestination(for: sourceURL.lastPathComponent, in: destinationDirectory)
        try copy(sourceURL, to: destination)
        return destination
    }

    /// Copia a un destino exacto; falla si ya existe.
    func copy(_ sourceURL: URL, to destination: URL) throws {
        try validateTransfer(of: sourceURL, to: destination, kind: .copy)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileOperationError.nameAlreadyExists(destination)
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
    }

    /// Mueve a un destino exacto (que puede tener otro nombre); falla si ya existe.
    func move(_ sourceURL: URL, to destination: URL) throws {
        try validateTransfer(of: sourceURL, to: destination, kind: .move)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileOperationError.nameAlreadyExists(destination)
        }
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destination)
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
    }

    /// Una carpeta no puede ir a parar dentro de sí misma, ni un ítem
    /// reemplazarse a sí mismo. Los symlinks de las carpetas padre se
    /// resuelven para que un alias (p. ej. /tmp → /private/tmp) no esquive
    /// el chequeo; la hoja no: un symlink que se mueve es el enlace en sí.
    func validateTransfer(of sourceURL: URL, to destination: URL, kind: FileTransferKind) throws {
        let sourcePath = Self.resolvingParentSymlinks(of: sourceURL)
        let destinationPath = Self.resolvingParentSymlinks(of: destination)
        let verb = kind == .copy ? "copiar" : "mover"
        guard destinationPath != sourcePath else {
            throw FileOperationError.other("No se puede \(verb) un ítem sobre sí mismo.")
        }
        guard !destinationPath.hasPrefix(sourcePath + "/") else {
            throw FileOperationError.other("No se puede \(verb) una carpeta dentro de sí misma.")
        }
    }

    /// Undoes `record`. Throws if the filesystem no longer allows it.
    func revert(_ record: FileOperationRecord) throws {
        switch record {
        case .moved(let from, let to):
            try moveExactly(to, to: from)
        case .copied(_, let created), .createdFolder(let created), .createdFile(let created, _):
            try trash(created)
        case .trashed(let original, let trashed):
            try moveExactly(trashed, to: original)
        }
    }

    /// Re-applies `record` after an undo; returns the (possibly updated) record.
    func reapply(_ record: FileOperationRecord) throws -> FileOperationRecord {
        switch record {
        case .moved(let from, let to):
            try moveExactly(from, to: to)
            return record
        case .copied(let source, let created):
            do {
                try FileManager.default.copyItem(at: source, to: created)
            } catch {
                throw FileOperationError.other(error.localizedDescription)
            }
            return record
        case .createdFolder(let url):
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            } catch {
                throw FileOperationError.other(error.localizedDescription)
            }
            return record
        case .createdFile(let url, let contents):
            do {
                try contents.write(to: url, options: .withoutOverwriting)
            } catch {
                throw FileOperationError.other(error.localizedDescription)
            }
            return record
        case .trashed(let original, _):
            let newTrashed = try trash(original) ?? original
            return .trashed(original: original, trashed: newTrashed)
        }
    }

    private func moveExactly(_ source: URL, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileOperationError.nameAlreadyExists(destination)
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
    }

    func createFolder(in directory: URL, named name: String) throws -> URL {
        try validate(name)
        let destination = directory.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileOperationError.nameAlreadyExists(destination)
        }
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
        return destination
    }

    func createFile(in directory: URL, named name: String, contents: Data = Data()) throws -> URL {
        try validate(name)
        let destination = directory.appendingPathComponent(name, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileOperationError.nameAlreadyExists(destination)
        }
        do {
            try contents.write(to: destination, options: .withoutOverwriting)
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
        return destination
    }

    /// Creates a POSIX symbolic link in `directory` pointing to `targetPath` (`DolphinNewFileMenu` / `KNewFileMenu`).
    func createSymbolicLink(in directory: URL, named linkName: String, pointingTo targetPath: String) throws -> URL {
        try validate(linkName)
        let trimmedTarget = targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else {
            throw FileOperationError.invalidName
        }
        let destination = directory.appendingPathComponent(linkName, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileOperationError.nameAlreadyExists(destination)
        }
        do {
            try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: trimmedTarget)
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
        return destination
    }

    /// Creates a non-clobbering symbolic link for `sourceURL` inside `destinationDirectory`.
    func createSymbolicLink(for sourceURL: URL, in destinationDirectory: URL) throws -> URL {
        let baseName = sourceURL.lastPathComponent
        let ext = (baseName as NSString).pathExtension
        let stem = (baseName as NSString).deletingPathExtension
        let defaultLinkName = ext.isEmpty ? "\(stem) enlace" : "\(stem) enlace.\(ext)"
        let destination = uniqueDestination(for: defaultLinkName, in: destinationDirectory)
        do {
            try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: sourceURL)
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
        return destination
    }

    /// Resolves the target URL of a symbolic link (`DolphinMainWindow::showTarget`).
    func resolvedSymbolicLinkTarget(of symlinkURL: URL) -> URL? {
        guard let destPath = try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkURL.path) else {
            return nil
        }
        if destPath.hasPrefix("/") {
            return URL(fileURLWithPath: destPath).standardizedFileURL
        }
        return symlinkURL.deletingLastPathComponent().appendingPathComponent(destPath).standardizedFileURL
    }

    func restore(_ item: FileItem, to destinationDirectory: URL) throws -> URL {
        let destination = destinationDirectory.appendingPathComponent(item.name)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileOperationError.nameAlreadyExists(destination)
        }
        do {
            try FileManager.default.moveItem(at: item.url, to: destination)
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
        return destination
    }

    func move(_ sourceURL: URL, toDirectory destinationDirectory: URL) throws -> URL {
        let destination = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        // Symlinks in the parent folders are resolved so an alias (e.g. /tmp -> /private/tmp, or
        // dropping a folder onto its own symlink) can't slip past these guards, but the leaf is
        // kept as-is: a symlink being moved is the link itself, never its target.
        let sourcePath = Self.resolvingParentSymlinks(of: sourceURL)
        let destinationPath = Self.resolvingParentSymlinks(of: destination)
        guard destinationPath != sourcePath else {
            return sourceURL
        }
        let destinationDirectoryPath = destinationDirectory.resolvingSymlinksInPath().path
        guard destinationDirectoryPath != sourcePath else {
            return sourceURL
        }
        guard !destinationDirectoryPath.hasPrefix(sourcePath + "/") else {
            throw FileOperationError.other("No se puede mover una carpeta dentro de sí misma.")
        }
        guard !FileManager.default.fileExists(atPath: destinationPath) else {
            throw FileOperationError.nameAlreadyExists(destination)
        }
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destination)
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }
        return destination
    }

    private static func resolvingParentSymlinks(of url: URL) -> String {
        url.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent)
            .path
    }

    func emptyTrash(at trashURL: URL) throws {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: trashURL,
                includingPropertiesForKeys: nil
            )
        } catch {
            throw FileOperationError.other(error.localizedDescription)
        }

        var failures: [String] = []
        for url in contents {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                failures.append(url.lastPathComponent)
            }
        }

        if !failures.isEmpty {
            throw FileOperationError.other("No se pudieron eliminar: \(failures.joined(separator: ", "))")
        }
    }
}
