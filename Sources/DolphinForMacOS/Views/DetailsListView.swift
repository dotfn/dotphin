import SwiftUI

struct DetailsListView: View {
    let items: [FileItem]
    let selectedItem: FileItem?
    let onSelect: (FileItem) -> Void
    let onOpen: (FileItem) -> Void

    var body: some View {
        Table(items) {
            TableColumn("Nombre") { item in
                Label(item.name, systemImage: item.isDirectory ? "folder.fill" : "doc.fill")
                    .padding(.vertical, 2)
                    .background(
                        item.id == selectedItem?.id ? Color.accentColor.opacity(0.15) : Color.clear
                    )
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded { onOpen(item) }
                            .exclusively(before: TapGesture(count: 1).onEnded { onSelect(item) })
                    )
            }
            TableColumn("Tamaño") { item in
                Text(FileMetadataFormatter().metadata(for: item).sizeText)
            }
            TableColumn("Modificado") { item in
                Text(FileMetadataFormatter().metadata(for: item).modifiedText)
            }
        }
    }
}
