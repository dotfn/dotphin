import SwiftUI

struct DetailsListView: View {
    let items: [FileItem]
    @Binding var selectedID: FileItem.ID?
    let gitStatuses: [String: GitFileStatus]
    let currentURL: URL
    let onOpen: (FileItem) -> Void
    let onDelete: (FileItem) -> Void
    let onMoveDropped: ([URL], URL) -> Void

    var body: some View {
        Table(items, selection: $selectedID) {
            TableColumn("Nombre") { item in
                HStack {
                    Label(item.name, systemImage: item.isDirectory ? "folder.fill" : "doc.fill")
                    GitStatusBadge(status: gitStatuses[item.name])
                }
                .contentShape(Rectangle())
                .draggable(item.url)
                .dropDestination(for: URL.self) { urls, _ in
                    onMoveDropped(urls, item.isDirectory ? item.url : currentURL)
                    return true
                }
            }
            TableColumn("Tamaño") { item in
                Text(FileMetadataFormatter().metadata(for: item).sizeText)
            }
            TableColumn("Modificado") { item in
                Text(FileMetadataFormatter().metadata(for: item).modifiedText)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            onMoveDropped(urls, currentURL)
            return true
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                Button("Eliminar", role: .destructive) { onDelete(item) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                onOpen(item)
            }
        }
    }
}
