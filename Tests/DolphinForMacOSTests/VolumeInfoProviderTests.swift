import XCTest
@testable import DolphinForMacOS

final class VolumeInfoProviderTests: XCTestCase {
    func test_availableCapacity_forRealPath_returnsPositiveValue() {
        let provider = VolumeInfoProvider()
        let capacity = provider.availableCapacity(for: FileManager.default.temporaryDirectory)
        XCTAssertNotNil(capacity)
        XCTAssertTrue((capacity ?? 0) > 0)
    }

    func test_availableCapacity_forNonExistentPath_returnsNil() {
        let provider = VolumeInfoProvider()
        let missing = URL(fileURLWithPath: "/this/does/not/exist/at/all")
        XCTAssertNil(provider.availableCapacity(for: missing))
    }
}
