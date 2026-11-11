import AppKit
import ImageIO
import PDFKit
import QuickLookThumbnailing

struct ThumbnailLoader {
    nonisolated(unsafe) private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    nonisolated(unsafe) private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    static func cachedThumbnail(for url: URL) -> NSImage? {
        cache.object(forKey: url.standardizedFileURL as NSURL)
    }

    /// Returns the system file/folder icon cached in memory so scrolling and SwiftUI redraws avoid repeated disk/LaunchServices lookups.
    static func icon(forFile path: String) -> NSImage {
        let key = path as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        iconCache.setObject(image, forKey: key)
        return image
    }

    /// Ícono de un ítem de la lista: una carpeta con etiqueta de color se ve de
    /// ese color (como el color de carpeta de Dolphin). Solo cambia lo que se
    /// muestra en Dotphin, no el ícono guardado en el disco.
    static func icon(for item: FileItem) -> NSImage {
        let base = icon(forFile: item.url.path)
        guard item.isDirectory, let color = item.colorTag.nsColor else { return base }
        let key = "\(item.url.path)#\(item.colorTag.rawValue)" as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        let tinted = tinted(base, with: color)
        iconCache.setObject(tinted, forKey: key)
        return tinted
    }

    /// Mezcla "color": toma el tono y la saturación de `color` y la luminosidad
    /// del ícono, recortado a su silueta. Conserva el relieve, los brillos y el
    /// dibujo de carpetas especiales (Descargas, Escritorio…).
    static func tinted(_ base: NSImage, with color: NSColor) -> NSImage {
        let image = NSImage(size: base.size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            base.draw(in: rect)
            var proposed = rect
            guard let mask = base.cgImage(forProposedRect: &proposed, context: NSGraphicsContext.current, hints: nil) else { return true }
            context.saveGState()
            context.clip(to: rect, mask: mask)
            context.setBlendMode(.color)
            context.setFillColor(color.usingColorSpace(.sRGB)?.cgColor ?? color.cgColor)
            context.fill(rect)
            context.restoreGState()
            return true
        }
        image.accessibilityDescription = base.accessibilityDescription
        return image
    }

    /// Olvida el ícono guardado de `path` (también sus versiones teñidas por
    /// etiqueta), p. ej. tras cambiar el ícono de una carpeta.
    static func invalidateIcon(forFile path: String) {
        iconCache.removeObject(forKey: path as NSString)
        for tag in FinderColorTag.allCases {
            iconCache.removeObject(forKey: "\(path)#\(tag.rawValue)" as NSString)
        }
    }

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let key = url.standardizedFileURL as NSURL
        if let cached = Self.cache.object(forKey: key) {
            return cached
        }
        let maxPixel = Int(max(size.width, size.height) * 2)
        if let inProcessImage = await Task.detached(priority: .utility, operation: { () -> NSImage? in
            Self.decodeImageThumbnailInProcess(for: url, maxPixelSize: maxPixel)
        }).value {
            Self.cache.setObject(inProcessImage, forKey: key)
            return inProcessImage
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 2,
            representationTypes: .thumbnail
        )
        let generated: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
        if let generated {
            Self.cache.setObject(generated, forKey: key)
        }
        return generated
    }

    nonisolated private static func decodeImageThumbnailInProcess(for url: URL, maxPixelSize: Int) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        if ext == "svg" {
            return NSImage(contentsOf: url)
        }
        if ext == "pdf" {
            if let doc = PDFDocument(url: url), let page = doc.page(at: 0) {
                let side = CGFloat(max(64, maxPixelSize))
                return page.thumbnail(of: NSSize(width: side, height: side), for: .cropBox)
            }
            return nil
        }
        let imageExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "avif",
            "tiff", "tif", "bmp", "icns", "ico", "dng", "cr2", "nef", "arw", "raw"
        ]
        guard imageExtensions.contains(ext),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixelSize)
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
    }
}

