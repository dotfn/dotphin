import Foundation
import Observation

@Observable
final class BrowserViewModel {
    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    private(set) var error: DirectoryReadError?
    private(set) var viewProperties: ViewProperties
    private(set) var selectedItem: FileItem?
    var filterText: String = "" {
        didSet {
            if let selectedItem, !filteredItems.contains(selectedItem) {
                self.selectedItem = nil
            }
        }
    }

    var filteredItems: [FileItem] {
        guard !filterText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
    }

    private(set) var operationError: FileOperationError?

    var searchQuery: String = "" {
        didSet {
            selectedItem = nil
        }
    }
    private(set) var searchResults: [FileItem] = []

    private(set) var gitStatuses: [String: GitFileStatus] = [:]

    private let reader: DirectoryReader
    private let store: ViewPropertiesStore
    private let operations: FileOperationsService
    private let search: SearchService
    private let trashURL: URL
    private let gitStatus: GitStatusProvider

    var isBrowsingTrash: Bool {
        currentURL.standardizedFileURL.path == trashURL.standardizedFileURL.path
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
        currentURL = url
        viewProperties = store.properties(for: url)
        selectedItem = nil
        filterText = ""
        searchQuery = ""
        searchResults = []
        load(url)
    }

    func performSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        searchResults = search.search(for: searchQuery, in: currentURL)
    }

    func select(_ item: FileItem?) {
        selectedItem = item
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
        items = items.sorted(by: field, ascending: ascending)
    }

    func setZoomLevel(_ level: Double) {
        viewProperties.zoomLevel = level
        store.setProperties(viewProperties, for: currentURL)
    }

    func renameSelected(to newName: String) {
        guard let item = selectedItem else { return }
        do {
            _ = try operations.rename(item, to: newName)
            refresh()
            selectedItem = items.first { $0.name == newName }
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        delete(item)
    }

    func delete(_ item: FileItem) {
        do {
            try operations.moveToTrash(item)
            refresh()
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    func createFolder(named name: String) {
        do {
            _ = try operations.createFolder(in: currentURL, named: name)
            refresh()
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    func clearOperationError() {
        operationError = nil
    }

    func moveDroppedItems(_ urls: [URL], into directory: URL) {
        defer { refresh() }
        var failures: [String] = []
        for url in urls {
            do {
                _ = try operations.move(url, toDirectory: directory)
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        if !failures.isEmpty {
            operationError = .other("No se pudieron mover: \(failures.joined(separator: ", "))")
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
        guard let item = selectedItem else { return }
        do {
            _ = try operations.restore(item, to: FileManager.default.homeDirectoryForCurrentUser)
            selectedItem = nil
            refresh()
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    private func load(_ url: URL) {
        do {
            items = try reader.contents(of: url, sortField: viewProperties.sortField, ascending: viewProperties.ascending)
            error = nil
        } catch let readError as DirectoryReadError {
            items = []
            error = readError
        } catch {
            items = []
            self.error = .other(error.localizedDescription)
        }
        selectedItem = selectedItem.flatMap { current in items.first { $0.id == current.id } }
        gitStatuses = gitStatus.statuses(in: url)
    }
}
