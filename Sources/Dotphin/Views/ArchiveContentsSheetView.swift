import AppKit
import SwiftUI

/// Sheet view that lists the contents of an archive (`.zip`, `.tar`, `.tar.gz`, etc.)
/// (`DolphinView::openItemAsFolderUrl` / `BrowseThroughArchives` in `src/views/dolphinview.cpp`),
/// allowing the user to filter entries and optionally extract & open the archive as a folder.
struct ArchiveContentsSheetView: View {
    let archiveItem: FileItem
    let onExtractAndOpen: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [ArchiveEntryItem] = []
    @State private var filterText: String = ""

    private var filteredEntries: [ArchiveEntryItem] {
        guard !filterText.isEmpty else { return entries }
        return entries.filter { $0.path.localizedCaseInsensitiveContains(filterText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: archiveItem.url.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(archiveItem.name)
                        .font(.headline)
                    Text(String(localized: "\(entries.count) entrada(s) en el archivo comprimido", bundle: #bundle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField(String(localized: "Filtrar contenido…", bundle: #bundle), text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
            }

            Divider()

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    filterText.isEmpty ? String(localized: "Archivo comprimido vacío", bundle: #bundle) : String(localized: "Sin coincidencias", bundle: #bundle),
                    systemImage: "doc.zipper",
                    description: Text(
                        filterText.isEmpty
                            ? String(localized: "No se encontraron entradas legibles en «\(archiveItem.name)».", bundle: #bundle)
                            : String(localized: "Ninguna entrada coincide con «\(filterText)».", bundle: #bundle)
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredEntries) { entry in
                    HStack(spacing: 6) {
                        if entry.depth > 0 {
                            Spacer()
                                .frame(width: CGFloat(min(6, entry.depth)) * 14)
                        }
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                            .font(.system(size: 12))
                            .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                        Text(entry.displayName)
                            .font(.system(size: 12.5, weight: entry.isDirectory ? .medium : .regular))
                            .lineLimit(1)
                        Spacer()
                        Text(entry.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .padding(.vertical, 1)
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            }

            HStack {
                Button(String(localized: "Mostrar en Finder", bundle: #bundle)) {
                    NSWorkspace.shared.activateFileViewerSelecting([archiveItem.url])
                }
                Spacer()
                Button(String(localized: "Cerrar", bundle: #bundle), role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Extraer aquí y abrir carpeta", bundle: #bundle)) {
                    dismiss()
                    onExtractAndOpen()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 580, height: 440)
        .onAppear {
            entries = ArchiveService().listEntries(of: archiveItem.url)
        }
    }
}
