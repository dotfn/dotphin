import SwiftUI

struct ContentView: View {
    @State private var tabsViewModel = TabsViewModel(
        startingAt: AppSettingsStore().settings().startupURL
    )
    @State private var showsInfoPanel = false
    private let places = PlacesProvider().allPlaces()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                PlacesSidebarView(
                    places: places,
                    currentURL: tabsViewModel.selectedTab?.focused.currentURL ?? FileManager.default.homeDirectoryForCurrentUser
                ) { place in
                    tabsViewModel.selectedTab?.focused.navigate(to: place.url)
                }
                .frame(maxHeight: 200)

                Divider()

                List {
                    FolderTreeRow(url: FileManager.default.homeDirectoryForCurrentUser) { url in
                        tabsViewModel.selectedTab?.focused.navigate(to: url)
                    }
                }
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
                        .help("Dividir vista")
                        .accessibilityLabel("Dividir vista")
                    }
                    Button {
                        showsInfoPanel.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .padding(.trailing, 8)
                    .help("Mostrar/ocultar panel de información")
                    .accessibilityLabel("Mostrar/ocultar panel de información")
                }
                Divider()
                if let tab = tabsViewModel.selectedTab {
                    SplitBrowserView(tab: tab) { index in
                        tabsViewModel.setFocusedPane(index, for: tab.id)
                    }
                }
            }
            .inspector(isPresented: $showsInfoPanel) {
                InfoPanelView(item: tabsViewModel.selectedTab?.focused.selectedItem)
            }
        }
    }
}
