import SwiftUI

struct BatchRenameSheetView: View {
    let items: [FileItem]
    let onCommit: (String, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var pattern: String = "Archivo_#"
    @State private var startIndex: Int = 1

    private var previewPairs: [(item: FileItem, newName: String)] {
        BatchRenameFormatter.plannedRenames(for: items, pattern: pattern, startIndex: startIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Renombrar \(items.count) ítems")
                .font(.headline)

            Text("Usa un carácter '#' o varios ('###') donde quieras insertar la numeración consecutiva. La extensión de cada archivo se mantiene automáticamente.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                TextField("Patrón (ej. Foto_###)", text: $pattern)
                    .textFieldStyle(.roundedBorder)

                Stepper("Inicio: \(startIndex)", value: $startIndex, in: 0...99999)
                    .fixedSize()
            }

            Divider()

            Text("Vista previa")
                .font(.subheadline.weight(.semibold))

            List(previewPairs, id: \.item.id) { pair in
                HStack(spacing: 8) {
                    Text(pair.item.name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(pair.newName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 190)

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) {
                    dismiss()
                }
                Button("Renombrar") {
                    onCommit(pattern, startIndex)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(previewPairs.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
    }
}
