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

    private let reader: DirectoryReader
    private let store: ViewPropertiesStore
    private let operations: FileOperationsService

    init(
        startingAt url: URL,
        reader: DirectoryReader = DirectoryReader(),
        store: ViewPropertiesStore = ViewPropertiesStore(),
        operations: FileOperationsService = FileOperationsService()
    ) {
        self.currentURL = url
        self.reader = reader
        self.store = store
        self.operations = operations
        self.viewProperties = store.properties(for: url)
        load(url)
    }

    func navigate(to url: URL) {
        currentURL = url
        viewProperties = store.properties(for: url)
        selectedItem = nil
        filterText = ""
        load(url)
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
        } catch let opError as FileOperationError {
            operationError = opError
        } catch {
            operationError = .other(error.localizedDescription)
        }
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        do {
            try operations.moveToTrash(item)
            selectedItem = nil
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
    }
}
