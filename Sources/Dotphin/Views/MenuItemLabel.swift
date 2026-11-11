import SwiftUI

/// Texto de un ítem de menú con su ícono a la izquierda, como en Dolphin y en
/// los menús de macOS 26. El ícono se puede apagar en Configuración
/// (`showsMenuIcons`); las casillas (`Toggle`) no llevan: la marca ya es su ícono.
struct MenuItemLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        if AppSettingsModel.shared.settings.showsMenuIcons {
            SwiftUI.Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

extension Button where Label == MenuItemLabel {
    init(_ title: String, menuIcon: String, role: ButtonRole? = nil, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) {
            MenuItemLabel(title: title, systemImage: menuIcon)
        }
    }
}

extension Menu where Label == MenuItemLabel {
    init(_ title: String, menuIcon: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) {
            MenuItemLabel(title: title, systemImage: menuIcon)
        }
    }
}
