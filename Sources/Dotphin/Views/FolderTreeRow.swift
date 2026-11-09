import AppKit
import SwiftUI

struct FolderTreeRow: View {
    let url: URL
    var currentURL: URL? = nil
    var showsHiddenFiles: Binding<Bool>? = nil
    var limitToHomeDirectory: Binding<Bool>? = nil
    var depth: Int = 0
    let onSelect: (URL) -> Void
    var onOpenInNewTab: ((URL) -> Void)? = nil
    var onOpenInSplitView: ((URL) -> Void)? = nil

    @State private var children: [URL]?
    @State private var isExpanded = false

    private var isSelected: Bool {
        guard let currentURL else { return false }
        return url.standardizedFileURL.path == currentURL.standardizedFileURL.path
    }

    private var isAncestorOfCurrentURL: Bool {
        guard let currentURL, depth < 5 else { return false }
        let selfPath = url.standardizedFileURL.path
        let targetPath = currentURL.standardizedFileURL.path
        guard targetPath != selfPath else { return false }
        let prefix = selfPath.hasSuffix("/") ? selfPath : selfPath + "/"
        return targetPath.hasPrefix(prefix)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let children {
                ForEach(children, id: \.self) { child in
                    FolderTreeRow(
                        url: child,
                        currentURL: currentURL,
                        showsHiddenFiles: showsHiddenFiles,
                        limitToHomeDirectory: limitToHomeDirectory,
                        depth: depth + 1,
                        onSelect: onSelect,
                        onOpenInNewTab: onOpenInNewTab,
                        onOpenInSplitView: onOpenInSplitView
                    )
                }
            }
        } label: {
            Button {
                onSelect(url)
            } label: {
                HStack(spacing: 6) {
                    Image(nsImage: ThumbnailLoader.icon(forFile: url.path))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                    Text(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Abrir") {
                    onSelect(url)
                }
                if let onOpenInNewTab {
                    Button("Abrir en una pestaña nueva") {
                        onOpenInNewTab(url)
                    }
                }
                if let onOpenInSplitView {
                    Button("Abrir en vista dividida") {
                        onOpenInSplitView(url)
                    }
                }
                Divider()
                let places = PlacesProvider()
                if places.isBookmarked(url) {
                    Button("Quitar de Lugares") {
                        places.removeBookmark(for: url)
                    }
                } else {
                    Button("Añadir a Lugares") {
                        places.addBookmark(for: url)
                    }
                }
                Button("Copiar ubicación") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
                Button("Mostrar en Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                if showsHiddenFiles != nil || limitToHomeDirectory != nil {
                    Divider()
                    if let showsHiddenFiles {
                        Button(showsHiddenFiles.wrappedValue ? "Mostrar archivos ocultos ✓" : "Mostrar archivos ocultos") {
                            showsHiddenFiles.wrappedValue.toggle()
                        }
                    }
                    if let limitToHomeDirectory {
                        Button(limitToHomeDirectory.wrappedValue ? "Limitar a la carpeta personal ✓" : "Limitar a la carpeta personal") {
                            limitToHomeDirectory.wrappedValue.toggle()
                        }
                    }
                }
            }
        }
        .onAppear {
            if isAncestorOfCurrentURL && !isExpanded {
                isExpanded = true
            }
        }
        .onChange(of: currentURL) { _, _ in
            if isAncestorOfCurrentURL && !isExpanded {
                isExpanded = true
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                reloadChildren()
            }
        }
        .onChange(of: showsHiddenFiles?.wrappedValue ?? false) { _, _ in
            if isExpanded {
                reloadChildren()
            }
        }
    }

    private func reloadChildren() {
        let showHidden = showsHiddenFiles?.wrappedValue ?? false
        children = FolderTreeProvider(showsHiddenFiles: showHidden).subdirectories(of: url)
    }
}
