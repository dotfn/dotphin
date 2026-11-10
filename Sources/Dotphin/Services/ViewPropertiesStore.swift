import Foundation

/// Mirrors KDE Dolphin's `ViewPropertiesDialog` apply scope radio buttons.
enum ViewPropertiesApplyScope: String, CaseIterable, Identifiable {
    case currentFolder
    case currentAndSubfolders
    case allFolders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentFolder:
            return String(localized: "Carpeta actual", bundle: #bundle)
        case .currentAndSubfolders:
            return String(localized: "Carpeta actual y todas las subcarpetas", bundle: #bundle)
        case .allFolders:
            return String(localized: "Todas las carpetas", bundle: #bundle)
        }
    }
}

struct ViewPropertiesStore {
    private let defaults: UserDefaults
    private let appSettingsStore: AppSettingsStore
    private static let globalDefaultPropertiesKey = "viewProperties.__globalDefault__"

    init(defaults: UserDefaults = .standard, appSettingsStore: AppSettingsStore = AppSettingsStore()) {
        self.defaults = defaults
        self.appSettingsStore = appSettingsStore
    }

    private func key(for url: URL) -> String {
        "viewProperties.\(url.path)"
    }

    func defaultProperties() -> ViewProperties {
        let appMode = appSettingsStore.settings().defaultViewMode
        if let data = defaults.data(forKey: Self.globalDefaultPropertiesKey),
           var decoded = try? JSONDecoder().decode(ViewProperties.self, from: data) {
            decoded.mode = appMode
            return decoded
        }
        return ViewProperties(mode: appMode)
    }

    func properties(for url: URL) -> ViewProperties {
        guard let data = defaults.data(forKey: key(for: url)),
              let decoded = try? JSONDecoder().decode(ViewProperties.self, from: data) else {
            return defaultProperties()
        }
        return decoded
    }

    func setProperties(_ properties: ViewProperties, for url: URL) {
        guard let data = try? JSONEncoder().encode(properties) else { return }
        defaults.set(data, forKey: key(for: url))
    }

    /// Removes any custom override for `url` and returns `defaultProperties()` (`DolphinViewActionHandler::restoreViewSettingsToDefaults`).
    @discardableResult
    func resetPropertiesToDefault(for url: URL) -> ViewProperties {
        defaults.removeObject(forKey: key(for: url))
        return defaultProperties()
    }

    func applyProperties(
        _ properties: ViewProperties,
        to url: URL,
        scope: ViewPropertiesApplyScope,
        useAsDefault: Bool
    ) {
        if useAsDefault || scope == .allFolders {
            if let data = try? JSONEncoder().encode(properties) {
                defaults.set(data, forKey: Self.globalDefaultPropertiesKey)
            }
            var settings = appSettingsStore.settings()
            settings.defaultViewMode = properties.mode
            appSettingsStore.setSettings(settings)
        }

        switch scope {
        case .currentFolder:
            setProperties(properties, for: url)

        case .currentAndSubfolders:
            setProperties(properties, for: url)
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                var count = 0
                for case let childURL as URL in enumerator {
                    guard count < 500 else { break }
                    if (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        setProperties(properties, for: childURL)
                        count += 1
                    }
                }
            }

        case .allFolders:
            for existingKey in defaults.dictionaryRepresentation().keys
                where existingKey.hasPrefix("viewProperties.") && existingKey != Self.globalDefaultPropertiesKey {
                defaults.removeObject(forKey: existingKey)
            }
            setProperties(properties, for: url)
        }
    }
}
