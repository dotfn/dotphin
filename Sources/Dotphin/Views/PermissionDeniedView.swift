import SwiftUI
import       AppKit

struct PermissionDeniedView: View {
    let url: URL

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Sin acceso a \(url.path)")
                .font(.headline)
            Text("Otorgá acceso completo al disco en Configuración del Sistema para navegar esta carpeta.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Abrir Configuración del Sistema") {
                if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(settingsURL)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
