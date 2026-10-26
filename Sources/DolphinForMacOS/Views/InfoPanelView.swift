import AppKit
import SwiftUI

struct InfoPanelView: View {
    let item: FileItem?

    @State private var thumbnail: NSImage?

    var body: some View {
        if let item {
            let meta = FileMetadataFormatter().metadata(for: item)
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 8) {
                    Group {
                        if let thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .task(id: item.url) {
                        thumbnail = nil
                        guard !item.isDirectory else { return }
                        let image = await ThumbnailLoader().thumbnail(for: item.url, size: CGSize(width: 128, height: 128))
                        // El continuation de QLThumbnailGenerator no tiene punto de
                        // cancelación cooperativa: si el ítem seleccionado cambió
                        // mientras esto cargaba, este Task ya está cancelado pero
                        // puede reanudar igual — sin este guard, el thumbnail viejo
                        // pisa el del ítem nuevo.
                        guard !Task.isCancelled else { return }
                        thumbnail = image
                    }
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
