import AppKit
import Foundation

/// Presets for Dolphin's "Set Folder Icon" (`setfoldericonitemaction.cpp`) adapted to native macOS SF Symbols & colors.
enum FolderIconPreset: String, CaseIterable, Identifiable {
    case `default`
    case bookmark
    case code
    case pictures
    case music
    case videos
    case documents
    case downloads
    case archive
    case games
    case important
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default: return String(localized: "Por defecto", bundle: #bundle)
        case .bookmark: return String(localized: "Favoritos", bundle: #bundle)
        case .code: return String(localized: "Desarrollo / Código", bundle: #bundle)
        case .pictures: return String(localized: "Imágenes", bundle: #bundle)
        case .music: return String(localized: "Música", bundle: #bundle)
        case .videos: return String(localized: "Videos", bundle: #bundle)
        case .documents: return String(localized: "Documentos", bundle: #bundle)
        case .downloads: return String(localized: "Descargas", bundle: #bundle)
        case .archive: return String(localized: "Archivo", bundle: #bundle)
        case .games: return String(localized: "Juegos", bundle: #bundle)
        case .important: return String(localized: "Importante", bundle: #bundle)
        case .cloud: return String(localized: "Nube / Red", bundle: #bundle)
        }
    }

    var badgeSymbol: String? {
        switch self {
        case .default: return nil
        case .bookmark: return "star.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .pictures: return "photo.fill"
        case .music: return "music.note"
        case .videos: return "film.fill"
        case .documents: return "doc.text.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .archive: return "archivebox.fill"
        case .games: return "gamecontroller.fill"
        case .important: return "exclamationmark.triangle.fill"
        case .cloud: return "icloud.fill"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .default: return .controlAccentColor
        case .bookmark: return .systemYellow
        case .code: return .systemTeal
        case .pictures: return .systemPink
        case .music: return .systemPurple
        case .videos: return .systemIndigo
        case .documents: return .systemBlue
        case .downloads: return .systemCyan
        case .archive: return .systemBrown
        case .games: return .systemGreen
        case .important: return .systemRed
        case .cloud: return .systemMint
        }
    }
}

struct FolderIconAndTagService {
    private static let finderCommentXattr = "com.apple.metadata:kMDItemFinderComment"

    /// Sets or clears the macOS Finder color label (`labelNumberKey` & `tagNamesKey`) on a file or folder.
    func setColorTag(_ tag: FinderColorTag, for url: URL) throws {
        let nsURL = url as NSURL
        let tags: [String] = tag == .none ? [] : [tag.title]
        try? nsURL.setResourceValue(tags as NSArray, forKey: .tagNamesKey)
        try nsURL.setResourceValue(NSNumber(value: tag.rawValue), forKey: .labelNumberKey)
    }

    /// Reads the macOS Finder/Spotlight comment (`kMDItemFinderComment` extended attribute) for a file or folder (`Baloo::FileMetaDataWidget`).
    func getFinderComment(for url: URL) -> String {
        let path = url.path
        let attrName = Self.finderCommentXattr
        let size = getxattr(path, attrName, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return "" }
        var buffer = Data(count: size)
        let readBytes = buffer.withUnsafeMutableBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return getxattr(path, attrName, base, size, 0, XATTR_NOFOLLOW)
        }
        guard readBytes > 0 else { return "" }
        if let str = try? PropertyListSerialization.propertyList(from: buffer, options: [], format: nil) as? String {
            return str
        }
        return String(data: buffer, encoding: .utf8) ?? ""
    }

    /// Writes or clears the macOS Finder/Spotlight comment (`kMDItemFinderComment` extended attribute) for a file or folder (`Baloo::FileMetaDataWidget`).
    @discardableResult
    func setFinderComment(_ comment: String, for url: URL) -> Bool {
        let path = url.path
        let attrName = Self.finderCommentXattr
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            _ = removexattr(path, attrName, XATTR_NOFOLLOW)
            return true
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: trimmed, format: .binary, options: 0) else {
            return false
        }
        let result = data.withUnsafeBytes { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return -1 }
            return setxattr(path, attrName, base, data.count, 0, XATTR_NOFOLLOW)
        }
        return result == 0
    }

    /// Applies a custom folder icon (`SetFolderIconItemAction`) or resets to default via `NSWorkspace.setIcon`.
    @discardableResult
    func setFolderIcon(_ preset: FolderIconPreset, for folderURL: URL) -> Bool {
        if preset == .default {
            return NSWorkspace.shared.setIcon(nil, forFile: folderURL.path, options: [])
        }
        guard let badgeSymbol = preset.badgeSymbol else {
            return NSWorkspace.shared.setIcon(nil, forFile: folderURL.path, options: [])
        }
        let customImage = Self.makeBadgedFolderIcon(badgeSymbol: badgeSymbol, tint: preset.tintColor)
        return NSWorkspace.shared.setIcon(customImage, forFile: folderURL.path, options: [])
    }

    private static func makeBadgedFolderIcon(badgeSymbol: String, tint: NSColor) -> NSImage {
        let targetSize = NSSize(width: 256, height: 256)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        let baseFolder = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        let folderConfig = NSImage.SymbolConfiguration(pointSize: 196, weight: .regular)
            .applying(.init(hierarchicalColor: tint))
        if let configuredFolder = baseFolder?.withSymbolConfiguration(folderConfig) {
            let rect = NSRect(x: 16, y: 20, width: 224, height: 196)
            configuredFolder.draw(in: rect)
        }

        if let badge = NSImage(systemSymbolName: badgeSymbol, accessibilityDescription: nil) {
            let badgeConfig = NSImage.SymbolConfiguration(pointSize: 78, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            if let configuredBadge = badge.withSymbolConfiguration(badgeConfig) {
                let badgeRect = NSRect(x: 84, y: 58, width: 88, height: 88)
                configuredBadge.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 0.92)
            }
        }

        return image
    }
}
