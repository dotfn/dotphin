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
            kind = String(localized: "Carpeta", bundle: #bundle)
        } else {
            let ext = item.url.pathExtension
            kind = ext.isEmpty ? String(localized: "Documento", bundle: #bundle) : ext.uppercased()
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
        let cacheKey = Self.directorySizeCacheKey(for: item, mode: directorySizeMode)
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
            computed = visibleCount == 1 ? String(localized: "1 ítem", bundle: #bundle) : String(localized: "\(visibleCount) ítems", bundle: #bundle)
        case .contentSize:
            // Recursivo, como Dolphin: antes solo sumaba los archivos del primer
            // nivel y una carpeta con todo dentro de subcarpetas mostraba casi 0.
            let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
            guard let enumerator = FileManager.default.enumerator(
                at: item.url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else {
                return "—"
            }
            var totalBytes: Int64 = 0
            for case let child as URL in enumerator {
                if Task.isCancelled { return "—" }
                if let vals = try? child.resourceValues(forKeys: Set(keys)),
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

    /// Solo lo ya calculado, sin tocar el disco: para el `body` de las vistas,
    /// que no puede bloquearse listando carpetas fila por fila.
    func cachedSizeDisplayText(for item: FileItem, directorySizeMode: DirectorySizeMode) -> String? {
        if !item.isDirectory || directorySizeMode == .none {
            return sizeDisplayText(for: item, directorySizeMode: directorySizeMode)
        }
        return Self.directorySizeCache.object(forKey: Self.directorySizeCacheKey(for: item, mode: directorySizeMode)) as String?
    }

    @concurrent
    func computedSizeDisplayText(for item: FileItem, directorySizeMode: DirectorySizeMode) async -> String {
        sizeDisplayText(for: item, directorySizeMode: directorySizeMode)
    }

    private static func directorySizeCacheKey(for item: FileItem, mode: DirectorySizeMode) -> NSString {
        let modStamp = item.modificationDate?.timeIntervalSince1970 ?? 0
        return "\(item.url.path)|\(modStamp)|\(mode.rawValue)" as NSString
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
                return String(localized: "Hoy, \(date.formatted(date: .omitted, time: .shortened))", bundle: #bundle)
            } else if cal.isDateInYesterday(date) {
                return String(localized: "Ayer, \(date.formatted(date: .omitted, time: .shortened))", bundle: #bundle)
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
        var lines: [String] = [item.name, String(localized: "Tipo: \(base.kind)", bundle: #bundle)]
        var isComplete = true
        if item.isDirectory {
            // Solo si ya se calculó: el tooltip se arma en el `body` de cada fila.
            // Sin el conteo no se cachea, para que aparezca cuando esté listo.
            if let countText = cachedSizeDisplayText(for: item, directorySizeMode: .contentCount) {
                if countText != "—" {
                    lines.append(String(localized: "Contenido: \(countText)", bundle: #bundle))
                }
            } else {
                isComplete = false
            }
        } else {
            lines.append(String(localized: "Tamaño: \(base.sizeText)", bundle: #bundle))
        }
        if item.modificationDate != nil {
            lines.append(String(localized: "Modificado: \(base.modifiedText)", bundle: #bundle))
        }
        if item.isSymbolicLink,
           let target = FileOperationsService().resolvedSymbolicLinkTarget(of: item.url) {
            lines.append(String(localized: "Destino del enlace: \(target.path)", bundle: #bundle))
        }
        let joined = lines.joined(separator: "\n")
        if isComplete {
            Self.tooltipCache.setObject(joined as NSString, forKey: cacheKey)
        }
        return joined
    }
}
