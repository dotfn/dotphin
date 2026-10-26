import Foundation

enum DirectoryReadError: Error, Equatable {
    case permissionDenied(URL)
    case notFound(URL)
    case other(String)
}

struct DirectoryReader {
    var showsHiddenFiles: Bool = false

    func contents(of url: URL) throws -> [FileItem] {
        try contents(of: url, sortField: .name, ascending: true)
    }

    func contents(of url: URL, sortField: SortField, ascending: Bool) throws -> [FileItem] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: []
            )
        } catch let error as NSError {
            switch error.code {
            case NSFileReadNoPermissionError:
                throw DirectoryReadError.permissionDenied(url)
            case NSFileReadNoSuchFileError:
                throw DirectoryReadError.notFound(url)
            default:
                throw DirectoryReadError.other(error.localizedDescription)
            }
        }

        let items = try urls
            .filter { showsHiddenFiles || !$0.lastPathComponent.hasPrefix(".") }
            .map { itemURL -> FileItem in
                let values = try itemURL.resourceValues(forKeys: keys)
                let isSymbolicLink = values.isSymbolicLink ?? false
                var isDirectory = values.isDirectory ?? false
                if isSymbolicLink {
                    // A symlink's own resourceValues report isDirectory against the
                    // link, not its target — resolve it so a link to a folder can be
                    // opened like one. A dangling link falls back to false.
                    let resolved = itemURL.resolvingSymlinksInPath()
                    isDirectory = (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                }
                return FileItem(
                    url: itemURL,
                    name: itemURL.lastPathComponent,
                    isDirectory: isDirectory,
                    isSymbolicLink: isSymbolicLink,
                    size: values.fileSize.map(Int64.init),
                    modificationDate: values.contentModificationDate
                )
            }

        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            let result: Bool
            switch sortField {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .size:
                result = (lhs.size ?? 0) < (rhs.size ?? 0)
            case .modificationDate:
                result = (lhs.modificationDate ?? .distantPast) < (rhs.modificationDate ?? .distantPast)
            }
            return ascending ? result : !result
        }
    }
}
