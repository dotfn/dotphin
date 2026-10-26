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

    func test_info_forRealPath_returnsPositiveCapacitiesAndFormat() {
        let provider = VolumeInfoProvider()
        let info = provider.info(for: FileManager.default.temporaryDirectory)
        XCTAssertNotNil(info.totalCapacity)
        XCTAssertNotNil(info.availableCapacity)
        XCTAssertNotNil(info.format)
        XCTAssertTrue((info.totalCapacity ?? 0) > 0)
    }

    func test_info_forNonExistentPath_returnsAllNil() {
        let provider = VolumeInfoProvider()
        let info = provider.info(for: URL(fileURLWithPath: "/this/does/not/exist/at/all"))
        XCTAssertNil(info.totalCapacity)
        XCTAssertNil(info.availableCapacity)
        XCTAssertNil(info.format)
    }
}
