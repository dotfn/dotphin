import CoreGraphics
import Foundation

enum StartupLocation: String, Codable, CaseIterable {
    case home, desktop, custom
}

/// KDE Dolphin's `SortingChoice` (`dolphin_generalsettings.kcfg`): Natural, Case Insensitive, or Case Sensitive.
enum SortingChoice: String, Codable, CaseIterable, Identifiable {
    case natural
    case caseInsensitive
    case caseSensitive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: return "Natural (ej. archivo2 antes de archivo10)"
        case .caseInsensitive: return "Alfabético (sin distinguir mayúsculas)"
        case .caseSensitive: return "Alfabético (distinguiendo mayúsculas)"
        }
    }

    func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        switch self {
        case .natural:
            return lhs.localizedStandardCompare(rhs)
        case .caseInsensitive:
            return lhs.localizedCaseInsensitiveCompare(rhs)
        case .caseSensitive:
            return lhs.compare(rhs)
        }
    }
}

/// KDE Dolphin's `DirectorySizeMode` (`dolphin_contentdisplaysettings.kcfg`).
enum DirectorySizeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case contentCount
    case contentSize
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contentCount: return "Cantidad de elementos dentro de la carpeta"
        case .contentSize: return "Tamaño de los archivos directos"
        case .none: return "No mostrar tamaño (—)"
        }
    }
}

/// KDE Dolphin's `UsePermissionsFormat` (`dolphin_contentdisplaysettings.kcfg`).
enum PermissionsDisplayFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case symbolic
    case numeric
    case combined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .symbolic: return "Simbólico (rwxr-xr-x)"
        case .numeric: return "Numérico octal (755)"
        case .combined: return "Combinado (rwxr-xr-x (755))"
        }
    }
}

/// KDE Dolphin's `ShowStatusBar` (`dolphin_generalsettings.kcfg` & `dolphinstatusbar.cpp`).
enum StatusBarDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fullWidth
    case small
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullWidth: return "Ancho completo (con zoom y espacio libre)"
        case .small: return "Compacta (solo resumen de elementos)"
        case .disabled: return "Oculta"
        }
    }
}

enum ToolbarTextPosition: String, Codable, CaseIterable {
    case iconsOnly
    case textAlongsideIcons
    case textOnly
    case textUnderIcons

    var title: String {
        switch self {
        case .iconsOnly: return "Solo iconos"
        case .textAlongsideIcons: return "Texto junto a los iconos"
        case .textOnly: return "Solo texto"
        case .textUnderIcons: return "Texto bajo los iconos"
        }
    }
}

enum ToolbarConfigEntry: Equatable, Identifiable, Hashable {
    case action(ToolbarActionItem)
    case divider(UUID)
    case fixedSpacer(UUID)
    case separator(UUID)
    case expandingSpacer

    var id: String {
        switch self {
        case .action(let item):
            return "action-\(item.rawValue)"
        case .divider(let uuid):
            return "div-\(uuid.uuidString)"
        case .fixedSpacer(let uuid):
            return "fspace-\(uuid.uuidString)"
        case .separator(let uuid):
            return "sep-\(uuid.uuidString)"
        case .expandingSpacer:
            return "expanding-spacer"
        }
    }

    var title: String {
        switch self {
        case .action(let item):
            return item.title
        case .divider:
            return "| Divisor (Divider)"
        case .fixedSpacer, .expandingSpacer:
            return "↔ Espaciador (Divider Space)"
        case .separator:
            return "— Separador de grupo —"
        }
    }

    var systemImage: String {
        switch self {
        case .action(let item):
            return item.systemImage
        case .divider:
            return "poweron"
        case .fixedSpacer, .expandingSpacer:
            return "arrow.left.and.right"
        case .separator:
            return "rectangle.split.2x1"
        }
    }
}

