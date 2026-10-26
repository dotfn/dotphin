import SwiftUI

struct PlacesSidebarView: View {
    let places: [PlaceItem]
    let currentURL: URL
    let onSelect: (PlaceItem) -> Void

    var body: some View {
        List(places) { place in
            Button {
                onSelect(place)
            } label: {
                Label(place.name, systemImage: place.systemImage)
            }
            .buttonStyle(.plain)
            .listRowBackground(
                place.url == currentURL ? Color.accentColor.opacity(0.15) : Color.clear
            )
        }
    }
}
