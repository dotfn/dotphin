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
        case .plainText: return String(localized: "Texto plano", bundle: #bundle)
        case .glob: return String(localized: "Patrón Glob (*, ?)", bundle: #bundle)
        case .regex: return String(localized: "Expresión regular", bundle: #bundle)
        }
    }
}

/// Opciones de "Agrupar por" (`DolphinViewActionHandler::slotGroupByTriggered`).
enum GroupByChoice: Hashable {
    case none
    case sameAsSort
    case field(SortField)
}

@MainActor
@Observable
final class BrowserViewModel {
    private(set) var currentURL: URL
    private(set) var items: [FileItem] = [] {
        didSet { itemsVersion &+= 1 }
    }
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

    private struct FilterCacheKey: Equatable {
        let itemsVersion: Int
        let filterText: String
        let filterMode: FilterPatternMode
        let isCaseSensitive: Bool
        let typeFilter: SearchTypeFilter
        let dateFilter: SearchDateFilter
        let sizeFilter: SearchSizeFilter
        let colorTagFilter: FinderColorTag
    }

    @ObservationIgnored private var itemsVersion = 0
    @ObservationIgnored private var filteredItemsCache: (key: FilterCacheKey, items: [FileItem])?

    /// Se lee varias veces por redibujado (vistas + didSets); con regex y miles de
    /// ítems filtrar cada vez se notaba. Se recalcula solo si cambian ítems o filtros.
    /// Las propiedades se leen igual al armar la clave, así Observation sigue registrándolas.
    var filteredItems: [FileItem] {
        let key = FilterCacheKey(
            itemsVersion: itemsVersion,
            filterText: filterText,
            filterMode: filterMode,
            isCaseSensitive: isFilterCaseSensitive,
            typeFilter: searchTypeFilter,
            dateFilter: searchDateFilter,
            sizeFilter: searchSizeFilter,
            colorTagFilter: searchColorTagFilter
        )
        _ = items
        if let cached = filteredItemsCache, cached.key == key {
            return cached.items
        }
        let computed = computeFilteredItems()
        filteredItemsCache = (key, computed)
        return computed
    }

    private func computeFilteredItems() -> [FileItem] {
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
    /// Copia o movimiento en curso (corre fuera del main actor).
    private(set) var activeTransfer: FileTransferProgress?
    /// `true` cuando hay una vista que puede preguntar qué hacer ante un
    /// nombre repetido. Sin ella: copiar conserva ambos y mover informa error.
    @ObservationIgnored var presentsConflictPrompts = false
    @ObservationIgnored private var transferTask: Task<Void, Never>?
    /// Lo prende la vista que muestra este panel: la carpeta actual se
    /// vuelve a leer sola cuando cambia en disco (FSEvents).
    @ObservationIgnored var watchesCurrentDirectory = false {
        didSet { updateDirectoryWatcher() }
    }
    @ObservationIgnored private let directoryWatcher = DirectoryWatcher()
    @ObservationIgnored private let transfers = FileTransferService()
    /// Para refrescar al instante los otros paneles que muestran una carpeta
    /// afectada por una operación propia (el observador de carpetas cubre los
    /// cambios que vienen de afuera, con una pequeña demora).
    private static let liveViewModels = NSHashTable<BrowserViewModel>.weakObjects()

    var searchQuery: String = "" {
        didSet {
            selectedIDs = []
        }
    }
    private(set) var searchResults: [FileItem] = []
    /// `true` mientras la búsqueda en segundo plano no terminó; la vista muestra
    /// progreso en vez de "sin resultados" en ese intervalo.
    private(set) var isSearching: Bool = false
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var gitTask: Task<Void, Never>?
    @ObservationIgnored private var gitStatusesURL: URL?

    private(set) var gitStatuses: [String: GitFileStatus] = [:]
    private(set) var isGitRepository: Bool = false
    private(set) var gitBranchName: String? = nil
    private(set) var availableCapacity: Int64?
    /// Indicates whether `currentURL` is writable (`DolphinView::m_isFolderWritable` in `src/views/dolphinview.cpp` & `Admin::Bar`).
    private(set) var isCurrentDirectoryWritable: Bool = true
    /// Type-ahead selection buffer (`KItemListController::typeAheadUsed` in `src/views/dolphinview.cpp`).
    private(set) var typeAheadBuffer: String = ""
    @ObservationIgnored private var lastTypeAheadTimestamp: Date = .distantPast
    @ObservationIgnored private var typeAheadResetTask: Task<Void, Never>?
    /// Ítem que la vista de archivos está renombrando en línea.
    var renamingItemID: FileItem.ID?
    /// `UndoManager` de la ventana: ahí se registran las operaciones de archivo
    /// para que Deshacer/Rehacer sean los del menú Edición estándar.
    @ObservationIgnored weak var undoManager: UndoManager?
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
        Self.liveViewModels.add(self)
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
        cancelSearch()
        load(url)
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        searchResults = []
    }

