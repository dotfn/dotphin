import AppKit
import Observation

/// Desde macOS 27, AppKit oculta por defecto las imágenes de los ítems de menú
/// ("Automatic"): los íconos de Dotphin llegaban al `NSMenuItem` pero no se
/// dibujaban. Este coordinador marca cada ítem de los menús de la app según la
/// opción "Mostrar íconos en los menús": `.visible` o `.hidden`. Con la opción
/// apagada también se ocultan los íconos que pone el sistema (Cortar, Copiar…).
///
/// Los menús de SwiftUI (barra de menús, `NSHostingMenu` de los menús
/// contextuales) arman sus ítems por su cuenta, así que se escuchan los avisos
/// de ítems agregados o cambiados en cualquier menú.
@MainActor
final class MenuImageVisibility {
    static let shared = MenuImageVisibility()

    private var observers: [NSObjectProtocol] = []

    private init() {}

    func install() {
        guard observers.isEmpty else { return }
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
                // AppKit avisa desde el hilo principal (los menús viven ahí);
                // `assumeIsolated` lo comprueba en tiempo de ejecución.
                nonisolated(unsafe) let menu = notification.object as? NSMenu
                let index = notification.userInfo?["NSMenuItemIndex"] as? Int
                MainActor.assumeIsolated {
                    guard let self, let menu else { return }
                    if let index, menu.items.indices.contains(index) {
                        self.apply(to: menu.items[index])
                    } else {
                        self.apply(to: menu)
                    }
                }
            })
        }
        followSetting()
        if let mainMenu = NSApp?.mainMenu {
            apply(to: mainMenu)
        }
    }

    private var wantedVisibility: NSMenuItem.ImageVisibility {
        AppSettingsModel.shared.settings.showsMenuIcons ? .visible : .hidden
    }

    func apply(to menu: NSMenu) {
        for item in menu.items {
            apply(to: item)
        }
    }

    private func apply(to item: NSMenuItem) {
        // En una paleta (los colores de las etiquetas) la imagen es el ítem: siempre visible.
        let wanted = item.menu?.presentationStyle == .palette ? .visible : wantedVisibility
        // Cambiar la visibilidad vuelve a avisar `didChangeItem`: solo si hace falta.
        if item.preferredImageVisibility != wanted {
            item.preferredImageVisibility = wanted
        }
        if let submenu = item.submenu {
            apply(to: submenu)
        }
    }

    /// Al cambiar la opción, la barra de menús se actualiza en el momento; los
    /// menús contextuales se arman de nuevo cada vez que se abren.
    private func followSetting() {
        withObservationTracking {
            _ = AppSettingsModel.shared.settings.showsMenuIcons
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let mainMenu = NSApp?.mainMenu {
                    self.apply(to: mainMenu)
                }
                self.followSetting()
            }
        }
    }
}
