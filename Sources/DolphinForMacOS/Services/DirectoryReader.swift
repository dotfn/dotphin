import Foundation

enum DirectoryReadError: Error, Equatable {
    case permissionDenied(URL)
    case notFound(URL)
    case other(String)
}

struct DirectoryReader {
    var showsHiddenFiles: Bool = false

    func contents(of url: URL) throws -> [FileItem] {
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
                return FileItem(
                    url: itemURL,
                    name: itemURL.lastPathComponent,
                    isDirectory: values.isDirectory ?? false,
                    isSymbolicLink: values.isSymbolicLink ?? false,
                    size: values.fileSize.map(Int64.init),
                    modificationDate: values.contentModificationDate
                )
            }

        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
