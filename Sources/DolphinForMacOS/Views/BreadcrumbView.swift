import SwiftUI

struct BreadcrumbView: View {
    let url: URL
    let onNavigate: (URL) -> Void

    private var ancestors: [URL] {
        var result: [URL] = [url]
        var current = url
        while current.pathComponents.count > 1 {
            current = current.deletingLastPathComponent()
            result.append(current)
        }
        return result.reversed()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ancestors, id: \.self) { ancestor in
                    Button(ancestor.lastPathComponent.isEmpty ? "/" : ancestor.lastPathComponent) {
                        onNavigate(ancestor)
                    }
                    .buttonStyle(.plain)
                    if ancestor != ancestors.last {
                        Text("›")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
