import Foundation

extension Notification.Name {
    static let placesBookmarksDidChange = Notification.Name("Dotphin.placesBookmarksDidChange")
}

struct PlacesProvider {
    let defaults: UserDefaults
    private static let customBookmarksKey = "dolphin.customBookmarks"
    private static let savedSearchesKey = "dolphin.savedSearches"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func savedSearches() -> [SavedSearchItem] {
        guard let data = defaults.data(forKey: Self.savedSearchesKey),
              let decoded = try? JSONDecoder().decode([SavedSearchItem].self, from: data) else {
            return []
        }
        return decoded
    }

    func addSavedSearch(_ item: SavedSearchItem) {
        var current = savedSearches()
        current.append(item)
        saveSavedSearches(current)
    }

    func removeSavedSearch(id: UUID) {
        var current = savedSearches()
        current.removeAll { $0.id == id }
        saveSavedSearches(current)
    }

    private func saveSavedSearches(_ items: [SavedSearchItem]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.savedSearchesKey)
            NotificationCenter.default.post(name: .placesBookmarksDidChange, object: nil)
        }
    }

    func staticBookmarks() -> [PlaceItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Desktop")
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Documents")
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Downloads")
        let trash = (try? fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) ?? home.appendingPathComponent(".Trash")

        return [
            PlaceItem(url: home, name: "Home", systemImage: "house", kind: .bookmark),
            PlaceItem(url: desktop, name: "Desktop", systemImage: "desktopcomputer", kind: .bookmark),
            PlaceItem(url: documents, name: "Documents", systemImage: "doc.text", kind: .bookmark),
            PlaceItem(url: downloads, name: "Downloads", systemImage: "arrow.down.circle", kind: .bookmark),
            PlaceItem(url: trash, name: "Trash", systemImage: "trash", kind: .bookmark),
        ]
    }

    func customBookmarks() -> [PlaceItem] {
        guard let data = defaults.data(forKey: Self.customBookmarksKey),
              let decoded = try? JSONDecoder().decode([PlaceItem].self, from: data) else {
            return []
        }
        return decoded
    }

    func isBookmarked(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if staticBookmarks().contains(where: { $0.url.standardizedFileURL.path == path }) {
            return true
        }
        return customBookmarks().contains(where: { $0.url.standardizedFileURL.path == path })
    }

    func addBookmark(for url: URL, name: String? = nil, systemImage: String = "bookmark.fill") {
        let normalized = url.standardizedFileURL
        guard !favorites(includingHidden: true).contains(where: { Self.sidebarKey($0.url) == Self.sidebarKey(normalized) }) else { return }
        var current = customBookmarks()
        let rawTitle = name ?? (normalized.lastPathComponent.isEmpty ? normalized.path : normalized.lastPathComponent)
        current.append(
            PlaceItem(
                url: normalized,
                name: rawTitle,
                systemImage: systemImage,
                kind: .customBookmark,
                isEjectable: false
            )
        )
        saveCustomBookmarks(current)
    }

    func removeBookmark(for url: URL) {
        let path = url.standardizedFileURL.path
        var current = customBookmarks()
        current.removeAll { $0.url.standardizedFileURL.path == path }
        saveCustomBookmarks(current)
    }

    func renameBookmark(for url: URL, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let path = url.standardizedFileURL.path
        var current = customBookmarks()
        guard let idx = current.firstIndex(where: { $0.url.standardizedFileURL.path == path }) else { return }
        let existing = current[idx]
        current[idx] = PlaceItem(
            url: existing.url,
            name: trimmed,
            systemImage: existing.systemImage,
            kind: existing.kind,
            isEjectable: existing.isEjectable
        )
        saveCustomBookmarks(current)
    }

    func moveBookmark(from sourceIndex: Int, to destinationIndex: Int) {
        var current = customBookmarks()
        guard current.indices.contains(sourceIndex),
              current.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else { return }
        let item = current.remove(at: sourceIndex)
        current.insert(item, at: destinationIndex)
        saveCustomBookmarks(current)
    }

    /// Replicates `DolphinBookmarkHandler::bookmarkTabsAsFolderAction` (`add_bookmarks_list` in `dolphinbookmarkhandler.cpp`):
    /// bookmarks all provided tab URLs that are not yet bookmarked.
    func addBookmarks(for urls: [URL]) {
        for url in urls {
            addBookmark(for: url)
        }
    }

    private func saveCustomBookmarks(_ items: [PlaceItem]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.customBookmarksKey)
            NotificationCenter.default.post(name: .placesBookmarksDidChange, object: nil)
        }
    }

    func mountedVolumes() -> [PlaceItem] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey]
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return volumes.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isInternal = values?.volumeIsInternal ?? false
            let name = values?.volumeName ?? url.lastPathComponent
            let isEjectable = (values?.volumeIsEjectable ?? false) || (values?.volumeIsRemovable ?? false)
            return PlaceItem(
                url: url,
                name: name,
                systemImage: isInternal ? "internaldrive" : "externaldrive",
                kind: .volume,
                isEjectable: isEjectable
            )
        }
    }

    func allPlaces() -> [PlaceItem] {
        staticBookmarks() + customBookmarks() + mountedVolumes()
    }
}
