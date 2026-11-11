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
            Button(String(localized: "Nueva pestaña", bundle: #bundle), menuIcon: "plus.square.on.square") {
                commands?.perform(.addTab)
            }
            .keyboardShortcut("t", modifiers: .command)

            Button(String(localized: "Duplicar pestaña actual", bundle: #bundle), menuIcon: "square.on.square") {
                commands?.perform(.duplicateTab)
            }

            Button(String(localized: "Reabrir pestaña cerrada", bundle: #bundle), menuIcon: "arrow.uturn.backward") {
                commands?.perform(.reopenClosedTab)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Nueva carpeta…", bundle: #bundle), menuIcon: "folder.badge.plus") {
                commands?.perform(.createNewFolder)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button(String(localized: "Mover selección a carpeta nueva…", bundle: #bundle), menuIcon: "tray.and.arrow.down") {
                commands?.perform(.moveToNewFolder)
            }
            .keyboardShortcut("n", modifiers: [.command, .control])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Crear enlace simbólico aquí", bundle: #bundle), menuIcon: "link.badge.plus") {
                viewModel?.createSymbolicLinkToSelected()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Cerrar pestaña", bundle: #bundle), menuIcon: "xmark") {
                commands?.perform(.closeTab)
            }
            .keyboardShortcut("w", modifiers: .command)

            Button(String(localized: "Cerrar otras pestañas", bundle: #bundle), menuIcon: "xmark.square") {
                commands?.perform(.closeOtherTabs)
            }

            Divider()

            Button(String(localized: "Vista rápida", bundle: #bundle), menuIcon: "eye") {
                commands?.perform(.quickLookSelectedFiles)
            }
            .keyboardShortcut("y", modifiers: .command)
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Comparar archivos seleccionados…", bundle: #bundle), menuIcon: "arrow.left.arrow.right") {
                commands?.perform(.compareFiles)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Button(String(localized: "Propiedades…", bundle: #bundle), menuIcon: "info.circle") {
                commands?.perform(.showProperties)
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        // Deshacer/Rehacer y Cortar/Copiar/Pegar/Seleccionar todo son los del
        // menú Edición estándar: van por la responder chain (campos de texto,
        // `UndoManager` de la ventana y, para archivos, `AppDelegate`).
        CommandGroup(after: .pasteboard) {
            Divider()

            Button(String(localized: "Duplicar aquí", bundle: #bundle), menuIcon: "square.on.square") {
                viewModel?.duplicateSelected()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button((viewModel?.selectedIDs.count ?? 0) > 1 ? String(localized: "Copiar ubicaciones", bundle: #bundle) : String(localized: "Copiar ubicación", bundle: #bundle), menuIcon: "link") {
                viewModel?.copySelectedPathsToPasteboard()
            }
            .keyboardShortcut("c", modifiers: [.command, .control, .option])
            .disabled(viewModel == nil)

            Button(String(localized: "Copiar al otro panel dividido", bundle: #bundle), menuIcon: "doc.on.doc") {
                commands?.perform(.copyToOtherSplitPane)
            }
            .keyboardShortcut(Self.fKey(NSF5FunctionKey), modifiers: [.shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Mover al otro panel dividido", bundle: #bundle), menuIcon: "arrow.right.square") {
                commands?.perform(.moveToOtherSplitPane)
            }
            .keyboardShortcut(Self.fKey(NSF6FunctionKey), modifiers: [.shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Divider()

            Button((viewModel?.isSelectionModeActive ?? false) ? String(localized: "Salir del modo de selección", bundle: #bundle) : String(localized: "Modo de selección", bundle: #bundle), menuIcon: "checkmark.circle") {
                viewModel?.isSelectionModeActive.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button(String(localized: "Deseleccionar todo", bundle: #bundle), menuIcon: "xmark.circle") {
                viewModel?.deselectAll()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Seleccionar ítems por patrón…", bundle: #bundle), menuIcon: "text.magnifyingglass") {
                commands?.perform(.selectByPattern)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button(String(localized: "Invertir selección", bundle: #bundle), menuIcon: "circle.lefthalf.filled") {
                viewModel?.invertSelection()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Renombrar…", bundle: #bundle), menuIcon: "pencil") {
                commands?.perform(.renameSelectedFiles)
            }
            .keyboardShortcut(Self.fKey(NSF2FunctionKey), modifiers: [])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Mover a la Papelera", bundle: #bundle), menuIcon: "trash") {
                commands?.perform(.deleteSelectedFiles)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button(String(localized: "Eliminar permanentemente…", bundle: #bundle), menuIcon: "trash.slash") {
                commands?.perform(.permanentDeleteSelectedFiles)
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)
        }

        // Dentro del menú Visualización del sistema (el de pantalla completa y
        // barra lateral), como Finder: un menú propio "Ver" quedaba duplicado.
        CommandGroup(before: .sidebar) {
            Button(String(localized: "Modo Iconos", bundle: #bundle), menuIcon: "square.grid.2x2") {
                viewModel?.setViewMode(.icons)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button(String(localized: "Modo Compacto", bundle: #bundle), menuIcon: "rectangle.grid.3x2") {
                viewModel?.setViewMode(.compact)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button(String(localized: "Modo Lista", bundle: #bundle), menuIcon: "list.bullet") {
                viewModel?.setViewMode(.list)
            }
            .keyboardShortcut("3", modifiers: .command)

            Button(String(localized: "Modo Detalles", bundle: #bundle), menuIcon: "tablecells") {
                viewModel?.setViewMode(.details)
            }
            .keyboardShortcut("4", modifiers: .command)

            Divider()

            Toggle(String(localized: "Mostrar en grupos", bundle: #bundle), isOn: Binding(
                get: { viewModel?.viewProperties.showInGroups ?? false },
                set: { _ in viewModel?.toggleShowInGroups() }
            ))
            .keyboardShortcut("g", modifiers: .command)

            Menu(String(localized: "Agrupar por", bundle: #bundle), menuIcon: "rectangle.3.group") {
                GroupByPicker(selection: Binding(
                    get: { viewModel?.groupByChoice ?? .none },
                    set: { viewModel?.groupByChoice = $0 }
                ))
            }

            Toggle(String(localized: "Mostrar vistas previas", bundle: #bundle), isOn: Binding(
                get: { viewModel?.viewProperties.showPreviews ?? true },
                set: { _ in viewModel?.toggleShowPreviews() }
            ))
            .keyboardShortcut(Self.fKey(NSF12FunctionKey), modifiers: [])

            Toggle(String(localized: "Mostrar archivos ocultos", bundle: #bundle), isOn: Binding(
                get: { viewModel?.effectiveShowsHiddenFiles ?? false },
                set: { _ in viewModel?.toggleShowsHiddenFiles() }
            ))
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Button(String(localized: "Estilo de visualización de vista…", bundle: #bundle), menuIcon: "slider.horizontal.3") {
                commands?.perform(.showViewPropertiesDialog)
            }
            .keyboardShortcut("j", modifiers: .command)

            Button(String(localized: "Restablecer configuración de vista a los valores predeterminados", bundle: #bundle), menuIcon: "arrow.counterclockwise") {
                viewModel?.resetViewPropertiesToDefault()
            }

            Divider()

            Button(String(localized: "Aumentar zoom", bundle: #bundle), menuIcon: "plus.magnifyingglass") {
                viewModel?.increaseZoom()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button(String(localized: "Reducir zoom", bundle: #bundle), menuIcon: "minus.magnifyingglass") {
                viewModel?.decreaseZoom()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button(String(localized: "Tamaño real (100%)", bundle: #bundle), menuIcon: "1.magnifyingglass") {
                viewModel?.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button(String(localized: "Dividir vista", bundle: #bundle), menuIcon: "rectangle.split.2x1") {
                commands?.perform(.toggleSplit)
            }
            .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [])

            Button(String(localized: "Enfocar el otro panel dividido", bundle: #bundle), menuIcon: "rectangle.righthalf.inset.filled") {
                commands?.perform(.focusOtherSplitPane)
            }
            .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [.control])

            Button(String(localized: "Separar vista dividida en pestañas", bundle: #bundle), menuIcon: "rectangle.on.rectangle") {
                commands?.perform(.moveSplitToTabs)
            }
            .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [.control, .shift])

            Button(String(localized: "Intercambiar paneles divididos", bundle: #bundle), menuIcon: "arrow.left.arrow.right") {
                commands?.perform(.swapSplitPanes)
            }

            Divider()

            Button(String(localized: "Panel de información", bundle: #bundle), menuIcon: "sidebar.right") {
                commands?.perform(.toggleInfoPanel)
            }
            .keyboardShortcut(Self.fKey(NSF11FunctionKey), modifiers: [])

            Toggle(String(localized: "Barra de filtro", bundle: #bundle), isOn: Binding(
                get: { viewModel?.isFilterBarVisible ?? false },
                set: { _ in commands?.perform(.toggleFilterBar) }
            ))
            .keyboardShortcut("/", modifiers: [.command])

            Button(String(localized: "Panel de Terminal integrada", bundle: #bundle), menuIcon: "terminal") {
                commands?.perform(.toggleEmbeddedTerminal)
            }
            .keyboardShortcut(Self.fKey(NSF4FunctionKey), modifiers: [])

            Button(String(localized: "Abrir Terminal externa aquí", bundle: #bundle), menuIcon: "arrow.up.forward.app") {
                commands?.perform(.openTerminal)
            }
            .keyboardShortcut(Self.fKey(NSF4FunctionKey), modifiers: [.shift])

            Divider()

            Button(String(localized: "Estadísticas de uso de disco…", bundle: #bundle), menuIcon: "chart.pie") {
                commands?.perform(.showDiskUsageAnalyzer)
            }
            .keyboardShortcut("u", modifiers: .command)

            Button(String(localized: "Refrescar", bundle: #bundle), menuIcon: "arrow.clockwise") {
                viewModel?.refresh()
            }
            .keyboardShortcut(Self.fKey(NSF5FunctionKey), modifiers: [])
        }

        CommandMenu(String(localized: "Ir", bundle: #bundle)) {
            Button(String(localized: "Atrás", bundle: #bundle), menuIcon: "chevron.left") {
                viewModel?.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!(viewModel?.canGoBack ?? false))

            Button(String(localized: "Adelante", bundle: #bundle), menuIcon: "chevron.right") {
                viewModel?.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!(viewModel?.canGoForward ?? false))

            Button(String(localized: "Subir carpeta", bundle: #bundle), menuIcon: "chevron.up") {
                viewModel?.goUp()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button(String(localized: "Abrir ítem seleccionado", bundle: #bundle), menuIcon: "arrow.up.forward.square") {
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

            Button(String(localized: "Carpeta personal", bundle: #bundle), menuIcon: "house") {
                viewModel?.navigate(to: FileManager.default.homeDirectoryForCurrentUser)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button(String(localized: "Buscar…", bundle: #bundle), menuIcon: "magnifyingglass") {
                commands?.perform(.focusSearch)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(String(localized: "Editar ubicación…", bundle: #bundle), menuIcon: "character.cursor.ibeam") {
                commands?.perform(.editLocationBar)
            }
            .keyboardShortcut("l", modifiers: .command)

            if let backStack = viewModel?.backStack, !backStack.isEmpty {
                Menu(String(localized: "Historial hacia atrás", bundle: #bundle), menuIcon: "clock.arrow.circlepath") {
                    ForEach(Array(backStack.enumerated().reversed()), id: \.offset) { idx, entryURL in
                        Button(entryURL.lastPathComponent.isEmpty ? "/" : entryURL.lastPathComponent) {
                            viewModel?.jumpBack(toStackIndex: idx)
                        }
                    }
                }
            }

            if let forwardStack = viewModel?.forwardStack, !forwardStack.isEmpty {
                Menu(String(localized: "Historial hacia adelante", bundle: #bundle), menuIcon: "clock.arrow.circlepath") {
                    ForEach(Array(forwardStack.enumerated().reversed()), id: \.offset) { idx, entryURL in
                        Button(entryURL.lastPathComponent.isEmpty ? "/" : entryURL.lastPathComponent) {
                            viewModel?.jumpForward(toStackIndex: idx)
                        }
                    }
                }
            }

            Divider()

            Button(String(localized: "Pestaña siguiente", bundle: #bundle), menuIcon: "chevron.right.2") {
                commands?.perform(.selectNextTab)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button(String(localized: "Pestaña anterior", bundle: #bundle), menuIcon: "chevron.left.2") {
                commands?.perform(.selectPrevTab)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Button(String(localized: "Reabrir última pestaña cerrada", bundle: #bundle), menuIcon: "arrow.uturn.backward") {
                commands?.perform(.reopenClosedTab)
            }
        }

        CommandMenu(String(localized: "Marcadores", bundle: #bundle)) {
            Button(String(localized: "Añadir carpeta actual a Lugares", bundle: #bundle), menuIcon: "bookmark") {
                guard let url = viewModel?.currentURL else { return }
                PlacesProvider().addBookmark(for: url)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(viewModel == nil)

            Button(String(localized: "Añadir todas las pestañas abiertas a Marcadores", bundle: #bundle), menuIcon: "rectangle.stack.badge.plus") {
                commands?.perform(.bookmarkAllTabs)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button(String(localized: "Abrir todos los marcadores en pestañas", bundle: #bundle), menuIcon: "rectangle.stack") {
                commands?.perform(.openAllBookmarksInTabs)
            }
            .disabled(PlacesProvider().customBookmarks().isEmpty)

            Button(String(localized: "Editar marcadores…", bundle: #bundle), menuIcon: "square.and.pencil") {
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
