import AppKit
import SwiftUI

private struct ExpandableDetailRow: Identifiable {
    let item: FileItem
    let depth: Int
    let groupTitle: String?
    var id: URL { item.id }
}

struct DetailsListView: View {
    let items: [FileItem]
    var groups: [FileItemGroup] = []
    var showInGroups: Bool = false
    var visibleColumns: [DetailsColumn] = [.type, .size, .modificationDate]
    var zoomLevel: Double = 1.0
    @Binding var selection: Set<FileItem.ID>
    let gitStatuses: [String: GitFileStatus]
    let currentURL: URL
    var sortField: SortField = .name
    var ascending: Bool = true
    var onChangeSort: ((SortField, Bool) -> Void)? = nil
    let onOpen: (FileItem) -> Void
    var onRename: ((FileItem) -> Void)? = nil
    var onBatchRename: (() -> Void)? = nil
    let onDelete: (FileItem) -> Void
    let onDeleteSelection: () -> Void
    let onMoveDropped: ([URL], URL) -> Void
    var contextMenuActions: BrowserContextMenuActions? = nil

    @State private var expandedDirectories: Set<URL> = []
    @State private var directoryChildren: [URL: [FileItem]] = [:]

    private var iconDimension: CGFloat {
        max(15, 18 * min(1.35, zoomLevel))
    }

    private var flattenedRows: [ExpandableDetailRow] {
        var result: [ExpandableDetailRow] = []
        func appendItems(_ list: [FileItem], depth: Int, groupTitle: String?) {
            for (idx, item) in list.enumerated() {
                result.append(ExpandableDetailRow(item: item, depth: depth, groupTitle: idx == 0 ? groupTitle : nil))
                if item.isDirectory, expandedDirectories.contains(item.url),
                   let children = directoryChildren[item.url] {
                    appendItems(children, depth: depth + 1, groupTitle: nil)
                }
            }
        }
        if showInGroups && !groups.isEmpty {
            for group in groups {
                appendItems(group.items, depth: 0, groupTitle: group.title)
            }
        } else {
            appendItems(items, depth: 0, groupTitle: nil)
        }
        return result
    }

    private var allVisibleItems: [FileItem] {
        flattenedRows.map(\.item)
    }

    var body: some View {
        let contentSettings = AppSettingsStore().settings()
        Table(of: ExpandableDetailRow.self, selection: $selection) {
            TableColumn("Nombre") { row in
                let item = row.item
                HStack(spacing: 6) {
                    if let groupTitle = row.groupTitle, showInGroups {
                        Text(groupTitle)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    if row.depth > 0 {
                        Spacer()
                            .frame(width: CGFloat(row.depth) * 16)
                    }
                    if item.isDirectory && contentSettings.expandableFoldersInDetails {
                        Button {
                            toggleExpansion(for: item.url)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(expandedDirectories.contains(item.url) ? 90 : 0))
                                .animation(.snappy(duration: 0.18), value: expandedDirectories.contains(item.url))
                                .frame(width: 14, height: 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else if contentSettings.expandableFoldersInDetails {
                        Spacer()
                            .frame(width: 14)
                    }

                    Image(nsImage: ThumbnailLoader.icon(forFile: item.url.path))
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconDimension, height: iconDimension)
                    Text(item.name)
                        .lineLimit(1)
                    if let nsColor = item.colorTag.nsColor {
                        Circle()
                            .fill(Color(nsColor: nsColor))
                            .frame(width: 8, height: 8)
                            .help("Etiqueta: \(item.colorTag.title)")
                    }
                    GitStatusBadge(status: gitStatuses[item.name])
                }
                .opacity(item.isHiddenItem ? 0.62 : 1.0)
                .contentShape(Rectangle())
                .help(FileMetadataFormatter().hoverTooltip(for: item))
            }

            if visibleColumns.contains(.type) {
                TableColumn("Tipo") { row in
                    Text(FileMetadataFormatter().metadata(for: row.item).kind)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 64, ideal: 95, max: 140)
            }

            if visibleColumns.contains(.extensionType) {
                TableColumn("Extensión") { row in
                    let ext = row.item.fileExtension
                    Text(ext.isEmpty ? "—" : ext)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 58, ideal: 78, max: 110)
            }

            if visibleColumns.contains(.size) {
                TableColumn("Tamaño") { row in
                    Text(
                        FileMetadataFormatter().sizeDisplayText(
                            for: row.item,
                            directorySizeMode: contentSettings.directorySizeMode
                        )
                    )
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                .width(min: 62, ideal: 86, max: 125)
            }

            if visibleColumns.contains(.modificationDate) {
                TableColumn("Modificado") { row in
                    Text(
                        FileMetadataFormatter().formatDate(
                            row.item.modificationDate,
                            useRelativeDates: contentSettings.useRelativeDates
                        )
                    )
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                .width(min: 100, ideal: 145, max: 210)
            }

            if visibleColumns.contains(.creationDate) {
                TableColumn("Creado") { row in
                    Text(
                        FileMetadataFormatter().formatDate(
                            row.item.creationDate,
                            useRelativeDates: contentSettings.useRelativeDates
                        )
                    )
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                .width(min: 100, ideal: 145, max: 210)
            }

            if visibleColumns.contains(.permissions) {
                TableColumn("Permisos") { row in
                    Text(
                        FileMetadataFormatter().permissionsDisplayText(
                            for: row.item,
                            format: contentSettings.permissionsFormat
                        )
                    )
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                .width(min: 74, ideal: 108, max: 145)
            }

            if visibleColumns.contains(.tags) {
                TableColumn("Etiquetas") { row in
                    let tag = row.item.colorTag
                    if tag != .none, let nsColor = tag.nsColor {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(nsColor: nsColor))
                                .frame(width: 7, height: 7)
                            Text(tag.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(min: 68, ideal: 95, max: 135)
            }
        } rows: {
            ForEach(flattenedRows) { row in
                TableRow(row)
                    .draggable(row.item.url)
                    .dropDestination(for: URL.self) { urls in
                        onMoveDropped(urls, row.item.isDirectory ? row.item.url : currentURL)
                    }
            }
        }
        .alternatingRowBackgrounds(.enabled)
        .onChange(of: currentURL) { _, _ in
            expandedDirectories.removeAll()
            directoryChildren.removeAll()
        }
        .dropDestination(for: URL.self) { urls, _ in
            onMoveDropped(urls, currentURL)
            return true
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            let visible = allVisibleItems
            let targetItems = visible.filter { ids.contains($0.id) }
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
            } else if let id = ids.first, let item = visible.first(where: { $0.id == id }) {
                if let onRename {
                    Button("Renombrar…") { onRename(item) }
                }
                Button("Eliminar", role: .destructive) { onDelete(item) }
            }
        } primaryAction: { ids in
            let visible = allVisibleItems
            if let id = ids.first, let item = visible.first(where: { $0.id == id }) {
                onOpen(item)
            }
        }
    }

    private func toggleExpansion(for directoryURL: URL) {
        withAnimation(.snappy(duration: 0.2)) {
            if expandedDirectories.contains(directoryURL) {
                expandedDirectories.remove(directoryURL)
            } else {
                let showsHidden = AppSettingsStore().settings().showsHiddenFiles
                let reader = DirectoryReader(showsHiddenFiles: showsHidden)
                if let children = try? reader.contents(of: directoryURL, sortField: sortField, ascending: ascending) {
                    directoryChildren[directoryURL] = children
                } else {
                    directoryChildren[directoryURL] = []
                }
                expandedDirectories.insert(directoryURL)
            }
        }
    }
}
