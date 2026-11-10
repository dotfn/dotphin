import AppKit
import SwiftUI

/// Fila ya aplanada de la vista "Detalles": encabezado de grupo o ítem con su
/// nivel de sangría (las carpetas expandidas insertan a sus hijos debajo).
enum DetailsTableRow: Equatable {
    case header(String)
    case item(FileItem, depth: Int, isExpanded: Bool)

    var item: FileItem? {
        if case .item(let item, _, _) = self { return item }
        return nil
    }
}

/// Vista "Detalles" sobre un `NSTableView` nativo de varias columnas.
///
/// Reemplaza al `Table` de SwiftUI por lo mismo que `FileTableView` reemplazó
/// al `List`: con `.draggable` en la celda, el clic sobre el nombre no
/// seleccionaba de inmediato y no había arrastre de toda la selección. Acá
/// selección, arrastre y drop son los de AppKit, como en Finder.
struct DetailsTableView: NSViewRepresentable {
    let rows: [DetailsTableRow]
    let visibleColumns: [DetailsColumn]
    let zoomLevel: Double
    @Binding var selection: Set<FileItem.ID>
    let gitStatuses: [String: GitFileStatus]
    let expandableFolders: Bool
    let directorySizeMode: DirectorySizeMode
    let useRelativeDates: Bool
    let permissionsFormat: PermissionsDisplayFormat
    let currentURL: URL
    let sortField: SortField
    let ascending: Bool
    let onChangeSort: ((SortField, Bool) -> Void)?
    /// Clic derecho en el encabezado: mostrar u ocultar una columna.
    let onToggleColumn: ((DetailsColumn) -> Void)?
    let onOpen: (FileItem) -> Void
    let onToggleExpansion: (URL) -> Void
    let onMoveDropped: ([URL], URL) -> Void
    /// Menú contextual para los ítems clickeados; vacío = fondo de la tabla.
    let menuForItems: ([FileItem]) -> NSMenu?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = FileNSTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsTypeSelect = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let nameColumn = NSTableColumn(identifier: Coordinator.nameColumnID)
        nameColumn.title = "Nombre"
        nameColumn.minWidth = 160
        nameColumn.width = 320
        nameColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: SortField.name.rawValue, ascending: true)
        tableView.addTableColumn(nameColumn)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.menuProvider = { [weak coordinator = context.coordinator] row in
            coordinator?.menu(forClickedRow: row)
        }

        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.move, .copy, .generic], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy, .generic], forLocal: false)
        tableView.draggingDestinationFeedbackStyle = .regular

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        context.coordinator.tableView = tableView
        tableView.itemAtRow = { [weak coordinator = context.coordinator] row in
            coordinator?.item(at: row)
        }
        tableView.onDragLeft = { [weak coordinator = context.coordinator] in
            coordinator?.dragLeft()
        }
        tableView.onRenamingEnded = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return }
            coordinator.apply(coordinator.parent)
        }
        context.coordinator.apply(self)
        tableView.update(
            interaction: context.environment.fileViewInteraction,
            isActivePane: context.environment.isActiveBrowserPane
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Igual que en FileTableView: refrescar callbacks y binding en cada update.
        context.coordinator.parent = self
        context.coordinator.apply(self)
        context.coordinator.tableView?.update(
            interaction: context.environment.fileViewInteraction,
            isActivePane: context.environment.isActiveBrowserPane
        )
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let nameColumnID = NSUserInterfaceItemIdentifier("name")

        var parent: DetailsTableView
        weak var tableView: FileNSTableView?

        private var rows: [DetailsTableRow] = []
        private var renderedColumns: [DetailsColumn]?
        private var renderedAppearance: Appearance?
        /// Evita reenviar a SwiftUI una selección / un orden que pusimos nosotros.
        private var isApplyingSelection = false
        private var isApplyingSort = false

        /// Todo lo que, al cambiar, obliga a redibujar las celdas.
        private struct Appearance: Equatable {
            let zoomLevel: Double
            let gitStatuses: [String: GitFileStatus]
            let expandableFolders: Bool
            let directorySizeMode: DirectorySizeMode
            let useRelativeDates: Bool
            let permissionsFormat: PermissionsDisplayFormat
        }

        init(parent: DetailsTableView) {
            self.parent = parent
        }

        // MARK: SwiftUI → AppKit

        func apply(_ representable: DetailsTableView) {
            guard let tableView else { return }

            if renderedColumns != representable.visibleColumns {
                renderedColumns = representable.visibleColumns
                rebuildColumns(representable.visibleColumns, in: tableView)
            }

            let appearance = Appearance(
                zoomLevel: representable.zoomLevel,
                gitStatuses: representable.gitStatuses,
                expandableFolders: representable.expandableFolders,
                directorySizeMode: representable.directorySizeMode,
                useRelativeDates: representable.useRelativeDates,
                permissionsFormat: representable.permissionsFormat
            )
            if renderedAppearance?.zoomLevel != appearance.zoomLevel {
                tableView.rowHeight = max(22, 24 * min(1.35, appearance.zoomLevel))
            }

            let needsReload = rows != representable.rows || renderedAppearance != appearance
            // Recargar en medio de una edición en línea la cortaría: se pospone.
            if needsReload && tableView.isRenaming { return }
            if needsReload {
                rows = representable.rows
                renderedAppearance = appearance
                isApplyingSelection = true
                tableView.reloadData()
                isApplyingSelection = false
            }

            applySort(field: representable.sortField, ascending: representable.ascending)
            applySelection(representable.selection)
        }

        private func rebuildColumns(_ columns: [DetailsColumn], in tableView: NSTableView) {
            for column in tableView.tableColumns where column.identifier != Self.nameColumnID {
                tableView.removeTableColumn(column)
            }
            for detailsColumn in columns {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(detailsColumn.rawValue))
                column.title = detailsColumn.title
                let (minWidth, ideal, maxWidth) = Self.widths(for: detailsColumn)
                column.minWidth = minWidth
                column.width = ideal
                column.maxWidth = maxWidth
                column.resizingMask = .userResizingMask
                if let field = Self.sortField(for: detailsColumn) {
                    column.sortDescriptorPrototype = NSSortDescriptor(key: field.rawValue, ascending: true)
                }
                tableView.addTableColumn(column)
            }
            tableView.sizeToFit()
            tableView.headerView?.menu = makeColumnsMenu(visible: columns)

            // Anchos de columna recordados por AppKit entre sesiones. Hay que
            // reactivarlo cada vez que se rearman las columnas para que
            // vuelva a aplicar lo guardado; el orden lo sigue mandando el modelo.
            isApplyingSort = true
            tableView.autosaveName = Self.columnsAutosaveName
            tableView.autosaveTableColumns = false
            tableView.autosaveTableColumns = true
            isApplyingSort = false
        }

        static let columnsAutosaveName = "Dotphin.DetailsColumns"

        /// Menú del encabezado, como en Finder y Dolphin: una entrada por columna opcional.
        private func makeColumnsMenu(visible: [DetailsColumn]) -> NSMenu {
            let menu = NSMenu(title: "Columnas")
            for column in DetailsColumn.allCases {
                let item = NSMenuItem(title: column.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = column.rawValue
                item.state = visible.contains(column) ? .on : .off
                menu.addItem(item)
            }
            return menu
        }

        @objc private func toggleColumn(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? String,
                  let column = DetailsColumn(rawValue: rawValue) else { return }
            parent.onToggleColumn?(column)
        }

        private static func widths(for column: DetailsColumn) -> (CGFloat, CGFloat, CGFloat) {
            switch column {
            case .type: return (64, 95, 140)
            case .extensionType: return (58, 78, 110)
            case .size: return (62, 86, 125)
            case .modificationDate, .creationDate: return (100, 160, 210)
            case .permissions: return (74, 108, 145)
            case .tags: return (68, 95, 135)
            }
        }

        private static func sortField(for column: DetailsColumn) -> SortField? {
            switch column {
            case .type: return .type
            case .extensionType: return .extensionType
            case .size: return .size
            case .modificationDate: return .modificationDate
            case .creationDate: return .creationDate
            case .permissions, .tags: return nil
            }
        }

        private func applySort(field: SortField, ascending: Bool) {
            guard let tableView else { return }
            let current = tableView.sortDescriptors.first
            guard current?.key != field.rawValue || current?.ascending != ascending else { return }
            isApplyingSort = true
            tableView.sortDescriptors = [NSSortDescriptor(key: field.rawValue, ascending: ascending)]
            isApplyingSort = false
        }

        private func applySelection(_ selection: Set<FileItem.ID>) {
            guard let tableView else { return }
            let desired = IndexSet(rows.indices.filter { index in
                guard let item = rows[index].item else { return false }
                return selection.contains(item.id)
            })
            guard desired != tableView.selectedRowIndexes else { return }
            isApplyingSelection = true
            tableView.selectRowIndexes(desired, byExtendingSelection: false)
            isApplyingSelection = false
            if desired.count == 1, let row = desired.first {
                tableView.scrollRowToVisible(row)
            }
        }

        // MARK: AppKit → SwiftUI

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let tableView else { return }
            let ids = selectedIDs(in: tableView)
            DebugEventLog.log("selección", "Detalles (NSTableView): \(DebugEventLog.names(ids))")
            if ids != parent.selection {
                parent.selection = ids
            }
        }

        /// Clic en un encabezado de columna: ordena por ese campo (o invierte).
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isApplyingSort,
                  let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key,
                  let field = SortField(rawValue: key)
            else { return }
            parent.onChangeSort?(field, descriptor.ascending)
        }

        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard rows.indices.contains(row), let item = rows[row].item else { return }
            DebugEventLog.log("detalles", "doble clic en \(item.name)")
            parent.onOpen(item)
        }

        /// Clic derecho: como Finder, si la fila no estaba seleccionada pasa a
        /// ser la selección antes de armar el menú.
        func menu(forClickedRow row: Int) -> NSMenu? {
            guard let tableView else { return nil }
            guard rows.indices.contains(row), let item = rows[row].item else {
                return parent.menuForItems([])
            }
            if !tableView.selectedRowIndexes.contains(row) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            let ids = selectedIDs(in: tableView)
            let targets = rows.compactMap(\.item).filter { ids.contains($0.id) }
            return parent.menuForItems(targets.isEmpty ? [item] : targets)
        }

        private func selectedIDs(in tableView: NSTableView) -> Set<FileItem.ID> {
            Set(tableView.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].item?.id : nil })
        }

        // MARK: Data source / delegate

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func item(at row: Int) -> FileItem? {
            rows.indices.contains(row) ? rows[row].item : nil
        }

        /// Búsqueda al tipear nativa de `NSTableView` (`allowsTypeSelect`).
        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            item(at: row)?.name
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            if case .header = rows[row] { return true }
            return false
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            rows[row].item != nil
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            switch rows[row] {
            case .header(let title):
                let identifier = NSUserInterfaceItemIdentifier("DetailsTableHeader")
                let field = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField) ?? {
                    let label = NSTextField(labelWithString: "")
                    label.identifier = identifier
                    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
                    label.textColor = .secondaryLabelColor
                    return label
                }()
                field.stringValue = title
                return field

            case .item(let item, let depth, let isExpanded):
                guard let tableColumn else { return nil }
                if tableColumn.identifier == Self.nameColumnID {
                    let cell = (tableView.makeView(withIdentifier: FileRowCellView.identifier, owner: nil) as? FileRowCellView)
                        ?? FileRowCellView()
                    let url = item.url
                    cell.configure(
                        with: item,
                        gitStatus: parent.gitStatuses[item.name],
                        zoomLevel: min(1.35, parent.zoomLevel),
                        directorySizeMode: parent.directorySizeMode,
                        showsSize: false,
                        outline: parent.expandableFolders
                            ? FileRowCellView.Outline(
                                depth: depth,
                                isExpanded: item.isDirectory ? isExpanded : nil,
                                onToggle: { [weak self] in self?.parent.onToggleExpansion(url) }
                            )
                            : nil
                    )
                    return cell
                }

                guard let column = DetailsColumn(rawValue: tableColumn.identifier.rawValue) else { return nil }
                let cell = (tableView.makeView(withIdentifier: DetailsTextCellView.identifier, owner: nil) as? DetailsTextCellView)
                    ?? DetailsTextCellView()
                configure(cell, column: column, item: item)
                return cell
            }
        }

        private func configure(_ cell: DetailsTextCellView, column: DetailsColumn, item: FileItem) {
            let formatter = FileMetadataFormatter()
            switch column {
            case .type:
                cell.setText(formatter.metadata(for: item).kind)
            case .extensionType:
                cell.setText(item.fileExtension.isEmpty ? "—" : item.fileExtension)
            case .size:
                let mode = parent.directorySizeMode
                if let cached = formatter.cachedSizeDisplayText(for: item, directorySizeMode: mode) {
                    cell.setText(cached, digits: true)
                } else {
                    // Contar/sumar una carpeta va en segundo plano (ver DirectorySizeText).
                    cell.setText("…", digits: true) {
                        await formatter.computedSizeDisplayText(for: item, directorySizeMode: mode)
                    }
                }
            case .modificationDate:
                cell.setText(formatter.formatDate(item.modificationDate, useRelativeDates: parent.useRelativeDates), digits: true)
            case .creationDate:
                cell.setText(formatter.formatDate(item.creationDate, useRelativeDates: parent.useRelativeDates), digits: true)
            case .permissions:
                cell.setText(formatter.permissionsDisplayText(for: item, format: parent.permissionsFormat), monospaced: true)
            case .tags:
                if item.colorTag != .none, let color = item.colorTag.nsColor {
                    let text = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: color])
                    text.append(NSAttributedString(
                        string: item.colorTag.title,
                        attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                    ))
                    cell.setAttributedText(text)
                } else {
                    cell.setText("—")
                }
            }
        }

        // MARK: Arrastrar (origen)

        /// Una fila → un `NSURL`. Si se arrastra una fila seleccionada, AppKit
        /// pide un writer por cada fila de la selección: viaja todo, como Finder.
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard rows.indices.contains(row), let item = rows[row].item else { return nil }
            return item.url as NSURL
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
            let urls = rowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].item?.url : nil }
            DebugEventLog.log("drag", "Detalles (NSTableView): empieza arrastre de \(DebugEventLog.names(urls))")
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            DebugEventLog.log("drag", "Detalles (NSTableView): termina arrastre operación=\(operation.rawValue)")
        }

        // MARK: Soltar (destino)

        private let drops = FileDropController()

        /// Carpeta bajo el cursor cuando el drop es "sobre" una fila.
        private func dropFolder(row: Int, dropOperation: NSTableView.DropOperation) -> FileItem? {
            guard dropOperation == .on, let item = item(at: row), item.isDirectory else { return nil }
            return item
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: any NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            let proposal = drops.validate(
                info,
                folder: dropFolder(row: row, dropOperation: dropOperation),
                currentURL: parent.currentURL,
                onSpringOpen: { [weak self] folder in self?.parent.onOpen(folder) }
            )
            guard let proposal else { return [] }
            if case .currentDirectory = proposal.target {
                // Resalta toda la tabla: cae en la carpeta que se está mostrando.
                tableView.setDropRow(-1, dropOperation: .on)
            }
            return proposal.operation
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: any NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            drops.accept(
                info,
                folder: row >= 0 ? dropFolder(row: row, dropOperation: dropOperation) : nil,
                currentURL: parent.currentURL,
                source: "Detalles (NSTableView)",
                onMove: parent.onMoveDropped,
                onCopy: { urls, destination in self.tableView?.interaction.onCopyDropped(urls, destination) }
            )
        }

        /// El arrastre salió de la tabla o terminó: se desarma el resorte.
        func dragLeft() {
            drops.springLoading.cancel()
        }
    }
}

// MARK: - Celda de texto

/// Celda de las columnas secundarias (tipo, tamaño, fechas, permisos, etiquetas).
final class DetailsTextCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("DetailsTextCellView")

    private let label = NSTextField(labelWithString: "")
    private var textTask: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        textField = label
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        textTask?.cancel()
        textTask = nil
    }

    /// `pending`: valor que se calcula en segundo plano y reemplaza al texto.
    func setText(
        _ text: String,
        digits: Bool = false,
        monospaced: Bool = false,
        pending: (@Sendable () async -> String)? = nil
    ) {
        textTask?.cancel()
        textTask = nil
        if monospaced {
            label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        } else if digits {
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        } else {
            label.font = .systemFont(ofSize: 13)
        }
        label.textColor = .secondaryLabelColor
        label.stringValue = text
        guard let pending else { return }
        textTask = Task { [weak self] in
            let value = await pending()
            guard !Task.isCancelled else { return }
            self?.label.stringValue = value
        }
    }

    func setAttributedText(_ text: NSAttributedString) {
        textTask?.cancel()
        textTask = nil
        label.font = .systemFont(ofSize: 13)
        label.attributedStringValue = text
    }
}
