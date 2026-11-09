import Foundation

struct AppSettingsStore {
    private static let key = "appSettings"
    nonisolated(unsafe) private static var cachedStandardSettings: AppSettings?
    nonisolated(unsafe) private static var cachedStandardData: Data?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func settings() -> AppSettings {
        if defaults === UserDefaults.standard {
            let currentData = defaults.data(forKey: Self.key)
            if let cached = Self.cachedStandardSettings, Self.cachedStandardData == currentData {
                return cached
            }
            guard let data = currentData,
                  let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
                let fallback = AppSettings()
                Self.cachedStandardData = nil
                Self.cachedStandardSettings = fallback
                return fallback
            }
            Self.cachedStandardData = data
            Self.cachedStandardSettings = decoded
            return decoded
        }
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }

    func setSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
        if defaults === UserDefaults.standard {
            Self.cachedStandardData = data
            Self.cachedStandardSettings = settings
        }
    }
}
