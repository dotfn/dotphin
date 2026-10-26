import SwiftUI

struct ContentView: View {
    @State private var viewModel = BrowserViewModel(
        startingAt: FileManager.default.homeDirectoryForCurrentUser
    )
    private let places = PlacesProvider().allPlaces()

    var body: some View {
        NavigationSplitView {
            PlacesSidebarView(places: places, currentURL: viewModel.currentURL) { place in
                viewModel.navigate(to: place.url)
            }
        } detail: {
            BrowserView(viewModel: viewModel)
        }
    }
}
