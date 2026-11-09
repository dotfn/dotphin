import AppKit
import Foundation
import Observation

/// 4-way directional arrow navigation (`←`, `→`, `↑`, `↓`) across Grid, Compact, List, and Details views.
enum ArrowDirection: String, Equatable, Sendable {
    case up
    case down
    case left
    case right
}

/// KDE Dolphin's `KFileItemModelFilter::FilterMode` (`src/filterbar/filterbar.cpp` & `kfileitemmodelfilter.h`).
enum FilterPatternMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case plainText
    case glob
    case regex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plainText: return "Texto plano"
        case .glob: return "Patrón Glob (*, ?)"
        case .regex: return "Expresión regular"
        }
    }
}

@Observable
final class BrowserViewModel {
    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    private(set) var error: DirectoryReadError?
    private(set) var viewProperties: ViewProperties
    private(set) var selectedIDs: Set<FileItem.ID> = []
    /// Anchor for Shift-click / Shift-arrow range selection.
    private var selectionAnchor: FileItem.ID?
    /// Moving head for Shift-arrow directional selection.
    private var selectionCursor: FileItem.ID?
    /// Active column count reported by `IconGridView` / `CompactGridView` for 2D `↑`/`↓` navigation.
    var gridColumnsCount: Int = 5

    /// Dolphin's Selection Mode (`src/selectionmode/`).
    var isSelectionModeActive: Bool = false

    /// Every selected item that is currently visible (folder listing or search results).
    var selectedItems: [FileItem] {
        guard !selectedIDs.isEmpty else { return [] }
        var seen = Set<FileItem.ID>()
        return (items + searchResults).filter { selectedIDs.contains($0.id) && seen.insert($0.id).inserted }
    }

    /// The selected item when exactly one is selected (info panel, rename, toolbar state).
    var selectedItem: FileItem? {
        let current = selectedItems
        return current.count == 1 ? current[0] : nil
    }

    var filterText: String = "" {
        didSet {
            let visible = Set(filteredItems.map(\.id))
            selectedIDs = selectedIDs.intersection(visible)
        }
    }

    /// Dolphin's `FilterBar` (`src/filterbar/filterbar.cpp`) options:
    var filterMode: FilterPatternMode = .plainText {
        didSet {
            let visible = Set(filteredItems.map(\.id))
            selectedIDs = selectedIDs.intersection(visible)
        }
    }

    var isFilterCaseSensitive: Bool = false {
        didSet {
            let visible = Set(filteredItems.map(\.id))
            selectedIDs = selectedIDs.intersection(visible)
        }
    }

    /// When true (`m_lockButton` in `FilterBar`), changing folders keeps `filterText` active.
    var isFilterLocked: Bool = false

    /// Dedicated bottom/top `FilterBar` visibility (`Ctrl+I` / `⌘/`).
    var isFilterBarVisible: Bool = false

    /// Indicates whether `filterText` is a valid pattern in the current `filterMode` (`updateInvalidPatternView` in `filterbar.cpp`).
    var isFilterPatternValid: Bool {
        guard !filterText.isEmpty, filterMode == .regex else { return true }
        let options: NSRegularExpression.Options = isFilterCaseSensitive ? [] : [.caseInsensitive]
        return (try? NSRegularExpression(pattern: filterText, options: options)) != nil
    }

    var searchTypeFilter: SearchTypeFilter = .all {
        didSet {
            let visible = Set(filteredItems.map(\.id))
            selectedIDs = selectedIDs.intersection(visible)
            if !searchQuery.isEmpty {
                performSearch()
            }
        }
    }

    var searchDateFilter: SearchDateFilter = .any {
        didSet {
            let visible = Set(filteredItems.map(\.id))
            selectedIDs = selectedIDs.intersection(visible)
            if !searchQuery.isEmpty {
                performSearch()
            }
        }
    }

    var searchSizeFilter: SearchSizeFilter = .any {
        didSet {
            let visible = Set(filteredItems.map(\.id))
            selectedIDs = selectedIDs.intersection(visible)
            if !searchQuery.isEmpty {
                performSearch()
            }
        }
    }

    var searchColorTagFilter: FinderColorTag = .none {
        didSet {
            let visible = Set(filteredItems.map(\.id))
            selectedIDs = selectedIDs.intersection(visible)
            if !searchQuery.isEmpty {
                performSearch()
            }
        }
    }

    var searchLocationScope: SearchLocationScope = .fromHere {
        didSet {
            if !searchQuery.isEmpty {
                performSearch()
            }
        }
    }

    var searchMatchMode: SearchMatchMode = .filename {
        didSet {
            if !searchQuery.isEmpty {
                performSearch()
            }
        }
    }

    var filteredItems: [FileItem] {
        if filterText.isEmpty && !hasActiveFacets {
            return items
        }
        let compiledRegex = compiledFilterRegex()
        return items.filter { item in
            let matchesText: Bool
            if filterText.isEmpty {
                matchesText = true
            } else if filterMode == .plainText {
                matchesText = isFilterCaseSensitive
                    ? item.name.contains(filterText)
                    : item.name.localizedCaseInsensitiveContains(filterText)
            } else if let regex = compiledRegex {
                let range = NSRange(item.name.startIndex..<item.name.endIndex, in: item.name)
                matchesText = regex.firstMatch(in: item.name, options: [], range: range) != nil
            } else {
                matchesText = false
            }
            let matchesColorTag = searchColorTagFilter == .none || item.colorTag == searchColorTagFilter
            return matchesText
                && searchTypeFilter.matches(item)
                && searchDateFilter.matches(item)
                && searchSizeFilter.matches(item)
                && matchesColorTag
        }
    }

