import Foundation
import Observation

@Observable
final class TabsViewModel {
    private(set) var tabs: [Tab]
    private(set) var selectedTabID: Tab.ID

    var selectedTab: Tab? { tabs.first { $0.id == selectedTabID } }

    init(startingAt url: URL) {
        let first = Tab(id: UUID(), primary: BrowserViewModel(startingAt: url), secondary: nil, focusedPaneIndex: 0)
        self.tabs = [first]
        self.selectedTabID = first.id
    }

    func addTab(startingAt url: URL) {
        let tab = Tab(id: UUID(), primary: BrowserViewModel(startingAt: url), secondary: nil, focusedPaneIndex: 0)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func closeTab(_ id: Tab.ID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedTabID == id {
            let newIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[newIndex].id
        }
    }

    func selectTab(_ id: Tab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func toggleSplit(for id: Tab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if tabs[index].isSplit {
            tabs[index].secondary = nil
            tabs[index].focusedPaneIndex = 0
        } else {
            tabs[index].secondary = BrowserViewModel(startingAt: tabs[index].primary.currentURL)
        }
    }

    func setFocusedPane(_ index: Int, for id: Tab.ID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        guard tabs[tabIndex].isSplit || index == 0 else { return }
        tabs[tabIndex].focusedPaneIndex = index
    }
}
