import Foundation

/// Archivos con una etiqueta de color, como Finder → Etiquetas: se le pregunta
/// a Spotlight (`NSMetadataQuery`) en vez de recorrer el disco. Se busca por
/// número de color (`kMDItemFSLabel`), que no depende del idioma en que se
/// escribió el nombre de la etiqueta.
@MainActor
struct TaggedItemsSearch {
    var limit = 500

    func items(labeled tag: FinderColorTag) async -> [FileItem] {
        guard tag != .none else { return [] }
        let urls = await taggedURLs(labelNumber: tag.rawValue)
        return await Self.makeItems(urls)
    }

    private func taggedURLs(labelNumber: Int) async -> [URL] {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemFSLabel == %d", labelNumber)
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        let limit = limit
        // La consulta y el observador viajan juntos al aviso, que llega en el main actor.
        let box = QueryBox(query: query)
        return await withCheckedContinuation { continuation in
            box.token = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    let query = box.query
                    query.stop()
                    let count = min(query.resultCount, limit)
                    let urls = (0..<count).compactMap { index -> URL? in
                        guard let item = query.result(at: index) as? NSMetadataItem,
                              let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
                        return URL(fileURLWithPath: path)
                    }
                    if let token = box.token {
                        NotificationCenter.default.removeObserver(token)
                    }
                    continuation.resume(returning: urls)
                }
            }
            box.query.start()
        }
    }

    /// Lee los datos de cada archivo fuera del main actor; saltea los ocultos
    /// (empiezan con punto o están dentro de una carpeta oculta).
    @concurrent
    private static func makeItems(_ urls: [URL]) async -> [FileItem] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
            .labelNumberKey, .tagNamesKey, .isPackageKey, .localizedTypeDescriptionKey,
        ]
        return urls.compactMap { url in
            guard !url.pathComponents.contains(where: { $0.hasPrefix(".") }),
                  let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: values.isDirectory ?? false,
                isSymbolicLink: values.isSymbolicLink ?? false,
                size: values.fileSize.map(Int64.init),
                modificationDate: values.contentModificationDate,
                labelNumber: values.labelNumber ?? 0,
                tagNames: values.tagNames ?? [],
                isPackage: values.isPackage ?? false,
                typeDescription: values.localizedTypeDescription
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Solo se usa en el main actor (la consulta arranca ahí y avisa en `.main`).
private final class QueryBox: @unchecked Sendable {
    let query: NSMetadataQuery
    var token: (any NSObjectProtocol)?

    init(query: NSMetadataQuery) {
        self.query = query
    }
}