    private func compiledFilterRegex() -> NSRegularExpression? {
        guard !filterText.isEmpty else { return nil }
        let options: NSRegularExpression.Options = isFilterCaseSensitive ? [] : [.caseInsensitive]
        switch filterMode {
        case .plainText:
            return nil
        case .glob:
            var regexPattern = ""
            for ch in filterText {
                switch ch {
                case "*": regexPattern.append(".*")
                case "?": regexPattern.append(".")
                default:
                    regexPattern.append(NSRegularExpression.escapedPattern(for: String(ch)))
                }
            }
            return try? NSRegularExpression(pattern: regexPattern, options: options)
        case .regex:
            return try? NSRegularExpression(pattern: filterText, options: options)
        }
    }

    /// Evaluates `KFileItemModelFilter::matchesPattern` (`src/kitemviews/private/kfileitemmodelfilter.cpp`).
    func matchesFilterPattern(_ itemName: String) -> Bool {
        guard !filterText.isEmpty else { return true }
        if filterMode == .plainText {
            return isFilterCaseSensitive
                ? itemName.contains(filterText)
                : itemName.localizedCaseInsensitiveContains(filterText)
        }
        guard let regex = compiledFilterRegex() else { return false }
        let range = NSRange(itemName.startIndex..<itemName.endIndex, in: itemName)
        return regex.firstMatch(in: itemName, options: [], range: range) != nil
    }

    var groupedFilteredItems: [FileItemGroup] {
        filteredItems.grouped(by: viewProperties.effectiveGroupField, foldersFirst: viewProperties.sortFoldersFirst)
    }

    var hasActiveFacets: Bool {
        searchTypeFilter != .all || searchDateFilter != .any || searchSizeFilter != .any || searchColorTagFilter != .none
    }

    private(set) var operationError: FileOperationError?

    var searchQuery: String = "" {
        didSet {
            selectedIDs = []
        }
    }
    private(set) var searchResults: [FileItem] = []

    private(set) var gitStatuses: [String: GitFileStatus] = [:]
    private(set) var isGitRepository: Bool = false
    private(set) var gitBranchName: String? = nil
    private(set) var availableCapacity: Int64?
    /// Indicates whether `currentURL` is writable (`DolphinView::m_isFolderWritable` in `src/views/dolphinview.cpp` & `Admin::Bar`).
    private(set) var isCurrentDirectoryWritable: Bool = true
    /// Type-ahead selection buffer (`KItemListController::typeAheadUsed` in `src/views/dolphinview.cpp`).
    private(set) var typeAheadBuffer: String = ""
    @ObservationIgnored private var lastTypeAheadTimestamp: Date = .distantPast
    @ObservationIgnored private var typeAheadResetWorkItem: DispatchWorkItem?
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []
    private(set) var history = FileOperationHistory()
    @ObservationIgnored private let clipboard = FileClipboard()

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    private var reader: DirectoryReader
    private let store: ViewPropertiesStore
    private let operations: FileOperationsService
    private let search: SearchService
    private let trashURL: URL
    private let gitStatus: GitStatusProvider

    var isBrowsingTrash: Bool {
        currentURL.standardizedFileURL.path == trashURL.standardizedFileURL.path
    }

    var effectiveShowsHiddenFiles: Bool {
        viewProperties.showsHiddenFilesOverride ?? reader.showsHiddenFiles
    }

    init(
        startingAt url: URL,
        reader: DirectoryReader = DirectoryReader(showsHiddenFiles: AppSettingsStore().settings().showsHiddenFiles),
        store: ViewPropertiesStore = ViewPropertiesStore(),
        operations: FileOperationsService = FileOperationsService(),
        search: SearchService = SearchService(),
        trashURL: URL = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"),
        gitStatus: GitStatusProvider = GitStatusProvider()
    ) {
        self.currentURL = url
        self.reader = reader
        self.store = store
        self.operations = operations
        self.search = search
        self.trashURL = trashURL
        self.gitStatus = gitStatus
        self.viewProperties = store.properties(for: url)
        load(url)
    }

    func navigate(to url: URL) {
        if url.standardizedFileURL.path != currentURL.standardizedFileURL.path {
            backStack.append(currentURL)
            forwardStack.removeAll()
        }
        applyNavigation(to: url)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        applyNavigation(to: previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        applyNavigation(to: next)
    }

    /// Jumps directly to an entry in `backStack` (`slotGoBack` in `dolphinmainwindow.cpp`).
    func jumpBack(toStackIndex index: Int) {
        guard backStack.indices.contains(index) else { return }
        let target = backStack[index]
        let skipped = Array(backStack[(index + 1)...].reversed())
        backStack.removeSubrange(index..<backStack.count)
        forwardStack.append(currentURL)
        forwardStack.append(contentsOf: skipped)
        applyNavigation(to: target)
    }

    /// Jumps directly to an entry in `forwardStack` (`slotGoForward` in `dolphinmainwindow.cpp`).
    func jumpForward(toStackIndex index: Int) {
        guard forwardStack.indices.contains(index) else { return }
        let target = forwardStack[index]
        let skipped = Array(forwardStack[(index + 1)...].reversed())
        forwardStack.removeSubrange(index..<forwardStack.count)
        backStack.append(currentURL)
        backStack.append(contentsOf: skipped)
        applyNavigation(to: target)
    }

    private func applyNavigation(to url: URL) {
        currentURL = url
        viewProperties = store.properties(for: url)
        selectedIDs = []
        if !isFilterLocked {
            filterText = ""
        }
        searchQuery = ""
        searchTypeFilter = .all
        searchDateFilter = .any
        searchSizeFilter = .any
        searchColorTagFilter = .none
        searchResults = []
        load(url)
    }

    func performSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        let rootURL = searchLocationScope == .everywhere
            ? FileManager.default.homeDirectoryForCurrentUser
            : currentURL
        searchResults = search.search(
            for: searchQuery,
            in: rootURL,
            typeFilter: searchTypeFilter,
            dateFilter: searchDateFilter,
            sizeFilter: searchSizeFilter,
            colorTagFilter: searchColorTagFilter,
            matchMode: searchMatchMode
        )
    }

