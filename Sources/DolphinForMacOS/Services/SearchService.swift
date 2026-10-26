import Foundation

struct SearchService {
    // ponytail: recorrido recursivo simple, no indexado. Si hace falta
    // escalar a carpetas con muchísimos archivos, migrar a NSMetadataQuery
    // (Spotlight), que indexa en background en vez de recorrer en el momento.
    func search(for query: String, in directory: URL, maxResults: Int = 200) -> [FileItem] {
        guard !query.isEmpty else { return [] }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [FileItem] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.localizedCaseInsensitiveContains(query) else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            results.append(FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: values.isDirectory ?? false,
                isSymbolicLink: values.isSymbolicLink ?? false,
                size: values.fileSize.map(Int64.init),
                modificationDate: values.contentModificationDate
            ))
            if results.count >= maxResults { break }
        }
        return results
    }
}
