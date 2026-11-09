import Foundation

struct FileMetadata {
    let kind: String
    let sizeText: String
    let modifiedText: String
}

struct FileMetadataFormatter {
    nonisolated(unsafe) private static let directorySizeCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 512
        return cache
    }()

    nonisolated(unsafe) private static let tooltipCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 512
        return cache
    }()

    nonisolated(unsafe) private static let permissionsCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 512
        return cache
    }()

    static func clearCaches() {
        directorySizeCache.removeAllObjects()
        tooltipCache.removeAllObjects()
        permissionsCache.removeAllObjects()
    }

    func metadata(for item: FileItem) -> FileMetadata {
        let kind: String
        if item.isDirectory {
            kind = "Carpeta"
        } else {
            let ext = item.url.pathExtension
            kind = ext.isEmpty ? "Documento" : ext.uppercased()
        }

        let sizeText = item.isDirectory
            ? "—"
            : ByteCountFormatter.string(fromByteCount: item.size ?? 0, countStyle: .file)

        let modifiedText = item.modificationDate.map {
            $0.formatted(date: .abbreviated, time: .shortened)
        } ?? "—"

        return FileMetadata(kind: kind, sizeText: sizeText, modifiedText: modifiedText)
    }

    /// Formats the size cell for a file or folder according to KDE Dolphin's `DirectorySizeMode` (`dolphin_contentdisplaysettings.kcfg`).
    func sizeDisplayText(for item: FileItem, directorySizeMode: DirectorySizeMode) -> String {
        if !item.isDirectory {
            return ByteCountFormatter.string(fromByteCount: item.size ?? 0, countStyle: .file)
        }
        if directorySizeMode == .none {
            return "—"
        }
        let modStamp = item.modificationDate?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(item.url.path)|\(modStamp)|\(directorySizeMode.rawValue)" as NSString
        if let cached = Self.directorySizeCache.object(forKey: cacheKey) {
            return cached as String
        }
        let computed: String
        switch directorySizeMode {
        case .none:
            computed = "—"
        case .contentCount:
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: item.url.path) else {
                return "—"
            }
            let visibleCount = entries.filter { !$0.hasPrefix(".") }.count
            computed = visibleCount == 1 ? "1 ítem" : "\(visibleCount) ítems"
        case .contentSize:
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: item.url,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return "—"
            }
            var totalBytes: Int64 = 0
            for child in urls {
                if let vals = try? child.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                   vals.isDirectory != true,
                   let sz = vals.fileSize {
                    totalBytes += Int64(sz)
                }
            }
            computed = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        }
        Self.directorySizeCache.setObject(computed as NSString, forKey: cacheKey)
        return computed
    }

    /// Formats POSIX permissions according to KDE Dolphin's `UsePermissionsFormat` (`SymbolicFormat`, `NumericFormat`, `CombinedFormat`).
    static func formatPermissions(_ mode: Int, format: PermissionsDisplayFormat) -> String {
        let symbolic = FilePropertiesSheetView.symbolicPermissions(mode)
        let octal = String(mode & 0o777, radix: 8)
        switch format {
        case .symbolic:
            return symbolic
        case .numeric:
            return octal
        case .combined:
            return "\(symbolic) (\(octal))"
        }
    }

    /// Cached POSIX permissions display string for a `FileItem` so table rows don't hit `attributesOfItem(atPath:)` on every redraw.
    func permissionsDisplayText(for item: FileItem, format: PermissionsDisplayFormat) -> String {
        let modStamp = item.modificationDate?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(item.url.path)|\(modStamp)|\(format.rawValue)" as NSString
        if let cached = Self.permissionsCache.object(forKey: cacheKey) {
            return cached as String
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: item.url.path),
              let posix = (attrs[.posixPermissions] as? NSNumber)?.intValue else {
            return "—"
        }
        let result = Self.formatPermissions(posix, format: format)
        Self.permissionsCache.setObject(result as NSString, forKey: cacheKey)
        return result
    }

    /// Formats modification date according to `UseShortRelativeDates` (`dolphin_contentdisplaysettings.kcfg`).
    func formatDate(_ date: Date?, useRelativeDates: Bool) -> String {
        guard let date else { return "—" }
        if useRelativeDates {
            let cal = Calendar.current
            if cal.isDateInToday(date) {
                return "Hoy, \(date.formatted(date: .omitted, time: .shortened))"
            } else if cal.isDateInYesterday(date) {
                return "Ayer, \(date.formatted(date: .omitted, time: .shortened))"
            }
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Builds a rich multi-line tooltip mirroring KDE Dolphin's `TooltipManager` (`src/views/tooltips/tooltipmanager.cpp`).
    func hoverTooltip(for item: FileItem) -> String {
        let modStamp = item.modificationDate?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(item.url.path)|\(modStamp)|\(item.size ?? -1)|\(item.isSymbolicLink)" as NSString
        if let cached = Self.tooltipCache.object(forKey: cacheKey) {
            return cached as String
        }
        let base = metadata(for: item)
        var lines: [String] = [item.name, "Tipo: \(base.kind)"]
        if item.isDirectory {
            let countText = sizeDisplayText(for: item, directorySizeMode: .contentCount)
            if countText != "—" {
                lines.append("Contenido: \(countText)")
            }
        } else {
            lines.append("Tamaño: \(base.sizeText)")
        }
        if item.modificationDate != nil {
            lines.append("Modificado: \(base.modifiedText)")
        }
        if item.isSymbolicLink,
           let target = FileOperationsService().resolvedSymbolicLinkTarget(of: item.url) {
            lines.append("Destino del enlace: \(target.path)")
        }
        let joined = lines.joined(separator: "\n")
        Self.tooltipCache.setObject(joined as NSString, forKey: cacheKey)
        return joined
    }
}
