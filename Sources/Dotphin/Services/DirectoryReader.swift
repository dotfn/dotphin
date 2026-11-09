import Foundation

enum DirectoryReadError: Error, Equatable {
    case permissionDenied(URL)
    case notFound(URL)
    case other(String)
}

struct DirectoryReader {
    var showsHiddenFiles: Bool = false
    var sortingChoice: SortingChoice = .natural

    func contents(of url: URL) throws -> [FileItem] {
        try contents(of: url, sortField: .name, ascending: true, foldersFirst: true, hiddenLast: false)
    }

    func contents(
        of url: URL,
        sortField: SortField,
        ascending: Bool,
        foldersFirst: Bool = true,
        hiddenLast: Bool = false
    ) throws -> [FileItem] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .labelNumberKey,
            .tagNamesKey
        ]
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

        let dotHiddenNames = DotHiddenService().hiddenEntries(in: url)

        let items = try urls
            .filter { itemURL in
                let name = itemURL.lastPathComponent
                let isHidden = name.hasPrefix(".") || dotHiddenNames.contains(name)
                return showsHiddenFiles || !isHidden
            }
            .map { itemURL -> FileItem in
                let values = try itemURL.resourceValues(forKeys: keys)
                let isSymbolicLink = values.isSymbolicLink ?? false
                var isDirectory = values.isDirectory ?? false
                if isSymbolicLink {
                    let resolved = itemURL.resolvingSymlinksInPath()
                    isDirectory = (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                }
                let name = itemURL.lastPathComponent
                return FileItem(
                    url: itemURL,
                    name: name,
                    isDirectory: isDirectory,
                    isSymbolicLink: isSymbolicLink,
                    size: values.fileSize.map(Int64.init),
                    modificationDate: values.contentModificationDate,
                    creationDate: values.creationDate,
                    labelNumber: values.labelNumber ?? 0,
                    tagNames: values.tagNames ?? [],
                    isHiddenInDotHidden: dotHiddenNames.contains(name)
                )
            }

        return items.sorted(
            by: sortField,
            ascending: ascending,
            foldersFirst: foldersFirst,
            hiddenLast: hiddenLast,
            sortingChoice: sortingChoice
        )
    }
}
