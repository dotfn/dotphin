import SwiftUI

struct PlacesSidebarView: View {
    let places: [PlaceItem]
    let onSelect: (PlaceItem) -> Void

    @State private var selection: PlaceItem.ID?

    var body: some View {
        List(places, selection: $selection) { place in
            Label(place.name, systemImage: place.systemImage)
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue, let place = places.first(where: { $0.id == newValue }) else { return }
            onSelect(place)
        }
    }
}