enum ToolbarActionItem: String, Codable, CaseIterable, Identifiable, Hashable {
    case back
    case forward
    case up
    case viewMode
    case sort
    case newFolder
    case rename
    case delete
    case terminal
    case split
    case newTab
    case infoPanel
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: return "Atrás"
        case .forward: return "Adelante"
        case .up: return "Subir"
        case .viewMode: return "Vista"
        case .sort: return "Ordenar"
        case .newFolder: return "Nueva carpeta"
        case .rename: return "Renombrar"
        case .delete: return "Eliminar"
        case .terminal: return "Terminal"
        case .split: return "Dividir"
        case .newTab: return "Pestaña"
        case .infoPanel: return "Información"
        case .search: return "Buscar"
        }
    }

    var systemImage: String {
        switch self {
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .up: return "chevron.up"
        case .viewMode: return "square.grid.2x2"
        case .sort: return "arrow.up.arrow.down"
        case .newFolder: return "folder.badge.plus"
        case .rename: return "pencil"
        case .delete: return "trash"
        case .terminal: return "terminal"
        case .split: return "rectangle.split.2x1"
        case .newTab: return "plus.square.on.square"
        case .infoPanel: return "sidebar.right"
        case .search: return "magnifyingglass"
        }
    }

    /// Priority for remaining visible in the toolbar when space is constrained.
    /// Lower values move to the overflow ("…") menu first; higher values stay visible longest.
    var overflowPriority: Int {
        switch self {
        case .terminal: return 10
        case .split: return 20
        case .infoPanel: return 30
        case .delete: return 40
        case .rename: return 50
        case .newFolder: return 60
        case .newTab: return 70
        case .sort: return 80
        case .up: return 90
        case .viewMode: return 100
        case .forward: return 110
        case .back: return 120
        case .search: return 130
        }
    }

    static var defaultGroups: [[ToolbarActionItem]] {
        [
            [.back, .forward, .up],
            [.viewMode],
            [.sort],
            [.newFolder, .rename, .delete],
            [.split, .newTab, .infoPanel],
            [.terminal, .search]
        ]
    }
}

enum ToolbarDropTarget: Equatable {
    case separateGroup(atIndex: Int, indicatorX: CGFloat)
    case joinGroup(groupIndex: Int, insertIndex: Int)
}

enum ToolbarLayoutEngine {
    static func normalizedGroups(_ groups: [[ToolbarActionItem]]) -> [[ToolbarActionItem]] {
        var seen = Set<ToolbarActionItem>()
        var result: [[ToolbarActionItem]] = []

        for group in groups {
            let filtered = group.filter { seen.insert($0).inserted }
            if !filtered.isEmpty {
                result.append(filtered)
            }
        }

        for item in ToolbarActionItem.allCases where !seen.contains(item) {
            result.append([item])
        }

        return result
    }

    static func apply(
        dropTarget: ToolbarDropTarget,
        draggingItem: ToolbarActionItem,
        to groups: [[ToolbarActionItem]]
    ) -> [[ToolbarActionItem]] {
        var current = normalizedGroups(groups)
        guard let sourceGroupIndex = current.firstIndex(where: { $0.contains(draggingItem) }),
              let sourceItemIndex = current[sourceGroupIndex].firstIndex(of: draggingItem) else {
            return current
        }

        switch dropTarget {
        case .separateGroup(let rawTargetIndex, _):
            let wasSingleton = current[sourceGroupIndex].count == 1
            if wasSingleton && (rawTargetIndex == sourceGroupIndex || rawTargetIndex == sourceGroupIndex + 1) {
                return current
            }

            current[sourceGroupIndex].remove(at: sourceItemIndex)
            var adjustedIndex = rawTargetIndex
            if current[sourceGroupIndex].isEmpty {
                current.remove(at: sourceGroupIndex)
                if adjustedIndex > sourceGroupIndex {
                    adjustedIndex -= 1
                }
            }
            adjustedIndex = max(0, min(adjustedIndex, current.count))
            current.insert([draggingItem], at: adjustedIndex)
            return current

        case .joinGroup(let targetGroupIndex, let rawInsertIndex):
            guard current.indices.contains(targetGroupIndex) else { return current }

            if targetGroupIndex == sourceGroupIndex {
                if current[sourceGroupIndex].count <= 1 {
                    return current
                }
                current[sourceGroupIndex].remove(at: sourceItemIndex)
                var adjustedInsert = rawInsertIndex
                if adjustedInsert > sourceItemIndex {
                    adjustedInsert -= 1
                }
                adjustedInsert = max(0, min(adjustedInsert, current[sourceGroupIndex].count))
                current[sourceGroupIndex].insert(draggingItem, at: adjustedInsert)
                return current
            }

            current[sourceGroupIndex].remove(at: sourceItemIndex)
            var adjustedGroupIndex = targetGroupIndex
            if current[sourceGroupIndex].isEmpty {
                current.remove(at: sourceGroupIndex)
                if adjustedGroupIndex > sourceGroupIndex {
                    adjustedGroupIndex -= 1
                }
            }
            guard current.indices.contains(adjustedGroupIndex) else {
                current.append([draggingItem])
                return current
            }
            let clampedInsert = max(0, min(rawInsertIndex, current[adjustedGroupIndex].count))
            current[adjustedGroupIndex].insert(draggingItem, at: clampedInsert)
            return current
        }
    }

