import XCTest
@testable import Dotphin

final class AppSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_settings_withNoSavedEntry_returnsDefaults() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings(), AppSettings())
    }

    func test_setThenGet_roundTrips() {
        let store = AppSettingsStore(defaults: defaults)
        var settings = AppSettings()
        settings.defaultViewMode = .icons
        settings.showsHiddenFiles = true
        store.setSettings(settings)
        XCTAssertEqual(store.settings(), settings)
    }

    func test_settings_withCorruptData_returnsDefaults() {
        defaults.set("not valid json".data(using: .utf8), forKey: "appSettings")
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings(), AppSettings())
    }

    func test_startupURL_home_isHomeDirectory() {
        var settings = AppSettings()
        settings.startupLocation = .home
        XCTAssertEqual(settings.startupURL, FileManager.default.homeDirectoryForCurrentUser)
    }

    func test_startupURL_desktop_isDesktopFolder() {
        var settings = AppSettings()
        settings.startupLocation = .desktop
        XCTAssertEqual(
            settings.startupURL,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        )
    }

    func test_startupURL_customExistingPath_usesThatPath() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var settings = AppSettings()
        settings.startupLocation = .custom
        settings.customStartupPath = tempDir.path

        XCTAssertEqual(settings.startupURL.standardizedFileURL.path, tempDir.standardizedFileURL.path)
    }

    func test_startupURL_customMissingPath_fallsBackToHome() {
        var settings = AppSettings()
        settings.startupLocation = .custom
        settings.customStartupPath = "/no/existe/esta/carpeta/\(UUID().uuidString)"

        XCTAssertEqual(settings.startupURL, FileManager.default.homeDirectoryForCurrentUser)
    }

    func test_startupURL_customWithNilPath_fallsBackToHome() {
        var settings = AppSettings()
        settings.startupLocation = .custom
        settings.customStartupPath = nil

        XCTAssertEqual(settings.startupURL, FileManager.default.homeDirectoryForCurrentUser)
    }

    func test_settings_decodingOldBlobMissingNewKeys_keepsOldValuesAndDefaultsTheRest() {
        let oldBlob = """
        {"defaultViewMode":"details","showsHiddenFiles":true}
        """.data(using: .utf8)!
        defaults.set(oldBlob, forKey: "appSettings")

        let store = AppSettingsStore(defaults: defaults)
        let settings = store.settings()

        XCTAssertEqual(settings.defaultViewMode, .details, "un valor guardado antes de este slice no debe perderse")
        XCTAssertEqual(settings.showsHiddenFiles, true, "un valor guardado antes de este slice no debe perderse")
        XCTAssertEqual(settings.startupLocation, .home, "una clave nueva ausente debe usar su default, no romper el decode entero")
        XCTAssertNil(settings.customStartupPath)
    }

    /// Los ajustes de la toolbar vieja (grupos, etiquetas, ocultos) ya no
    /// existen: un blob guardado que todavía los trae se decodifica igual.
    func test_settings_decodingBlobWithRemovedToolbarKeys_stillDecodes() {
        let blob = """
        {"defaultViewMode":"icons","showsToolbarLabels":true,"toolbarGroups":[["back","forward"],["search"]],"isToolbarLocked":true}
        """.data(using: .utf8)!
        defaults.set(blob, forKey: "appSettings")
        XCTAssertEqual(AppSettingsStore(defaults: defaults).settings().defaultViewMode, .icons)
    }
}
