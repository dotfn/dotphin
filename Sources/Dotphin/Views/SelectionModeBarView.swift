import SwiftUI

/// Mirrors KDE Dolphin's `SelectionMode::TopBar` (`src/selectionmode/topbar.cpp`).
struct SelectionModeTopBarView: View {
    let onSelectByPattern: () -> Void
    let onExitSelectionMode: () -> Void

    @State private var showsHelpPopover = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 13, weight: .semibold))

            Text("Modo de selección: haz clic en archivos o carpetas para seleccionarlos o deseleccionarlos.")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            Button {
                showsHelpPopover.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Ayuda del modo de selección")
            .popover(isPresented: $showsHelpPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Modo de selección de Dolphin")
                        .font(.headline)
                    Text("• Un solo clic sobre un archivo o carpeta alterna su selección sin perder el resto.")
                    Text("• Usa la barra inferior para ejecutar acciones por lotes sobre los ítems marcados.")
                    Text("• Puedes seleccionar por patrón (p. ej. *.swift o *.png) o invertir la selección.")
                }
                .font(.caption)
                .padding(12)
                .frame(width: 320)
            }

            Spacer(minLength: 8)

            Button("Seleccionar por patrón…") {
                onSelectByPattern()
            }
            .controlSize(.small)

            Button {
                onExitSelectionMode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Salir del modo de selección")
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
    }
}

/// Mirrors KDE Dolphin's `SelectionMode::BottomBar` (`src/selectionmode/bottombar.cpp` & `bottombarcontentscontainer.cpp`).
struct SelectionModeBottomBarView: View {
    let viewModel: BrowserViewModel
    var otherPaneURL: URL? = nil
    let onRename: () -> Void
    let onMoveToNewFolder: () -> Void
    let onDelete: () -> Void
    let onSelectByPattern: () -> Void
    var onCompareSelected: (() -> Void)? = nil
    var onCrossPaneTransferCompleted: (() -> Void)? = nil

    private var selectedCount: Int {
        viewModel.selectedIDs.count
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text(selectedCount == 0 ? "Sin selección" : "\(selectedCount) \(selectedCount == 1 ? "seleccionado" : "seleccionados")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectedCount == 0 ? .secondary : .primary)
                    .monospacedDigit()

                Divider()
                    .frame(height: 16)

                Button("Seleccionar todo") {
                    viewModel.selectAll()
                }
                .controlSize(.small)

                Button("Invertir") {
                    viewModel.invertSelection()
                }
                .controlSize(.small)

                Button("Por patrón…") {
                    onSelectByPattern()
                }
                .controlSize(.small)

                if viewModel.canPaste {
                    Divider()
                        .frame(height: 16)

                    Button {
                        viewModel.paste()
                    } label: {
                        Label("Pegar aquí", systemImage: "doc.on.clipboard")
                    }
                    .controlSize(.small)
                }

                if selectedCount > 0 {
                    Button("Deseleccionar") {
                        viewModel.deselectAll()
                    }
                    .controlSize(.small)

                    Divider()
                        .frame(height: 16)

                    Button {
                        viewModel.copySelected()
                    } label: {
                        Label("Copiar", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)

                    Button {
                        viewModel.cutSelected()
                    } label: {
                        Label("Cortar", systemImage: "scissors")
                    }
                    .controlSize(.small)

                    Button {
                        viewModel.duplicateSelected()
                    } label: {
                        Label("Duplicar", systemImage: "plus.square.on.square")
                    }
                    .controlSize(.small)

                    Button {
                        onMoveToNewFolder()
                    } label: {
                        Label("Carpeta nueva con selección…", systemImage: "folder.badge.plus")
                    }
                    .controlSize(.small)

                    Button {
                        onRename()
                    } label: {
                        Label(selectedCount > 1 ? "Renombrar (\(selectedCount))…" : "Renombrar…", systemImage: "pencil")
                    }
                    .controlSize(.small)

                    Button {
                        viewModel.compressSelected()
                    } label: {
                        Label("Comprimir ZIP", systemImage: "doc.zipper")
                    }
                    .controlSize(.small)

                    if selectedCount == 2, let onCompareSelected {
                        Button {
                            onCompareSelected()
                        } label: {
                            Label("Comparar (2)…", systemImage: "arrow.left.and.right.doc.vertical")
                        }
                        .controlSize(.small)
                    }

                    if let otherPaneURL {
                        Divider()
                            .frame(height: 16)

                        Button {
                            viewModel.copySelected(to: otherPaneURL)
                            onCrossPaneTransferCompleted?()
                        } label: {
                            Label("Copiar al otro panel", systemImage: "arrow.right.doc.on.clipboard")
                        }
                        .controlSize(.small)

                        Button {
                            viewModel.moveSelected(to: otherPaneURL)
                            onCrossPaneTransferCompleted?()
                        } label: {
                            Label("Mover al otro panel", systemImage: "arrow.right.square")
                        }
                        .controlSize(.small)
                    }

                    Divider()
                        .frame(height: 16)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Mover a la Papelera", systemImage: "trash")
                    }
                    .controlSize(.small)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(.bar)
    }
}

/// Mirrors KDE Dolphin's `SelectionMode::BottomBar::PasteContents` (`ShowPasteBarAfterCopying` in `dolphin_generalsettings.kcfg`):
/// a compact bottom bar shown when items are in the clipboard, allowing one-click pasting or clearing the clipboard.
struct PasteAfterCopyingBarView: View {
    let itemCount: Int
    let isCut: Bool
    let firstFileName: String
    let destinationFolderName: String
    let onPasteHere: () -> Void
    let onCancelClipboard: () -> Void

    private var summaryText: String {
        if itemCount == 1 {
            return isCut
                ? "«\(firstFileName)» listo para mover"
                : "«\(firstFileName)» en el portapapeles"
        }
        return isCut
            ? "\(itemCount) ítems listos para mover"
            : "\(itemCount) ítems en el portapapeles"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCut ? "scissors" : "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(summaryText)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                onPasteHere()
            } label: {
                Label(
                    isCut ? "Mover aquí (\(destinationFolderName))" : "Pegar aquí (\(destinationFolderName))",
                    systemImage: "arrow.down.doc"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                onCancelClipboard()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Limpiar portapapeles")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
