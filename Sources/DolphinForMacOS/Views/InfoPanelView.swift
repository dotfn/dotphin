import SwiftUI

struct InfoPanelView: View {
    let item: FileItem?

    var body: some View {
        if let item {
            let meta = FileMetadataFormatter().metadata(for: item)
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 8) {
                    Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(item.isDirectory ? .blue : .secondary)
                    Text(item.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                Divider()

                LabeledContent("Tipo", value: meta.kind)
                LabeledContent("Tamaño", value: meta.sizeText)
                LabeledContent("Modificado", value: meta.modifiedText)

                Spacer()
            }
            .padding()
        } else {
            Text("Nada seleccionado")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