    static func separateItem(
        _ item: ToolbarActionItem,
        in groups: [[ToolbarActionItem]]
    ) -> [[ToolbarActionItem]] {
        var current = normalizedGroups(groups)
        guard let groupIdx = current.firstIndex(where: { $0.contains(item) }),
              current[groupIdx].count > 1,
              let itemIdx = current[groupIdx].firstIndex(of: item) else {
            return current
        }
        current[groupIdx].remove(at: itemIdx)
        current.insert([item], at: groupIdx + 1)
        return current
    }

    static func dropTarget(
        for draggingItem: ToolbarActionItem,
        at point: CGPoint,
        groups: [[ToolbarActionItem]],
        itemFrames: [ToolbarActionItem: CGRect],
        groupFrames: [Int: CGRect]
    ) -> ToolbarDropTarget? {
        guard !groups.isEmpty else { return nil }
        let edgeThreshold: CGFloat = 7

        if let firstRect = groupFrames[0], point.x <= firstRect.minX + edgeThreshold {
            return .separateGroup(atIndex: 0, indicatorX: max(2, firstRect.minX - 4))
        }

        let lastIdx = groups.count - 1
        if let lastRect = groupFrames[lastIdx], point.x >= lastRect.maxX - edgeThreshold {
            return .separateGroup(atIndex: groups.count, indicatorX: lastRect.maxX + 4)
        }

        for idx in 0..<(groups.count - 1) {
            guard let leftRect = groupFrames[idx],
                  let rightRect = groupFrames[idx + 1] else { continue }
            let gapStart = leftRect.maxX - edgeThreshold
            let gapEnd = rightRect.minX + edgeThreshold
            if point.x >= gapStart && point.x <= gapEnd {
                let midGap = (leftRect.maxX + rightRect.minX) / 2
                return .separateGroup(atIndex: idx + 1, indicatorX: midGap)
            }
        }

        for (groupIdx, group) in groups.enumerated() {
            guard let groupRect = groupFrames[groupIdx],
                  point.x >= groupRect.minX && point.x <= groupRect.maxX else { continue }

            if group == [draggingItem] {
                return nil
            }

            var insertIndex = group.count
            for (itemIdx, item) in group.enumerated() {
                if let rect = itemFrames[item], point.x < rect.midX {
                    insertIndex = itemIdx
                    break
                }
            }
            return .joinGroup(groupIndex: groupIdx, insertIndex: insertIndex)
        }

        return nil
    }

    static func estimatedItemWidth(
        _ item: ToolbarActionItem,
        labels: Set<ToolbarActionItem>,
        inGroupCount: Int,
        isSearchExpanded: Bool = false,
        effectiveSearchWidth: CGFloat = 196
    ) -> CGFloat {
        let labelExtra: CGFloat
        if labels.contains(item) {
            labelExtra = (item == .viewMode) ? 155 : (CGFloat(item.title.count) * 7.2 + 16)
        } else {
            labelExtra = 0
        }

        switch item {
        case .viewMode:
            return 106 + labelExtra
        case .sort:
            return 42 + labelExtra
        case .search:
            if isSearchExpanded {
                return effectiveSearchWidth + (inGroupCount > 1 ? 8 : 0)
            }
            return 30 + labelExtra
        default:
            return 30 + labelExtra
        }
    }

