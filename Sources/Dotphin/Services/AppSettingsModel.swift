import Foundation
import Observation

/// Ajustes de la app como estado observable y compartido: las vistas leen
/// `AppSettingsModel.shared.settings` y se actualizan solas cuando cambia,
/// en vez de guardar cada una su copia y releer `UserDefaults` en el `body`.
///
/// La persistencia sigue en `AppSettingsStore` (que también usan los servicios
/// fuera del main actor).
@MainActor
@Observable
final class AppSettingsModel {
    static let shared = AppSettingsModel()

    var settings: AppSettings {
        didSet {
            guard settings != oldValue, !isReloading else { return }
            store.setSettings(settings)
        }
    }

    @ObservationIgnored private let store = AppSettingsStore()
    @ObservationIgnored private var isReloading = false
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    private init() {
        settings = store.settings()
        // Otros componentes (p. ej. `ViewPropertiesStore`) escriben por `AppSettingsStore`.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadIfChanged()
            }
        }
    }

    private func reloadIfChanged() {
        let latest = store.settings()
        guard latest != settings else { return }
        isReloading = true
        settings = latest
        isReloading = false
    }
}
