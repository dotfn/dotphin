import Foundation

struct ViewPropertiesStore {
    private let defaults: UserDefaults
    private let appSettingsStore: AppSettingsStore

    init(defaults: UserDefaults = .standard, appSettingsStore: AppSettingsStore = AppSettingsStore()) {
        self.defaults = defaults
        self.appSettingsStore = appSettingsStore
    }

    private func key(for url: URL) -> String {
        "viewProperties.\(url.path)"
    }

    func properties(for url: URL) -> ViewProperties {
        guard let data = defaults.data(forKey: key(for: url)),
              let decoded = try? JSONDecoder().decode(ViewProperties.self, from: data) else {
            return ViewProperties(mode: appSettingsStore.settings().defaultViewMode)
        }
        return decoded
    }

    func setProperties(_ properties: ViewProperties, for url: URL) {
        guard let data = try? JSONEncoder().encode(properties) else { return }
        defaults.set(data, forKey: key(for: url))
    }
}