    func resetSearchAndFilters() {
        filterText = ""
        searchQuery = ""
        searchTypeFilter = .all
        searchDateFilter = .any
        searchSizeFilter = .any
        searchColorTagFilter = .none
        searchLocationScope = .fromHere
        searchMatchMode = .filename
        searchResults = []
    }

    /// Saves the current search configuration into the Places sidebar (`Search::Bar::slotSaveSearch`).
    @discardableResult
    func saveCurrentSearch(named customName: String? = nil, using provider: PlacesProvider = PlacesProvider()) -> SavedSearchItem? {
        guard !searchQuery.isEmpty || hasActiveFacets else { return nil }
        let defaultTitle: String = {
            if !searchQuery.isEmpty {
                return "«\(searchQuery)» en \(currentURL.lastPathComponent)"
            }
            var parts: [String] = []
            if searchTypeFilter != .all { parts.append(searchTypeFilter.title) }
            if searchDateFilter != .any { parts.append(searchDateFilter.title) }
            if searchSizeFilter != .any { parts.append(searchSizeFilter.title) }
            if searchColorTagFilter != .none { parts.append(searchColorTagFilter.title) }
            return "\(parts.joined(separator: " · ")) (\(currentURL.lastPathComponent))"
        }()
        let saved = SavedSearchItem(
            name: customName ?? defaultTitle,
            directoryURL: currentURL,
            query: searchQuery,
            typeFilter: searchTypeFilter,
            dateFilter: searchDateFilter,
            sizeFilter: searchSizeFilter,
            colorTagFilter: searchColorTagFilter,
            locationScope: searchLocationScope,
            matchMode: searchMatchMode
        )
        provider.addSavedSearch(saved)
        return saved
    }

    /// Restores a saved search from the Places sidebar (`Saved Searches`).
    func applySavedSearch(_ saved: SavedSearchItem) {
        if saved.directoryURL.standardizedFileURL.path != currentURL.standardizedFileURL.path,
           FileManager.default.fileExists(atPath: saved.directoryURL.path) {
            navigate(to: saved.directoryURL)
        }
        searchTypeFilter = saved.typeFilter
        searchDateFilter = saved.dateFilter
        searchSizeFilter = saved.sizeFilter
        searchColorTagFilter = saved.colorTagFilter
        searchLocationScope = saved.locationScope
        searchMatchMode = saved.matchMode
        searchQuery = saved.query
        if !searchQuery.isEmpty {
            performSearch()
        }
    }

