import SwiftUI

struct FileListView: View {
    let items: [FileItem]
    let onOpen: (FileItem) -> Void

    var body: some View {
        List(items) { item in
            Label(item.name, systemImage: item.isDirectory ? "folder" : "doc")
                .onTapGesture(count: 2) {
                    onOpen(item)
                }
        }
    }
}
