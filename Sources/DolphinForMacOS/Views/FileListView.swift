import SwiftUI

struct FileListView: View {
    let items: [FileItem]
    @Binding var selectedID: FileItem.ID?
    let onOpen: (FileItem) -> Void
    let onDelete: (FileItem) -> Void

    var body: some View {
        List(items, selection: $selectedID) { item in
            Label(item.name, systemImage: item.isDirectory ? "folder" : "doc")
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
