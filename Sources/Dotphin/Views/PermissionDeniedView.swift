import SwiftUI
import       AppKit

struct PermissionDeniedView: View {
    let url: URL

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "Sin acceso a \(url.path)", bundle: #bundle))
                .font(.headline)
            Text(String(localized: "Otorgá acceso completo al disco en Configuración del Sistema para navegar esta carpeta.", bundle: #bundle))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "Abrir Configuración del Sistema", bundle: #bundle)) {
                if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(settingsURL)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
