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
            Button(String(localized: "Nueva pestaña", bundle: #bundle)) {
                commands?.perform(.addTab)
            }
            .keyboardShortcut("t", modifiers: .command)

            Button(String(localized: "Duplicar pestaña actual", bundle: #bundle)) {
                commands?.perform(.duplicateTab)
            }

            Button(String(localized: "Reabrir pestaña cerrada", bundle: #bundle)) {
                commands?.perform(.reopenClosedTab)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Nueva carpeta…", bundle: #bundle)) {
                commands?.perform(.createNewFolder)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button(String(localized: "Mover selección a carpeta nueva…", bundle: #bundle)) {
                commands?.perform(.moveToNewFolder)
            }
            .keyboardShortcut("n", modifiers: [.command, .control])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Crear enlace simbólico aquí", bundle: #bundle)) {
                viewModel?.createSymbolicLinkToSelected()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Cerrar pestaña", bundle: #bundle)) {
                commands?.perform(.closeTab)
            }
            .keyboardShortcut("w", modifiers: .command)

            Button(String(localized: "Cerrar otras pestañas", bundle: #bundle)) {
                commands?.perform(.closeOtherTabs)
            }

            Divider()

            Button(String(localized: "Vista rápida", bundle: #bundle)) {
                commands?.perform(.quickLookSelectedFiles)
            }
            .keyboardShortcut("y", modifiers: .command)
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Comparar archivos seleccionados…", bundle: #bundle)) {
                commands?.perform(.compareFiles)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Button(String(localized: "Propiedades…", bundle: #bundle)) {
                commands?.perform(.showProperties)
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        // Deshacer/Rehacer y Cortar/Copiar/Pegar/Seleccionar todo son los del
        // menú Edición estándar: van por la responder chain (campos de texto,
        // `UndoManager` de la ventana y, para archivos, `AppDelegate`).
        CommandGroup(after: .pasteboard) {
            Divider()

            Button(String(localized: "Duplicar aquí", bundle: #bundle)) {
                viewModel?.duplicateSelected()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button((viewModel?.selectedIDs.count ?? 0) > 1 ? String(localized: "Copiar ubicaciones", bundle: #bundle) : String(localized: "Copiar ubicación", bundle: #bundle)) {
                viewModel?.copySelectedPathsToPasteboard()
            }
            .keyboardShortcut("c", modifiers: [.command, .control, .option])
            .disabled(viewModel == nil)

            Button(String(localized: "Copiar al otro panel dividido", bundle: #bundle)) {
                commands?.perform(.copyToOtherSplitPane)
            }
            .keyboardShortcut(Self.fKey(NSF5FunctionKey), modifiers: [.shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Mover al otro panel dividido", bundle: #bundle)) {
                commands?.perform(.moveToOtherSplitPane)
            }
            .keyboardShortcut(Self.fKey(NSF6FunctionKey), modifiers: [.shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Divider()

            Button((viewModel?.isSelectionModeActive ?? false) ? String(localized: "Salir del modo de selección", bundle: #bundle) : String(localized: "Modo de selección", bundle: #bundle)) {
                viewModel?.isSelectionModeActive.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button(String(localized: "Deseleccionar todo", bundle: #bundle)) {
                viewModel?.deselectAll()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Seleccionar ítems por patrón…", bundle: #bundle)) {
                commands?.perform(.selectByPattern)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button(String(localized: "Invertir selección", bundle: #bundle)) {
                viewModel?.invertSelection()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Renombrar…", bundle: #bundle)) {
                commands?.perform(.renameSelectedFiles)
            }
            .keyboardShortcut(Self.fKey(NSF2FunctionKey), modifiers: [])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Mover a la Papelera", bundle: #bundle)) {
                commands?.perform(.deleteSelectedFiles)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Eliminar permanentemente…", bundle: #bundle)) {
                commands?.perform(.permanentDeleteSelectedFiles)
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)
        }

        CommandMenu(String(localized: "Ver", bundle: #bundle)) {
            Button(String(localized: "Modo Iconos", bundle: #bundle)) {
                viewModel?.setViewMode(.icons)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button(String(localized: "Modo Compacto", bundle: #bundle)) {
                viewModel?.setViewMode(.compact)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button(String(localized: "Modo Lista", bundle: #bundle)) {
                viewModel?.setViewMode(.list)
            }
            .keyboardShortcut("3", modifiers: .command)

            Button(String(localized: "Modo Detalles", bundle: #bundle)) {
                viewModel?.setViewMode(.details)
            }
            .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button((viewModel?.viewProperties.showInGroups ?? false) ? "Mostrar en grupos ✓" : String(localized: "Mostrar en grupos", bundle: #bundle)) {
                viewModel?.toggleShowInGroups()
            }
            .keyboardShortcut("g", modifiers: .command)

            Menu(String(localized: "Agrupar por", bundle: #bundle)) {
                let props = viewModel?.viewProperties
                Button(!(props?.showInGroups ?? false) ? "Ninguno ✓" : String(localized: "Ninguno", bundle: #bundle)) {
                    viewModel?.setGroupBy(showInGroups: false, groupFieldOverride: nil)
                }
                Button(((props?.showInGroups ?? false) && props?.groupByFieldOverride == nil)
                    ? String(localized: "Igual que el criterio de ordenación ✓", bundle: #bundle)
                    : String(localized: "Igual que el criterio de ordenación", bundle: #bundle)
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

            Button((viewModel?.viewProperties.showPreviews ?? true) ? "Mostrar vistas previas ✓" : String(localized: "Mostrar vistas previas", bundle: #bundle)) {
                viewModel?.toggleShowPreviews()
            }
            .keyboardShortcut(Self.fKey(NSF12FunctionKey), modifiers: [])

            Button((viewModel?.effectiveShowsHiddenFiles ?? false) ? "Mostrar archivos ocultos ✓" : String(localized: "Mostrar archivos ocultos", bundle: #bundle)) {
                viewModel?.toggleShowsHiddenFiles()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Button(String(localized: "Estilo de visualización de vista…", bundle: #bundle)) {
                commands?.perform(.showViewPropertiesDialog)
            }
            .keyboardShortcut("j", modifiers: .command)

            Button(String(localized: "Restablecer configuración de vista a los valores predeterminados", bundle: #bundle)) {
                viewModel?.resetViewPropertiesToDefault()
            }

            Divider()

            Button(String(localized: "Aumentar zoom", bundle: #bundle)) {
                viewModel?.increaseZoom()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button(String(localized: "Reducir zoom", bundle: #bundle)) {
                viewModel?.decreaseZoom()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button(String(localized: "Tamaño real (100%)", bundle: #bundle)) {
                viewModel?.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button(String(localized: "Dividir vista", bundle: #bundle)) {
                commands?.perform(.toggleSplit)
            }
            .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [])

            Button(String(localized: "Enfocar el otro panel dividido", bundle: #bundle)) {
                commands?.perform(.focusOtherSplitPane)
            }
            .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [.control])

            Button(String(localized: "Separar vista dividida en pestañas", bundle: #bundle)) {
                commands?.perform(.moveSplitToTabs)
            }
            .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [.control, .shift])

            Button(String(localized: "Intercambiar paneles divididos", bundle: #bundle)) {
                commands?.perform(.swapSplitPanes)
            }

            Divider()

            Button(String(localized: "Panel de información", bundle: #bundle)) {
                commands?.perform(.toggleInfoPanel)
            }
            .keyboardShortcut(Self.fKey(NSF11FunctionKey), modifiers: [])

            Button((viewModel?.isFilterBarVisible ?? false) ? "Barra de filtro ✓" : String(localized: "Barra de filtro", bundle: #bundle)) {
                commands?.perform(.toggleFilterBar)
            }
            .keyboardShortcut("/", modifiers: [.command])

            Button(String(localized: "Panel de Terminal integrada", bundle: #bundle)) {
                commands?.perform(.toggleEmbeddedTerminal)
            }
            .keyboardShortcut(Self.fKey(NSF4FunctionKey), modifiers: [])

            Button(String(localized: "Abrir Terminal externa aquí", bundle: #bundle)) {
                commands?.perform(.openTerminal)
            }
            .keyboardShortcut(Self.fKey(NSF4FunctionKey), modifiers: [.shift])

            Divider()

            Button(String(localized: "Estadísticas de uso de disco…", bundle: #bundle)) {
                commands?.perform(.showDiskUsageAnalyzer)
            }
            .keyboardShortcut("u", modifiers: .command)

            Button(String(localized: "Refrescar", bundle: #bundle)) {
                viewModel?.refresh()
            }
            .keyboardShortcut(Self.fKey(NSF5FunctionKey), modifiers: [])
        }

        CommandMenu(String(localized: "Ir", bundle: #bundle)) {
            Button(String(localized: "Atrás", bundle: #bundle)) {
                viewModel?.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!(viewModel?.canGoBack ?? false))

            Button(String(localized: "Adelante", bundle: #bundle)) {
                viewModel?.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!(viewModel?.canGoForward ?? false))

            Button(String(localized: "Subir carpeta", bundle: #bundle)) {
                viewModel?.goUp()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button(String(localized: "Abrir ítem seleccionado", bundle: #bundle)) {
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

            Button(String(localized: "Carpeta personal", bundle: #bundle)) {
                viewModel?.navigate(to: FileManager.default.homeDirectoryForCurrentUser)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button(String(localized: "Buscar…", bundle: #bundle)) {
                commands?.perform(.focusSearch)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(String(localized: "Editar ubicación…", bundle: #bundle)) {
                commands?.perform(.editLocationBar)
            }
            .keyboardShortcut("l", modifiers: .command)

            if let backStack = viewModel?.backStack, !backStack.isEmpty {
                Menu(String(localized: "Historial hacia atrás", bundle: #bundle)) {
                    ForEach(Array(backStack.enumerated().reversed()), id: \.offset) { idx, entryURL in
                        Button(entryURL.lastPathComponent.isEmpty ? "/" : entryURL.lastPathComponent) {
                            viewModel?.jumpBack(toStackIndex: idx)
                        }
                    }
                }
            }

            if let forwardStack = viewModel?.forwardStack, !forwardStack.isEmpty {
                Menu(String(localized: "Historial hacia adelante", bundle: #bundle)) {
                    ForEach(Array(forwardStack.enumerated().reversed()), id: \.offset) { idx, entryURL in
                        Button(entryURL.lastPathComponent.isEmpty ? "/" : entryURL.lastPathComponent) {
                            viewModel?.jumpForward(toStackIndex: idx)
                        }
                    }
                }
            }

            Divider()

            Button(String(localized: "Pestaña siguiente", bundle: #bundle)) {
                commands?.perform(.selectNextTab)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button(String(localized: "Pestaña anterior", bundle: #bundle)) {
                commands?.perform(.selectPrevTab)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Button(String(localized: "Reabrir última pestaña cerrada", bundle: #bundle)) {
                commands?.perform(.reopenClosedTab)
            }
        }

        CommandMenu(String(localized: "Marcadores", bundle: #bundle)) {
            Button(String(localized: "Añadir carpeta actual a Lugares", bundle: #bundle)) {
                guard let url = viewModel?.currentURL else { return }
                PlacesProvider().addBookmark(for: url)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(viewModel == nil)

            Button(String(localized: "Añadir todas las pestañas abiertas a Marcadores", bundle: #bundle)) {
                commands?.perform(.bookmarkAllTabs)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button(String(localized: "Abrir todos los marcadores en pestañas", bundle: #bundle)) {
                commands?.perform(.openAllBookmarksInTabs)
            }
            .disabled(PlacesProvider().customBookmarks().isEmpty)

            Button(String(localized: "Editar marcadores…", bundle: #bundle)) {
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
