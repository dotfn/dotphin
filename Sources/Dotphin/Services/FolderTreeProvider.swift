import Foundation

struct FolderTreeProvider {
    var showsHiddenFiles: Bool = false

    func subdirectories(of url: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .isPackageKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            return []
        }

        return entries
            .filter { entry in
                guard let values = try? entry.resourceValues(forKeys: keys),
                      values.isDirectory == true,
                      // Un paquete (`.app`) no se despliega como carpeta.
                      values.isPackage != true else { return false }
                let isHidden = values.isHidden ?? entry.lastPathComponent.hasPrefix(".")
                return showsHiddenFiles || !isHidden
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
