import XCTest
@testable import Dotphin

final class VolumeEjectServiceTests: XCTestCase {
    func test_volumeEjectError_localizedDescription_returnsTheStoredMessage() {
        let error: Error = VolumeEjectError.failed("El volumen está en uso.")
        XCTAssertEqual(error.localizedDescription, "El volumen está en uso.")
    }
}
