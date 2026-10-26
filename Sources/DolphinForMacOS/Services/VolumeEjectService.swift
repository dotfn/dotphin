import AppKit
import Foundation

enum VolumeEjectError: Error {
    case failed(String)
}

struct VolumeEjectService {
    func eject(_ url: URL) throws {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        } catch {
            throw VolumeEjectError.failed(error.localizedDescription)
        }
    }
}
