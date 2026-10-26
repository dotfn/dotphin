import SwiftUI

struct FileListView: View {
    let items: [FileItem]
    let selectedItem: FileItem?
    let onSelect: (FileItem) -> Void
    let onOpen: (FileItem) -> Void

    var body: some View {
        List(items) { item in
            Label(item.name, systemImage: item.isDirectory ? "folder" : "doc")
                .listRowBackground(
                    item.id == selectedItem?.id ? Color.accentColor.opacity(0.15) : Color.clear
                )
                .gesture(
                    TapGesture(count: 2)
                        .onEnded { onOpen(item) }
                        .exclusively(before: TapGesture(count: 1).onEnded { onSelect(item) })
                )
        }
    }
}
