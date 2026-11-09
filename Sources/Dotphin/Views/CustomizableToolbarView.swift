import AppKit
import SwiftUI

enum ToolbarPlacementRole {
    case full
    case leading
    case trailing
}

final class ToolbarFrameStore {
    var itemFrames: [ToolbarActionItem: CGRect] = [:]
    var groupFrames: [Int: CGRect] = [:]
}

struct CustomizableToolbarView: View {
    let focusedViewModel: BrowserViewModel
    @Binding var settings: AppSettings
    let isSearchOrFilterVisible: Bool
    var availableToolbarWidth: CGFloat = 680
    var placementRole: ToolbarPlacementRole = .full
    let onNewFolder: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onRestore: () -> Void
    let onEmptyTrash: () -> Void
    let onOpenTerminal: () -> Void
    let onToggleSplit: () -> Void
    let onNewTab: () -> Void
    let onToggleInfoPanel: () -> Void
    let onToggleSearch: () -> Void
    var onOpenConfigureToolbar: (() -> Void)? = nil

    @State private var frameStore = ToolbarFrameStore()
    @State private var draggingItem: ToolbarActionItem?
    @State private var dragCurrentPoint: CGPoint = .zero
    @State private var dropTarget: ToolbarDropTarget?
    @State private var showsConfigureSheet = false
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFieldFocused: Bool
    @Namespace private var viewModeNamespace

    private var groups: [[ToolbarActionItem]] {
        let normalized = ToolbarLayoutEngine.normalizedGroups(settings.toolbarGroups)
        let visible = normalized.compactMap { group -> [ToolbarActionItem]? in
            let filtered = group.filter { !settings.hiddenToolbarItems.contains($0) }
            return filtered.isEmpty ? nil : filtered
        }
        return visible.isEmpty ? ToolbarActionItem.defaultGroups : visible
    }

    private var effectiveSearchWidth: CGFloat {
        guard isSearchExpanded else { return 30 }
        if availableToolbarWidth >= 680 {
            return 196
        }
        return max(136, min(196, availableToolbarWidth - 450))
    }

    private func totalEstimatedWidth(
        for indexedGroups: [(originalIndex: Int, items: [ToolbarActionItem])],
        labels: Set<ToolbarActionItem>,
        hasOverflow: Bool
    ) -> CGFloat {
        ToolbarLayoutEngine.totalEstimatedWidth(
            for: indexedGroups,
            labels: labels,
            dividersAfterItems: settings.dividersAfterItems,
            dividersAfterGroupIndices: settings.dividersAfterGroupIndices,
            isBrowsingTrash: focusedViewModel.isBrowsingTrash,
            isSearchExpanded: isSearchExpanded,
            effectiveSearchWidth: effectiveSearchWidth,
            hasOverflow: hasOverflow
        )
    }

    private var layoutPlan: (visibleGroups: [(originalIndex: Int, items: [ToolbarActionItem])], overflowItems: [ToolbarActionItem]) {
        ToolbarLayoutEngine.layoutPlan(
            for: groups,
            availableWidth: availableToolbarWidth,
            dividersAfterItems: settings.dividersAfterItems,
            dividersAfterGroupIndices: settings.dividersAfterGroupIndices,
            isBrowsingTrash: focusedViewModel.isBrowsingTrash,
            isSearchExpanded: isSearchExpanded,
            effectiveSearchWidth: effectiveSearchWidth
        )
    }

    private var effectiveLabelItems: Set<ToolbarActionItem> {
        let plan = layoutPlan
        guard plan.overflowItems.isEmpty else { return [] }

        let visibleItems = plan.visibleGroups.flatMap(\.items)
        let requested: [ToolbarActionItem]
        if settings.showsToolbarLabels || settings.toolbarTextPosition != .iconsOnly {
            requested = visibleItems
        } else {
            requested = visibleItems.filter { settings.toolbarItemsWithLabels.contains($0) }
        }
        guard !requested.isEmpty else { return [] }

        var result = Set<ToolbarActionItem>()
        for item in requested {
            var candidate = result
            candidate.insert(item)
            if totalEstimatedWidth(for: plan.visibleGroups, labels: candidate, hasOverflow: false) <= availableToolbarWidth {
                result = candidate
            }
        }
        return result
    }