    static func estimatedGroupWidth(
        _ group: [ToolbarActionItem],
        labels: Set<ToolbarActionItem>,
        dividersAfterItems: Set<ToolbarActionItem> = [],
        isSearchExpanded: Bool = false,
        effectiveSearchWidth: CGFloat = 196
    ) -> CGFloat {
        guard !group.isEmpty else { return 0 }
        var width: CGFloat = 10 + CGFloat(max(0, group.count - 1)) * 4
        for (idx, item) in group.enumerated() {
            width += estimatedItemWidth(
                item,
                labels: labels,
                inGroupCount: group.count,
                isSearchExpanded: isSearchExpanded,
                effectiveSearchWidth: effectiveSearchWidth
            )
            if idx < group.count - 1 && dividersAfterItems.contains(item) {
                width += 9
            }
        }
        return width
    }

    static func totalEstimatedWidth(
        for indexedGroups: [(originalIndex: Int, items: [ToolbarActionItem])],
        labels: Set<ToolbarActionItem>,
        dividersAfterItems: Set<ToolbarActionItem> = [],
        dividersAfterGroupIndices: Set<Int> = [],
        isBrowsingTrash: Bool = false,
        isSearchExpanded: Bool = false,
        effectiveSearchWidth: CGFloat = 196,
        hasOverflow: Bool
    ) -> CGFloat {
        var total: CGFloat = CGFloat(max(0, indexedGroups.count - 1)) * 8 + 8
        for entry in indexedGroups {
            total += estimatedGroupWidth(
                entry.items,
                labels: labels,
                dividersAfterItems: dividersAfterItems,
                isSearchExpanded: isSearchExpanded,
                effectiveSearchWidth: effectiveSearchWidth
            )
            if dividersAfterGroupIndices.contains(entry.originalIndex) {
                total += 14
            }
        }
        if isBrowsingTrash {
            total += 84
        }
        // Reserve 16pt min spacer + 46pt overflow button when overflowing (62pt),
        // and 52pt spacer reserve when full so transitioning to overflow never requires
        // dropping two items at once just to pay for the "…" button's width.
        total += hasOverflow ? 62 : 52
        return total
    }

    static func layoutPlan(
        for groups: [[ToolbarActionItem]],
        availableWidth: CGFloat,
        dividersAfterItems: Set<ToolbarActionItem> = [],
        dividersAfterGroupIndices: Set<Int> = [],
        isBrowsingTrash: Bool = false,
        isSearchExpanded: Bool = false,
        effectiveSearchWidth: CGFloat = 196
    ) -> (visibleGroups: [(originalIndex: Int, items: [ToolbarActionItem])], overflowItems: [ToolbarActionItem]) {
        var currentGroups: [(originalIndex: Int, items: [ToolbarActionItem])] = groups.enumerated().map {
            (originalIndex: $0.offset, items: $0.element)
        }
        var overflowSet = Set<ToolbarActionItem>()

        // Core items (viewMode, forward, back, search) have overflowPriority >= 100 and stay visible.
        let maxOverflowablePriority = ToolbarActionItem.up.overflowPriority

        while totalEstimatedWidth(
            for: currentGroups,
            labels: [],
            dividersAfterItems: dividersAfterItems,
            dividersAfterGroupIndices: dividersAfterGroupIndices,
            isBrowsingTrash: isBrowsingTrash,
            isSearchExpanded: isSearchExpanded,
            effectiveSearchWidth: effectiveSearchWidth,
            hasOverflow: !overflowSet.isEmpty
        ) > availableWidth {
            var bestCandidate: (groupIdx: Int, itemIdx: Int, item: ToolbarActionItem)?

            for (gIdx, groupEntry) in currentGroups.enumerated() {
                for (iIdx, item) in groupEntry.items.enumerated() where item.overflowPriority <= maxOverflowablePriority {
                    if let currentBest = bestCandidate {
                        if item.overflowPriority < currentBest.item.overflowPriority
                            || (item.overflowPriority == currentBest.item.overflowPriority && gIdx >= currentBest.groupIdx) {
                            bestCandidate = (gIdx, iIdx, item)
                        }
                    } else {
                        bestCandidate = (gIdx, iIdx, item)
                    }
                }
            }

            guard let candidate = bestCandidate else { break }
            let removed = currentGroups[candidate.groupIdx].items.remove(at: candidate.itemIdx)
            if currentGroups[candidate.groupIdx].items.isEmpty {
                currentGroups.remove(at: candidate.groupIdx)
            }
            overflowSet.insert(removed)
        }

        // Preserve natural left-to-right toolbar order inside the overflow menu.
        let orderedOverflow = groups.flatMap { $0 }.filter { overflowSet.contains($0) }
        return (currentGroups, orderedOverflow)
    }

