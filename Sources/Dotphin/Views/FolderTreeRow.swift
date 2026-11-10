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
                Button(String(localized: "Abrir", bundle: #bundle)) {
                    onSelect(url)
                }
                if let onOpenInNewTab {
                    Button(String(localized: "Abrir en una pestaña nueva", bundle: #bundle)) {
                        onOpenInNewTab(url)
                    }
                }
                if let onOpenInSplitView {
                    Button(String(localized: "Abrir en vista dividida", bundle: #bundle)) {
                        onOpenInSplitView(url)
                    }
                }
                Divider()
                let places = PlacesProvider()
                if places.isBookmarked(url) {
                    Button(String(localized: "Quitar de Lugares", bundle: #bundle)) {
                        places.removeBookmark(for: url)
                    }
                } else {
                    Button(String(localized: "Añadir a Lugares", bundle: #bundle)) {
                        places.addBookmark(for: url)
                    }
                }
                Button(String(localized: "Copiar ubicación", bundle: #bundle)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
                Button(String(localized: "Mostrar en Finder", bundle: #bundle)) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                if showsHiddenFiles != nil || limitToHomeDirectory != nil {
                    Divider()
                    if let showsHiddenFiles {
                        Button(showsHiddenFiles.wrappedValue ? "Mostrar archivos ocultos ✓" : String(localized: "Mostrar archivos ocultos", bundle: #bundle)) {
                            showsHiddenFiles.wrappedValue.toggle()
                        }
                    }
                    if let limitToHomeDirectory {
                        Button(limitToHomeDirectory.wrappedValue ? "Limitar a la carpeta personal ✓" : String(localized: "Limitar a la carpeta personal", bundle: #bundle)) {
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
