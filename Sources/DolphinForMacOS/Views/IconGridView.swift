import SwiftUI

struct IconGridView: View {
    let items: [FileItem]
    let zoomLevel: Double
    let onOpen: (FileItem) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 80 * zoomLevel))]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    VStack(spacing: 4) {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                            .font(.system(size: 32 * zoomLevel))
                            .foregroundStyle(item.isDirectory ? .blue : .secondary)
                        Text(item.name)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 80 * zoomLevel)
                    .onTapGesture(count: 2) {
                        onOpen(item)
                    }
                }
            }
            .padding()
        }
    }
}