    static func expandingSpacerVisibleOffsets(
        for visibleGroups: [(originalIndex: Int, items: [ToolbarActionItem])],
        fixedSpacesAfterGroupIndices: Set<Int>,
        spacerAfterGroupIndex: Int?
    ) -> Set<Int> {
        guard visibleGroups.count >= 2 else { return [] }
        var configured = fixedSpacesAfterGroupIndices
        if let spacerAfterGroupIndex {
            configured.insert(spacerAfterGroupIndex)
        }

        var result = Set<Int>()
        if !configured.isEmpty {
            for offset in 0..<(visibleGroups.count - 1) {
                let currOrig = visibleGroups[offset].originalIndex
                let nextOrig = visibleGroups[offset + 1].originalIndex
                if configured.contains(where: { currOrig <= $0 && $0 < nextOrig }) {
                    result.insert(offset)
                }
            }
        }

        if result.isEmpty {
            if let searchOffset = visibleGroups.lastIndex(where: { $0.items.contains(.search) }), searchOffset > 0 {
                result.insert(searchOffset - 1)
            } else {
                result.insert(visibleGroups.count - 2)
            }
        }
        return result
    }
}

struct AppSettings: Codable, Equatable {
    var defaultViewMode: ViewMode = .list
    var showsHiddenFiles: Bool = false
    var startupLocation: StartupLocation = .home
    var customStartupPath: String?
    var sortingChoice: SortingChoice = .natural
    var alwaysShowTabBar: Bool = false
    var rememberOpenedTabs: Bool = true
    var openNewTabAfterLastTab: Bool = true
    var startInSplitView: Bool = false
    var showFullPathInTitlebar: Bool = false
    var editableLocationByDefault: Bool = false
    var showPasteBarAfterCopying: Bool = true
    var statusBarMode: StatusBarDisplayMode = .fullWidth
    var showZoomSliderInStatusBar: Bool = true
    var confirmMoveToTrash: Bool = true
    var confirmEmptyTrash: Bool = true
    var confirmPermanentDelete: Bool = true
    var showPermanentDeleteCommand: Bool = false
    var directorySizeMode: DirectorySizeMode = .contentCount
    var permissionsFormat: PermissionsDisplayFormat = .symbolic
    var useRelativeDates: Bool = true
    var expandableFoldersInDetails: Bool = true
    var browseThroughArchives: Bool = false
    var showsToolbarLabels: Bool = false
    var toolbarTextPosition: ToolbarTextPosition = .iconsOnly
    var toolbarItemsWithLabels: Set<ToolbarActionItem> = []
    var hiddenToolbarItems: Set<ToolbarActionItem> = []
    var toolbarGroups: [[ToolbarActionItem]] = ToolbarActionItem.defaultGroups
    var dividersAfterItems: Set<ToolbarActionItem> = []
    var dividersAfterGroupIndices: Set<Int> = []
    var fixedSpacesAfterGroupIndices: Set<Int> = []
    var spacerAfterGroupIndex: Int? = nil
    var isToolbarLocked: Bool = false

