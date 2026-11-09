import AppKit
import SwiftUI

struct FileListView: View {
    let items: [FileItem]
    var groups: [FileItemGroup] = []
    var showInGroups: Bool = false
    var zoomLevel: Double = 1.0
    @Binding var selection: Set<FileItem.ID>
    let gitStatuses: [String: GitFileStatus]
    /// `nil` cuando esta lista muestra resultados de búsqueda de varias
    /// carpetas a la vez — ahí soltar sobre el fondo no tiene un destino
    /// sin ambigüedad, así que ese drop se deshabilita. Soltar sobre una
    /// fila de carpeta puntual sigue funcionando siempre.
    let currentURL: URL?
    let onOpen: (FileItem) -> Void
    var onRename: ((FileItem) -> Void)? = nil
    var onBatchRename: (() -> Void)? = nil
    let onDelete: (FileItem) -> Void
    let onDeleteSelection: () -> Void
    let onMoveDropped: ([URL], URL) -> Void
    var contextMenuActions: BrowserContextMenuActions? = nil

    private var iconDimension: CGFloat {
        max(16, 18 * zoomLevel)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            List(selection: $selection) {
                if showInGroups && !groups.isEmpty {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.items) { item in
                                rowView(for: item)
                                    .id(item.id)
                            }
                        } header: {
                            Text("\(group.title) (\(group.items.count))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(items) { item in
                        rowView(for: item)
                            .id(item.id)
                    }
                }
            }
            .onChange(of: selection) { _, newIDs in
                if newIDs.count == 1, let singleID = newIDs.first {
                    scrollProxy.scrollTo(singleID)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .dropDestination(for: URL.self) { urls, _ in
            guard let currentURL else { return false }
            onMoveDropped(urls, currentURL)
            return true
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            let targetItems = items.filter { ids.contains($0.id) }
            if let actions = contextMenuActions {
                if targetItems.isEmpty {
                    DotphinViewportContextMenu(actions: actions)
                } else {
                    DotphinItemContextMenu(targetItems: targetItems, actions: actions)
                }
            } else if ids.count > 1 {
                if let onBatchRename {
                    Button("Renombrar \(ids.count) ítems…") { onBatchRename() }
                }
                Button("Eliminar \(ids.count) ítems", role: .destructive) { onDeleteSelection() }
            } else if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                if let onRename {
                    Button("Renombrar…") { onRename(item) }
                }
                Button("Eliminar", role: .destructive) { onDelete(item) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                onOpen(item)
            }
        }
    }

    @ViewBuilder
    private func rowView(for item: FileItem) -> some View {
        let contentSettings = AppSettingsStore().settings()
        let formatter = FileMetadataFormatter()
        HStack(spacing: 8) {
            Image(nsImage: ThumbnailLoader.icon(forFile: item.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: iconDimension, height: iconDimension)
            Text(item.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            if let nsColor = item.colorTag.nsColor {
                Circle()
                    .fill(Color(nsColor: nsColor))
                    .frame(width: 8, height: 8)
                    .help("Etiqueta: \(item.colorTag.title)")
            }
            GitStatusBadge(status: gitStatuses[item.name])
            Spacer(minLength: 8)
            Text(formatter.sizeDisplayText(for: item, directorySizeMode: contentSettings.directorySizeMode))
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 58, alignment: .trailing)
        }
        .padding(.vertical, 1.5)
        .opacity(item.isHiddenItem ? 0.58 : 1.0)
        .contentShape(Rectangle())
        .help(formatter.hoverTooltip(for: item))
        .draggable(item.url)
        .dropDestination(for: URL.self) { urls, _ in
            let destination = item.isDirectory ? item.url : currentURL
            guard let destination else { return false }
            onMoveDropped(urls, destination)
            return true
        }
    }
}
