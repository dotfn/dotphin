import AppKit
import SwiftUI

private struct BrowserViewModelFocusedKey: FocusedValueKey {
    typealias Value = BrowserViewModel
}

extension FocusedValues {
    var browserViewModel: BrowserViewModel? {
        get { self[BrowserViewModelFocusedKey.self] }
        set { self[BrowserViewModelFocusedKey.self] = newValue }
    }
}

/// Edit, File, View, Go, and Bookmarks menu commands replicating Dolphin's keyboard shortcuts alongside native macOS ones.
struct FileEditCommands: Commands {
    @FocusedValue(\.browserViewModel) private var viewModel
    @FocusedValue(\.windowCommands) private var commands

    private static func fKey(_ code: Int) -> KeyEquivalent {
        KeyEquivalent(Character(UnicodeScalar(code)!))
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nueva pestaña") {
                commands?.perform(.addTab)
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Duplicar pestaña actual") {
                commands?.perform(.duplicateTab)
            }

            Button("Reabrir pestaña cerrada") {
                commands?.perform(.reopenClosedTab)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("Nueva carpeta…") {
                commands?.perform(.createNewFolder)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Mover selección a carpeta nueva…") {
                commands?.perform(.moveToNewFolder)
            }
            .keyboardShortcut("n", modifiers: [.command, .control])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Crear enlace simbólico aquí") {
                viewModel?.createSymbolicLinkToSelected()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Cerrar pestaña") {
                commands?.perform(.closeTab)
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("Cerrar otras pestañas") {
                commands?.perform(.closeOtherTabs)
            }

            Divider()

            Button("Vista rápida") {
                commands?.perform(.quickLookSelectedFiles)
            }
            .keyboardShortcut("y", modifiers: .command)
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Comparar archivos seleccionados…") {
                commands?.perform(.compareFiles)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Button("Propiedades…") {
                commands?.perform(.showProperties)
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        // Deshacer/Rehacer y Cortar/Copiar/Pegar/Seleccionar todo son los del
        // menú Edición estándar: van por la responder chain (campos de texto,
        // `UndoManager` de la ventana y, para archivos, `AppDelegate`).
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Duplicar aquí") {
                viewModel?.duplicateSelected()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button((viewModel?.selectedIDs.count ?? 0) > 1 ? "Copiar ubicaciones" : "Copiar ubicación") {
                viewModel?.copySelectedPathsToPasteboard()
            }
            .keyboardShortcut("c", modifiers: [.command, .control, .option])
            .disabled(viewModel == nil)

            Button("Copiar al otro panel dividido") {
                commands?.perform(.copyToOtherSplitPane)
            }
            .keyboardShortcut(Self.fKey(NSF5FunctionKey), modifiers: [.shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Mover al otro panel dividido") {
                commands?.perform(.moveToOtherSplitPane)
            }
            .keyboardShortcut(Self.fKey(NSF6FunctionKey), modifiers: [.shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Divider()

            Button((viewModel?.isSelectionModeActive ?? false) ? "Salir del modo de selección" : "Modo de selección") {
                viewModel?.isSelectionModeActive.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Deseleccionar todo") {
                viewModel?.deselectAll()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Seleccionar ítems por patrón…") {
                commands?.perform(.selectByPattern)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Invertir selección") {
                viewModel?.invertSelection()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Divider()

            Button("Renombrar…") {
                commands?.perform(.renameSelectedFiles)
            }
            .keyboardShortcut(Self.fKey(NSF2FunctionKey), modifiers: [])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Mover a la Papelera") {
                commands?.perform(.deleteSelectedFiles)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Eliminar permanentemente…") {
                commands?.perform(.permanentDeleteSelectedFiles)
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)
        }

        CommandMenu("Ver") {
            Button("Modo Iconos") {
                viewModel?.setViewMode(.icons)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Modo Compacto") {
                viewModel?.setViewMode(.compact)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Modo Lista") {
                viewModel?.setViewMode(.list)
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("Modo Detalles") {
                viewModel?.setViewMode(.details)
            }
            .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button((viewModel?.viewProperties.showInGroups ?? false) ? "Mostrar en grupos ✓" : "Mostrar en grupos") {
                viewModel?.toggleShowInGroups()
            }
            .keyboardShortcut("g", modifiers: .command)

            Menu("Agrupar por") {
                let props = viewModel?.viewProperties
                Button(!(props?.showInGroups ?? false) ? "Ninguno ✓" : "Ninguno") {
                    viewModel?.setGroupBy(showInGroups: false, groupFieldOverride: nil)
                }
                Button(((props?.showInGroups ?? false) && props?.groupByFieldOverride == nil)
                    ? "Igual que el criterio de ordenación ✓"
                    : "Igual que el criterio de ordenación"
                ) {
                    viewModel?.setGroupBy(showInGroups: true, groupFieldOverride: nil)
                }
                Divider()
                ForEach(SortField.allCases, id: \.self) { field in
                    let isChecked = (props?.showInGroups ?? false) && props?.groupByFieldOverride == field
                    Button(isChecked ? "\(field.title) ✓" : field.title) {
                        viewModel?.setGroupBy(showInGroups: true, groupFieldOverride: field)
                    }
                }
            }

            Button((viewModel?.viewProperties.showPreviews ?? true) ? "Mostrar vistas previas ✓" : "Mostrar vistas previas") {
                viewModel?.toggleShowPreviews()
            }
            .keyboardShortcut(Self.fKey(NSF12FunctionKey), modifiers: [])

            Button((viewModel?.effectiveShowsHiddenFiles ?? false) ? "Mostrar archivos ocultos ✓" : "Mostrar archivos ocultos") {
                viewModel?.toggleShowsHiddenFiles()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Button("Estilo de visualización de vista…") {
                commands?.perform(.showViewPropertiesDialog)
            }
            .keyboardShortcut("j", modifiers: .command)

            Button("Restablecer configuración de vista a los valores predeterminados") {
                viewModel?.resetViewPropertiesToDefault()
            }

            Divider()

            Button("Aumentar zoom") {
                viewModel?.increaseZoom()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Reducir zoom") {
                viewModel?.decreaseZoom()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Tamaño real (100%)") {
                viewModel?.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button("Dividir vista") {
                commands?.perform(.toggleSplit)
            }
            .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [])

            Button("Enfocar el otro panel dividido") {
                commands?.perform(.focusOtherSplitPane)
            }
            .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [.control])

            Button("Separar vista dividida en pestañas") {
                commands?.perform(.moveSplitToTabs)
            }
            .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [.control, .shift])

            Button("Intercambiar paneles divididos") {
                commands?.perform(.swapSplitPanes)
            }

            Divider()

            Button("Panel de información") {
                commands?.perform(.toggleInfoPanel)
            }
            .keyboardShortcut(Self.fKey(NSF11FunctionKey), modifiers: [])

            Button((viewModel?.isFilterBarVisible ?? false) ? "Barra de filtro ✓" : "Barra de filtro") {
                commands?.perform(.toggleFilterBar)
            }
            .keyboardShortcut("/", modifiers: [.command])

            Button("Panel de Terminal integrada") {
                commands?.perform(.toggleEmbeddedTerminal)
            }
            .keyboardShortcut(Self.fKey(NSF4FunctionKey), modifiers: [])

            Button("Abrir Terminal externa aquí") {
                commands?.perform(.openTerminal)
            }
            .keyboardShortcut(Self.fKey(NSF4FunctionKey), modifiers: [.shift])

            Divider()

            Button("Estadísticas de uso de disco…") {
                commands?.perform(.showDiskUsageAnalyzer)
            }
            .keyboardShortcut("u", modifiers: .command)

            Button("Refrescar") {
                viewModel?.refresh()
            }
            .keyboardShortcut(Self.fKey(NSF5FunctionKey), modifiers: [])
        }

        CommandMenu("Ir") {
            Button("Atrás") {
                viewModel?.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!(viewModel?.canGoBack ?? false))

            Button("Adelante") {
                viewModel?.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!(viewModel?.canGoForward ?? false))

            Button("Subir carpeta") {
                viewModel?.goUp()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Abrir ítem seleccionado") {
                guard let viewModel, let item = viewModel.selectedItem else { return }
                if item.isDirectory {
                    viewModel.navigate(to: item.url)
                } else {
                    NSWorkspace.shared.open(item.url)
                }
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(viewModel?.selectedItem == nil)

            Divider()

            Button("Carpeta personal") {
                viewModel?.navigate(to: FileManager.default.homeDirectoryForCurrentUser)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button("Editar ubicación…") {
                commands?.perform(.editLocationBar)
            }
            .keyboardShortcut("l", modifiers: .command)

            if let backStack = viewModel?.backStack, !backStack.isEmpty {
                Menu("Historial hacia atrás") {
                    ForEach(Array(backStack.enumerated().reversed()), id: \.offset) { idx, entryURL in
                        Button(entryURL.lastPathComponent.isEmpty ? "/" : entryURL.lastPathComponent) {
                            viewModel?.jumpBack(toStackIndex: idx)
                        }
                    }
                }
            }

            if let forwardStack = viewModel?.forwardStack, !forwardStack.isEmpty {
                Menu("Historial hacia adelante") {
                    ForEach(Array(forwardStack.enumerated().reversed()), id: \.offset) { idx, entryURL in
                        Button(entryURL.lastPathComponent.isEmpty ? "/" : entryURL.lastPathComponent) {
                            viewModel?.jumpForward(toStackIndex: idx)
                        }
                    }
                }
            }

            Divider()

            Button("Pestaña siguiente") {
                commands?.perform(.selectNextTab)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Pestaña anterior") {
                commands?.perform(.selectPrevTab)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Button("Reabrir última pestaña cerrada") {
                commands?.perform(.reopenClosedTab)
            }
        }

        CommandMenu("Marcadores") {
            Button("Añadir carpeta actual a Lugares") {
                guard let url = viewModel?.currentURL else { return }
                PlacesProvider().addBookmark(for: url)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(viewModel == nil)

            Button("Añadir todas las pestañas abiertas a Marcadores") {
                commands?.perform(.bookmarkAllTabs)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Abrir todos los marcadores en pestañas") {
                commands?.perform(.openAllBookmarksInTabs)
            }
            .disabled(PlacesProvider().customBookmarks().isEmpty)

            Button("Editar marcadores…") {
                commands?.perform(.editBookmarks)
            }
            .keyboardShortcut("b", modifiers: [.command, .option])

            let custom = PlacesProvider().customBookmarks()
            if !custom.isEmpty {
                Divider()
                ForEach(custom) { place in
                    Button(place.name) {
                        viewModel?.navigate(to: place.url)
                    }
                }
            }
        }
    }
}
