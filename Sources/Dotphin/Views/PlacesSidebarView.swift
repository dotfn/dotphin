import SwiftUI

struct PlacesSidebarView: View {
    let places: [PlaceItem]
    var savedSearches: [SavedSearchItem] = []
    let currentURL: URL
    let onSelect: (PlaceItem) -> Void
    var onSelectSavedSearch: ((SavedSearchItem) -> Void)? = nil
    var onOpenInNewTab: ((URL) -> Void)? = nil
    var onOpenInSplitView: ((URL) -> Void)? = nil
    var onSelectFolder: ((URL) -> Void)?

    @State private var pendingEject: PlaceItem?
    @State private var showsEjectConfirmation = false
    @State private var infoTarget: PlaceItem?
    @State private var ejectError: String?
    @State private var cachedVolumeUsages: [URL: Double] = [:]
    @State private var folderTreeShowsHiddenFiles = false
    @State private var folderTreeLimitToHome = true

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var standardPlaces: [PlaceItem] {
        places.filter { $0.kind == .bookmark || $0.kind == .customBookmark }
    }

    private var volumePlaces: [PlaceItem] {
        places.filter { $0.kind == .volume }
    }

    var body: some View {
        List {
            Section {
                ForEach(standardPlaces) { place in
                    placeRow(place)
                }
            } header: {
                Text(String(localized: "Lugares", bundle: #bundle))
                    .font(.xsSidebarHeader)
                    .foregroundStyle(.secondary)
            }

            if !savedSearches.isEmpty {
                Section {
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

            if !volumePlaces.isEmpty {
                Section {
                    ForEach(volumePlaces) { place in
                        placeRow(place)
                    }
                } header: {
                    Text(String(localized: "Dispositivos", bundle: #bundle))
                        .font(.xsSidebarHeader)
                        .foregroundStyle(.secondary)
                }
            }

            if let onSelectFolder {
                Section {
                    FolderTreeRow(
                        url: folderTreeLimitToHome
                            ? FileManager.default.homeDirectoryForCurrentUser
                            : URL(fileURLWithPath: "/"),
                        currentURL: currentURL,
                        showsHiddenFiles: $folderTreeShowsHiddenFiles,
                        limitToHomeDirectory: $folderTreeLimitToHome,
                        onSelect: onSelectFolder,
                        onOpenInNewTab: onOpenInNewTab,
                        onOpenInSplitView: onOpenInSplitView
                    )
                } header: {
                    Text(String(localized: "Carpetas", bundle: #bundle))
                        .font(.xsSidebarHeader)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            refreshVolumeUsages()
        }
        .onChange(of: places) { _, _ in
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
    private func placeRow(_ place: PlaceItem) -> some View {
        let isSelected = place.url.standardizedFileURL.path == currentURL.standardizedFileURL.path
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    onSelect(place)
                } label: {
                    Label {
                        Text(place.localizedDisplayName)
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: place.systemImage)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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
        .animation(.snappy(duration: 0.16), value: isSelected)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .padding(.horizontal, 4)
        )
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
            if place.kind == .customBookmark {
                Divider()
                Button(String(localized: "Quitar de Lugares", bundle: #bundle), menuIcon: "bookmark.slash", role: .destructive) {
                    PlacesProvider().removeBookmark(for: place.url)
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
