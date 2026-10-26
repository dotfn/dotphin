import SwiftUI

struct FolderTreeRow: View {
    let url: URL
    let onSelect: (URL) -> Void

    @State private var children: [URL]?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let children {
                ForEach(children, id: \.self) { child in
                    FolderTreeRow(url: child, onSelect: onSelect)
                }
            }
        } label: {
            Label(url.lastPathComponent, systemImage: "folder")
                .onTapGesture { onSelect(url) }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded && children == nil {
                children = FolderTreeProvider().subdirectories(of: url)
            }
        }
    }
}