    /// Lanza la búsqueda en segundo plano, cancelando la anterior: cambiar un
    /// filtro mientras corre ya no encola recorridos completos uno detrás de otro.
    func performSearch() {
        searchTask?.cancel()
        guard !searchQuery.isEmpty else {
            searchTask = nil
            isSearching = false
            searchResults = []
            return
        }
        let rootURL = searchLocationScope == .everywhere
            ? FileManager.default.homeDirectoryForCurrentUser
            : currentURL
        let query = searchQuery
        let typeFilter = searchTypeFilter
        let dateFilter = searchDateFilter
        let sizeFilter = searchSizeFilter
        let colorTagFilter = searchColorTagFilter
        let matchMode = searchMatchMode
        let search = search
        isSearching = true
        searchTask = Task { [weak self] in
            let results = await search.results(
                for: query,
                in: rootURL,
                typeFilter: typeFilter,
                dateFilter: dateFilter,
                sizeFilter: sizeFilter,
                colorTagFilter: colorTagFilter,
                matchMode: matchMode
            )
            guard !Task.isCancelled, let self else { return }
            self.searchResults = results
            self.isSearching = false
        }
    }

    /// Espera a que terminen la búsqueda y la carga de git en curso (para tests).
    func waitForBackgroundWork() async {
        await searchTask?.value
        await gitTask?.value
        await transferTask?.value
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
        cancelSearch()
    }

