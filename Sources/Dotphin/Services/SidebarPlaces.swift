import Foundation

/// Lo que muestra la barra lateral, como en Finder: Favoritos, Ubicaciones y Etiquetas.
struct SidebarPlaces: Equatable {
    var favorites: [PlaceItem]
    var locations: [PlaceItem]
    var tags: [FinderColorTag] = []
}

extension PlaceItem {
    /// El símbolo que usa Finder en su barra lateral para esta carpeta o disco.
    var sidebarSymbol: String {
        customSymbol ?? defaultSidebarSymbol
    }

    /// El símbolo que usa Finder en su barra lateral para esta carpeta o disco.
    var defaultSidebarSymbol: String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if kind == .volume {
            return path == "/" || systemImage == "internaldrive" ? "internaldrive" : "externaldrive"
        }
        if name == "Trash" { return "trash" }
        if path == home { return "house" }
        if path.hasSuffix("/com~apple~CloudDocs") { return "icloud" }
        if path == "/Applications" { return "a.circle" }
        let known: [String: String] = [
            "Desktop": "menubar.dock.rectangle",
            "Documents": "doc",
            "Downloads": "arrow.down.circle",
            "Developer": "hammer",
            "Movies": "film",
            "Music": "music.note",
            "Pictures": "photo",
            "Public": "person.2",
            "Library": "building.columns",
        ]
        if (path as NSString).deletingLastPathComponent == home, let symbol = known[url.lastPathComponent] {
            return symbol
        }
        return "folder"
    }
}

/// Orden de Favoritos y elementos ocultos de la barra lateral. Ocultar no
/// borra nada: se vuelve a mostrar desde Ajustes → Barra lateral.
extension PlacesProvider {
    private static let hiddenSidebarItemsKey = "sidebar.hiddenItems"
    private static let favoritesOrderKey = "sidebar.favoritesOrder"
    private static let customSymbolsKey = "sidebar.customSymbols"

    /// Símbolos que ofrece "Cambiar ícono…".
    static let symbolChoices = [
        "folder", "house", "doc", "doc.text", "tray", "tray.full", "archivebox", "shippingbox",
        "hammer", "wrench.and.screwdriver", "terminal", "chevron.left.forwardslash.chevron.right", "curlybraces", "globe",
        "network", "server.rack", "desktopcomputer", "laptopcomputer", "menubar.dock.rectangle", "arrow.down.circle", "icloud",
        "externaldrive", "internaldrive", "a.circle", "photo", "film", "music.note", "mic",
        "video", "camera", "paintbrush", "pencil", "book", "books.vertical", "graduationcap",
        "briefcase", "building.columns", "person", "person.2", "heart", "star", "bookmark",
        "flag", "tag", "gamecontroller", "cart", "creditcard", "banknote", "chart.bar",
        "calendar", "clock", "lock", "key", "gearshape", "leaf", "airplane", "trash",
    ]

    static func sidebarKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    func sidebarPlaces() -> SidebarPlaces {
        SidebarPlaces(favorites: favorites(), locations: locations(), tags: sidebarTags())
    }

    // MARK: Favoritos

    /// Las carpetas que Finder trae en Favoritos.
    func builtInFavorites() -> [PlaceItem] {
        let applications = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
            ?? URL(fileURLWithPath: "/Applications")
        return staticBookmarks().filter { ["Desktop", "Documents", "Downloads"].contains($0.name) }
            + [PlaceItem(url: applications, name: "Applications", systemImage: "square.grid.3x3", kind: .bookmark)]
    }

    /// Favoritos en el orden elegido por el usuario; los que no tienen lugar
    /// guardado (recién agregados) van al final.
    func favorites(includingHidden: Bool = false) -> [PlaceItem] {
        let all = withCustomSymbols(builtInFavorites() + customBookmarks())
        let order = defaults.stringArray(forKey: Self.favoritesOrderKey) ?? []
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = all.enumerated().sorted { lhs, rhs in
            let left = position[Self.sidebarKey(lhs.element.url)] ?? order.count + lhs.offset
            let right = position[Self.sidebarKey(rhs.element.url)] ?? order.count + rhs.offset
            return left < right
        }.map(\.element)
        return includingHidden ? sorted : sorted.filter { !isHiddenInSidebar($0) }
    }

    /// Mueve Favoritos visibles (como `onMove` de SwiftUI); los ocultos
    /// conservan su lugar relativo.
    func moveFavorites(fromOffsets source: IndexSet, toOffset destination: Int) {
        let visible = favorites()
        let moving = source.map { visible[$0] }
        guard !moving.isEmpty else { return }
        var full = favorites(includingHidden: true)
        full.removeAll { item in moving.contains(item) }
        let anchor = visible[destination...].first { !moving.contains($0) }
        let insertAt = anchor.flatMap { full.firstIndex(of: $0) } ?? full.count
        full.insert(contentsOf: moving, at: insertAt)
        defaults.set(full.map { Self.sidebarKey($0.url) }, forKey: Self.favoritesOrderKey)
        NotificationCenter.default.post(name: .placesBookmarksDidChange, object: nil)
    }

    /// Si `url` se ve en Favoritos.
    func isInFavorites(_ url: URL) -> Bool {
        favorites().contains { Self.sidebarKey($0.url) == Self.sidebarKey(url) }
    }

