import SwiftUI

struct PlacesSidebarView: View {
    let places: [PlaceItem]
    let currentURL: URL
    let onSelect: (PlaceItem) -> Void

    @State private var pendingEject: PlaceItem?
    @State private var showsEjectConfirmation = false
    @State private var infoTarget: PlaceItem?
    @State private var ejectError: String?

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        List(places) { place in
            Button {
                onSelect(place)
            } label: {
                Label(place.name, systemImage: place.systemImage)
            }
            .buttonStyle(.plain)
            .listRowBackground(
                place.url == currentURL ? Color.accentColor.opacity(0.15) : Color.clear
            )
            .contextMenu {
                if place.kind == .volume {
                    Button("Información") {
                        infoTarget = place
                    }
                    if place.isEjectable {
                        Button("Expulsar") {
                            pendingEject = place
                            showsEjectConfirmation = true
                        }
                    }
                }
            }
        }
        .alert(
            "¿Expulsar este volumen?",
            isPresented: $showsEjectConfirmation,
            presenting: pendingEject
        ) { place in
            Button("Expulsar") {
                do {
                    try VolumeEjectService().eject(place.url)
                } catch {
                    ejectError = error.localizedDescription
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { place in
            Text("Se expulsará «\(place.name)».")
        }
        .alert(
            "No se pudo expulsar",
            isPresented: Binding(
                get: { ejectError != nil },
                set: { if !$0 { ejectError = nil } }
            )
        ) {
            Button("OK") { ejectError = nil }
        } message: {
            Text(ejectError ?? "")
        }
        .alert(
            infoTarget?.name ?? "",
            isPresented: Binding(
                get: { infoTarget != nil },
                set: { if !$0 { infoTarget = nil } }
            )
        ) {
            Button("OK") { infoTarget = nil }
        } message: {
            Text(infoMessage)
        }
    }

    private var infoMessage: String {
        guard let target = infoTarget else { return "" }
        let info = VolumeInfoProvider().info(for: target.url)
        let total = info.totalCapacity.map(Self.sizeFormatter.string(fromByteCount:)) ?? "—"
        let available = info.availableCapacity.map(Self.sizeFormatter.string(fromByteCount:)) ?? "—"
        let format = info.format ?? "—"
        return "Formato: \(format)\nCapacidad: \(total)\nLibre: \(available)"
    }
}
