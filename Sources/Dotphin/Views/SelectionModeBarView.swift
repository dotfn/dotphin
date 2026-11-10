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

            Text(String(localized: "Modo de selección: haz clic en archivos o carpetas para seleccionarlos o deseleccionarlos.", bundle: #bundle))
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
            .help(String(localized: "Ayuda del modo de selección", bundle: #bundle))
            .popover(isPresented: $showsHelpPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Modo de selección de Dolphin", bundle: #bundle))
                        .font(.headline)
                    Text(String(localized: "• Un solo clic sobre un archivo o carpeta alterna su selección sin perder el resto.", bundle: #bundle))
                    Text(String(localized: "• Usa la barra inferior para ejecutar acciones por lotes sobre los ítems marcados.", bundle: #bundle))
                    Text(String(localized: "• Puedes seleccionar por patrón (p. ej. *.swift o *.png) o invertir la selección.", bundle: #bundle))
                }
                .font(.caption)
                .padding(12)
                .frame(width: 320)
            }

            Spacer(minLength: 8)

            Button(String(localized: "Seleccionar por patrón…", bundle: #bundle)) {
                onSelectByPattern()
            }
            .controlSize(.small)

            Button {
                onExitSelectionMode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(localized: "Salir del modo de selección", bundle: #bundle))
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
                Text(selectedCount == 0
                    ? String(localized: "Sin selección", bundle: #bundle)
                    : selectedCount == 1 ? String(localized: "1 seleccionado", bundle: #bundle) : String(localized: "\(selectedCount) seleccionados", bundle: #bundle))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectedCount == 0 ? .secondary : .primary)
                    .monospacedDigit()

                Divider()
                    .frame(height: 16)

                Button(String(localized: "Seleccionar todo", bundle: #bundle)) {
                    viewModel.selectAll()
                }
                .controlSize(.small)

                Button(String(localized: "Invertir", bundle: #bundle)) {
                    viewModel.invertSelection()
                }
                .controlSize(.small)

                Button(String(localized: "Por patrón…", bundle: #bundle)) {
                    onSelectByPattern()
                }
                .controlSize(.small)

                if viewModel.canPaste {
                    Divider()
                        .frame(height: 16)

                    Button {
                        viewModel.paste()
                    } label: {
                        Label(String(localized: "Pegar aquí", bundle: #bundle), systemImage: "doc.on.clipboard")
                    }
                    .controlSize(.small)
                }

                if selectedCount > 0 {
                    Button(String(localized: "Deseleccionar", bundle: #bundle)) {
                        viewModel.deselectAll()
                    }
                    .controlSize(.small)

                    Divider()
                        .frame(height: 16)

                    Button {
                        viewModel.copySelected()
                    } label: {
                        Label(String(localized: "Copiar", bundle: #bundle), systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)

                    Button {
                        viewModel.cutSelected()
                    } label: {
                        Label(String(localized: "Cortar", bundle: #bundle), systemImage: "scissors")
                    }
                    .controlSize(.small)

                    Button {
                        viewModel.duplicateSelected()
                    } label: {
                        Label(String(localized: "Duplicar", bundle: #bundle), systemImage: "plus.square.on.square")
                    }
                    .controlSize(.small)

                    Button {
                        onMoveToNewFolder()
                    } label: {
                        Label(String(localized: "Carpeta nueva con selección…", bundle: #bundle), systemImage: "folder.badge.plus")
                    }
                    .controlSize(.small)

                    Button {
                        onRename()
                    } label: {
                        Label(selectedCount > 1 ? String(localized: "Renombrar (\(selectedCount))…", bundle: #bundle) : String(localized: "Renombrar…", bundle: #bundle), systemImage: "pencil")
                    }
                    .controlSize(.small)

                    Button {
                        viewModel.compressSelected()
                    } label: {
                        Label(String(localized: "Comprimir ZIP", bundle: #bundle), systemImage: "doc.zipper")
                    }
                    .controlSize(.small)

                    if selectedCount == 2, let onCompareSelected {
                        Button {
                            onCompareSelected()
                        } label: {
                            Label(String(localized: "Comparar (2)…", bundle: #bundle), systemImage: "arrow.left.and.right.doc.vertical")
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
                            Label(String(localized: "Copiar al otro panel", bundle: #bundle), systemImage: "arrow.right.doc.on.clipboard")
                        }
                        .controlSize(.small)

                        Button {
                            viewModel.moveSelected(to: otherPaneURL)
                            onCrossPaneTransferCompleted?()
                        } label: {
                            Label(String(localized: "Mover al otro panel", bundle: #bundle), systemImage: "arrow.right.square")
                        }
                        .controlSize(.small)
                    }

                    Divider()
                        .frame(height: 16)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(String(localized: "Mover a la Papelera", bundle: #bundle), systemImage: "trash")
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
                ? String(localized: "«\(firstFileName)» listo para mover", bundle: #bundle)
                : String(localized: "«\(firstFileName)» en el portapapeles", bundle: #bundle)
        }
        return isCut
            ? String(localized: "\(itemCount) ítems listos para mover", bundle: #bundle)
            : String(localized: "\(itemCount) ítems en el portapapeles", bundle: #bundle)
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
                    isCut ? String(localized: "Mover aquí (\(destinationFolderName))", bundle: #bundle) : String(localized: "Pegar aquí (\(destinationFolderName))", bundle: #bundle),
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
            .help(String(localized: "Limpiar portapapeles", bundle: #bundle))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