    /// "Añadir a Favoritos": una carpeta de serie (o una oculta) vuelve a
    /// mostrarse; cualquier otra se agrega al final.
    func addToFavorites(_ url: URL, name: String? = nil) {
        if let existing = favorites(includingHidden: true).first(where: { Self.sidebarKey($0.url) == Self.sidebarKey(url) }) {
            setHiddenInSidebar(false, for: existing)
        } else {
            addBookmark(for: url, name: name)
        }
    }

    /// "Quitar de Favoritos", también para las carpetas de serie.
    func removeFromFavorites(_ url: URL) {
        guard let favorite = favorites(includingHidden: true).first(where: { Self.sidebarKey($0.url) == Self.sidebarKey(url) }) else { return }
        removeFromSidebar(favorite)
    }

    /// Carpetas soltadas en Favoritos: se agregan (o vuelven a mostrarse) en
    /// la posición `index` de la lista visible, como en Finder. Una que ya
    /// estaba se mueve ahí.
    func insertFavorites(_ urls: [URL], at index: Int) {
        let folders = urls.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return values?.isDirectory == true && values?.isPackage != true
        }
        guard !folders.isEmpty else { return }
        for folder in folders where !isInFavorites(folder) {
            addToFavorites(folder)
        }
        let keys = Set(folders.map(Self.sidebarKey))
        let visible = favorites()
        let offsets = IndexSet(visible.indices.filter { keys.contains(Self.sidebarKey(visible[$0].url)) })
        moveFavorites(fromOffsets: offsets, toOffset: min(index, visible.count))
    }

    // MARK: Ubicaciones

    /// Carpeta personal, disco de arranque, iCloud Drive, otros discos y Papelera.
    func locations(includingHidden: Bool = false) -> [PlaceItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var result = [PlaceItem(url: home, name: home.lastPathComponent, systemImage: "house", kind: .bookmark)]
        let volumes = mountedVolumes()
        result += volumes.filter { $0.url.path == "/" }
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if fm.fileExists(atPath: iCloud.path) {
            result.append(PlaceItem(url: iCloud, name: "iCloud Drive", systemImage: "icloud", kind: .bookmark))
        }
        result += volumes.filter { $0.url.path != "/" }
        result += staticBookmarks().filter { $0.name == "Trash" }
        result = withCustomSymbols(result)
        return includingHidden ? result : result.filter { !isHiddenInSidebar($0) }
    }

    // MARK: Íconos

    /// "Cambiar ícono…": `nil` vuelve al símbolo de Finder. Solo cambia la
    /// barra lateral, no la carpeta.
    func setSidebarSymbol(_ symbol: String?, for place: PlaceItem) {
        var symbols = defaults.dictionary(forKey: Self.customSymbolsKey) as? [String: String] ?? [:]
        symbols[Self.sidebarKey(place.url)] = symbol
        defaults.set(symbols, forKey: Self.customSymbolsKey)
        NotificationCenter.default.post(name: .placesBookmarksDidChange, object: nil)
    }

    private func withCustomSymbols(_ places: [PlaceItem]) -> [PlaceItem] {
        let symbols = defaults.dictionary(forKey: Self.customSymbolsKey) as? [String: String] ?? [:]
        guard !symbols.isEmpty else { return places }
        return places.map { place in
            var place = place
            place.customSymbol = symbols[Self.sidebarKey(place.url)]
            return place
        }
    }

    // MARK: Etiquetas

    /// Las etiquetas de color en el orden de Finder.
    func sidebarTags(includingHidden: Bool = false) -> [FinderColorTag] {
        let all = FinderColorTag.finderPaletteOrder
        return includingHidden ? all : all.filter { !isTagHiddenInSidebar($0) }
    }

    private static func sidebarKey(_ tag: FinderColorTag) -> String {
        "tag:\(tag.rawValue)"
    }

    func isTagHiddenInSidebar(_ tag: FinderColorTag) -> Bool {
        hiddenSidebarKeys().contains(Self.sidebarKey(tag))
    }

    func setTagHiddenInSidebar(_ hidden: Bool, for tag: FinderColorTag) {
        setHidden(hidden, key: Self.sidebarKey(tag))
    }

    // MARK: Ocultos

    func isHiddenInSidebar(_ place: PlaceItem) -> Bool {
        hiddenSidebarKeys().contains(Self.sidebarKey(place.url))
    }

    func setHiddenInSidebar(_ hidden: Bool, for place: PlaceItem) {
        setHidden(hidden, key: Self.sidebarKey(place.url))
    }

    private func setHidden(_ hidden: Bool, key: String) {
        var keys = hiddenSidebarKeys()
        if hidden { keys.insert(key) } else { keys.remove(key) }
        defaults.set(keys.sorted(), forKey: Self.hiddenSidebarItemsKey)
        NotificationCenter.default.post(name: .placesBookmarksDidChange, object: nil)
    }

    /// "Quitar de la barra lateral": un favorito agregado por el usuario se
    /// borra (como en Finder); el resto se oculta y vuelve desde Ajustes.
    func removeFromSidebar(_ place: PlaceItem) {
        if place.kind == .customBookmark {
            removeBookmark(for: place.url)
        } else {
            setHiddenInSidebar(true, for: place)
        }
    }

    private func hiddenSidebarKeys() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.hiddenSidebarItemsKey) ?? [])
    }
}
