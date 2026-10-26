import SwiftUI

struct DetailsListView: View {
    let items: [FileItem]
    let onOpen: (FileItem) -> Void

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        Table(items) {
            TableColumn("Nombre") { item in
                Label(item.name, systemImage: item.isDirectory ? "folder.fill" : "doc.fill")
                    .onTapGesture(count: 2) { onOpen(item) }
            }
            TableColumn("Tamaño") { item in
                Text(item.isDirectory ? "" : Self.sizeFormatter.string(fromByteCount: item.size ?? 0))
            }
            TableColumn("Modificado") { item in
                Text(item.modificationDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
            }
        }
    }
}
