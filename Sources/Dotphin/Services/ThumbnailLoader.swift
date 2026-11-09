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

    static func invalidateIcon(forFile path: String) {
        iconCache.removeObject(forKey: path as NSString)
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
