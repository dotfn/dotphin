import Foundation
import Observation

@Observable
final class BrowserViewModel {
    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    private(set) var error: DirectoryReadError?
    private(set) var viewProperties: ViewProperties
    private(set) var selectedItem: FileItem?
    var filterText: String = ""

    var filteredItems: [FileItem] {
        guard !filterText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
    }

    private let reader: DirectoryReader
    private let store: ViewPropertiesStore

    init(startingAt url: URL, reader: DirectoryReader = DirectoryReader(), store: ViewPropertiesStore = ViewPropertiesStore()) {
        self.currentURL = url
        self.reader = reader
        self.store = store
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
