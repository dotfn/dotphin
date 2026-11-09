import AppKit
import SwiftUI

/// KDE Dolphin's "Compact" view mode (`DolphinView::CompactView`):
/// arranges items in compact horizontal cells (icon + filename side-by-side) across adaptive columns,
/// scaling with `zoomLevel` and supporting grouped headers (`showInGroups`).
struct CompactGridView: View {
    let items: [FileItem]
    var groups: [FileItemGroup] = []
    var showInGroups: Bool = false
    let zoomLevel: Double
    let selectedIDs: Set<FileItem.ID>
    let currentURL: URL
    var isSelectionModeActive: Bool = false
    let onSelect: (FileItem, SelectionModifier) -> Void
    let onClearSelection: () -> Void
    let onOpen: (FileItem) -> Void
    var onRename: ((FileItem) -> Void)? = nil
    var onBatchRename: (() -> Void)? = nil
    let onDelete: (FileItem) -> Void
    let onDeleteSelection: () -> Void
    let onMoveDropped: ([URL], URL) -> Void
    let gitStatuses: [String: GitFileStatus]
    var contextMenuActions: BrowserContextMenuActions? = nil
    var onColumnCountChange: ((Int) -> Void)? = nil

    @State private var containerWidth: CGFloat = 680

    private var cellMinWidth: CGFloat {
        max(150, round(195 * zoomLevel))
    }

    static func columnCount(forContainerWidth width: CGFloat, zoomLevel: Double) -> Int {
        let cellMinW = max(150, round(195 * zoomLevel))
        let spacing: CGFloat = 10
        let innerWidth = max(cellMinW, width - 28)
        return max(1, Int(floor((innerWidth + spacing) / (cellMinW + spacing))))
    }

    private var activeColumnCount: Int {
        Self.columnCount(forContainerWidth: containerWidth, zoomLevel: zoomLevel)
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: cellMinWidth), spacing: 10, alignment: .leading),
            count: activeColumnCount
        )
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                if showInGroups && !groups.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups) { group in
                            Section {
                                gridBody(for: group.items)
                            } header: {
                                DotphinGroupSectionHeader(title: group.title, count: group.items.count)
                            }
                        }
                    }
                    .padding(14)
                    .transition(.opacity)
                } else {
                    gridBody(for: items)
                        .padding(14)
                        .transition(.opacity)
                }
            }
            .onChange(of: selectedIDs) { _, newIDs in
                if newIDs.count == 1, let singleID = newIDs.first {
                    withAnimation(.snappy(duration: 0.16)) {
                        scrollProxy.scrollTo(singleID)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            guard newWidth > 60 else { return }
            containerWidth = newWidth
            onColumnCountChange?(Self.columnCount(forContainerWidth: newWidth, zoomLevel: zoomLevel))
        }
        .onChange(of: zoomLevel) { _, newZoom in
            onColumnCountChange?(Self.columnCount(forContainerWidth: containerWidth, zoomLevel: newZoom))
        }
        .animation(.snappy(duration: 0.2), value: zoomLevel)
        .animation(.snappy(duration: 0.22), value: showInGroups)
        .animation(.snappy(duration: 0.18), value: isSelectionModeActive)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isSelectionModeActive {
                        onClearSelection()
                    }
                }
        )
        .contextMenu {
            if let actions = contextMenuActions {
                DotphinViewportContextMenu(actions: actions)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            onMoveDropped(urls, currentURL)
            return true
        }
    }

    private func gridBody(for sectionItems: [FileItem]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(sectionItems) { item in
                CompactGridCell(
                    item: item,
                    zoomLevel: zoomLevel,
                    isSelected: selectedIDs.contains(item.id),
                    isSelectionModeActive: isSelectionModeActive,
                    gitStatus: gitStatuses[item.name]
                )
                .id(item.id)
                .gesture(
                    TapGesture(count: 2)
                        .onEnded { onOpen(item) }
                        .exclusively(
                            before: TapGesture(count: 1).onEnded {
                                if NSApp?.keyWindow?.firstResponder is NSText {
                                    NSApp?.keyWindow?.makeFirstResponder(nil)
                                }
                                if isSelectionModeActive {
                                    onSelect(item, .toggle)
                                } else {
                                    onSelect(item, SelectionModifier.current)
                                }
                            }
                        )
                )
                .contextMenu {
                    if let actions = contextMenuActions {
                        let targetItems = (selectedIDs.count > 1 && selectedIDs.contains(item.id))
                            ? items.filter { selectedIDs.contains($0.id) }
                            : [item]
                        DotphinItemContextMenu(targetItems: targetItems, actions: actions)
                    } else if selectedIDs.count > 1 && selectedIDs.contains(item.id) {
                        if let onBatchRename {
                            Button("Renombrar \(selectedIDs.count) ítems…") { onBatchRename() }
                        }
                        Button("Eliminar \(selectedIDs.count) ítems", role: .destructive) { onDeleteSelection() }
                    } else {
                        if let onRename {
                            Button("Renombrar…") { onRename(item) }
                        }
                        Button("Eliminar", role: .destructive) { onDelete(item) }
                    }
                }
                .draggable(item.url)
                .dropDestination(for: URL.self) { urls, _ in
                    onMoveDropped(urls, item.isDirectory ? item.url : currentURL)
                    return true
                }
            }
        }
    }
}

private struct CompactGridCell: View {
    let item: FileItem
    let zoomLevel: Double
    let isSelected: Bool
    let isSelectionModeActive: Bool
    let gitStatus: GitFileStatus?

    @State private var isHovered = false

    private var iconDimension: CGFloat {
        max(18, 22 * zoomLevel)
    }

    var body: some View {
        HStack(spacing: 7) {
            if isSelectionModeActive {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .transition(.scale.combined(with: .opacity))
            }

            Image(nsImage: ThumbnailLoader.icon(forFile: item.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: iconDimension, height: iconDimension)

            Text(item.name)
                .font(.system(size: max(11.5, 12.5 * min(1.25, zoomLevel)), weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? Color.white : Color.primary)

            if let nsColor = item.colorTag.nsColor {
                Circle()
                    .fill(Color(nsColor: nsColor))
                    .overlay(Circle().strokeBorder(Color.white.opacity(isSelected ? 0.85 : 0.35), lineWidth: 0.8))
                    .frame(width: 8, height: 8)
                    .help("Etiqueta: \(item.colorTag.title)")
            }

            GitStatusBadge(status: gitStatus)

            Spacer(minLength: 0)
        }
        .opacity(item.isHiddenItem ? 0.58 : 1.0)
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(.snappy(duration: 0.15), value: isHovered)
        .animation(.snappy(duration: 0.15), value: isSelected)
        .onHover { isHovered = $0 }
        .help(isHovered ? FileMetadataFormatter().hoverTooltip(for: item) : item.name)
    }
}

struct DotphinGroupSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.85))
            Text("\(count)")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .contentTransition(.numericText())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            VStack {
                Divider()
                    .opacity(0.6)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(.bar)
    }
}