    private enum CodingKeys: String, CodingKey {
        case defaultViewMode
        case showsHiddenFiles
        case startupLocation
        case customStartupPath
        case sortingChoice
        case alwaysShowTabBar
        case rememberOpenedTabs
        case openNewTabAfterLastTab
        case startInSplitView
        case showFullPathInTitlebar
        case editableLocationByDefault
        case showPasteBarAfterCopying
        case statusBarMode
        case showZoomSliderInStatusBar
        case confirmMoveToTrash
        case confirmEmptyTrash
        case confirmPermanentDelete
        case showPermanentDeleteCommand
        case directorySizeMode
        case permissionsFormat
        case useRelativeDates
        case expandableFoldersInDetails
        case browseThroughArchives
        case showsToolbarLabels
        case toolbarTextPosition
        case toolbarItemsWithLabels
        case hiddenToolbarItems
        case toolbarGroups
        case dividersAfterItems
        case dividersAfterGroupIndices
        case fixedSpacesAfterGroupIndices
        case spacerAfterGroupIndex
        case isToolbarLocked
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultViewMode = try container.decodeIfPresent(ViewMode.self, forKey: .defaultViewMode) ?? .list
        showsHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showsHiddenFiles) ?? false
        startupLocation = try container.decodeIfPresent(StartupLocation.self, forKey: .startupLocation) ?? .home
        customStartupPath = try container.decodeIfPresent(String.self, forKey: .customStartupPath)
        sortingChoice = try container.decodeIfPresent(SortingChoice.self, forKey: .sortingChoice) ?? .natural
        alwaysShowTabBar = try container.decodeIfPresent(Bool.self, forKey: .alwaysShowTabBar) ?? false
        rememberOpenedTabs = try container.decodeIfPresent(Bool.self, forKey: .rememberOpenedTabs) ?? true
        openNewTabAfterLastTab = try container.decodeIfPresent(Bool.self, forKey: .openNewTabAfterLastTab) ?? true
        startInSplitView = try container.decodeIfPresent(Bool.self, forKey: .startInSplitView) ?? false
        showFullPathInTitlebar = try container.decodeIfPresent(Bool.self, forKey: .showFullPathInTitlebar) ?? false
        editableLocationByDefault = try container.decodeIfPresent(Bool.self, forKey: .editableLocationByDefault) ?? false
        showPasteBarAfterCopying = try container.decodeIfPresent(Bool.self, forKey: .showPasteBarAfterCopying) ?? true
        statusBarMode = try container.decodeIfPresent(StatusBarDisplayMode.self, forKey: .statusBarMode) ?? .fullWidth
        showZoomSliderInStatusBar = try container.decodeIfPresent(Bool.self, forKey: .showZoomSliderInStatusBar) ?? true
        confirmMoveToTrash = try container.decodeIfPresent(Bool.self, forKey: .confirmMoveToTrash) ?? true
        confirmEmptyTrash = try container.decodeIfPresent(Bool.self, forKey: .confirmEmptyTrash) ?? true
        confirmPermanentDelete = try container.decodeIfPresent(Bool.self, forKey: .confirmPermanentDelete) ?? true
        showPermanentDeleteCommand = try container.decodeIfPresent(Bool.self, forKey: .showPermanentDeleteCommand) ?? false
        directorySizeMode = try container.decodeIfPresent(DirectorySizeMode.self, forKey: .directorySizeMode) ?? .contentCount
        permissionsFormat = try container.decodeIfPresent(PermissionsDisplayFormat.self, forKey: .permissionsFormat) ?? .symbolic
        useRelativeDates = try container.decodeIfPresent(Bool.self, forKey: .useRelativeDates) ?? true
        expandableFoldersInDetails = try container.decodeIfPresent(Bool.self, forKey: .expandableFoldersInDetails) ?? true
        browseThroughArchives = try container.decodeIfPresent(Bool.self, forKey: .browseThroughArchives) ?? false
        showsToolbarLabels = try container.decodeIfPresent(Bool.self, forKey: .showsToolbarLabels) ?? false
        toolbarTextPosition = try container.decodeIfPresent(ToolbarTextPosition.self, forKey: .toolbarTextPosition)
            ?? (showsToolbarLabels ? .textAlongsideIcons : .iconsOnly)
        toolbarItemsWithLabels = try container.decodeIfPresent(Set<ToolbarActionItem>.self, forKey: .toolbarItemsWithLabels) ?? []
        hiddenToolbarItems = try container.decodeIfPresent(Set<ToolbarActionItem>.self, forKey: .hiddenToolbarItems) ?? []
        dividersAfterItems = try container.decodeIfPresent(Set<ToolbarActionItem>.self, forKey: .dividersAfterItems) ?? []
        dividersAfterGroupIndices = try container.decodeIfPresent(Set<Int>.self, forKey: .dividersAfterGroupIndices) ?? []
        fixedSpacesAfterGroupIndices = try container.decodeIfPresent(Set<Int>.self, forKey: .fixedSpacesAfterGroupIndices) ?? []
        spacerAfterGroupIndex = try container.decodeIfPresent(Int.self, forKey: .spacerAfterGroupIndex)
        isToolbarLocked = try container.decodeIfPresent(Bool.self, forKey: .isToolbarLocked) ?? false
        if let decodedGroups = try container.decodeIfPresent([[ToolbarActionItem]].self, forKey: .toolbarGroups) {
            let normalized = ToolbarLayoutEngine.normalizedGroups(decodedGroups)
            let isLegacyAllSingletons = normalized.count == ToolbarActionItem.allCases.count
                && normalized.allSatisfy { $0.count == 1 }
            toolbarGroups = isLegacyAllSingletons ? ToolbarActionItem.defaultGroups : normalized
        } else {
            toolbarGroups = ToolbarActionItem.defaultGroups
        }
    }

    func showsLabel(for item: ToolbarActionItem) -> Bool {
        showsToolbarLabels
            || toolbarTextPosition != .iconsOnly
            || toolbarItemsWithLabels.contains(item)
    }

    mutating func toggleLabel(for item: ToolbarActionItem) {
        if showsToolbarLabels || toolbarTextPosition == .textAlongsideIcons {
            showsToolbarLabels = false
            toolbarTextPosition = .iconsOnly
            toolbarItemsWithLabels = Set(ToolbarActionItem.allCases.filter { $0 != item })
        } else if toolbarItemsWithLabels.contains(item) {
            toolbarItemsWithLabels.remove(item)
        } else {
            toolbarItemsWithLabels.insert(item)
        }
    }

    mutating func toggleHidden(for item: ToolbarActionItem) {
        if hiddenToolbarItems.contains(item) {
            hiddenToolbarItems.remove(item)
        } else if hiddenToolbarItems.count < ToolbarActionItem.allCases.count - 1 {
            hiddenToolbarItems.insert(item)
        }
    }

    func activeConfigEntries() -> [ToolbarConfigEntry] {
        let visibleGroups = ToolbarLayoutEngine.normalizedGroups(toolbarGroups).compactMap { group -> [ToolbarActionItem]? in
            let filtered = group.filter { !hiddenToolbarItems.contains($0) }
            return filtered.isEmpty ? nil : filtered
        }
        var entries: [ToolbarConfigEntry] = []
        for (groupIdx, group) in visibleGroups.enumerated() {
            for (itemIdx, item) in group.enumerated() {
                entries.append(.action(item))
                if itemIdx < group.count - 1 && dividersAfterItems.contains(item) {
                    entries.append(.divider(UUID()))
                }
            }
            if dividersAfterGroupIndices.contains(groupIdx) {
                entries.append(.divider(UUID()))
            }
            if fixedSpacesAfterGroupIndices.contains(groupIdx) {
                entries.append(.fixedSpacer(UUID()))
            }
            if spacerAfterGroupIndex == groupIdx {
                entries.append(.expandingSpacer)
            }
            if groupIdx < visibleGroups.count - 1 {
                let alreadyHasGroupBoundary = dividersAfterGroupIndices.contains(groupIdx)
                    || fixedSpacesAfterGroupIndices.contains(groupIdx)
                    || spacerAfterGroupIndex == groupIdx
                if !alreadyHasGroupBoundary {
                    entries.append(.separator(UUID()))
                }
            }
        }
        return entries
    }

    mutating func applyConfigEntries(_ entries: [ToolbarConfigEntry]) {
        var newGroups: [[ToolbarActionItem]] = []
        var currentGroup: [ToolbarActionItem] = []
        var newDividersAfterItems = Set<ToolbarActionItem>()
        var newDividersAfterGroups = Set<Int>()
        var newFixedSpacesAfterGroups = Set<Int>()
        var newSpacerAfterGroupIndex: Int? = nil
        var activeActions = Set<ToolbarActionItem>()
        var pendingDividerForCurrentItem: ToolbarActionItem? = nil

        for entry in entries {
            switch entry {
            case .action(let item):
                if activeActions.insert(item).inserted {
                    if let prevItem = pendingDividerForCurrentItem {
                        newDividersAfterItems.insert(prevItem)
                        pendingDividerForCurrentItem = nil
                    }
                    currentGroup.append(item)
                }
            case .divider:
                if let lastItem = currentGroup.last {
                    pendingDividerForCurrentItem = lastItem
                } else if !newGroups.isEmpty {
                    newDividersAfterGroups.insert(newGroups.count - 1)
                }
            case .fixedSpacer:
                if let prev = pendingDividerForCurrentItem {
                    _ = prev
                    pendingDividerForCurrentItem = nil
                    if !currentGroup.isEmpty {
                        newGroups.append(currentGroup)
                        currentGroup = []
                    }
                    if !newGroups.isEmpty {
                        newDividersAfterGroups.insert(newGroups.count - 1)
                    }
                }
                if !currentGroup.isEmpty {
                    newGroups.append(currentGroup)
                    currentGroup = []
                }
                if !newGroups.isEmpty {
                    newFixedSpacesAfterGroups.insert(newGroups.count - 1)
                }
            case .separator:
                if pendingDividerForCurrentItem != nil {
                    pendingDividerForCurrentItem = nil
                    if !currentGroup.isEmpty {
                        newGroups.append(currentGroup)
                        currentGroup = []
                    }
                    if !newGroups.isEmpty {
                        newDividersAfterGroups.insert(newGroups.count - 1)
                    }
                } else if !currentGroup.isEmpty {
                    newGroups.append(currentGroup)
                    currentGroup = []
                }
            case .expandingSpacer:
                if pendingDividerForCurrentItem != nil {
                    pendingDividerForCurrentItem = nil
                    if !currentGroup.isEmpty {
                        newGroups.append(currentGroup)
                        currentGroup = []
                    }
                    if !newGroups.isEmpty {
                        newDividersAfterGroups.insert(newGroups.count - 1)
                    }
                } else if !currentGroup.isEmpty {
                    newGroups.append(currentGroup)
                    currentGroup = []
                }
                if !newGroups.isEmpty {
                    newSpacerAfterGroupIndex = newGroups.count - 1
                }
            }
        }
        if pendingDividerForCurrentItem != nil && !currentGroup.isEmpty {
            newGroups.append(currentGroup)
            currentGroup = []
            newDividersAfterGroups.insert(newGroups.count - 1)
        } else if !currentGroup.isEmpty {
            newGroups.append(currentGroup)
        }

        let newHidden = Set(ToolbarActionItem.allCases).subtracting(activeActions)
        if newHidden.count < ToolbarActionItem.allCases.count {
            hiddenToolbarItems = newHidden
        } else {
            hiddenToolbarItems = []
        }

        var fullGroups = newGroups
        for hiddenItem in ToolbarActionItem.allCases where newHidden.contains(hiddenItem) {
            fullGroups.append([hiddenItem])
        }
        toolbarGroups = ToolbarLayoutEngine.normalizedGroups(fullGroups)
        dividersAfterItems = newDividersAfterItems
        dividersAfterGroupIndices = newDividersAfterGroups
        fixedSpacesAfterGroupIndices = newFixedSpacesAfterGroups
        spacerAfterGroupIndex = newSpacerAfterGroupIndex
    }

    mutating func resetToolbarToDefaults() {
        toolbarGroups = ToolbarActionItem.defaultGroups
        hiddenToolbarItems.removeAll()
        dividersAfterItems.removeAll()
        dividersAfterGroupIndices.removeAll()
        fixedSpacesAfterGroupIndices.removeAll()
        spacerAfterGroupIndex = nil
        showsToolbarLabels = false
        toolbarTextPosition = .iconsOnly
        toolbarItemsWithLabels.removeAll()
    }
}

extension AppSettings {
    var startupURL: URL {
        switch startupLocation {
        case .home:
            return FileManager.default.homeDirectoryForCurrentUser
        case .desktop:
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        case .custom:
            var isDirectory: ObjCBool = false
            guard let customStartupPath,
                  FileManager.default.fileExists(atPath: customStartupPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return FileManager.default.homeDirectoryForCurrentUser
            }
            return URL(fileURLWithPath: customStartupPath, isDirectory: true)
        }
    }
}
