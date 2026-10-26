import SwiftUI

struct IconGridView: View {
    let items: [FileItem]
    let zoomLevel: Double
    let selectedItem: FileItem?
    let currentURL: URL
    let onSelect: (FileItem) -> Void
    let onOpen: (FileItem) -> Void
    let onDelete: (FileItem) -> Void
    let onMoveDropped: ([URL], URL) -> Void
    let gitStatuses: [String: GitFileStatus]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 80 * zoomLevel))]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                                .font(.system(size: 32 * zoomLevel))
                                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                            GitStatusBadge(status: gitStatuses[item.name])
                        }
                        Text(item.name)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 80 * zoomLevel)
                    .padding(4)
                    .background(
                        item.id == selectedItem?.id ? Color.accentColor.opacity(0.15) : Color.clear
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded { onOpen(item) }
                            .exclusively(before: TapGesture(count: 1).onEnded { onSelect(item) })
                    )
                    .contextMenu {
                        Button("Eliminar", role: .destructive) { onDelete(item) }
                    }
                    .draggable(item.url)
                    .dropDestination(for: URL.self) { urls, _ in
                        onMoveDropped(urls, item.isDirectory ? item.url : currentURL)
                        return true
                    }
                }
            }
            .padding()
        }
        .dropDestination(for: URL.self) { urls, _ in
            onMoveDropped(urls, currentURL)
            return true
        }
    }
}
