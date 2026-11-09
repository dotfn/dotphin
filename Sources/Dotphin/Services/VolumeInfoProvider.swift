import Foundation

struct VolumeInfo {
    let totalCapacity: Int64?
    let availableCapacity: Int64?
    let format: String?
}

struct VolumeInfoProvider {
    private final class CachedVolumeInfoBox {
        let info: VolumeInfo
        let timestamp: TimeInterval
        init(info: VolumeInfo, timestamp: TimeInterval) {
            self.info = info
            self.timestamp = timestamp
        }
    }

    nonisolated(unsafe) private static let cache: NSCache<NSString, CachedVolumeInfoBox> = {
        let cache = NSCache<NSString, CachedVolumeInfoBox>()
        cache.countLimit = 64
        return cache
    }()

    func availableCapacity(for url: URL) -> Int64? {
        info(for: url).availableCapacity
    }

    func info(for url: URL) -> VolumeInfo {
        let key = url.standardizedFileURL.path as NSString
        let now = Date().timeIntervalSinceReferenceDate
        if let cached = Self.cache.object(forKey: key), now - cached.timestamp < 5.0 {
            return cached.info
        }
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeLocalizedFormatDescriptionKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return VolumeInfo(totalCapacity: nil, availableCapacity: nil, format: nil)
        }
        let result = VolumeInfo(
            totalCapacity: values.volumeTotalCapacity.map(Int64.init),
            availableCapacity: values.volumeAvailableCapacity.map(Int64.init),
            format: values.volumeLocalizedFormatDescription
        )
        Self.cache.setObject(CachedVolumeInfoBox(info: result, timestamp: now), forKey: key)
        return result
    }
}