    /// Saves the current search configuration into the Places sidebar (`Search::Bar::slotSaveSearch`).
    @discardableResult
    func saveCurrentSearch(named customName: String? = nil, using provider: PlacesProvider = PlacesProvider()) -> SavedSearchItem? {
        guard !searchQuery.isEmpty || hasActiveFacets else { return nil }
        let defaultTitle: String = {
            if !searchQuery.isEmpty {
                return String(localized: "«\(searchQuery)» en \(currentURL.lastPathComponent)", bundle: #bundle)
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
        DebugEventLog.log("selección", "select(\(item?.name ?? "nil"))")
        selectedIDs = item.map { [$0.id] } ?? []
        selectionAnchor = item?.id
        selectionCursor = item?.id
    }

    func setSelection(_ ids: Set<FileItem.ID>) {
        DebugEventLog.log("selección", "setSelection(\(DebugEventLog.names(ids))) antes=\(DebugEventLog.names(selectedIDs)) runloop=\(DebugEventLog.runLoopModeDescription) evento=\(NSApp?.currentEvent.map { String(describing: $0.type) } ?? "nil")")
        // Lo normal es que los IDs vengan tal cual de la lista: entonces no hace
        // falta resolver symlinks (una llamada al disco por ítem, en cada clic).
        let knownIDs = Set(items.map(\.id)).union(searchResults.map(\.id))
        let normalized: Set<FileItem.ID>
        if ids.isSubset(of: knownIDs) {
            normalized = ids
        } else {
            let resolvedLookup = Dictionary(
                items.map { ($0.id.resolvingSymlinksInPath(), $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
            normalized = Set(ids.map { knownIDs.contains($0) ? $0 : (resolvedLookup[$0.resolvingSymlinksInPath()] ?? $0) })
        }
        selectedIDs = normalized
        if normalized.count == 1 {
            selectionAnchor = normalized.first
            selectionCursor = normalized.first
        }
    }

    func deselectAll() {
        DebugEventLog.log("selección", "deselectAll()")
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

        typeAheadResetTask?.cancel()
        typeAheadResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.15))
            guard !Task.isCancelled else { return }
            self?.typeAheadBuffer = ""
        }

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
        typeAheadResetTask?.cancel()
        typeAheadBuffer = ""
        lastTypeAheadTimestamp = .distantPast
    }

    func toggleSelection(_ item: FileItem) {
        DebugEventLog.log("selección", "toggleSelection(\(item.name))")
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
        selectionAnchor = item.id
    }

    /// Shift-click: select the contiguous range between the anchor and `item` in the visible order.
    func extendSelection(to item: FileItem) {
        DebugEventLog.log("selección", "extendSelection(to: \(item.name)) ancla=\(selectionAnchor?.lastPathComponent ?? "nil")")
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

    /// "Agrupar por" como una sola elección, para mostrarlo con un `Picker`.
    var groupByChoice: GroupByChoice {
        get {
            guard viewProperties.showInGroups else { return .none }
            return viewProperties.groupByFieldOverride.map(GroupByChoice.field) ?? .sameAsSort
        }
        set {
            switch newValue {
            case .none: setGroupBy(showInGroups: false, groupFieldOverride: nil)
            case .sameAsSort: setGroupBy(showInGroups: true, groupFieldOverride: nil)
            case .field(let field): setGroupBy(showInGroups: true, groupFieldOverride: field)
            }
        }
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

    /// Cierra la edición en línea; `newName == nil` = cancelada.
    func endRenaming(_ id: FileItem.ID, newName: String?) {
        renamingItemID = nil
        guard let newName,
              let item = items.first(where: { $0.id == id }) ?? searchResults.first(where: { $0.id == id }),
              !newName.isEmpty, newName != item.name
        else { return }
        select(item)
        renameSelected(to: newName)
    }

    func renameSelected(to newName: String) {
        guard let item = selectedItem else { return }
        do {
            let destination = try operations.rename(item, to: newName)
            record([.moved(from: item.url, to: destination)])
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
        record(batch)
        refresh()
        selectedIDs = newSelectedURLs.intersection(Set(items.map(\.id)))
        if !failures.isEmpty {
            operationError = .other(String(localized: "No se pudieron renombrar: \(failures.joined(separator: ", "))", bundle: #bundle))
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
            record(batch)
            refresh()
            if let folderItem = items.first(where: { $0.name == createdFolder.lastPathComponent }) {
                select(folderItem)
            }
            if !failures.isEmpty {
                operationError = .other(String(localized: "No se pudieron mover: \(failures.joined(separator: ", "))", bundle: #bundle))
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
                record([.trashed(original: item.url, trashed: trashed)])
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
            record([.createdFolder(created)])
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
            record([.createdFile(created, resolvedContents)])
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

    /// Mounts a `.iso`/`.dmg`/`.cdr`/`.img` via `hdiutil` (Dolphin's explicit "Montar" action).
    /// On success, refreshes the Places sidebar's volume list the same way adding/removing
    /// a bookmark does, so the newly-mounted volume shows up without relaunching the app.
    /// `hdiutil` verifies the image before mounting (seconds for large images), so it runs
    /// off the main actor; only the result comes back here.
    @MainActor
    func mountDiskImage(_ item: FileItem) async {
        let url = item.url
        let failure: String? = await Task.detached(priority: .userInitiated) {
            do {
                try DiskImageMountService().mount(url)
                return nil
            } catch {
                return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }.value
        if let failure {
            operationError = .other(failure)
        } else {
            NotificationCenter.default.post(name: .placesBookmarksDidChange, object: nil)
        }
    }

    /// Lets the view report a failure that happened before reaching the view model
    /// (e.g. a template file that vanished between opening the menu and pressing Crear).
    func reportOperationError(_ message: String) {
        operationError = .other(message)
    }

    /// Creates a symbolic link in `currentURL` pointing to `targetPath` (`DolphinNewFileMenu`).
    func createSymbolicLink(named linkName: String, pointingTo targetPath: String) {
        do {
            let created = try operations.createSymbolicLink(in: currentURL, named: linkName, pointingTo: targetPath)
            record([.createdFolder(created)])
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
        record(batch)
        refresh()
        selectedIDs = createdURLs.intersection(Set(items.map(\.id)))
        if !failures.isEmpty {
            operationError = .other(String(localized: "No se pudieron crear enlaces simbólicos: \(failures.joined(separator: ", "))", bundle: #bundle))
        }
    }

    /// Resolves a symbolic link's target, navigates to its parent folder, and selects it (`DolphinMainWindow::showTarget`).
    func showSymbolicLinkTarget(_ item: FileItem) {
        guard let targetURL = operations.resolvedSymbolicLinkTarget(of: item.url) else {
            operationError = .other(String(localized: "No se pudo resolver el destino del enlace simbólico «\(item.name)».", bundle: #bundle))
            return
        }
        let parentDir = targetURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parentDir.path) else {
            operationError = .other(String(localized: "El destino «\(targetURL.path)» no existe.", bundle: #bundle))
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
        // Cada ítem se duplica al lado suyo (en resultados de búsqueda pueden
        // venir de carpetas distintas).
        let byParent = Dictionary(grouping: targets.map(\.url)) { $0.deletingLastPathComponent() }
        for (parent, urls) in byParent {
            startTransfer(.copy, sources: urls, into: parent, failurePrefix: String(localized: "No se pudieron duplicar", bundle: #bundle)) { [weak self] result in
                guard let self else { return }
                self.selectedIDs = Set(result.createdURLs).intersection(Set(self.items.map(\.id)))
            }
        }
    }

    /// Dolphin's Split View "Copy to Inactive Split View" (F5 in Dolphin).
    func copySelected(to destinationDirectory: URL) {
        startTransfer(
            .copy,
            sources: selectedItems.map(\.url),
            into: destinationDirectory,
            failurePrefix: String(localized: "No se pudieron copiar", bundle: #bundle)
        )
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
            record([.createdFolder(archiveURL)])
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
            record([.createdFolder(extractedFolder)])
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
        DebugEventLog.log("drop", "moveDroppedItems(\(DebugEventLog.names(urls)) → \(directory.lastPathComponent))")
        startTransfer(.move, sources: urls, into: directory, failurePrefix: String(localized: "No se pudieron mover", bundle: #bundle))
    }

    /// Soltar con copia: ⌥ o destino en otro volumen.
    func copyDroppedItems(_ urls: [URL], into directory: URL) {
        DebugEventLog.log("drop", "copyDroppedItems(\(DebugEventLog.names(urls)) → \(directory.lastPathComponent))")
        startTransfer(.copy, sources: urls, into: directory, failurePrefix: String(localized: "No se pudieron copiar", bundle: #bundle))
    }

    // MARK: - Copiar / mover en segundo plano

    /// Lanza la transferencia fuera del main actor. Si ya hay una corriendo,
    /// esta espera su turno. Al terminar registra el lote para deshacer,
    /// refresca este panel y los demás que muestren una carpeta afectada.
    private func startTransfer(
        _ kind: FileTransferKind,
        sources: [URL],
        into directory: URL,
        failurePrefix: String,
        onFinished: (@MainActor (FileTransferResult) -> Void)? = nil
    ) {
        guard !sources.isEmpty else { return }
        let previous = transferTask
        let progress = FileTransferProgress(
            kind: kind,
            totalCount: sources.count,
            destinationName: directory.lastPathComponent.isEmpty ? "/" : directory.lastPathComponent
        )
        let task = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            self.activeTransfer = progress
            let slowTimer = Task {
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled { progress.markLongRunning() }
            }
            let asksUser = self.presentsConflictPrompts
            let result = await self.transfers.run(
                kind,
                sources: sources,
                into: directory,
                onProgress: { completed, current in
                    await progress.update(completed: completed, current: current)
                },
                resolveConflict: { conflict in
                    guard asksUser else {
                        return FileConflictDecision(resolution: kind == .copy ? .keepBoth : .reportError)
                    }
                    return await progress.ask(conflict)
                }
            )
            slowTimer.cancel()
            if self.activeTransfer === progress {
                self.activeTransfer = nil
            }
            self.record(result.records)
            self.refresh()
            let affected = Set(([directory] + sources.map { $0.deletingLastPathComponent() }).map(\.standardizedFileURL))
            for other in Self.liveViewModels.allObjects
            where other !== self && affected.contains(other.currentURL.standardizedFileURL) {
                other.refresh()
            }
            DebugEventLog.log("transfer", "hechos=\(result.records.count) fallaron=\(result.failures.count) cancelada=\(result.wasCancelled)")
            if !result.failures.isEmpty {
                self.operationError = .other("\(failurePrefix): \(result.failures.joined(separator: "; "))")
            }
            onFinished?(result)
        }
        progress.task = task
        transferTask = task
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
        record(batch)
        if !failures.isEmpty {
            operationError = .other(String(localized: "No se pudieron eliminar: \(failures.joined(separator: ", "))", bundle: #bundle))
        }
        refresh()
    }

    func paste() {
        paste(into: currentURL)
    }

    func paste(into directory: URL) {
        guard let (urls, mode) = clipboard.read() else { return }
        startTransfer(
            mode == .copy ? .copy : .move,
            sources: urls,
            into: directory,
            failurePrefix: String(localized: "No se pudieron pegar", bundle: #bundle)
        ) { [weak self] result in
            // Lo cortado se pega una sola vez.
            if mode == .cut && result.failures.isEmpty && !result.wasCancelled {
                self?.clipboard.clear()
            }
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

    /// Guarda el lote en el historial y lo registra en el `UndoManager` de la ventana.
    private func record(_ batch: [FileOperationRecord]) {
        guard !batch.isEmpty else { return }
        history.record(batch)
        registerUndo(named: FileOperationHistory.actionSummary(for: batch))
    }

    /// El mismo registro sirve para deshacer y rehacer: `UndoManager` apila en
    /// la pila contraria lo que se registra mientras deshace o rehace.
    private func registerUndo(named actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { viewModel in
            MainActor.assumeIsolated {
                guard let undoManager = viewModel.undoManager else { return }
                if undoManager.isUndoing {
                    viewModel.undo()
                } else {
                    viewModel.redo()
                }
                viewModel.registerUndo(named: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }

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
            operationError = .other(String(localized: "No se pudieron restaurar: \(failures.joined(separator: ", "))", bundle: #bundle))
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
            operationError = .other(String(localized: "No se pudieron eliminar permanentemente: \(failures.joined(separator: ", "))", bundle: #bundle))
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

    /// Detectar el repo es una caminata barata por `.git`; `git status` y la rama
    /// se piden en segundo plano y se descartan si mientras tanto se navegó a otro lado.
    private func loadGitState(for url: URL) {
        gitTask?.cancel()
        let isSameFolder = gitStatusesURL?.standardizedFileURL.path == url.standardizedFileURL.path
        isGitRepository = gitStatus.isGitRepository(in: url)
        guard isGitRepository else {
            gitTask = nil
            gitStatusesURL = url
            gitStatuses = [:]
            gitBranchName = nil
            return
        }
        if !isSameFolder {
            gitStatuses = [:]
        }
        let provider = gitStatus
        gitTask = Task { [weak self] in
            let snapshot = await provider.snapshot(in: url)
            guard !Task.isCancelled, let self else { return }
            self.gitStatusesURL = url
            self.gitStatuses = snapshot.statuses
            self.gitBranchName = snapshot.branch
        }
    }

    private func load(_ url: URL) {
        DebugEventLog.measure("carga", "load(\(url.lastPathComponent))") { loadNow(url) }
        DebugEventLog.log("carga", "\(items.count) ítems en \(url.lastPathComponent)")
        updateDirectoryWatcher()
    }

    /// Mantiene el observador apuntando a la carpeta que se está mostrando.
    private func updateDirectoryWatcher() {
        guard watchesCurrentDirectory else {
            directoryWatcher.stop()
            return
        }
        guard directoryWatcher.watchedURL != currentURL else { return }
        directoryWatcher.watch(currentURL) { [weak self] in
            self?.directoryChangedOnDisk()
        }
    }

    /// Otra app (o esta) tocó la carpeta: se relee. No relanza la búsqueda.
    private func directoryChangedOnDisk() {
        DebugEventLog.log("carga", "cambio en disco en \(currentURL.lastPathComponent)")
        load(currentURL)
    }

    private func loadNow(_ url: URL) {
        var activeReader = reader
        activeReader.sortingChoice = AppSettingsStore().settings().sortingChoice
        if let overrideHidden = viewProperties.showsHiddenFilesOverride {
            activeReader.showsHiddenFiles = overrideHidden
        }
        do {
            let loaded = try DebugEventLog.measure("carga", "  leer directorio") {
                try activeReader.contents(
                    of: url,
                    sortField: viewProperties.sortField,
                    ascending: viewProperties.ascending,
                    foldersFirst: viewProperties.sortFoldersFirst,
                    hiddenLast: viewProperties.sortHiddenLast
                )
            }
            DebugEventLog.measure("carga", "  asignar items (dispara SwiftUI)") { items = loaded }
            error = nil
        } catch let readError as DirectoryReadError {
            items = []
            error = readError
        } catch {
            items = []
            self.error = .other(error.localizedDescription)
        }
        selectedIDs = selectedIDs.intersection(Set(items.map(\.id)))
        DebugEventLog.measure("carga", "  git") { loadGitState(for: url) }
        availableCapacity = DebugEventLog.measure("carga", "  espacio del volumen") { VolumeInfoProvider().availableCapacity(for: url) }
        isCurrentDirectoryWritable = DebugEventLog.measure("carga", "  permisos de escritura") { FileManager.default.isWritableFile(atPath: url.path) }
    }
}
