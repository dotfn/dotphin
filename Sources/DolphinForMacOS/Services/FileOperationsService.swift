import Foundation

enum FileOperationError: Error, Equatable {
    case nameAlreadyExists(URL)
    case invalidName
    case other(String)
}

struct FileOperationsService {
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

    func moveToTrash(_ item: FileItem) throws {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
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