    var body: some View {
        let plan = layoutPlan
        let spacerOffsets = ToolbarLayoutEngine.expandingSpacerVisibleOffsets(
            for: plan.visibleGroups,
            fixedSpacesAfterGroupIndices: settings.fixedSpacesAfterGroupIndices,
            spacerAfterGroupIndex: settings.spacerAfterGroupIndex
        )
        let splitAfterOffset: Int? = {
            if let firstSpacer = spacerOffsets.sorted().first {
                return firstSpacer
            }
            if plan.visibleGroups.count >= 2 {
                return plan.visibleGroups.count - 2
            }
            return nil
        }()
        let displayedGroups: [(visibleOffset: Int, entry: (originalIndex: Int, items: [ToolbarActionItem]))] = {
            let all = Array(plan.visibleGroups.enumerated()).map { (visibleOffset: $0.offset, entry: $0.element) }
            switch placementRole {
            case .full:
                return all
            case .leading:
                guard let splitAfterOffset else { return all }
                return all.filter { $0.visibleOffset <= splitAfterOffset }
            case .trailing:
                guard let splitAfterOffset else { return [] }
                return all.filter { $0.visibleOffset > splitAfterOffset }
            }
        }()
        // Keep search anchored to the trailing edge: the "…" pill goes before it.
        let overflowBeforeSearch = !plan.overflowItems.isEmpty
            && !focusedViewModel.isBrowsingTrash
            && (plan.visibleGroups.last?.items.contains(.search) ?? false)
        ZStack(alignment: .topLeading) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(displayedGroups, id: \.entry.originalIndex) { item in
                        let visibleOffset = item.visibleOffset
                        let groupIndex = item.entry.originalIndex
                        let group = item.entry.items

                        if overflowBeforeSearch && visibleOffset == plan.visibleGroups.count - 1 {
                            if placementRole == .full && plan.visibleGroups.count == 1 {
                                Spacer(minLength: 16)
                            }
                            overflowMenuPill(items: plan.overflowItems)
                        }

                        groupPill(group: group, groupIndex: groupIndex)

                        if settings.dividersAfterGroupIndices.contains(groupIndex) {
                            Capsule()
                                .fill(Color.primary.opacity(0.28))
                                .frame(width: 1.5, height: 18)
                                .padding(.horizontal, 2)
                        }

                        if placementRole == .full && spacerOffsets.contains(visibleOffset) {
                            Spacer(minLength: 16)
                        }
                    }

                    if placementRole == .full && plan.visibleGroups.count == 1 && !plan.overflowItems.isEmpty && !overflowBeforeSearch {
                        Spacer(minLength: 16)
                    }

                    if placementRole != .leading && focusedViewModel.isBrowsingTrash {
                        trashContextualPill
                    }

                    if placementRole != .leading && !plan.overflowItems.isEmpty && !overflowBeforeSearch {
                        overflowMenuPill(items: plan.overflowItems)
                    }
                }
                .padding(.vertical, 3)
                .fixedSize(horizontal: placementRole != .full, vertical: false)
                .animation(nil, value: availableToolbarWidth)
                .animation(nil, value: plan.overflowItems)
            }
            .animation(nil, value: availableToolbarWidth)
            .animation(nil, value: plan.overflowItems)
            .coordinateSpace(name: "toolbarSpace")
            .background(
                ToolbarCommandDragMonitorView(
                    frameStore: frameStore,
                    groups: groups,
                    showsToolbarLabels: settings.showsToolbarLabels,
                    toolbarTextPosition: settings.toolbarTextPosition,
                    toolbarItemsWithLabels: settings.toolbarItemsWithLabels,
                    hiddenToolbarItems: settings.hiddenToolbarItems,
                    dividersAfterItems: settings.dividersAfterItems,
                    dividersAfterGroupIndices: settings.dividersAfterGroupIndices,
                    fixedSpacesAfterGroupIndices: settings.fixedSpacesAfterGroupIndices,
                    spacerAfterGroupIndex: settings.spacerAfterGroupIndex,
                    isToolbarLocked: settings.isToolbarLocked,
                    isSearchExpanded: isSearchExpanded,
                    onClickOutsideExpandedSearch: {
                        if isSearchExpanded && focusedViewModel.filterText.isEmpty {
                            collapseSearch(clearText: false)
                        }
                    },
                    onStartDrag: { item, point in
                        draggingItem = item
                        dragCurrentPoint = point
                        dropTarget = ToolbarLayoutEngine.dropTarget(
                            for: item,
                            at: point,
                            groups: groups,
                            itemFrames: frameStore.itemFrames,
                            groupFrames: frameStore.groupFrames
                        )
                    },
                    onUpdateDrag: { point in
                        guard let draggingItem else { return }
                        dragCurrentPoint = point
                        dropTarget = ToolbarLayoutEngine.dropTarget(
                            for: draggingItem,
                            at: point,
                            groups: groups,
                            itemFrames: frameStore.itemFrames,
                            groupFrames: frameStore.groupFrames
                        )
                    },
                    onEndDrag: { point in
                        defer {
                            draggingItem = nil
                            dropTarget = nil
                        }
                        guard let draggingItem else { return }
                        let finalTarget = ToolbarLayoutEngine.dropTarget(
                            for: draggingItem,
                            at: point,
                            groups: groups,
                            itemFrames: frameStore.itemFrames,
                            groupFrames: frameStore.groupFrames
                        ) ?? dropTarget
                        guard let finalTarget else { return }
                        withAnimation(.snappy(duration: 0.22)) {
                            settings.toolbarGroups = ToolbarLayoutEngine.apply(
                                dropTarget: finalTarget,
                                draggingItem: draggingItem,
                                to: ToolbarLayoutEngine.normalizedGroups(settings.toolbarGroups)
                            )
                        }
                    },
                    onCancelDrag: {
                        draggingItem = nil
                        dropTarget = nil
                    },
                    onToggleItemLabel: { item in
                        settings.toggleLabel(for: item)
                    },
                    onSetTextPosition: { position in
                        settings.toolbarTextPosition = position
                        settings.showsToolbarLabels = (position == .textAlongsideIcons)
                        if position == .iconsOnly {
                            settings.toolbarItemsWithLabels.removeAll()
                        }
                    },
                    onToggleDividerAfterItem: { item in
                        if let gIdx = groups.firstIndex(where: { $0.contains(item) }) {
                            if groups[gIdx].last == item {
                                if settings.dividersAfterGroupIndices.contains(gIdx) {
                                    settings.dividersAfterGroupIndices.remove(gIdx)
                                } else {
                                    settings.dividersAfterGroupIndices.insert(gIdx)
                                }
                            } else {
                                if settings.dividersAfterItems.contains(item) {
                                    settings.dividersAfterItems.remove(item)
                                } else {
                                    settings.dividersAfterItems.insert(item)
                                }
                            }
                        }
                    },
                    onToggleFixedSpaceAfterGroup: { groupIdx in
                        if settings.fixedSpacesAfterGroupIndices.contains(groupIdx) {
                            settings.fixedSpacesAfterGroupIndices.remove(groupIdx)
                        } else {
                            settings.fixedSpacesAfterGroupIndices.insert(groupIdx)
                        }
                    },
                    onToggleExpandingSpacerAfterGroup: { groupIdx in
                        if settings.spacerAfterGroupIndex == groupIdx {
                            settings.spacerAfterGroupIndex = nil
                        } else {
                            settings.spacerAfterGroupIndex = groupIdx
                        }
                    },
                    onHideItem: { item in
                        settings.toggleHidden(for: item)
                    },
                    onRestoreHiddenItems: {
                        settings.hiddenToolbarItems.removeAll()
                    },
                    onSeparateItem: { item in
                        withAnimation(.snappy(duration: 0.22)) {
                            settings.toolbarGroups = ToolbarLayoutEngine.separateItem(
                                item,
                                in: ToolbarLayoutEngine.normalizedGroups(settings.toolbarGroups)
                            )
                        }
                    },
                    onToggleLockToolbar: {
                        settings.isToolbarLocked.toggle()
                    },
                    onOpenConfigureSheet: {
                        if let onOpenConfigureToolbar {
                            onOpenConfigureToolbar()
                        } else {
                            showsConfigureSheet = true
                        }
                    },
                    onResetGroups: {
                        withAnimation(.snappy(duration: 0.22)) {
                            settings.resetToolbarToDefaults()
                        }
                    }
                )
            )

            if case .separateGroup(_, let indicatorX) = dropTarget {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 26)
                    .shadow(color: Color.accentColor.opacity(0.6), radius: 3)
                    .offset(x: indicatorX - 1.5, y: 5)
                    .allowsHitTesting(false)
            }

            if let draggingItem {
                floatingDragPreview(for: draggingItem)
                    .position(x: dragCurrentPoint.x, y: dragCurrentPoint.y)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showsConfigureSheet) {
            ToolbarConfigurationSheetView(settings: $settings)
        }
        .onChange(of: focusedViewModel.filterText) { _, newValue in
            if !newValue.isEmpty && !isSearchExpanded {
                withAnimation(.spring(duration: 0.34, bounce: 0.12)) {
                    isSearchExpanded = true
                }
            }
        }
    }

    @ViewBuilder
    private func groupPill(group: [ToolbarActionItem], groupIndex: Int) -> some View {
        let isJoinTarget: Bool = {
            if case .joinGroup(let targetIdx, _) = dropTarget {
                return targetIdx == groupIndex
            }
            return false
        }()

        if isSearchExpanded, let searchIdx = group.firstIndex(of: .search) {
            let leadingItems = Array(group[..<searchIdx])
            let trailingItems = Array(group[(searchIdx + 1)...])

            HStack(spacing: 8) {
                if !leadingItems.isEmpty {
                    pillSegment(
                        items: leadingItems,
                        fullGroup: group,
                        isJoinTarget: isJoinTarget
                    )
                }

                expandedSearchCapsule

                if !trailingItems.isEmpty {
                    pillSegment(
                        items: trailingItems,
                        fullGroup: group,
                        isJoinTarget: isJoinTarget
                    )
                }
            }
            .background(
                GeometryReader { geo in
                    let rect = geo.frame(in: .named("toolbarSpace"))
                    let _ = { frameStore.groupFrames[groupIndex] = rect }()
                    Color.clear
                }
            )
        } else {
            pillSegment(
                items: group,
                fullGroup: group,
                isJoinTarget: isJoinTarget
            )
            .background(
                GeometryReader { geo in
                    let rect = geo.frame(in: .named("toolbarSpace"))
                    let _ = { frameStore.groupFrames[groupIndex] = rect }()
                    Color.clear
                }
            )
        }
    }

    @ViewBuilder
    private func pillSegment(
        items: [ToolbarActionItem],
        fullGroup: [ToolbarActionItem],
        isJoinTarget: Bool
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                itemView(for: item, inGroup: fullGroup)
                    .opacity(draggingItem == item ? 0.35 : 1.0)
                    .background(
                        GeometryReader { geo in
                            let rect = geo.frame(in: .named("toolbarSpace"))
                            let _ = { frameStore.itemFrames[item] = rect }()
                            Color.clear
                        }
                    )

                if idx < items.count - 1 && settings.dividersAfterItems.contains(item) {
                    Divider()
                        .frame(height: 15)
                        .opacity(0.55)
                        .padding(.horizontal, 2)
                }
            }
        }
        .padding(.horizontal, 5)
        .frame(minHeight: 30)
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(isJoinTarget ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private var expandedSearchCapsule: some View {
        HStack(spacing: 7) {
            Button {
                if focusedViewModel.filterText.isEmpty {
                    collapseSearch(clearText: false)
                } else {
                    isSearchFieldFocused = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            TextField(
                "Buscar o filtrar…",
                text: Binding(
                    get: { focusedViewModel.filterText },
                    set: { newValue in
                        focusedViewModel.filterText = newValue
                        if newValue.isEmpty {
                            focusedViewModel.searchQuery = ""
                        }
                    }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .regular))
            .focused($isSearchFieldFocused)
            .fixedSize(horizontal: false, vertical: true)
            .transaction { $0.animation = nil }
            .onSubmit {
                let query = focusedViewModel.filterText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    focusedViewModel.searchQuery = query
                    focusedViewModel.performSearch()
                }
            }
            .onExitCommand {
                collapseSearch(clearText: true)
            }

            if !focusedViewModel.filterText.isEmpty {
                Button {
                    collapseSearch(clearText: true)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Limpiar y cerrar búsqueda")
                .accessibilityLabel("Limpiar y cerrar búsqueda")
            }
        }
        .padding(.horizontal, 11)
        .frame(width: effectiveSearchWidth, height: 30)
        .glassEffect(.regular.interactive(), in: Capsule())
        .background(
            GeometryReader { geo in
                let rect = geo.frame(in: .named("toolbarSpace"))
                let _ = { frameStore.itemFrames[.search] = rect }()
                Color.clear
            }
        )
    }

    private func expandSearch() {
        withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
            isSearchExpanded = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            isSearchFieldFocused = true
        }
    }

    private func collapseSearch(clearText: Bool) {
        isSearchFieldFocused = false
        if clearText {
            focusedViewModel.filterText = ""
            focusedViewModel.searchQuery = ""
        }
        withAnimation(.spring(duration: 0.32, bounce: 0.08)) {
            isSearchExpanded = false
        }
    }

    @ViewBuilder
    private func itemView(for item: ToolbarActionItem, inGroup group: [ToolbarActionItem]) -> some View {
        let showLabel = effectiveLabelItems.contains(item)
        let textOnly = showLabel && settings.toolbarTextPosition == .textOnly
        let textUnder = showLabel && settings.toolbarTextPosition == .textUnderIcons

        switch item {
        case .viewMode:
            let modes = ViewMode.allCases
            HStack(spacing: 0) {
                ForEach(Array(modes.enumerated()), id: \.element) { idx, mode in
                    let isSelected = focusedViewModel.viewProperties.mode == mode
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            focusedViewModel.setViewMode(mode)
                        }
                    } label: {
                        Group {
                            if textUnder {
                                VStack(spacing: 2) {
                                    Image(systemName: viewModeIcon(for: mode))
                                        .font(.system(size: 12, weight: .medium))
                                    Text(viewModeTitle(for: mode))
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(1)
                                }
                            } else {
                                HStack(spacing: 5) {
                                    if !textOnly {
                                        Image(systemName: viewModeIcon(for: mode))
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    if showLabel {
                                        Text(viewModeTitle(for: mode))
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, showLabel ? 9 : 0)
                        .frame(minWidth: 32, minHeight: textUnder ? 32 : 24)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.primary.opacity(0.16))
                                    .matchedGeometryEffect(id: "activeViewModeCapsule", in: viewModeNamespace)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(viewModeTitle(for: mode))
                    .accessibilityLabel(viewModeTitle(for: mode))

                    if idx < modes.count - 1 {
                        let nextMode = modes[idx + 1]
                        let hideDivider = isSelected || focusedViewModel.viewProperties.mode == nextMode
                        Divider()
                            .frame(height: 14)
                            .opacity(hideDivider ? 0 : 0.35)
                            .padding(.horizontal, 2)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)

        case .sort:
            Button {
                showSortPopupMenu(for: .sort)
            } label: {
                Group {
                    if textUnder {
                        VStack(spacing: 2) {
                            HStack(spacing: 3) {
                                Image(systemName: item.systemImage)
                                    .font(.system(size: 12, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.title)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                    } else {
                        HStack(spacing: 5) {
                            if !textOnly {
                                Image(systemName: item.systemImage)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            if showLabel {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.primary)
                .padding(.horizontal, showLabel ? 9 : 0)
                .frame(width: showLabel ? nil : 42, height: textUnder ? 32 : 24)
                .frame(minWidth: 42)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Ordenar")
            .accessibilityLabel("Ordenar por")

        default:
            let disabled = isItemDisabled(item)
            Button {
                performAction(for: item)
            } label: {
                Group {
                    if textUnder {
                        VStack(spacing: 2) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 12, weight: .medium))
                            Text(item.title)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                    } else {
                        HStack(spacing: 5) {
                            if !textOnly {
                                Image(systemName: item.systemImage)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            if showLabel {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(disabled ? .tertiary : .primary)
                .padding(.horizontal, showLabel ? 9 : 0)
                .frame(width: showLabel ? nil : 30, height: textUnder ? 32 : 24)
                .frame(minWidth: 30)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .help(item.title)
            .accessibilityLabel(item.title)
        }
    }

    private func showSortPopupMenu(for item: ToolbarActionItem) {
        let menu = NSMenu()
        let fields: [(String, SortField)] = SortField.allCases.map { ($0.title, $0) }
        for (title, field) in fields {
            let menuItem = NSMenuItem(
                title: title,
                action: nil,
                keyEquivalent: ""
            )
            menuItem.state = focusedViewModel.viewProperties.sortField == field ? .on : .off
            menuItem.representedObject = SortMenuAction {
                let isSameField = focusedViewModel.viewProperties.sortField == field
                let nextAscending = isSameField
                    ? !focusedViewModel.viewProperties.ascending
                    : field.defaultAscending
                focusedViewModel.setSort(field: field, ascending: nextAscending)
            }
            menuItem.target = SortMenuDispatcher.shared
            menuItem.action = #selector(SortMenuDispatcher.invoke(_:))
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())

        let directionTitle = focusedViewModel.viewProperties.ascending ? "Ascendente" : "Descendente"
        let directionItem = NSMenuItem(
            title: directionTitle,
            action: #selector(SortMenuDispatcher.invoke(_:)),
            keyEquivalent: ""
        )
        directionItem.image = NSImage(
            systemSymbolName: focusedViewModel.viewProperties.ascending ? "arrow.up" : "arrow.down",
            accessibilityDescription: directionTitle
        )
        directionItem.representedObject = SortMenuAction {
            focusedViewModel.setSort(
                field: focusedViewModel.viewProperties.sortField,
                ascending: !focusedViewModel.viewProperties.ascending
            )
        }
        directionItem.target = SortMenuDispatcher.shared
        menu.addItem(directionItem)

        menu.addItem(.separator())

        let groupItem = NSMenuItem(
            title: "Mostrar en grupos",
            action: #selector(SortMenuDispatcher.invoke(_:)),
            keyEquivalent: ""
        )
        groupItem.state = focusedViewModel.viewProperties.showInGroups ? .on : .off
        groupItem.representedObject = SortMenuAction {
            focusedViewModel.toggleShowInGroups()
        }
        groupItem.target = SortMenuDispatcher.shared
        menu.addItem(groupItem)

        if let currentEvent = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: currentEvent, for: NSApp.keyWindow?.contentView ?? NSView())
        }
    }

    private var trashContextualPill: some View {
        HStack(spacing: 2) {
            Button(action: onRestore) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .medium))
                    if settings.showsToolbarLabels {
                        Text("Restaurar")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .foregroundStyle(focusedViewModel.selectedItem == nil ? .tertiary : .primary)
                .padding(.horizontal, settings.showsToolbarLabels ? 9 : 6)
                .frame(minWidth: 28, minHeight: 24)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .disabled(focusedViewModel.selectedItem == nil)
            .help("Restaurar")
            .accessibilityLabel("Restaurar")

            Divider()
                .frame(height: 14)
                .opacity(0.35)

            Button(action: onEmptyTrash) {
                HStack(spacing: 5) {
                    Image(systemName: "trash.slash")
                        .font(.system(size: 13, weight: .medium))
                    if settings.showsToolbarLabels {
                        Text("Vaciar")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, settings.showsToolbarLabels ? 9 : 6)
                .frame(minWidth: 28, minHeight: 24)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .help("Vaciar la papelera")
            .accessibilityLabel("Vaciar la papelera")
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 4)
        .frame(minHeight: 30)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private func overflowMenuPill(items: [ToolbarActionItem]) -> some View {
        Menu {
            ForEach(items) { item in
                switch item {
                case .viewMode:
                    Menu("Vista") {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Button {
                                focusedViewModel.setViewMode(mode)
                            } label: {
                                Label(viewModeTitle(for: mode), systemImage: viewModeIcon(for: mode))
                            }
                        }
                    }
                case .sort:
                    Menu("Ordenar") {
                        Button("Nombre") {
                            focusedViewModel.setSort(field: .name, ascending: focusedViewModel.viewProperties.ascending)
                        }
                        Button("Tamaño") {
                            focusedViewModel.setSort(field: .size, ascending: focusedViewModel.viewProperties.ascending)
                        }
                        Button("Fecha") {
                            focusedViewModel.setSort(field: .modificationDate, ascending: focusedViewModel.viewProperties.ascending)
                        }
                        Divider()
                        Button(focusedViewModel.viewProperties.ascending ? "Ascendente" : "Descendente") {
                            focusedViewModel.setSort(
                                field: focusedViewModel.viewProperties.sortField,
                                ascending: !focusedViewModel.viewProperties.ascending
                            )
                        }
                    }
                default:
                    Button {
                        performAction(for: item)
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                    }
                    .disabled(isItemDisabled(item))
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 24)
                .padding(.horizontal, 5)
                .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 38, height: 30)
        .glassEffect(.regular.interactive(), in: Capsule())
        .help("Más acciones")
        .accessibilityLabel("Más acciones")
    }

    private func floatingDragPreview(for item: ToolbarActionItem) -> some View {
        HStack(spacing: 5) {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .semibold))
            if settings.showsLabel(for: item) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
    }

    private func isItemDisabled(_ item: ToolbarActionItem) -> Bool {
        switch item {
        case .back:
            return !focusedViewModel.canGoBack
        case .forward:
            return !focusedViewModel.canGoForward
        case .up:
            return focusedViewModel.currentURL.path == "/"
        case .rename, .delete:
            return focusedViewModel.selectedIDs.isEmpty
        default:
            return false
        }
    }

    private func performAction(for item: ToolbarActionItem) {
        switch item {
        case .back:
            focusedViewModel.goBack()
        case .forward:
            focusedViewModel.goForward()
        case .up:
            focusedViewModel.goUp()
        case .viewMode, .sort:
            break
        case .newFolder:
            onNewFolder()
        case .rename:
            onRename()
        case .delete:
            onDelete()
        case .terminal:
            onOpenTerminal()
        case .split:
            onToggleSplit()
        case .newTab:
            onNewTab()
        case .infoPanel:
            onToggleInfoPanel()
        case .search:
            if isSearchExpanded {
                collapseSearch(clearText: true)
            } else {
                expandSearch()
            }
        }
    }

    private func viewModeIcon(for mode: ViewMode) -> String {
        mode.systemImage
    }

    private func viewModeTitle(for mode: ViewMode) -> String {
        mode.title
    }
}

private final class SortMenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }
}

@MainActor
private final class SortMenuDispatcher: NSObject {
    static let shared = SortMenuDispatcher()
    @objc func invoke(_ sender: NSMenuItem) {
        if let action = sender.representedObject as? SortMenuAction {
            action.handler()
        }
    }
}

private struct ToolbarCommandDragMonitorView: NSViewRepresentable {
    let frameStore: ToolbarFrameStore
    let groups: [[ToolbarActionItem]]
    let showsToolbarLabels: Bool
    let toolbarTextPosition: ToolbarTextPosition
    let toolbarItemsWithLabels: Set<ToolbarActionItem>
    let hiddenToolbarItems: Set<ToolbarActionItem>
    let dividersAfterItems: Set<ToolbarActionItem>
    let dividersAfterGroupIndices: Set<Int>
    let fixedSpacesAfterGroupIndices: Set<Int>
    let spacerAfterGroupIndex: Int?
    let isToolbarLocked: Bool
    let isSearchExpanded: Bool
    let onClickOutsideExpandedSearch: () -> Void
    let onStartDrag: (ToolbarActionItem, CGPoint) -> Void
    let onUpdateDrag: (CGPoint) -> Void
    let onEndDrag: (CGPoint) -> Void
    let onCancelDrag: () -> Void
    let onToggleItemLabel: (ToolbarActionItem) -> Void
    let onSetTextPosition: (ToolbarTextPosition) -> Void
    let onToggleDividerAfterItem: (ToolbarActionItem) -> Void
    let onToggleFixedSpaceAfterGroup: (Int) -> Void
    let onToggleExpandingSpacerAfterGroup: (Int) -> Void
    let onHideItem: (ToolbarActionItem) -> Void
    let onRestoreHiddenItems: () -> Void
    let onSeparateItem: (ToolbarActionItem) -> Void
    let onToggleLockToolbar: () -> Void
    let onOpenConfigureSheet: () -> Void
    let onResetGroups: () -> Void

    func makeNSView(context: Context) -> MonitorNSView {
        let view = MonitorNSView()
        view.updateCallbacks(
            frameStore: frameStore,
            groups: groups,
            showsToolbarLabels: showsToolbarLabels,
            toolbarTextPosition: toolbarTextPosition,
            toolbarItemsWithLabels: toolbarItemsWithLabels,
            hiddenToolbarItems: hiddenToolbarItems,
            dividersAfterItems: dividersAfterItems,
            dividersAfterGroupIndices: dividersAfterGroupIndices,
            fixedSpacesAfterGroupIndices: fixedSpacesAfterGroupIndices,
            spacerAfterGroupIndex: spacerAfterGroupIndex,
            isToolbarLocked: isToolbarLocked,
            isSearchExpanded: isSearchExpanded,
            onClickOutsideExpandedSearch: onClickOutsideExpandedSearch,
            onStartDrag: onStartDrag,
            onUpdateDrag: onUpdateDrag,
            onEndDrag: onEndDrag,
            onCancelDrag: onCancelDrag,
            onToggleItemLabel: onToggleItemLabel,
            onSetTextPosition: onSetTextPosition,
            onToggleDividerAfterItem: onToggleDividerAfterItem,
            onToggleFixedSpaceAfterGroup: onToggleFixedSpaceAfterGroup,
            onToggleExpandingSpacerAfterGroup: onToggleExpandingSpacerAfterGroup,
            onHideItem: onHideItem,
            onRestoreHiddenItems: onRestoreHiddenItems,
            onSeparateItem: onSeparateItem,
            onToggleLockToolbar: onToggleLockToolbar,
            onOpenConfigureSheet: onOpenConfigureSheet,
            onResetGroups: onResetGroups
        )
        return view
    }

    func updateNSView(_ nsView: MonitorNSView, context: Context) {
        nsView.updateCallbacks(
            frameStore: frameStore,
            groups: groups,
            showsToolbarLabels: showsToolbarLabels,
            toolbarTextPosition: toolbarTextPosition,
            toolbarItemsWithLabels: toolbarItemsWithLabels,
            hiddenToolbarItems: hiddenToolbarItems,
            dividersAfterItems: dividersAfterItems,
            dividersAfterGroupIndices: dividersAfterGroupIndices,
            fixedSpacesAfterGroupIndices: fixedSpacesAfterGroupIndices,
            spacerAfterGroupIndex: spacerAfterGroupIndex,
            isToolbarLocked: isToolbarLocked,
            isSearchExpanded: isSearchExpanded,
            onClickOutsideExpandedSearch: onClickOutsideExpandedSearch,
            onStartDrag: onStartDrag,
            onUpdateDrag: onUpdateDrag,
            onEndDrag: onEndDrag,
            onCancelDrag: onCancelDrag,
            onToggleItemLabel: onToggleItemLabel,
            onSetTextPosition: onSetTextPosition,
            onToggleDividerAfterItem: onToggleDividerAfterItem,
            onToggleFixedSpaceAfterGroup: onToggleFixedSpaceAfterGroup,
            onToggleExpandingSpacerAfterGroup: onToggleExpandingSpacerAfterGroup,
            onHideItem: onHideItem,
            onRestoreHiddenItems: onRestoreHiddenItems,
            onSeparateItem: onSeparateItem,
            onToggleLockToolbar: onToggleLockToolbar,
            onOpenConfigureSheet: onOpenConfigureSheet,
            onResetGroups: onResetGroups
        )
    }

    final class MonitorNSView: NSView {
        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        private var frameStore: ToolbarFrameStore?
        private var groups: [[ToolbarActionItem]] = []
        private var showsToolbarLabels = false
        private var toolbarTextPosition: ToolbarTextPosition = .iconsOnly
        private var toolbarItemsWithLabels: Set<ToolbarActionItem> = []
        private var hiddenToolbarItems: Set<ToolbarActionItem> = []
        private var dividersAfterItems: Set<ToolbarActionItem> = []
        private var dividersAfterGroupIndices: Set<Int> = []
        private var fixedSpacesAfterGroupIndices: Set<Int> = []
        private var spacerAfterGroupIndex: Int?
        private var isToolbarLocked = false
        private var isSearchExpanded = false
        private var onClickOutsideExpandedSearch: (() -> Void)?
        private var onStartDrag: ((ToolbarActionItem, CGPoint) -> Void)?
        private var onUpdateDrag: ((CGPoint) -> Void)?
        private var onEndDrag: ((CGPoint) -> Void)?
        private var onCancelDrag: (() -> Void)?
        private var onToggleItemLabel: ((ToolbarActionItem) -> Void)?
        private var onSetTextPosition: ((ToolbarTextPosition) -> Void)?
        private var onToggleDividerAfterItem: ((ToolbarActionItem) -> Void)?
        private var onToggleFixedSpaceAfterGroup: ((Int) -> Void)?
        private var onToggleExpandingSpacerAfterGroup: ((Int) -> Void)?
        private var onHideItem: ((ToolbarActionItem) -> Void)?
        private var onRestoreHiddenItems: (() -> Void)?
        private var onSeparateItem: ((ToolbarActionItem) -> Void)?
        private var onToggleLockToolbar: (() -> Void)?
        private var onOpenConfigureSheet: (() -> Void)?
        private var onResetGroups: (() -> Void)?
        private var eventMonitor: Any?
        private var isDragging = false
        private var pendingDragItem: ToolbarActionItem?
        private var mouseDownPoint: CGPoint = .zero

        func updateCallbacks(
            frameStore: ToolbarFrameStore,
            groups: [[ToolbarActionItem]],
            showsToolbarLabels: Bool,
            toolbarTextPosition: ToolbarTextPosition,
            toolbarItemsWithLabels: Set<ToolbarActionItem>,
            hiddenToolbarItems: Set<ToolbarActionItem>,
            dividersAfterItems: Set<ToolbarActionItem>,
            dividersAfterGroupIndices: Set<Int>,
            fixedSpacesAfterGroupIndices: Set<Int>,
            spacerAfterGroupIndex: Int?,
            isToolbarLocked: Bool,
            isSearchExpanded: Bool,
            onClickOutsideExpandedSearch: @escaping () -> Void,
            onStartDrag: @escaping (ToolbarActionItem, CGPoint) -> Void,
            onUpdateDrag: @escaping (CGPoint) -> Void,
            onEndDrag: @escaping (CGPoint) -> Void,
            onCancelDrag: @escaping () -> Void,
            onToggleItemLabel: @escaping (ToolbarActionItem) -> Void,
            onSetTextPosition: @escaping (ToolbarTextPosition) -> Void,
            onToggleDividerAfterItem: @escaping (ToolbarActionItem) -> Void,
            onToggleFixedSpaceAfterGroup: @escaping (Int) -> Void,
            onToggleExpandingSpacerAfterGroup: @escaping (Int) -> Void,
            onHideItem: @escaping (ToolbarActionItem) -> Void,
            onRestoreHiddenItems: @escaping () -> Void,
            onSeparateItem: @escaping (ToolbarActionItem) -> Void,
            onToggleLockToolbar: @escaping () -> Void,
            onOpenConfigureSheet: @escaping () -> Void,
            onResetGroups: @escaping () -> Void
        ) {
            self.frameStore = frameStore
            self.groups = groups
            self.showsToolbarLabels = showsToolbarLabels
            self.toolbarTextPosition = toolbarTextPosition
            self.toolbarItemsWithLabels = toolbarItemsWithLabels
            self.hiddenToolbarItems = hiddenToolbarItems
            self.dividersAfterItems = dividersAfterItems
            self.dividersAfterGroupIndices = dividersAfterGroupIndices
            self.fixedSpacesAfterGroupIndices = fixedSpacesAfterGroupIndices
            self.spacerAfterGroupIndex = spacerAfterGroupIndex
            self.isToolbarLocked = isToolbarLocked
            self.isSearchExpanded = isSearchExpanded
            self.onClickOutsideExpandedSearch = onClickOutsideExpandedSearch
            self.onStartDrag = onStartDrag
            self.onUpdateDrag = onUpdateDrag
            self.onEndDrag = onEndDrag
            self.onCancelDrag = onCancelDrag
            self.onToggleItemLabel = onToggleItemLabel
            self.onSetTextPosition = onSetTextPosition
            self.onToggleDividerAfterItem = onToggleDividerAfterItem
            self.onToggleFixedSpaceAfterGroup = onToggleFixedSpaceAfterGroup
            self.onToggleExpandingSpacerAfterGroup = onToggleExpandingSpacerAfterGroup
            self.onHideItem = onHideItem
            self.onRestoreHiddenItems = onRestoreHiddenItems
            self.onSeparateItem = onSeparateItem
            self.onToggleLockToolbar = onToggleLockToolbar
            self.onOpenConfigureSheet = onOpenConfigureSheet
            self.onResetGroups = onResetGroups

            if let toolbar = window?.toolbar {
                if !toolbar.isVisible { toolbar.isVisible = true }
                if toolbar.displayMode != .iconOnly { toolbar.displayMode = .iconOnly }
                if toolbar.allowsUserCustomization { toolbar.allowsUserCustomization = false }
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                if let toolbar = window.toolbar {
                    if !toolbar.isVisible { toolbar.isVisible = true }
                    if toolbar.displayMode != .iconOnly { toolbar.displayMode = .iconOnly }
                    if toolbar.allowsUserCustomization { toolbar.allowsUserCustomization = false }
                }
                if eventMonitor == nil {
                    installMonitor()
                }
            } else {
                if let monitor = eventMonitor {
                    NSEvent.removeMonitor(monitor)
                    eventMonitor = nil
                }
            }
        }

        private func installMonitor() {
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]
            ) { [weak self] event in
                guard let self, let window = self.window, event.window === window else {
                    return event
                }

                let localPoint = self.convert(event.locationInWindow, from: nil)
                let currentItemFrames = self.frameStore?.itemFrames ?? [:]

                switch event.type {
                case .leftMouseDown:
                    self.pendingDragItem = nil
                    if self.isSearchExpanded {
                        let searchFrame = currentItemFrames[.search] ?? .zero
                        if !searchFrame.insetBy(dx: -6, dy: -6).contains(localPoint) {
                            self.onClickOutsideExpandedSearch?()
                        }
                    }
                    guard self.bounds.insetBy(dx: -8, dy: -8).contains(localPoint),
                          let hitItem = currentItemFrames.first(where: {
                              $0.value.insetBy(dx: -4, dy: -4).contains(localPoint)
                          })?.key else {
                        return event
                    }
                    if hitItem == .search && self.isSearchExpanded && !event.modifierFlags.contains(.command) {
                        return event
                    }
                    if event.modifierFlags.contains(.command) {
                        self.isDragging = true
                        self.onStartDrag?(hitItem, localPoint)
                        return nil
                    } else if !self.isToolbarLocked {
                        self.pendingDragItem = hitItem
                        self.mouseDownPoint = localPoint
                    }
                    return event

                case .leftMouseDragged:
                    if !self.isDragging, let pending = self.pendingDragItem {
                        let dist = hypot(localPoint.x - self.mouseDownPoint.x, localPoint.y - self.mouseDownPoint.y)
                        if dist >= 6 {
                            self.isDragging = true
                            self.pendingDragItem = nil
                            self.onStartDrag?(pending, localPoint)
                            return nil
                        }
                    }
                    guard self.isDragging else { return event }
                    self.onUpdateDrag?(localPoint)
                    return nil

                case .leftMouseUp:
                    self.pendingDragItem = nil
                    guard self.isDragging else { return event }
                    self.isDragging = false
                    self.onEndDrag?(localPoint)
                    return nil

                case .rightMouseDown:
                    let isInToolbarBounds = self.bounds.insetBy(dx: -12, dy: -8).contains(localPoint)
                    let isInWindowTitlebar = event.locationInWindow.y > window.contentLayoutRect.maxY
                    guard isInToolbarBounds || isInWindowTitlebar else {
                        return event
                    }
                    let hitItem = currentItemFrames.first(where: {
                        $0.value.insetBy(dx: -4, dy: -4).contains(localPoint)
                    })?.key
                    self.presentContextMenu(for: hitItem, with: event)
                    return nil

                default:
                    return event
                }
            }
        }

        private func presentContextMenu(for hitItem: ToolbarActionItem?, with event: NSEvent) {
            let menu = NSMenu()

            if let item = hitItem {
                let hasLabel = showsToolbarLabels || toolbarTextPosition != .iconsOnly || toolbarItemsWithLabels.contains(item)
                let toggleItem = NSMenuItem(
                    title: hasLabel
                        ? "Ocultar texto en «\(item.title)»"
                        : "Mostrar texto al costado en «\(item.title)»",
                    action: #selector(SortMenuDispatcher.invoke(_:)),
                    keyEquivalent: ""
                )
                toggleItem.image = NSImage(
                    systemSymbolName: hasLabel ? "tag.slash" : "tag",
                    accessibilityDescription: nil
                )
                toggleItem.representedObject = SortMenuAction { [weak self] in
                    self?.onToggleItemLabel?(item)
                }
                toggleItem.target = SortMenuDispatcher.shared
                menu.addItem(toggleItem)

                if let group = groups.first(where: { $0.contains(item) }), group.count > 1 {
                    let separateMenuItem = NSMenuItem(
                        title: "Separar «\(item.title)» en su propio grupo",
                        action: #selector(SortMenuDispatcher.invoke(_:)),
                        keyEquivalent: ""
                    )
                    separateMenuItem.image = NSImage(
                        systemSymbolName: "arrow.left.and.right.square",
                        accessibilityDescription: nil
                    )
                    separateMenuItem.representedObject = SortMenuAction { [weak self] in
                        self?.onSeparateItem?(item)
                    }
                    separateMenuItem.target = SortMenuDispatcher.shared
                    menu.addItem(separateMenuItem)
                }

                let hideMenuItem = NSMenuItem(
                    title: "Quitar «\(item.title)» de la barra",
                    action: #selector(SortMenuDispatcher.invoke(_:)),
                    keyEquivalent: ""
                )
                hideMenuItem.image = NSImage(
                    systemSymbolName: "minus.circle",
                    accessibilityDescription: nil
                )
                hideMenuItem.representedObject = SortMenuAction { [weak self] in
                    self?.onHideItem?(item)
                }
                hideMenuItem.target = SortMenuDispatcher.shared
                menu.addItem(hideMenuItem)

                if let gIdx = groups.firstIndex(where: { $0.contains(item) }) {
                    menu.addItem(.separator())

                    let hasDivider = (groups[gIdx].last == item)
                        ? dividersAfterGroupIndices.contains(gIdx)
                        : dividersAfterItems.contains(item)
                    let divItem = NSMenuItem(
                        title: hasDivider
                            ? "Quitar «| Divisor» después de «\(item.title)»"
                            : "Agregar «| Divisor» después de «\(item.title)»",
                        action: #selector(SortMenuDispatcher.invoke(_:)),
                        keyEquivalent: ""
                    )
                    divItem.image = NSImage(systemSymbolName: "poweron", accessibilityDescription: nil)
                    divItem.representedObject = SortMenuAction { [weak self] in
                        self?.onToggleDividerAfterItem?(item)
                    }
                    divItem.target = SortMenuDispatcher.shared
                    menu.addItem(divItem)

                    let hasSpacer = fixedSpacesAfterGroupIndices.contains(gIdx) || spacerAfterGroupIndex == gIdx
                    let spaceItem = NSMenuItem(
                        title: hasSpacer
                            ? "Quitar «↔ Espaciador (Divider Space)» tras este grupo"
                            : "Agregar «↔ Espaciador (Divider Space)» tras este grupo",
                        action: #selector(SortMenuDispatcher.invoke(_:)),
                        keyEquivalent: ""
                    )
                    spaceItem.image = NSImage(systemSymbolName: "arrow.left.and.right", accessibilityDescription: nil)
                    spaceItem.representedObject = SortMenuAction { [weak self] in
                        self?.onToggleFixedSpaceAfterGroup?(gIdx)
                    }
                    spaceItem.target = SortMenuDispatcher.shared
                    menu.addItem(spaceItem)
                }

                menu.addItem(.separator())
            }

            // KDE Dolphin "Posición del texto" submenu
            let textPosSubmenu = NSMenu()
            for position in ToolbarTextPosition.allCases {
                let posItem = NSMenuItem(
                    title: position.title,
                    action: #selector(SortMenuDispatcher.invoke(_:)),
                    keyEquivalent: ""
                )
                posItem.state = (toolbarTextPosition == position) ? .on : .off
                posItem.representedObject = SortMenuAction { [weak self] in
                    self?.onSetTextPosition?(position)
                }
                posItem.target = SortMenuDispatcher.shared
                textPosSubmenu.addItem(posItem)
            }
            let textPosRoot = NSMenuItem(title: "Posición del texto", action: nil, keyEquivalent: "")
            textPosRoot.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
            textPosRoot.submenu = textPosSubmenu
            menu.addItem(textPosRoot)

            // KDE Dolphin "Bloquear posiciones de la barra de herramientas"
            let lockItem = NSMenuItem(
                title: "Bloquear posiciones de la barra de herramientas",
                action: #selector(SortMenuDispatcher.invoke(_:)),
                keyEquivalent: ""
            )
            lockItem.state = isToolbarLocked ? .on : .off
            lockItem.image = NSImage(
                systemSymbolName: isToolbarLocked ? "lock.fill" : "lock.open",
                accessibilityDescription: nil
            )
            lockItem.representedObject = SortMenuAction { [weak self] in
                self?.onToggleLockToolbar?()
            }
            lockItem.target = SortMenuDispatcher.shared
            menu.addItem(lockItem)

            if !hiddenToolbarItems.isEmpty {
                let restoreHiddenItem = NSMenuItem(
                    title: "Restaurar acciones ocultas (\(hiddenToolbarItems.count))",
                    action: #selector(SortMenuDispatcher.invoke(_:)),
                    keyEquivalent: ""
                )
                restoreHiddenItem.image = NSImage(
                    systemSymbolName: "eye",
                    accessibilityDescription: nil
                )
                restoreHiddenItem.representedObject = SortMenuAction { [weak self] in
                    self?.onRestoreHiddenItems?()
                }
                restoreHiddenItem.target = SortMenuDispatcher.shared
                menu.addItem(restoreHiddenItem)
            }

            menu.addItem(.separator())

            // KDE Dolphin "Configurar barras de herramientas…"
            let configureItem = NSMenuItem(
                title: "Configurar barras de herramientas…",
                action: #selector(SortMenuDispatcher.invoke(_:)),
                keyEquivalent: ""
            )
            configureItem.image = NSImage(
                systemSymbolName: "slider.horizontal.3",
                accessibilityDescription: nil
            )
            configureItem.representedObject = SortMenuAction { [weak self] in
                self?.onOpenConfigureSheet?()
            }
            configureItem.target = SortMenuDispatcher.shared
            menu.addItem(configureItem)

            let resetMenuItem = NSMenuItem(
                title: "Restablecer valores predeterminados",
                action: #selector(SortMenuDispatcher.invoke(_:)),
                keyEquivalent: ""
            )
            resetMenuItem.image = NSImage(
                systemSymbolName: "arrow.counterclockwise",
                accessibilityDescription: nil
            )
            resetMenuItem.representedObject = SortMenuAction { [weak self] in
                self?.onResetGroups?()
            }
            resetMenuItem.target = SortMenuDispatcher.shared
            menu.addItem(resetMenuItem)

            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}
