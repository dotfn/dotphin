import AppKit
import Foundation

/// macOS Finder color labels (1...7) and their display metadata.
enum FinderColorTag: Int, Codable, CaseIterable, Identifiable, Sendable {
    case none = 0
    case gray = 1
    case green = 2
    case purple = 3
    case blue = 4
    case yellow = 5
    case red = 6
    case orange = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return String(localized: "Sin etiqueta", bundle: #bundle)
        case .gray: return String(localized: "Gris", bundle: #bundle)
        case .green: return String(localized: "Verde", bundle: #bundle)
        case .purple: return String(localized: "Púrpura", bundle: #bundle)
        case .blue: return String(localized: "Azul", bundle: #bundle)
        case .yellow: return String(localized: "Amarillo", bundle: #bundle)
        case .red: return String(localized: "Rojo", bundle: #bundle)
        case .orange: return String(localized: "Naranja", bundle: #bundle)
        }
    }

    var nsColor: NSColor? {
        switch self {
        case .none: return nil
        case .gray: return .systemGray
        case .green: return .systemGreen
        case .purple: return .systemPurple
        case .blue: return .systemBlue
        case .yellow: return .systemYellow
        case .red: return .systemRed
        case .orange: return .systemOrange
        }
    }
}

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let size: Int64?
    let modificationDate: Date?
    let creationDate: Date?
    let labelNumber: Int
    let tagNames: [String]
    let isHiddenInDotHidden: Bool

    var id: URL { url }

    var fileExtension: String {
        isDirectory ? "" : url.pathExtension.lowercased()
    }

    var colorTag: FinderColorTag {
        if let byLabel = FinderColorTag(rawValue: labelNumber), byLabel != .none {
            return byLabel
        }
        for name in tagNames {
            if let matched = FinderColorTag.allCases.first(where: { $0 != .none && $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
                return matched
            }
        }
        return .none
    }

    var isHiddenItem: Bool {
        name.hasPrefix(".") || isHiddenInDotHidden
    }

    init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        size: Int64?,
        modificationDate: Date?,
        creationDate: Date? = nil,
        labelNumber: Int = 0,
        tagNames: [String] = [],
        isHiddenInDotHidden: Bool = false
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.size = size
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.labelNumber = labelNumber
        self.tagNames = tagNames
        self.isHiddenInDotHidden = isHiddenInDotHidden
    }
}
