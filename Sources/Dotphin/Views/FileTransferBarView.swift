import SwiftUI

/// Barra inferior con el avance de una copia o movimiento que tarda, y el
/// botón para detenerla.
struct FileTransferBarView: View {
    let transfer: FileTransferProgress

    private var title: String {
        let verb = transfer.kind == .copy ? "Copiando" : "Moviendo"
        let position = min(transfer.completedCount + 1, transfer.totalCount)
        return "\(verb) \(position) de \(transfer.totalCount) a «\(transfer.destinationName)»"
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(transfer.completedCount), total: Double(max(1, transfer.totalCount)))
                .frame(width: 160)
                .accessibilityLabel(title)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Text(transfer.currentName)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button("Detener", role: .cancel) {
                transfer.cancel()
            }
            .controlSize(.small)
            .help("Detener después del ítem en curso; lo ya transferido queda")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

/// Diálogo "ya existe un ítem con ese nombre": Reemplazar / Conservar ambos /
/// Omitir / Detener, con la casilla estándar para aplicar a todos.
struct FileConflictDialogModifier: ViewModifier {
    let transfer: FileTransferProgress?
    @State private var applyToAll = false

    private var isPresented: Binding<Bool> {
        Binding(
            get: { transfer?.pendingConflict != nil },
            // Cerrar el diálogo sin elegir (Esc) equivale a detener.
            set: { if !$0 { transfer?.resolve(.stop) } }
        )
    }

    func body(content: Content) -> some View {
        content.alert(
            "Ya existe «\(transfer?.pendingConflict?.existing.lastPathComponent ?? "")» en «\(transfer?.destinationName ?? "")»",
            isPresented: isPresented,
            presenting: transfer?.pendingConflict
        ) { _ in
            Button("Reemplazar", role: .destructive) { answer(.replace) }
            Button("Conservar ambos") { answer(.keepBoth) }
            Button("Omitir") { answer(.skip) }
            Button("Detener", role: .cancel) { answer(.stop) }
        } message: { _ in
            Text("Si lo reemplazás, el que ya estaba va a la Papelera y podés deshacerlo.")
        }
        .dialogSuppressionToggle("Aplicar a todos", isSuppressed: $applyToAll)
    }

    private func answer(_ resolution: FileConflictResolution) {
        transfer?.resolve(resolution, applyToAll: applyToAll)
        applyToAll = false
    }
}
