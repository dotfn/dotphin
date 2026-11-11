import SwiftUI

/// Ajustes → Barra lateral, como en Finder: qué se muestra en Favoritos y en
/// Ubicaciones. Lo que se quita con clic derecho vuelve desde acá.
struct SidebarSettingsView: View {
    @State private var favorites = PlacesProvider().favorites(includingHidden: true)
    @State private var locations = PlacesProvider().locations(includingHidden: true)
    @State private var hidden: Set<String> = []
    @State private var hiddenTags: Set<FinderColorTag> = []

    var body: some View {
        Form {
            Section(String(localized: "Favoritos", bundle: #bundle)) {
                ForEach(favorites) { place in
                    toggle(for: place)
                }
            }
            Section(String(localized: "Ubicaciones", bundle: #bundle)) {
                ForEach(locations) { place in
                    toggle(for: place)
                }
            }
            Section(String(localized: "Etiquetas", bundle: #bundle)) {
                ForEach(PlacesProvider().sidebarTags(includingHidden: true)) { tag in
                    Toggle(isOn: Binding(
                        get: { !hiddenTags.contains(tag) },
                        set: { PlacesProvider().setTagHiddenInSidebar(!$0, for: tag) }
                    )) {
                        Label {
                            Text(tag.title)
                        } icon: {
                            Circle()
                                .fill(Color(nsColor: tag.nsColor ?? .secondaryLabelColor))
                                .frame(width: 10, height: 10)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .placesBookmarksDidChange)) { _ in reload() }
    }

    private func toggle(for place: PlaceItem) -> some View {
        Toggle(isOn: Binding(
            get: { !hidden.contains(PlacesProvider.sidebarKey(place.url)) },
            set: { PlacesProvider().setHiddenInSidebar(!$0, for: place) }
        )) {
            Label {
                Text(place.localizedDisplayName)
            } icon: {
                Image(systemName: place.sidebarSymbol)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func reload() {
        let provider = PlacesProvider()
        favorites = provider.favorites(includingHidden: true)
        locations = provider.locations(includingHidden: true)
        hidden = Set((favorites + locations).filter(provider.isHiddenInSidebar).map { PlacesProvider.sidebarKey($0.url) })
        hiddenTags = Set(provider.sidebarTags(includingHidden: true).filter(provider.isTagHiddenInSidebar))
    }
}
