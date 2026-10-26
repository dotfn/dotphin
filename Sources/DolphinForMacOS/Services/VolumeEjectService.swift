import AppKit
import Foundation

enum VolumeEjectError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
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
