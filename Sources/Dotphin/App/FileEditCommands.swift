import AppKit
import SwiftUI

extension Notification.Name {
    static let renameSelectedFiles = Notification.Name("Dotphin.renameSelectedFiles")
    static let createNewFolderShortcut = Notification.Name("Dotphin.createNewFolderShortcut")
    static let moveToNewFolderShortcut = Notification.Name("Dotphin.moveToNewFolderShortcut")
    static let selectByPatternShortcut = Notification.Name("Dotphin.selectByPatternShortcut")
    static let deleteSelectedFilesShortcut = Notification.Name("Dotphin.deleteSelectedFilesShortcut")
    static let permanentDeleteSelectedFilesShortcut = Notification.Name("Dotphin.permanentDeleteSelectedFilesShortcut")
    static let quickLookSelectedFilesShortcut = Notification.Name("Dotphin.quickLookSelectedFilesShortcut")
    static let showPropertiesShortcut = Notification.Name("Dotphin.showPropertiesShortcut")
    static let showViewPropertiesDialogShortcut = Notification.Name("Dotphin.showViewPropertiesDialogShortcut")
    static let showDiskUsageAnalyzerShortcut = Notification.Name("Dotphin.showDiskUsageAnalyzerShortcut")
    static let addTabShortcut = Notification.Name("Dotphin.addTabShortcut")
    static let duplicateTabShortcut = Notification.Name("Dotphin.duplicateTabShortcut")
    static let closeTabShortcut = Notification.Name("Dotphin.closeTabShortcut")
    static let closeOtherTabsShortcut = Notification.Name("Dotphin.closeOtherTabsShortcut")
    static let reopenClosedTabShortcut = Notification.Name("Dotphin.reopenClosedTabShortcut")
    static let selectNextTabShortcut = Notification.Name("Dotphin.selectNextTabShortcut")
    static let selectPrevTabShortcut = Notification.Name("Dotphin.selectPrevTabShortcut")
    static let toggleSplitShortcut = Notification.Name("Dotphin.toggleSplitShortcut")
    static let focusOtherSplitPaneShortcut = Notification.Name("Dotphin.focusOtherSplitPaneShortcut")
    static let moveSplitToTabsShortcut = Notification.Name("Dotphin.moveSplitToTabsShortcut")
    static let swapSplitPanesShortcut = Notification.Name("Dotphin.swapSplitPanesShortcut")
    static let copyToOtherSplitPaneShortcut = Notification.Name("Dotphin.copyToOtherSplitPaneShortcut")
    static let moveToOtherSplitPaneShortcut = Notification.Name("Dotphin.moveToOtherSplitPaneShortcut")
    static let compareFilesShortcut = Notification.Name("Dotphin.compareFilesShortcut")
    static let toggleInfoPanelShortcut = Notification.Name("Dotphin.toggleInfoPanelShortcut")
    static let toggleFilterBarShortcut = Notification.Name("Dotphin.toggleFilterBarShortcut")
    static let toggleEmbeddedTerminalShortcut = Notification.Name("Dotphin.toggleEmbeddedTerminalShortcut")
    static let openTerminalShortcut = Notification.Name("Dotphin.openTerminalShortcut")
    static let bookmarkAllTabsShortcut = Notification.Name("Dotphin.bookmarkAllTabsShortcut")
    static let editBookmarksShortcut = Notification.Name("Dotphin.editBookmarksShortcut")
    static let openAllBookmarksInTabsShortcut = Notification.Name("Dotphin.openAllBookmarksInTabsShortcut")
}

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

    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    private static func fKey(_ code: Int) -> KeyEquivalent {
        KeyEquivalent(Character(UnicodeScalar(code)!))
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nueva pestaña") {
                NotificationCenter.default.post(name: .addTabShortcut, object: nil)
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Duplicar pestaña actual") {
                NotificationCenter.default.post(name: .duplicateTabShortcut, object: nil)
            }

            Button("Reabrir pestaña cerrada") {
                NotificationCenter.default.post(name: .reopenClosedTabShortcut, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("Nueva carpeta…") {
                NotificationCenter.default.post(name: .createNewFolderShortcut, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Mover selección a carpeta nueva…") {
                NotificationCenter.default.post(name: .moveToNewFolderShortcut, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .control])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Crear enlace simbólico aquí") {
                viewModel?.createSymbolicLinkToSelected()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Cerrar pestaña") {
                NotificationCenter.default.post(name: .closeTabShortcut, object: nil)
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("Cerrar otras pestañas") {
                NotificationCenter.default.post(name: .closeOtherTabsShortcut, object: nil)
            }

            Divider()

            Button("Vista rápida") {
                NotificationCenter.default.post(name: .quickLookSelectedFilesShortcut, object: nil)
            }
            .keyboardShortcut("y", modifiers: .command)
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Comparar archivos seleccionados…") {
                NotificationCenter.default.post(name: .compareFilesShortcut, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Button("Propiedades…") {
                NotificationCenter.default.post(name: .showPropertiesShortcut, object: nil)
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        CommandGroup(replacing: .undoRedo) {
            Button(isEditingText ? "Deshacer" : (viewModel?.history.undoMenuTitle ?? "Deshacer")) {
                if isEditingText {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                } else {
                    viewModel?.undo()
                }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!isEditingText && !(viewModel?.canUndo ?? false))

            Button(isEditingText ? "Rehacer" : (viewModel?.history.redoMenuTitle ?? "Rehacer")) {
                if isEditingText {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                } else {
                    viewModel?.redo()
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!isEditingText && !(viewModel?.canRedo ?? false))
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cortar") {
                if isEditingText {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                } else {
                    viewModel?.cutSelected()
                }
            }
            .keyboardShortcut("x", modifiers: .command)
            Button("Copiar") {
                if isEditingText {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                } else {
                    viewModel?.copySelected()
                }
            }
            .keyboardShortcut("c", modifiers: .command)
            Button("Pegar") {
                if isEditingText {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                } else {
                    viewModel?.paste()
                }
            }
            .keyboardShortcut("v", modifiers: .command)
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
                NotificationCenter.default.post(name: .copyToOtherSplitPaneShortcut, object: nil)
            }
            .keyboardShortcut(Self.fKey(NSF5FunctionKey), modifiers: [.shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Mover al otro panel dividido") {
                NotificationCenter.default.post(name: .moveToOtherSplitPaneShortcut, object: nil)
            }
            .keyboardShortcut(Self.fKey(NSF6FunctionKey), modifiers: [.shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Divider()

            Button((viewModel?.isSelectionModeActive ?? false) ? "Salir del modo de selección" : "Modo de selección") {
                viewModel?.isSelectionModeActive.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Seleccionar todo") {
                if isEditingText {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                } else {
                    viewModel?.selectAll()
                }
            }
            .keyboardShortcut("a", modifiers: .command)

            Button("Deseleccionar todo") {
                viewModel?.deselectAll()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Seleccionar ítems por patrón…") {
                NotificationCenter.default.post(name: .selectByPatternShortcut, object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Invertir selección") {
                viewModel?.invertSelection()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Divider()

            Button("Renombrar…") {
                NotificationCenter.default.post(name: .renameSelectedFiles, object: nil)
            }
            .keyboardShortcut(Self.fKey(NSF2FunctionKey), modifiers: [])
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Mover a la Papelera") {
                NotificationCenter.default.post(name: .deleteSelectedFilesShortcut, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel?.selectedIDs.isEmpty ?? true)

            Button("Eliminar permanentemente…") {
                NotificationCenter.default.post(name: .permanentDeleteSelectedFilesShortcut, object: nil)
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
                NotificationCenter.default.post(name: .showViewPropertiesDialogShortcut, object: nil)
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
                NotificationCenter.default.post(name: .toggleSplitShortcut, object: nil)
            }
            .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [])

            Button("Enfocar el otro panel dividido") {
                NotificationCenter.default.post(name: .focusOtherSplitPaneShortcut, object: nil)
            }
            .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [.control])

            Button("Separar vista dividida en pestañas") {
                NotificationCenter.default.post(name: .moveSplitToTabsShortcut, object: nil)
            }
            .keyboardShortcut(Self.fKey(NSF3FunctionKey), modifiers: [.control, .shift])

            Button("Intercambiar paneles divididos") {
                NotificationCenter.default.post(name: .swapSplitPanesShortcut, object: nil)
            }

            Divider()

            Button("Panel de información") {
                NotificationCenter.default.post(name: .toggleInfoPanelShortcut, object: nil)
            }
            .keyboardShortcut(Self.fKey(NSF11FunctionKey), modifiers: [])

            Button((viewModel?.isFilterBarVisible ?? false) ? "Barra de filtro ✓" : "Barra de filtro") {
                NotificationCenter.default.post(name: .toggleFilterBarShortcut, object: nil)
            }
            .keyboardShortcut("/", modifiers: [.command])

            Button("Panel de Terminal integrada") {
                NotificationCenter.default.post(name: .toggleEmbeddedTerminalShortcut, object: nil)
            }
            .keyboardShortcut(Self.fKey(NSF4FunctionKey), modifiers: [])

            Button("Abrir Terminal externa aquí") {
                NotificationCenter.default.post(name: .openTerminalShortcut, object: nil)
            }
            .keyboardShortcut(Self.fKey(NSF4FunctionKey), modifiers: [.shift])

            Divider()

            Button("Estadísticas de uso de disco…") {
                NotificationCenter.default.post(name: .showDiskUsageAnalyzerShortcut, object: nil)
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
                NotificationCenter.default.post(name: .editLocationBar, object: nil)
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
                NotificationCenter.default.post(name: .selectNextTabShortcut, object: nil)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Pestaña anterior") {
                NotificationCenter.default.post(name: .selectPrevTabShortcut, object: nil)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Button("Reabrir última pestaña cerrada") {
                NotificationCenter.default.post(name: .reopenClosedTabShortcut, object: nil)
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
                NotificationCenter.default.post(name: .bookmarkAllTabsShortcut, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Abrir todos los marcadores en pestañas") {
                NotificationCenter.default.post(name: .openAllBookmarksInTabsShortcut, object: nil)
            }
            .disabled(PlacesProvider().customBookmarks().isEmpty)

            Button("Editar marcadores…") {
                NotificationCenter.default.post(name: .editBookmarksShortcut, object: nil)
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
