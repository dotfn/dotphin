import Foundation

struct VolumeInfo {
    let totalCapacity: Int64?
    let availableCapacity: Int64?
    let format: String?
}

struct VolumeInfoProvider {
    func availableCapacity(for url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let capacity = values.volumeAvailableCapacity else {
            return nil
        }
        return Int64(capacity)
    }

    func info(for url: URL) -> VolumeInfo {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeLocalizedFormatDescriptionKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return VolumeInfo(totalCapacity: nil, availableCapacity: nil, format: nil)
        }
        return VolumeInfo(
            totalCapacity: values.volumeTotalCapacity.map(Int64.init),
            availableCapacity: values.volumeAvailableCapacity.map(Int64.init),
            format: values.volumeLocalizedFormatDescription
        )
    }
}