    /// Navigates to the parent folder of a search result item and selects it (`DolphinContextMenu::addOpenParentFolderActions`).
    func openContainingFolder(of item: FileItem) {
        let parent = item.url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path) else { return }
        navigate(to: parent)
        if let match = items.first(where: { $0.url.standardizedFileURL == item.url.standardizedFileURL }) {
            select(match)
        }
    }

    func select(_ item: FileItem?) {
        selectedIDs = item.map { [$0.id] } ?? []
        selectionAnchor = item?.id
        selectionCursor = item?.id
    }

    func setSelection(_ ids: Set<FileItem.ID>) {
        let resolvedLookup = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id.resolvingSymlinksInPath(), $0.id) }
        )
        let normalized = Set(ids.map { resolvedLookup[$0.resolvingSymlinksInPath()] ?? $0 })
        selectedIDs = normalized
        if normalized.count == 1 {
            selectionAnchor = normalized.first
            selectionCursor = normalized.first
        }
    }

    func deselectAll() {
        selectedIDs = []
        selectionAnchor = nil
        selectionCursor = nil
    }

    /// Items in their visual display order (respecting search results and `showInGroups` sections).
    var orderedVisibleItems: [FileItem] {
        if !searchQuery.isEmpty {
            return searchResults
        }
        if viewProperties.showInGroups {
            let groups = groupedFilteredItems
            if !groups.isEmpty {
                return groups.flatMap(\.items)
            }
        }
        return filteredItems
    }

    /// Moves selection by `offset` (`-1`, `+1`, etc.) within the visible list (`orderedVisibleItems`),
    /// matching macOS Finder arrow-key navigation.
    func selectAdjacentItem(by offset: Int) {
        let visible = orderedVisibleItems
        guard !visible.isEmpty else { return }
        if let cursor = selectionCursor ?? selectionAnchor ?? selectedIDs.first,
           let currentIdx = visible.firstIndex(where: { $0.id == cursor }) {
            let nextIdx = max(0, min(visible.count - 1, currentIdx + offset))
            select(visible[nextIdx])
        } else {
            select(offset >= 0 ? visible.first : visible.last)
        }
    }

    /// Navigates selection in all 4 directions (`↑`, `↓`, `←`, `→`) across 2D Grids (`.icons`, `.compact`,
    /// both ungrouped and grouped) and 1D Lists/Tables (`.list`, `.details`, and search results).
    func navigateSelection(direction: ArrowDirection, extendSelection: Bool = false) {
        let visible = orderedVisibleItems
        guard !visible.isEmpty else { return }

        let activeCursorID = selectionCursor ?? selectionAnchor ?? selectedIDs.first
        guard let cursorID = activeCursorID,
              visible.contains(where: { $0.id == cursorID }) else {
            switch direction {
            case .down, .right:
                select(visible.first)
            case .up, .left:
                select(visible.last)
            }
            return
        }

        let isGridMode = searchQuery.isEmpty && (viewProperties.mode == .icons || viewProperties.mode == .compact)
        let cols = max(1, gridColumnsCount)
        var targetItem: FileItem?

        if isGridMode && viewProperties.showInGroups {
            let groups = groupedFilteredItems
            if !groups.isEmpty,
               let groupIdx = groups.firstIndex(where: { $0.items.contains(where: { $0.id == cursorID }) }),
               let itemIdx = groups[groupIdx].items.firstIndex(where: { $0.id == cursorID }) {
                let currentGroupItems = groups[groupIdx].items
                let col = itemIdx % cols
                let row = itemIdx / cols
                let groupRows = (currentGroupItems.count + cols - 1) / cols

                switch direction {
                case .left:
                    if itemIdx > 0 {
                        targetItem = currentGroupItems[itemIdx - 1]
                    } else if groupIdx > 0 {
                        targetItem = groups[groupIdx - 1].items.last
                    } else {
                        targetItem = currentGroupItems[itemIdx]
                    }
                case .right:
                    if itemIdx + 1 < currentGroupItems.count {
                        targetItem = currentGroupItems[itemIdx + 1]
                    } else if groupIdx + 1 < groups.count {
                        targetItem = groups[groupIdx + 1].items.first
                    } else {
                        targetItem = currentGroupItems[itemIdx]
                    }
                case .up:
                    if row > 0 {
                        targetItem = currentGroupItems[itemIdx - cols]
                    } else if groupIdx > 0 {
                        let prevItems = groups[groupIdx - 1].items
                        let prevLastRowStart = ((prevItems.count - 1) / cols) * cols
                        let targetIdx = min(prevItems.count - 1, prevLastRowStart + col)
                        targetItem = prevItems[targetIdx]
                    } else {
                        targetItem = currentGroupItems[itemIdx]
                    }
                case .down:
                    if row + 1 < groupRows {
                        let targetIdx = min(currentGroupItems.count - 1, itemIdx + cols)
                        targetItem = currentGroupItems[targetIdx]
                    } else if groupIdx + 1 < groups.count {
                        let nextItems = groups[groupIdx + 1].items
                        let targetIdx = min(nextItems.count - 1, col)
                        targetItem = nextItems[targetIdx]
                    } else {
                        targetItem = currentGroupItems[itemIdx]
                    }
                }
            }
        } else if isGridMode {
            if let idx = visible.firstIndex(where: { $0.id == cursorID }) {
                let row = idx / cols
                let totalRows = (visible.count + cols - 1) / cols
                switch direction {
                case .left:
                    targetItem = visible[max(0, idx - 1)]
                case .right:
                    targetItem = visible[min(visible.count - 1, idx + 1)]
                case .up:
                    if row > 0 {
                        targetItem = visible[idx - cols]
                    } else {
                        targetItem = visible[idx]
                    }
                case .down:
                    if row + 1 < totalRows {
                        targetItem = visible[min(visible.count - 1, idx + cols)]
                    } else {
                        targetItem = visible[idx]
                    }
                }
            }
        } else {
            // 1D List / Details / Search results
            if let idx = visible.firstIndex(where: { $0.id == cursorID }) {
                switch direction {
                case .up, .left:
                    targetItem = visible[max(0, idx - 1)]
                case .down, .right:
                    targetItem = visible[min(visible.count - 1, idx + 1)]
                }
            }
        }

        guard let resolvedTarget = targetItem else { return }
        if extendSelection {
            let anchorID = selectionAnchor ?? cursorID
            selectionAnchor = anchorID
            selectionCursor = resolvedTarget.id
            if let from = visible.firstIndex(where: { $0.id == anchorID }),
               let to = visible.firstIndex(where: { $0.id == resolvedTarget.id }) {
                selectedIDs = Set(visible[min(from, to)...max(from, to)].map(\.id))
            } else {
                select(resolvedTarget)
            }
        } else {
            select(resolvedTarget)
        }
    }

    /// Selects the first visible item matching a typed character sequence (`KItemListController::typeAheadUsed` in `dolphinview.cpp`
    /// and native macOS Finder type-to-select). Buffers characters typed within 1.0 second.
    @discardableResult
    func selectItemByTypeAhead(_ characters: String, now: Date = Date()) -> FileItem? {
        let cleaned = characters.trimmingCharacters(in: .controlCharacters)
        guard !cleaned.isEmpty else { return nil }

        if now.timeIntervalSince(lastTypeAheadTimestamp) > 1.0 {
            typeAheadBuffer = cleaned
        } else {
            typeAheadBuffer.append(cleaned)
        }
        lastTypeAheadTimestamp = now

        typeAheadResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.typeAheadBuffer = ""
        }
        typeAheadResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)

        let visible = searchQuery.isEmpty ? filteredItems : searchResults
        guard !visible.isEmpty else { return nil }

        // Prefer prefix match first, then fallback to case-insensitive substring match
        if let prefixMatch = visible.first(where: {
            $0.name.range(of: typeAheadBuffer, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
        }) {
            select(prefixMatch)
            return prefixMatch
        }
        if let containsMatch = visible.first(where: {
            $0.name.range(of: typeAheadBuffer, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }) {
            select(containsMatch)
            return containsMatch
        }
        return nil
    }

    func clearTypeAheadBuffer() {
        typeAheadResetWorkItem?.cancel()
        typeAheadBuffer = ""
        lastTypeAheadTimestamp = .distantPast
    }

    func toggleSelection(_ item: FileItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
        selectionAnchor = item.id
    }

    /// Shift-click: select the contiguous range between the anchor and `item` in the visible order.
    func extendSelection(to item: FileItem) {
        let visible = filteredItems
        guard let anchor = selectionAnchor,
              let from = visible.firstIndex(where: { $0.id == anchor }),
              let to = visible.firstIndex(where: { $0.id == item.id }) else {
            select(item)
            return
        }
        selectedIDs = Set(visible[min(from, to)...max(from, to)].map(\.id))
    }

    func selectAll() {
        selectedIDs = Set(filteredItems.map(\.id))
    }

    /// Selects items matching a Dolphin wildcard pattern (`*.swift`, `photo_?.jpg`) or substring.
    func selectItems(matchingPattern rawPattern: String, additive: Bool = false) {
        let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        let matched = filteredItems.filter { Self.matchesPattern(name: $0.name, pattern: pattern) }.map(\.id)
        if additive {
            selectedIDs.formUnion(matched)
        } else {
            selectedIDs = Set(matched)
        }
    }

    static func matchesPattern(name: String, pattern: String) -> Bool {
        if pattern.contains("*") || pattern.contains("?") {
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".")
            let regexPattern = "^\(escaped)$"
            return name.range(of: regexPattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return name.localizedCaseInsensitiveContains(pattern)
    }

    func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent.path != currentURL.path else { return }
        navigate(to: parent)
    }

    func refresh() {
        load(currentURL)
        if !searchQuery.isEmpty {
            performSearch()
        }
    }

    func setViewMode(_ mode: ViewMode) {
        viewProperties.mode = mode
        store.setProperties(viewProperties, for: currentURL)
    }

    func setSort(field: SortField, ascending: Bool) {
        viewProperties.sortField = field
        viewProperties.ascending = ascending
        store.setProperties(viewProperties, for: currentURL)
        let sortingChoice = AppSettingsStore().settings().sortingChoice
        items = items.sorted(
            by: field,
            ascending: ascending,
            foldersFirst: viewProperties.sortFoldersFirst,
            hiddenLast: viewProperties.sortHiddenLast,
            sortingChoice: sortingChoice
        )
    }

    func setZoomLevel(_ level: Double) {
        viewProperties.zoomLevel = min(2.0, max(0.5, (level * 100).rounded() / 100))
        store.setProperties(viewProperties, for: currentURL)
    }

    /// Mirrors `DolphinView::slotIncreaseZoom` (`src/views/dolphinview.cpp` lines 1337-1343).
    func increaseZoom() {
        setZoomLevel(viewProperties.zoomLevel + 0.1)
    }

    /// Mirrors `DolphinView::slotDecreaseZoom` (`src/views/dolphinview.cpp` lines 1345-1351).
    func decreaseZoom() {
        setZoomLevel(viewProperties.zoomLevel - 0.1)
    }

    /// Mirrors `DolphinViewActionHandler::resetZoomLevel` (`⌘0`).
    func resetZoom() {
        setZoomLevel(1.0)
    }

    /// Toggles a visible column in Details mode (`DolphinView::slotHeaderContextMenuRequested` in `dolphinview.cpp`).
    func toggleDetailsColumn(_ column: DetailsColumn) {
        if viewProperties.visibleDetailsColumns.contains(column) {
            if viewProperties.visibleDetailsColumns.count > 1 {
                viewProperties.visibleDetailsColumns.removeAll { $0 == column }
            }
        } else {
            viewProperties.visibleDetailsColumns.append(column)
        }
        store.setProperties(viewProperties, for: currentURL)
    }

    func toggleShowInGroups() {
        viewProperties.showInGroups.toggle()
        store.setProperties(viewProperties, for: currentURL)
    }

    /// Sets the `Group By` role (`DolphinViewActionHandler::slotGroupByTriggered`).
    /// Pass `showInGroups: false` for "Ninguno", `groupFieldOverride: nil` for "Igual que el criterio de ordenación", or a specific `SortField`.
    func setGroupBy(showInGroups: Bool, groupFieldOverride: SortField? = nil) {
        viewProperties.showInGroups = showInGroups
        viewProperties.groupByFieldOverride = groupFieldOverride
        store.setProperties(viewProperties, for: currentURL)
    }

    /// Toggles `showPreviews` (`DolphinViewActionHandler::togglePreview` / `F12`).
    func toggleShowPreviews() {
        viewProperties.showPreviews.toggle()
        store.setProperties(viewProperties, for: currentURL)
    }

    /// Toggles `sortFoldersFirst` (`DolphinViewActionHandler::toggleSortFoldersFirst`).
    func toggleSortFoldersFirst() {
        viewProperties.sortFoldersFirst.toggle()
        store.setProperties(viewProperties, for: currentURL)
        setSort(field: viewProperties.sortField, ascending: viewProperties.ascending)
    }

    /// Toggles `sortHiddenLast` (`DolphinViewActionHandler::toggleSortHiddenLast`).
    func toggleSortHiddenLast() {
        viewProperties.sortHiddenLast.toggle()
        store.setProperties(viewProperties, for: currentURL)
        setSort(field: viewProperties.sortField, ascending: viewProperties.ascending)
    }

    /// Resets the current folder's view settings to defaults (`DolphinViewActionHandler::restoreViewSettingsToDefaults`).
    func resetViewPropertiesToDefault() {
        viewProperties = store.resetPropertiesToDefault(for: currentURL)
        refresh()
    }

    func toggleShowsHiddenFiles() {
        let next = !effectiveShowsHiddenFiles
        viewProperties.showsHiddenFilesOverride = next
        store.setProperties(viewProperties, for: currentURL)
        refresh()
    }

    func applyViewProperties(
        _ updated: ViewProperties,
        scope: ViewPropertiesApplyScope,
        useAsDefault: Bool
    ) {
        viewProperties = updated
        store.applyProperties(updated, to: currentURL, scope: scope, useAsDefault: useAsDefault)
        refresh()
    }

    func renameSelected(to newName: String) {
        guard let item = selectedItem else { return }
        do {
            let destination = try operations.rename(item, to: newName)
            history.record([.moved(from: item.url, to: destination)])
            refresh()
            if let renamed = items.first(where: { $0.name == newName }) { select(renamed) } else { selectedIDs = [] }
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    func batchRenameSelected(pattern: String, startIndex: Int = 1) {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        let plan = BatchRenameFormatter.plannedRenames(for: targets, pattern: pattern, startIndex: startIndex)
        guard !plan.isEmpty else {
            operationError = .invalidName
            return
        }
        var batch: [FileOperationRecord] = []
        var newSelectedURLs = Set<URL>()
        var failures: [String] = []
        for entry in plan {
            if entry.newName == entry.item.name {
                newSelectedURLs.insert(entry.item.url)
                continue
            }
            do {
                let destination = try operations.rename(entry.item, to: entry.newName)
                batch.append(.moved(from: entry.item.url, to: destination))
                newSelectedURLs.insert(destination)
            } catch {
                failures.append(entry.item.name)
            }
        }
        history.record(batch)
        refresh()
        selectedIDs = newSelectedURLs.intersection(Set(items.map(\.id)))
        if !failures.isEmpty {
            operationError = .other("No se pudieron renombrar: \(failures.joined(separator: ", "))")
        }
    }

    /// Dolphin's `MoveToNewFolderItemAction` (`src/itemactions/movetonewfolderitemaction.cpp`):
    /// creates a new folder in `currentURL` and moves all selected items into it as one undoable operation.
    func moveSelectedToNewFolder(named folderName: String) {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        do {
            let createdFolder = try operations.createFolder(in: currentURL, named: folderName)
            var batch: [FileOperationRecord] = [.createdFolder(createdFolder)]
            var failures: [String] = []
            for item in targets where item.url.standardizedFileURL != createdFolder.standardizedFileURL {
                do {
                    let movedURL = try operations.move(item.url, toDirectory: createdFolder)
                    if movedURL != item.url {
                        batch.append(.moved(from: item.url, to: movedURL))
                    }
                } catch {
                    failures.append(item.name)
                }
            }
            history.record(batch)
            refresh()
            if let folderItem = items.first(where: { $0.name == createdFolder.lastPathComponent }) {
                select(folderItem)
            }
            if !failures.isEmpty {
                operationError = .other("No se pudieron mover: \(failures.joined(separator: ", "))")
            }
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    /// Dolphin's `HideFileItemAction` (`src/itemactions/hidefileitemaction.cpp`): hides/unhides via `.hidden`.
    func hideItemsInDotHidden(_ targets: [FileItem]) {
        let names = targets.map(\.name).filter { !$0.hasPrefix(".") }
        guard !names.isEmpty else { return }
        do {
            try DotHiddenService().hide(names: names, in: currentURL)
            refresh()
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    func unhideItemsInDotHidden(_ targets: [FileItem]) {
        let names = targets.map(\.name)
        guard !names.isEmpty else { return }
        do {
            try DotHiddenService().unhide(names: names, in: currentURL)
            refresh()
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    func setColorTag(_ tag: FinderColorTag, for targets: [FileItem]) {
        let service = FolderIconAndTagService()
        for item in targets {
            try? service.setColorTag(tag, for: item.url)
        }
        refresh()
    }

    func setFolderIcon(_ preset: FolderIconPreset, for folderURL: URL) {
        _ = FolderIconAndTagService().setFolderIcon(preset, for: folderURL)
        refresh()
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        delete(item)
    }

    func delete(_ item: FileItem) {
        do {
            if let trashed = try operations.moveToTrash(item) {
                history.record([.trashed(original: item.url, trashed: trashed)])
            }
            refresh()
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    func createFolder(named name: String) {
        do {
            let created = try operations.createFolder(in: currentURL, named: name)
            history.record([.createdFolder(created)])
            refresh()
            if let item = items.first(where: { $0.url.standardizedFileURL == created.standardizedFileURL }) {
                select(item)
            }
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    nonisolated static func templateContents(forFileName name: String) -> Data {
        let lower = name.lowercased()
        let baseName = (name as NSString).deletingPathExtension
        if lower.hasSuffix(".sh") {
            return Data("#!/usr/bin/env zsh\nset -euo pipefail\n\n".utf8)
        } else if lower.hasSuffix(".md") {
            return Data("# \(baseName)\n\n".utf8)
        } else if lower.hasSuffix(".swift") {
            return Data("import Foundation\n\n".utf8)
        } else if lower.hasSuffix(".json") {
            return Data("{\n  \n}\n".utf8)
        } else if lower.hasSuffix(".html") {
            return Data("<!DOCTYPE html>\n<html lang=\"es\">\n<head>\n  <meta charset=\"utf-8\">\n  <title>\(baseName)</title>\n</head>\n<body>\n  \n</body>\n</html>\n".utf8)
        }
        return Data()
    }

    func createFile(named name: String, contents: Data? = nil) {
        do {
            let resolvedContents = contents ?? Self.templateContents(forFileName: name)
            let created = try operations.createFile(in: currentURL, named: name, contents: resolvedContents)
            if name.lowercased().hasSuffix(".sh") {
                try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: created.path)
            }
            history.record([.createdFile(created, resolvedContents)])
            refresh()
            if let item = items.first(where: { $0.url.standardizedFileURL == created.standardizedFileURL }) {
                select(item)
            }
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    /// Creates a symbolic link in `currentURL` pointing to `targetPath` (`DolphinNewFileMenu`).
    func createSymbolicLink(named linkName: String, pointingTo targetPath: String) {
        do {
            let created = try operations.createSymbolicLink(in: currentURL, named: linkName, pointingTo: targetPath)
            history.record([.createdFolder(created)])
            refresh()
            if let item = items.first(where: { $0.url.standardizedFileURL == created.standardizedFileURL }) {
                select(item)
            }
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    /// Creates symbolic links in `currentURL` for all currently selected items (undoable).
    func createSymbolicLinkToSelected() {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        var batch: [FileOperationRecord] = []
        var createdURLs = Set<URL>()
        var failures: [String] = []
        for item in targets {
            do {
                let linkURL = try operations.createSymbolicLink(for: item.url, in: currentURL)
                batch.append(.createdFolder(linkURL))
                createdURLs.insert(linkURL)
            } catch {
                failures.append(item.name)
            }
        }
        history.record(batch)
        refresh()
        selectedIDs = createdURLs.intersection(Set(items.map(\.id)))
        if !failures.isEmpty {
            operationError = .other("No se pudieron crear enlaces simbólicos: \(failures.joined(separator: ", "))")
        }
    }

    /// Resolves a symbolic link's target, navigates to its parent folder, and selects it (`DolphinMainWindow::showTarget`).
    func showSymbolicLinkTarget(_ item: FileItem) {
        guard let targetURL = operations.resolvedSymbolicLinkTarget(of: item.url) else {
            operationError = .other("No se pudo resolver el destino del enlace simbólico «\(item.name)».")
            return
        }
        let parentDir = targetURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parentDir.path) else {
            operationError = .other("El destino «\(targetURL.path)» no existe.")
            return
        }
        navigate(to: parentDir)
        if let targetItem = items.first(where: { $0.url.standardizedFileURL == targetURL.standardizedFileURL }) {
            select(targetItem)
        }
    }

    /// Dolphin's "Duplicate Here" (Ctrl+D / ⌘D): copies every selected item into its own parent directory.
    func duplicateSelected() {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        var batch: [FileOperationRecord] = []
        var createdURLs = Set<URL>()
        var failures: [String] = []
        for item in targets {
            let parent = item.url.deletingLastPathComponent()
            do {
                let copyURL = try operations.copy(item.url, toDirectory: parent)
                batch.append(.copied(source: item.url, to: copyURL))
                createdURLs.insert(copyURL)
            } catch {
                failures.append(item.name)
            }
        }
        history.record(batch)
        refresh()
        selectedIDs = createdURLs.intersection(Set(items.map(\.id)))
        if !failures.isEmpty {
            operationError = .other("No se pudieron duplicar: \(failures.joined(separator: ", "))")
        }
    }

    /// Dolphin's Split View "Copy to Inactive Split View" (F5 in Dolphin).
    func copySelected(to destinationDirectory: URL) {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        var batch: [FileOperationRecord] = []
        var failures: [String] = []
        for item in targets {
            do {
                let copyURL = try operations.copy(item.url, toDirectory: destinationDirectory)
                batch.append(.copied(source: item.url, to: copyURL))
            } catch {
                failures.append(item.name)
            }
        }
        history.record(batch)
        refresh()
        if !failures.isEmpty {
            operationError = .other("No se pudieron copiar al otro panel: \(failures.joined(separator: ", "))")
        }
    }

    /// Dolphin's Split View "Move to Inactive Split View" (F6 in Dolphin).
    func moveSelected(to destinationDirectory: URL) {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        moveDroppedItems(targets.map(\.url), into: destinationDirectory)
    }

    /// Compresses the currently selected items into a `.zip` archive in `currentURL` (undoable).
    func compressSelected(archiveName: String? = nil) {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        do {
            let archiveURL = try ArchiveService().compress(
                targets.map(\.url),
                in: currentURL,
                archiveName: archiveName
            )
            history.record([.createdFolder(archiveURL)])
            refresh()
            if let createdItem = items.first(where: { $0.url.standardizedFileURL == archiveURL.standardizedFileURL }) {
                select(createdItem)
            }
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    /// Extracts an archive file into a new subfolder in `currentURL` (undoable).
    func extractArchive(_ item: FileItem) {
        do {
            let extractedFolder = try ArchiveService().extract(item.url, in: currentURL)
            history.record([.createdFolder(extractedFolder)])
            refresh()
            if let createdItem = items.first(where: { $0.url.standardizedFileURL == extractedFolder.standardizedFileURL }) {
                select(createdItem)
            }
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    func invertSelection() {
        let visible = Set(filteredItems.map(\.id))
        selectedIDs = visible.subtracting(selectedIDs)
    }

    func clearOperationError() {
        operationError = nil
    }

    func moveDroppedItems(_ urls: [URL], into directory: URL) {
        defer { refresh() }
        var failures: [String] = []
        var batch: [FileOperationRecord] = []
        for url in urls {
            do {
                let destination = try operations.move(url, toDirectory: directory)
                if destination != url {
                    batch.append(.moved(from: url, to: destination))
                }
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        history.record(batch)
        if !failures.isEmpty {
            operationError = .other("No se pudieron mover: \(failures.joined(separator: ", "))")
        }
    }

    // MARK: - Clipboard (Copiar / Cortar / Pegar)

    var canPaste: Bool { clipboard.read() != nil }

    var clipboardSummary: (count: Int, isCut: Bool, firstFileName: String)? {
        guard let (urls, mode) = clipboard.read(), let first = urls.first else { return nil }
        return (urls.count, mode == .cut, first.lastPathComponent)
    }

    func clearClipboard() {
        clipboard.clear()
    }

    func copySelected() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        clipboard.write(urls, mode: .copy)
    }

    func cutSelected() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        clipboard.write(urls, mode: .cut)
    }

    /// Moves every selected item to the Trash as one undoable step.
    func deleteSelectedItems() {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        var batch: [FileOperationRecord] = []
        var failures: [String] = []
        for item in targets {
            do {
                if let trashed = try operations.moveToTrash(item) {
                    batch.append(.trashed(original: item.url, trashed: trashed))
                }
            } catch {
                failures.append(item.name)
            }
        }
        history.record(batch)
        if !failures.isEmpty {
            operationError = .other("No se pudieron eliminar: \(failures.joined(separator: ", "))")
        }
        refresh()
    }

    func paste() {
        paste(into: currentURL)
    }

    func paste(into directory: URL) {
        guard let (urls, mode) = clipboard.read() else { return }
        defer { refresh() }
        var failures: [String] = []
        var batch: [FileOperationRecord] = []
        for url in urls {
            do {
                switch mode {
                case .copy:
                    let created = try operations.copy(url, toDirectory: directory)
                    batch.append(.copied(source: url, to: created))
                case .cut:
                    let destination = try operations.move(url, toDirectory: directory)
                    if destination != url {
                        batch.append(.moved(from: url, to: destination))
                    }
                }
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        history.record(batch)
        if mode == .cut && failures.isEmpty {
            clipboard.clear()
        }
        if !failures.isEmpty {
            operationError = .other("No se pudieron pegar: \(failures.joined(separator: ", "))")
        }
    }

    func copySelectedPathsToPasteboard() {
        let targets = selectedItems
        let paths = targets.isEmpty ? [currentURL.path] : targets.map(\.url.path)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths.joined(separator: "\n"), forType: .string)
    }

    // MARK: - Deshacer / Rehacer

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    func undo() {
        defer { refresh() }
        do {
            try history.undo(using: operations)
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    func redo() {
        defer { refresh() }
        do {
            try history.redo(using: operations)
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    func emptyTrash() {
        guard isBrowsingTrash else { return }
        defer { refresh() }
        do {
            try operations.emptyTrash(at: trashURL)
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    func restoreSelected() {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        restoreItemsFromTrash(targets)
    }

    func restoreItemsFromTrash(_ targets: [FileItem]) {
        guard !targets.isEmpty else { return }
        let defaultDest = FileManager.default.homeDirectoryForCurrentUser
        var failures: [String] = []
        for item in targets {
            do {
                _ = try operations.restore(item, to: defaultDest)
            } catch {
                failures.append(item.name)
            }
        }
        selectedIDs = []
        refresh()
        if !failures.isEmpty {
            operationError = .other("No se pudieron restaurar: \(failures.joined(separator: ", "))")
        }
    }

    /// Permanently deletes `targets` bypassing the Trash (`KStandardAction::deleteFile` / `Shift+Delete`).
    func deletePermanently(_ targets: [FileItem]) {
        guard !targets.isEmpty else { return }
        var failures: [String] = []
        for item in targets {
            do {
                try operations.deletePermanently(item.url)
            } catch {
                failures.append(item.name)
            }
        }
        selectedIDs = []
        refresh()
        if !failures.isEmpty {
            operationError = .other("No se pudieron eliminar permanentemente: \(failures.joined(separator: ", "))")
        }
    }

    func deleteSelectedPermanently() {
        deletePermanently(selectedItems)
    }

    // MARK: - Control de versiones Git (KVersionControlPlugin)

    func gitStageItems(_ targets: [FileItem]) {
        guard !targets.isEmpty else { return }
        _ = gitStatus.stage(urls: targets.map(\.url), in: currentURL)
        refresh()
    }

    func gitUnstageItems(_ targets: [FileItem]) {
        guard !targets.isEmpty else { return }
        _ = gitStatus.unstage(urls: targets.map(\.url), in: currentURL)
        refresh()
    }

    func gitDiscardChanges(_ targets: [FileItem]) {
        guard !targets.isEmpty else { return }
        _ = gitStatus.discardChanges(urls: targets.map(\.url), in: currentURL)
        refresh()
    }

    @discardableResult
    func gitCommit(message: String) -> Bool {
        let ok = gitStatus.commit(message: message, in: currentURL)
        refresh()
        return ok
    }

    func gitDiff(for targets: [FileItem] = []) -> String {
        gitStatus.diff(for: targets.map(\.url), in: currentURL)
    }

    func gitRecentCommits(limit: Int = 25) -> [GitCommitEntry] {
        gitStatus.recentCommits(in: currentURL, limit: limit)
    }

    private func load(_ url: URL) {
        var activeReader = reader
        activeReader.sortingChoice = AppSettingsStore().settings().sortingChoice
        if let overrideHidden = viewProperties.showsHiddenFilesOverride {
            activeReader.showsHiddenFiles = overrideHidden
        }
        do {
            items = try activeReader.contents(
                of: url,
                sortField: viewProperties.sortField,
                ascending: viewProperties.ascending,
                foldersFirst: viewProperties.sortFoldersFirst,
                hiddenLast: viewProperties.sortHiddenLast
            )
            error = nil
        } catch let readError as DirectoryReadError {
            items = []
            error = readError
        } catch {
            items = []
            self.error = .other(error.localizedDescription)
        }
        selectedIDs = selectedIDs.intersection(Set(items.map(\.id)))
        isGitRepository = gitStatus.isGitRepository(in: url)
        gitStatuses = isGitRepository ? gitStatus.statuses(in: url) : [:]
        gitBranchName = isGitRepository ? gitStatus.currentBranch(in: url) : nil
        availableCapacity = VolumeInfoProvider().availableCapacity(for: url)
        isCurrentDirectoryWritable = FileManager.default.isWritableFile(atPath: url.path)
    }
}
