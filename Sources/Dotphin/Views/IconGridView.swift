import AppKit
import SwiftUI

/// Modifier keys held during a click, mirroring Dolphin: Ctrl/Cmd toggles, Shift extends a range.
enum SelectionModifier {
    case none, toggle, range

    static var current: SelectionModifier {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) { return .range }
        if flags.contains(.command) || flags.contains(.control) { return .toggle }
        return .none
    }
}

struct IconGridView: View {
    let items: [FileItem]
    var groups: [FileItemGroup] = []
    var showInGroups: Bool = false
    var showPreviews: Bool = true
    var isSelectionModeActive: Bool = false
    let zoomLevel: Double
    let selectedIDs: Set<FileItem.ID>
    let currentURL: URL
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

    static func columnCount(forContainerWidth width: CGFloat, zoomLevel: Double) -> Int {
        let cellMinWidth = max(72, round(96 * zoomLevel))
        let spacing: CGFloat = 14
        let innerWidth = max(cellMinWidth, width - 32)
        return max(1, Int(floor((innerWidth + spacing) / (cellMinWidth + spacing))))
    }

    private var activeColumnCount: Int {
        Self.columnCount(forContainerWidth: containerWidth, zoomLevel: zoomLevel)
    }

    private var columns: [GridItem] {
        let cellMinWidth = max(72, round(96 * zoomLevel))
        return Array(
            repeating: GridItem(.flexible(minimum: cellMinWidth), spacing: 14, alignment: .top),
            count: activeColumnCount
        )
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                if showInGroups && !groups.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups) { group in
                            Section {
                                gridBody(for: group.items)
                            } header: {
                                DotphinGroupSectionHeader(title: group.title, count: group.items.count)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                } else {
                    gridBody(for: items)
                        .padding(16)
                        .frame(maxWidth: .infinity)
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
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(sectionItems) { item in
                IconGridCell(
                    item: item,
                    zoomLevel: zoomLevel,
                    showPreviews: showPreviews,
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

private struct IconGridCell: View {
    let item: FileItem
    let zoomLevel: Double
    let showPreviews: Bool
    let isSelected: Bool
    let isSelectionModeActive: Bool
    let gitStatus: GitFileStatus?

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    private var iconDimension: CGFloat {
        58 * zoomLevel
    }

    var body: some View {
        VStack(spacing: 4) {
            // Native macOS Finder icon plate: rounded box around the icon only
            ZStack(alignment: .topTrailing) {
                Group {
                    if showPreviews, let resolvedThumbnail = thumbnail ?? ThumbnailLoader.cachedThumbnail(for: item.url) {
                        Image(nsImage: resolvedThumbnail)
                            .resizable()
                            .scaledToFit()
                            .padding(2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.6)
                            )
                            .shadow(color: .black.opacity(0.18), radius: 2.5, y: 1)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        Image(nsImage: ThumbnailLoader.icon(forFile: item.url.path))
                            .resizable()
                            .scaledToFit()
                            .shadow(color: .black.opacity(0.10), radius: 1.5, y: 0.5)
                    }
                }
                .frame(width: iconDimension, height: iconDimension)
                .scaleEffect(isHovered && !isSelected ? 1.035 : 1.0)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.primary.opacity(0.12)
                                : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                        )
                )

                HStack(spacing: 3) {
                    if isSelectionModeActive {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                            .background(Circle().fill(.regularMaterial))
                            .transition(.scale.combined(with: .opacity))
                    }
                    GitStatusBadge(status: gitStatus)
                }
                .padding(3)
            }

            // Native macOS Finder label pill: blue accent pill tightly wrapping the filename
            HStack(spacing: 4) {
                if let nsColor = item.colorTag.nsColor {
                    Circle()
                        .fill(Color(nsColor: nsColor))
                        .overlay(Circle().strokeBorder(Color.white.opacity(isSelected ? 0.85 : 0.35), lineWidth: 0.8))
                        .frame(width: 7.5, height: 7.5)
                }
                Text(item.name)
                    .font(.system(size: max(11, min(13, 11.5 * zoomLevel)), weight: isSelected ? .medium : .regular))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)

            Spacer(minLength: 0)
        }
        .opacity(item.isHiddenItem ? 0.58 : 1.0)
        .frame(width: 96 * zoomLevel)
        .frame(minHeight: 92 * zoomLevel, alignment: .top)
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.snappy(duration: 0.16), value: isHovered)
        .animation(.snappy(duration: 0.16), value: isSelected)
        .onHover { isHovered = $0 }
        .help(isHovered ? FileMetadataFormatter().hoverTooltip(for: item) : item.name)
        .task(id: item.url) {
            guard showPreviews else {
                thumbnail = nil
                return
            }
            if let cached = ThumbnailLoader.cachedThumbnail(for: item.url) {
                thumbnail = cached
                return
            }
            thumbnail = nil
            guard !item.isDirectory else { return }
            let image = await ThumbnailLoader().thumbnail(
                for: item.url,
                size: CGSize(width: 128, height: 128)
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                thumbnail = image
            }
        }
    }
}
