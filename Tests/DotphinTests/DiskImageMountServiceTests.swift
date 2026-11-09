import XCTest
@testable import Dotphin

final class DiskImageMountServiceTests: XCTestCase {
    func test_isDiskImage_recognizesSupportedExtensionsCaseInsensitively() {
        for ext in ["iso", "ISO", "dmg", "Dmg", "cdr", "img"] {
            XCTAssertTrue(DiskImageMountService.isDiskImage(URL(fileURLWithPath: "/tmp/file.\(ext)")))
        }
    }

    func test_isDiskImage_rejectsUnrelatedExtensions() {
        for ext in ["txt", "zip", "app", ""] {
            XCTAssertFalse(DiskImageMountService.isDiskImage(URL(fileURLWithPath: "/tmp/file.\(ext)")))
        }
    }

    func test_mount_whenNotADiskImage_throwsWithoutShellingOut() {
        let notAnImage = URL(fileURLWithPath: "/tmp/plain.txt")
        XCTAssertThrowsError(try DiskImageMountService().mount(notAnImage)) { error in
            XCTAssertEqual(error as? DiskImageMountError, .notADiskImage)
        }
    }

    func test_mount_whenPathDoesNotExist_throwsFailedWithNonEmptyMessage() {
        let missing = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-does-not-exist.iso")
        XCTAssertThrowsError(try DiskImageMountService().mount(missing)) { error in
            guard case DiskImageMountError.failed(let message) = error else {
                XCTFail("esperaba .failed, fue \(error)")
                return
            }
            XCTAssertFalse(message.isEmpty)
        }
    }
}
