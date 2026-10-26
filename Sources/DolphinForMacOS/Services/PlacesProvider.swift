import Foundation

struct PlacesProvider {
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
        staticBookmarks() + mountedVolumes()
    }
}
