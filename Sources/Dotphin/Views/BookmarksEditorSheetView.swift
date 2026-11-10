import AppKit
import SwiftUI

/// KDE Dolphin's `edit_bookmarks` dialog (`src/dolphinbookmarkhandler.cpp`):
/// Allows adding, renaming, reordering, removing, or opening custom bookmarks in tabs.
struct BookmarksEditorSheetView: View {
    @Environment(\.dismiss) private var dismiss
    var onOpenAllInTabs: (([URL]) -> Void)? = nil

    @State private var bookmarks: [PlaceItem] = PlacesProvider().customBookmarks()
    @State private var selectedURL: URL? = nil
    @State private var renameDraft: String = ""

    private let provider = PlacesProvider()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "Editar marcadores", bundle: #bundle), systemImage: "bookmark.square.fill")
                    .font(.headline)
                Spacer()
                if !bookmarks.isEmpty, let onOpenAllInTabs {
                    Button {
                        onOpenAllInTabs(bookmarks.map(\.url))
                        dismiss()
                    } label: {
                        Label(String(localized: "Abrir todos en pestañas", bundle: #bundle), systemImage: "plus.square.on.square")
                    }
                    .controlSize(.small)
                }
            }

            if bookmarks.isEmpty {
                ContentUnavailableView(
                    String(localized: "Sin marcadores personalizados", bundle: #bundle),
                    systemImage: "bookmark",
                    description: Text(String(localized: "Añade carpetas a tus marcadores con ⌘B o el botón «Añadir carpeta…».", bundle: #bundle))
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List(selection: $selectedURL) {
                    ForEach(Array(bookmarks.enumerated()), id: \.element.url) { idx, item in
                        HStack(spacing: 10) {
                            Image(systemName: item.systemImage)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(item.url.path)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Button {
                                    provider.moveBookmark(from: idx, to: idx - 1)
                                    reload()
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(idx == 0)
                                .help(String(localized: "Subir marcador", bundle: #bundle))

                                Button {
                                    provider.moveBookmark(from: idx, to: idx + 1)
                                    reload()
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(idx == bookmarks.count - 1)
                                .help(String(localized: "Bajar marcador", bundle: #bundle))

                                Button(role: .destructive) {
                                    provider.removeBookmark(for: item.url)
                                    reload()
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .help(String(localized: "Eliminar marcador", bundle: #bundle))
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(item.url)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 200)
            }

            if let selectedURL,
               let selectedItem = bookmarks.first(where: { $0.url == selectedURL }) {
                HStack(spacing: 8) {
                    Text(String(localized: "Nombre:", bundle: #bundle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Nombre del marcador", bundle: #bundle), text: $renameDraft)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit {
                            provider.renameBookmark(for: selectedItem.url, to: renameDraft)
                            reload()
                        }
                    Button(String(localized: "Guardar nombre", bundle: #bundle)) {
                        provider.renameBookmark(for: selectedItem.url, to: renameDraft)
                        reload()
                    }
                    .controlSize(.small)
                    .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Divider()

            HStack {
                Button {
                    chooseFolderToAdd()
                } label: {
                    Label(String(localized: "Añadir carpeta…", bundle: #bundle), systemImage: "plus")
                }

                Spacer()

                Button(String(localized: "Cerrar", bundle: #bundle)) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520, height: 380)
        .onChange(of: selectedURL) { _, newURL in
            if let newURL, let item = bookmarks.first(where: { $0.url == newURL }) {
                renameDraft = item.name
            } else {
                renameDraft = ""
            }
        }
    }

    private func reload() {
        bookmarks = provider.customBookmarks()
        if let selectedURL, !bookmarks.contains(where: { $0.url == selectedURL }) {
            self.selectedURL = nil
        }
    }

    private func chooseFolderToAdd() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Añadir a Marcadores", bundle: #bundle)
        if panel.runModal() == .OK {
            provider.addBookmarks(for: panel.urls)
            reload()
        }
    }
}
