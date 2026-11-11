import SwiftUI
import UniformTypeIdentifiers

/// Barra lateral al estilo Finder: Favoritos, Ubicaciones y Etiquetas. Cada
/// sección se pliega como en Finder y lo recuerda.
struct PlacesSidebarView: View {
    let sidebar: SidebarPlaces
    var savedSearches: [SavedSearchItem] = []
    let currentURL: URL
    /// Etiqueta cuyos archivos se muestran en el panel activo, si hay una.
    var shownTag: FinderColorTag? = nil
    let onSelect: (PlaceItem) -> Void
    var onSelectTag: ((FinderColorTag) -> Void)? = nil
    var onSelectSavedSearch: ((SavedSearchItem) -> Void)? = nil
    var onOpenInNewTab: ((URL) -> Void)? = nil
    var onOpenInSplitView: ((URL) -> Void)? = nil

    @State private var pendingEject: PlaceItem?
    @State private var showsEjectConfirmation = false
    @State private var infoTarget: PlaceItem?
    /// Fila cuyo selector de ícono está abierto.
    @State private var symbolTarget: Selection?
    @State private var ejectError: String?
    @State private var cachedVolumeUsages: [URL: Double] = [:]
    @AppStorage("sidebar.section.favorites") private var favoritesExpanded = true
    @AppStorage("sidebar.section.locations") private var locationsExpanded = true
    @AppStorage("sidebar.section.tags") private var tagsExpanded = true
    @AppStorage("sidebar.section.savedSearches") private var savedSearchesExpanded = true

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    /// Fila elegida de la barra lateral. La sección va en el valor porque la
    /// misma carpeta puede estar en Favoritos y en Ubicaciones.
    enum Selection: Hashable {
        case favorite(URL)
        case location(URL)
        case tag(FinderColorTag)
    }

    /// La selección sale de la carpeta que se está viendo: al entrar en una
    /// subcarpeta se deselecciona, y volver a tocar el favorito vuelve a navegar.
    private var selection: Binding<Selection?> {
        Binding(
            get: {
                if let shownTag {
                    return .tag(shownTag)
                }
                let key = PlacesProvider.sidebarKey(currentURL)
                if let place = sidebar.favorites.first(where: { PlacesProvider.sidebarKey($0.url) == key }) {
                    return .favorite(place.url)
                }
                if let place = sidebar.locations.first(where: { PlacesProvider.sidebarKey($0.url) == key }) {
                    return .location(place.url)
                }
                return nil
            },
            set: { newValue in
                let place: PlaceItem?
                switch newValue {
                case .favorite(let url): place = sidebar.favorites.first { $0.url == url }
                case .location(let url): place = sidebar.locations.first { $0.url == url }
                case .tag(let tag):
                    onSelectTag?(tag)
                    return
                case nil: place = nil
                }
                if let place { onSelect(place) }
            }
        )
    }

    private var volumePlaces: [PlaceItem] {
        sidebar.locations.filter { $0.kind == .volume }
    }

