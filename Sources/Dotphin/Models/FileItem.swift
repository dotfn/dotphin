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

    /// Qué etiqueta queda al elegir `chosen` en la fila de colores: como en
    /// Finder, volver a elegir el color que ya tiene lo quita.
    static func tagToApply(choosing chosen: FinderColorTag, current: FinderColorTag?) -> FinderColorTag {
        chosen == current ? .none : chosen
    }

    /// Los colores en el orden de la fila de Finder.
    static let finderPaletteOrder: [FinderColorTag] = [.red, .orange, .yellow, .green, .blue, .purple, .gray]

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
    /// Oculto por el sistema (`isHiddenKey`): además de los nombres con punto,
    /// lo que lleva la marca de oculto, como `~/Library` o `/usr`.
    let isHiddenByFlag: Bool
    /// Paquete (`.app`, `.xcodeproj`…): es una carpeta en disco, pero se abre
    /// como un archivo.
    let isPackage: Bool
    /// "Tipo" como lo describe el sistema (`localizedTypeDescriptionKey`).
    let typeDescription: String?

    var id: URL { url }

    /// Carpeta en la que se entra al abrirla; un paquete no.
    var opensAsFolder: Bool {
        isDirectory && !isPackage
    }

    /// El tipo que se muestra: el del sistema o, si no se leyó, la extensión.
    var kindDescription: String {
        if let typeDescription, !typeDescription.isEmpty {
            return typeDescription
        }
        if isDirectory {
            return String(localized: "Carpeta", bundle: #bundle)
        }
        let ext = url.pathExtension
        return ext.isEmpty ? String(localized: "Documento", bundle: #bundle) : ext.uppercased()
    }

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
        name.hasPrefix(".") || isHiddenByFlag || isHiddenInDotHidden
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
        isHiddenInDotHidden: Bool = false,
        isHiddenByFlag: Bool = false,
        isPackage: Bool = false,
        typeDescription: String? = nil
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
        self.isHiddenByFlag = isHiddenByFlag
        self.isPackage = isPackage
        self.typeDescription = typeDescription
    }
}
