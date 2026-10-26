import Foundation

struct FileMetadata {
    let kind: String
    let sizeText: String
    let modifiedText: String
}

struct FileMetadataFormatter {
    func metadata(for item: FileItem) -> FileMetadata {
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.countStyle = .file
        let kind: String
        if item.isDirectory {
            kind = "Carpeta"
        } else {
            let ext = item.url.pathExtension
            kind = ext.isEmpty ? "Documento" : ext.uppercased()
        }

        let sizeText = item.isDirectory ? "—" : sizeFormatter.string(fromByteCount: item.size ?? 0)

        let modifiedText = item.modificationDate.map {
            $0.formatted(date: .abbreviated, time: .shortened)
        } ?? "—"

        return FileMetadata(kind: kind, sizeText: sizeText, modifiedText: modifiedText)
    }
}
