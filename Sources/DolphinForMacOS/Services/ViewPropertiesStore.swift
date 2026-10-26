import Foundation

struct ViewPropertiesStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for url: URL) -> String {
        "viewProperties.\(url.path)"
    }

    func properties(for url: URL) -> ViewProperties {
        guard let data = defaults.data(forKey: key(for: url)),
              let decoded = try? JSONDecoder().decode(ViewProperties.self, from: data) else {
            return ViewProperties()
        }
        return decoded
    }

    func setProperties(_ properties: ViewProperties, for url: URL) {
        guard let data = try? JSONEncoder().encode(properties) else { return }
        defaults.set(data, forKey: key(for: url))
    }
}
