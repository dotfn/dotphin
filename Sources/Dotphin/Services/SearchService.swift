import Foundation
import UniformTypeIdentifiers

/// Where Dolphin searches (`SearchLocations` in `src/search/dolphinquery.h`).
enum SearchLocationScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case fromHere
    case everywhere

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fromHere: return String(localized: "Desde aquí", bundle: #bundle)
        case .everywhere: return String(localized: "En todas partes", bundle: #bundle)
        }
    }

    var systemImage: String {
        switch self {
        case .fromHere: return "folder.badge.questionmark"
        case .everywhere: return "globe"
        }
    }
}

/// What Dolphin matches against (`SearchMode`: Filename vs Content).
enum SearchMatchMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case filename
    case content

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filename: return String(localized: "Nombre de archivo", bundle: #bundle)
        case .content: return String(localized: "Contenido", bundle: #bundle)
        }
    }

    var systemImage: String {
        switch self {
        case .filename: return "textformat"
        case .content: return "doc.text.magnifyingglass"
        }
    }
}

/// Date modification filter (`modifiedSinceDate` in `src/search/dolphinquery.h`).
enum SearchDateFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case any
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case thisYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return String(localized: "Cualquier fecha", bundle: #bundle)
        case .today: return String(localized: "Hoy", bundle: #bundle)
        case .yesterday: return String(localized: "Ayer", bundle: #bundle)
        case .thisWeek: return String(localized: "Esta semana", bundle: #bundle)
        case .thisMonth: return String(localized: "Este mes", bundle: #bundle)
        case .thisYear: return String(localized: "Este año", bundle: #bundle)
        }
    }

    func matches(_ item: FileItem, referenceDate: Date = Date()) -> Bool {
        guard self != .any else { return true }
        guard let modDate = item.modificationDate else { return false }
        let cal = Calendar.current
        switch self {
        case .any:
            return true
        case .today:
            return cal.isDate(modDate, inSameDayAs: referenceDate)
        case .yesterday:
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: referenceDate) else { return false }
            return cal.isDate(modDate, inSameDayAs: yesterday) || modDate >= yesterday
        case .thisWeek:
            guard let weekAgo = cal.date(byAdding: .day, value: -7, to: referenceDate) else { return false }
            return modDate >= weekAgo
        case .thisMonth:
            guard let monthAgo = cal.date(byAdding: .month, value: -1, to: referenceDate) else { return false }
            return modDate >= monthAgo
        case .thisYear:
            guard let yearAgo = cal.date(byAdding: .year, value: -1, to: referenceDate) else { return false }
            return modDate >= yearAgo
        }
    }
}

/// File size filter in Dolphin's search bar.
enum SearchSizeFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case any
    case empty
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return String(localized: "Cualquier tamaño", bundle: #bundle)
        case .empty: return String(localized: "Vacío (0 B)", bundle: #bundle)
        case .small: return String(localized: "Pequeño (< 1 MB)", bundle: #bundle)
        case .medium: return String(localized: "Mediano (1–100 MB)", bundle: #bundle)
        case .large: return String(localized: "Grande (> 100 MB)", bundle: #bundle)
        }
    }

    func matches(_ item: FileItem) -> Bool {
        guard self != .any else { return true }
        guard !item.isDirectory else { return false }
        let bytes = item.size ?? 0
        switch self {
        case .any:
            return true
        case .empty:
            return bytes == 0
        case .small:
            return bytes > 0 && bytes < 1_048_576
        case .medium:
            return bytes >= 1_048_576 && bytes <= 104_857_600
        case .large:
            return bytes > 104_857_600
        }
    }
}

/// File type filter categories mirroring KDE Dolphin's search facets (All, Folders, Documents, Images, Audio, Video, Code).
enum SearchTypeFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case folders
    case documents
    case images
    case audio
    case video
    case code

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "Todo", bundle: #bundle)
        case .folders: return String(localized: "Carpetas", bundle: #bundle)
        case .documents: return String(localized: "Documentos", bundle: #bundle)
        case .images: return String(localized: "Imágenes", bundle: #bundle)
        case .audio: return "Audio"
        case .video: return "Video"
        case .code: return String(localized: "Código", bundle: #bundle)
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .folders: return "folder"
        case .documents: return "doc.text"
        case .images: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    func matches(_ item: FileItem) -> Bool {
        switch self {
        case .all:
            return true
        case .folders:
            return item.opensAsFolder
        case .documents:
            guard !item.isDirectory else { return false }
            let ext = item.url.pathExtension.lowercased()
            let docExts: Set<String> = [
                "pdf", "txt", "rtf", "rtfd", "md", "doc", "docx", "xls", "xlsx",
                "ppt", "pptx", "pages", "numbers", "key", "csv", "epub", "odt"
            ]
            if docExts.contains(ext) { return true }
            if let type = UTType(filenameExtension: ext) {
                return type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .spreadsheet) || type.conforms(to: .presentation)
            }
            return false
        case .images:
            guard !item.isDirectory else { return false }
            let ext = item.url.pathExtension.lowercased()
            if let type = UTType(filenameExtension: ext) {
                return type.conforms(to: .image)
            }
            return ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "tiff", "bmp", "ico"].contains(ext)
        case .audio:
            guard !item.isDirectory else { return false }
            let ext = item.url.pathExtension.lowercased()
            if let type = UTType(filenameExtension: ext) {
                return type.conforms(to: .audio)
            }
            return ["mp3", "m4a", "wav", "flac", "aac", "ogg", "aiff"].contains(ext)
        case .video:
            guard !item.isDirectory else { return false }
            let ext = item.url.pathExtension.lowercased()
            if let type = UTType(filenameExtension: ext) {
                return type.conforms(to: .movie) || type.conforms(to: .video)
            }
            return ["mp4", "mov", "mkv", "avi", "webm", "m4v"].contains(ext)
        case .code:
            guard !item.isDirectory else { return false }
            let ext = item.url.pathExtension.lowercased()
            let codeExts: Set<String> = [
                "swift", "c", "cpp", "h", "hpp", "m", "mm", "py", "js", "ts", "tsx", "jsx",
                "rs", "go", "java", "kt", "rb", "php", "sh", "zsh", "json", "yaml", "yml",
                "toml", "xml", "html", "css", "scss", "sql"
            ]
            if codeExts.contains(ext) { return true }
            if let type = UTType(filenameExtension: ext) {
                return type.conforms(to: .sourceCode)
            }
            return false
        }
    }
}

/// A saved search query in the Places sidebar (`Search::Bar::slotSaveSearch` in `src/search/bar.cpp`).
struct SavedSearchItem: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var directoryURL: URL
    var query: String
    var typeFilter: SearchTypeFilter = .all
    var dateFilter: SearchDateFilter = .any
    var sizeFilter: SearchSizeFilter = .any
    var colorTagFilter: FinderColorTag = .none
    var locationScope: SearchLocationScope = .fromHere
    var matchMode: SearchMatchMode = .filename
}

struct SearchService {
    /// Misma búsqueda que `search(for:...)` pero fuera del main actor: recorrer
    /// el home entero (alcance "en todas partes") o leer contenidos bloqueaba la UI.
    /// Se corta en cuanto la tarea que la llamó se cancela.
    @concurrent
    func results(
        for query: String,
        in directory: URL,
        typeFilter: SearchTypeFilter,
        dateFilter: SearchDateFilter,
        sizeFilter: SearchSizeFilter,
        colorTagFilter: FinderColorTag,
        matchMode: SearchMatchMode
    ) async -> [FileItem] {
        search(
            for: query,
            in: directory,
            typeFilter: typeFilter,
            dateFilter: dateFilter,
            sizeFilter: sizeFilter,
            colorTagFilter: colorTagFilter,
            matchMode: matchMode
        )
    }

    func search(
        for query: String,
        in directory: URL,
        typeFilter: SearchTypeFilter = .all,
        dateFilter: SearchDateFilter = .any,
        sizeFilter: SearchSizeFilter = .any,
        colorTagFilter: FinderColorTag = .none,
        matchMode: SearchMatchMode = .filename,
        maxResults: Int = 200
    ) -> [FileItem] {
        let hasFacetFilter = typeFilter != .all || dateFilter != .any || sizeFilter != .any || colorTagFilter != .none
        guard !query.isEmpty || hasFacetFilter else { return [] }

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .labelNumberKey,
            .tagNamesKey,
            .isPackageKey,
            .localizedTypeDescriptionKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            // No se busca dentro de los paquetes (`.app`…), como Finder.
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [FileItem] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { return [] }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let isDirectory = values.isDirectory ?? false
            let fileSize = values.fileSize.map(Int64.init)

            let matchesQuery: Bool
            if query.isEmpty {
                matchesQuery = true
            } else {
                switch matchMode {
                case .filename:
                    matchesQuery = url.lastPathComponent.localizedCaseInsensitiveContains(query)
                case .content:
                    if url.lastPathComponent.localizedCaseInsensitiveContains(query) {
                        matchesQuery = true
                    } else if !isDirectory, let size = fileSize, size > 0, size <= 2_097_152 {
                        matchesQuery = (try? String(contentsOf: url, encoding: .utf8))?.localizedCaseInsensitiveContains(query) ?? false
                    } else {
                        matchesQuery = false
                    }
                }
            }
            guard matchesQuery else { continue }

            let item = FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: isDirectory,
                isSymbolicLink: values.isSymbolicLink ?? false,
                size: fileSize,
                modificationDate: values.contentModificationDate,
                labelNumber: values.labelNumber ?? 0,
                tagNames: values.tagNames ?? [],
                isPackage: values.isPackage ?? false,
                typeDescription: values.localizedTypeDescription
            )
            guard typeFilter.matches(item),
                  dateFilter.matches(item),
                  sizeFilter.matches(item),
                  (colorTagFilter == .none || item.colorTag == colorTagFilter) else { continue }
            results.append(item)
            if results.count >= maxResults { break }
        }
        return results
    }
}