    var body: some View {
        // Selección nativa, como Finder: las filas no son botones, así la lista
        // recibe el clic y puede arrastrar Favoritos para reordenarlos.
        List(selection: selection) {
            Section(isExpanded: $favoritesExpanded) {
                ForEach(sidebar.favorites) { place in
                    placeRow(place, row: .favorite(place.url))
                        .tag(Selection.favorite(place.url))
                }
                // Reordenar arrastrando, como en Finder.
                .onMove { source, destination in
                    PlacesProvider().moveFavorites(fromOffsets: source, toOffset: destination)
                }
                // Carpetas soltadas desde la lista de archivos o desde Finder.
                .onInsert(of: [.fileURL]) { index, providers in
                    for (offset, provider) in providers.enumerated() {
                        _ = provider.loadTransferable(type: URL.self) { result in
                            guard let url = try? result.get() else { return }
                            Task { @MainActor in
                                PlacesProvider().insertFavorites([url], at: index + offset)
                            }
                        }
                    }
                }
            } header: {
                Text(String(localized: "Favoritos", bundle: #bundle))
                    .font(.xsSidebarHeader)
                    .foregroundStyle(.secondary)
            }

            Section(isExpanded: $locationsExpanded) {
                ForEach(sidebar.locations) { place in
                    placeRow(place, row: .location(place.url))
                        .tag(Selection.location(place.url))
                }
            } header: {
                Text(String(localized: "Ubicaciones", bundle: #bundle))
                    .font(.xsSidebarHeader)
                    .foregroundStyle(.secondary)
            }

            if onSelectTag != nil, !sidebar.tags.isEmpty {
                Section(isExpanded: $tagsExpanded) {
                    ForEach(sidebar.tags) { tag in
                        tagRow(tag)
                            .tag(Selection.tag(tag))
                    }
                } header: {
                    Text(String(localized: "Etiquetas", bundle: #bundle))
                        .font(.xsSidebarHeader)
                        .foregroundStyle(.secondary)
                }
            }

            if !savedSearches.isEmpty {
                Section(isExpanded: $savedSearchesExpanded) {
                    ForEach(savedSearches) { saved in
                        Button {
                            onSelectSavedSearch?(saved)
                        } label: {
                            Label {
                                Text(saved.name)
                                    .lineLimit(1)
                            } icon: {
                                Image(systemName: "magnifyingglass.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(String(localized: "Ejecutar búsqueda", bundle: #bundle), menuIcon: "magnifyingglass") {
                                onSelectSavedSearch?(saved)
                            }
                            Divider()
                            Button(String(localized: "Quitar búsqueda guardada", bundle: #bundle), menuIcon: "trash", role: .destructive) {
                                PlacesProvider().removeSavedSearch(id: saved.id)
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "Búsquedas guardadas", bundle: #bundle))
                        .font(.xsSidebarHeader)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            refreshVolumeUsages()
        }
        .onChange(of: sidebar) { _, _ in
            refreshVolumeUsages()
        }
        .alert(
            String(localized: "¿Expulsar este volumen?", bundle: #bundle),
            isPresented: $showsEjectConfirmation,
            presenting: pendingEject
        ) { place in
            Button(String(localized: "Expulsar", bundle: #bundle)) {
                do {
                    try VolumeEjectService().eject(place.url)
                } catch {
                    ejectError = error.localizedDescription
                }
            }
            Button(String(localized: "Cancelar", bundle: #bundle), role: .cancel) {}
        } message: { place in
            Text(String(localized: "Se expulsará «\(place.name)».", bundle: #bundle))
        }
        .alert(
            String(localized: "No se pudo expulsar", bundle: #bundle),
            isPresented: Binding(
                get: { ejectError != nil },
                set: { if !$0 { ejectError = nil } }
            )
        ) {
            Button(String(localized: "OK", bundle: #bundle)) { ejectError = nil }
        } message: {
            Text(ejectError ?? "")
        }
        .alert(
            infoTarget?.name ?? "",
            isPresented: Binding(
                get: { infoTarget != nil },
                set: { if !$0 { infoTarget = nil } }
            )
        ) {
            Button(String(localized: "OK", bundle: #bundle)) { infoTarget = nil }
        } message: {
            Text(infoMessage)
        }
    }

    @ViewBuilder
    private func placeRow(_ place: PlaceItem, row: Selection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label {
                    Text(place.localizedDisplayName)
                        .lineLimit(1)
                } icon: {
                    // Los símbolos de la barra lateral de Finder.
                    Image(systemName: place.sidebarSymbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if place.kind == .volume && place.isEjectable {
                    Button {
                        pendingEject = place
                        showsEjectConfirmation = true
                    } label: {
                        Image(systemName: "eject.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Expulsar \(place.localizedDisplayName)", bundle: #bundle))
                    .accessibilityLabel(String(localized: "Expulsar \(place.localizedDisplayName)", bundle: #bundle))
                }
            }

            if place.kind == .volume, let usage = cachedVolumeUsages[place.url] ?? computeVolumeUsageFraction(for: place.url) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                            .frame(height: 3.5)
                        Capsule()
                            .fill(usage > 0.9 ? Color.orange : Color.accentColor)
                            .frame(width: max(4, geo.size.width * usage), height: 3.5)
                    }
                    .environment(\.controlActiveState, .key)
                }
                .frame(height: 3.5)
                .padding(.leading, 24)
                .padding(.trailing, 4)
            }
        }
        .padding(.vertical, 2.5)
        .popover(
            isPresented: Binding(
                get: { symbolTarget == row },
                set: { if !$0 { symbolTarget = nil } }
            ),
            arrowEdge: .trailing
        ) {
            SidebarSymbolPicker(current: place.sidebarSymbol, defaultSymbol: place.defaultSidebarSymbol) { symbol in
                PlacesProvider().setSidebarSymbol(symbol, for: place)
                symbolTarget = nil
            }
        }
        .contextMenu {
            Button(String(localized: "Abrir", bundle: #bundle), menuIcon: "arrow.up.forward.square") {
                onSelect(place)
            }
            if let onOpenInNewTab {
                Button(String(localized: "Abrir en una pestaña nueva", bundle: #bundle), menuIcon: "plus.square.on.square") {
                    onOpenInNewTab(place.url)
                }
            }
            if let onOpenInSplitView {
                Button(String(localized: "Abrir en vista dividida", bundle: #bundle), menuIcon: "rectangle.split.2x1") {
                    onOpenInSplitView(place.url)
                }
            }
            if place.kind == .volume {
                Divider()
                Button(String(localized: "Información", bundle: #bundle), menuIcon: "info.circle") {
                    infoTarget = place
                }
                if place.isEjectable {
                    Button(String(localized: "Expulsar", bundle: #bundle), menuIcon: "eject") {
                        pendingEject = place
                        showsEjectConfirmation = true
                    }
                }
            }
            Divider()
            Button(String(localized: "Cambiar ícono…", bundle: #bundle), menuIcon: "square.grid.3x3") {
                symbolTarget = row
            }
            // Como Finder. Lo agregado por el usuario se borra; lo demás se
            // oculta y vuelve desde Ajustes → Barra lateral.
            Button(String(localized: "Quitar de la barra lateral", bundle: #bundle), menuIcon: "minus.circle") {
                PlacesProvider().removeFromSidebar(place)
            }
        }
    }

    /// Como Finder: un punto del color y el nombre de la etiqueta.
    private func tagRow(_ tag: FinderColorTag) -> some View {
        Label {
            Text(tag.title)
                .lineLimit(1)
        } icon: {
            Circle()
                .fill(Color(nsColor: tag.nsColor ?? .secondaryLabelColor))
                .frame(width: 10, height: 10)
        }
        .padding(.vertical, 2.5)
        .contextMenu {
            Button(String(localized: "Quitar de la barra lateral", bundle: #bundle), menuIcon: "minus.circle") {
                PlacesProvider().setTagHiddenInSidebar(true, for: tag)
            }
        }
    }

    private func refreshVolumeUsages() {
        var updated: [URL: Double] = [:]
        for place in volumePlaces {
            if let usage = computeVolumeUsageFraction(for: place.url) {
                updated[place.url] = usage
            }
        }
        cachedVolumeUsages = updated
    }

    private func computeVolumeUsageFraction(for url: URL) -> Double? {
        let info = VolumeInfoProvider().info(for: url)
        guard let total = info.totalCapacity, let available = info.availableCapacity, total > 0 else {
            return nil
        }
        let used = max(0, total - available)
        return min(1.0, Double(used) / Double(total))
    }

    private var infoMessage: String {
        guard let target = infoTarget else { return "" }
        let info = VolumeInfoProvider().info(for: target.url)
        let total = info.totalCapacity.map(Self.sizeFormatter.string(fromByteCount:)) ?? "—"
        let available = info.availableCapacity.map(Self.sizeFormatter.string(fromByteCount:)) ?? "—"
        let format = info.format ?? "—"
        return String(localized: "Formato: \(format)\nCapacidad: \(total)\nLibre: \(available)", bundle: #bundle)
    }
}

private extension Font {
    static let xsSidebarHeader = Font.system(size: 11, weight: .semibold)
}
