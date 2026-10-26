import SwiftUI

struct ContentView: View {
    @State private var tabsViewModel = TabsViewModel(
        startingAt: FileManager.default.homeDirectoryForCurrentUser
    )
    private let places = PlacesProvider().allPlaces()

    var body: some View {
        NavigationSplitView {
            PlacesSidebarView(
                places: places,
                currentURL: tabsViewModel.selectedTab?.focused.currentURL ?? FileManager.default.homeDirectoryForCurrentUser
            ) { place in
                tabsViewModel.selectedTab?.focused.navigate(to: place.url)
            }
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    TabBarView(viewModel: tabsViewModel)
                    if let tab = tabsViewModel.selectedTab {
                        Button {
                            tabsViewModel.toggleSplit(for: tab.id)
                        } label: {
                            Image(systemName: "rectangle.split.2x1")
                        }
                        .padding(.trailing, 8)
                    }
                }
                Divider()
                if let tab = tabsViewModel.selectedTab {
                    SplitBrowserView(tab: tab) { index in
                        tabsViewModel.setFocusedPane(index, for: tab.id)
                    }
                }
            }
        }
    }
}
