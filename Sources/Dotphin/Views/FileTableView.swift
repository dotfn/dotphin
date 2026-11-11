import AppKit
import Quartz
import SwiftUI

/// Vista "Lista" sobre un `NSTableView` nativo (como el `NSOutlineView` de Finder).
///
/// Reemplaza al `List(selection:)` de SwiftUI, que en macOS no da arrastre
/// múltiple, convierte el arrastre desde una fila no seleccionada en selección
/// por recuadro y, después de la primera sesión de arrastre, aplica cada cambio
/// de selección recién con el clic siguiente (verificado con `DebugEventLog`;
/// ver docs/decisions.md). Acá AppKit maneja clic/⌘/⇧, el arrastre de toda la
/// selección y la validación de drop por fila, igual que Finder.
struct FileTableView: NSViewRepresentable {
    let items: [FileItem]
    let groups: [FileItemGroup]
    let showInGroups: Bool
    let zoomLevel: Double
    @Binding var selection: Set<FileItem.ID>
    let gitStatuses: [String: GitFileStatus]
    let directorySizeMode: DirectorySizeMode
    /// `nil` en resultados de búsqueda: soltar sobre el fondo no tiene destino.
    let currentURL: URL?
    let onOpen: (FileItem) -> Void
    let onMoveDropped: ([URL], URL) -> Void
    /// Menú contextual para los ítems clickeados; vacío = fondo de la lista.
    let menuForItems: ([FileItem]) -> NSMenu?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = FileNSTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.headerView = nil
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsTypeSelect = true
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let column = NSTableColumn(identifier: FileRowCellView.identifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

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
        // El coordinator vive todo el ciclo; hay que refrescarle los callbacks
        // y el binding en cada update o escribe sobre estado viejo (axiom-macos).
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
        var parent: FileTableView
        weak var tableView: FileNSTableView?

        private var rows: [Row] = []
        private var renderedGitStatuses: [String: GitFileStatus] = [:]
        private var renderedSizeMode: DirectorySizeMode?
        private var renderedZoom: Double?
        /// Evita reenviar a SwiftUI una selección que pusimos nosotros.
        private var isApplyingSelection = false

        enum Row: Equatable {
            case header(String)
            case item(FileItem)

            var item: FileItem? {
                if case .item(let item) = self { return item }
                return nil
            }
        }

        init(parent: FileTableView) {
            self.parent = parent
        }

        // MARK: SwiftUI → AppKit

        func apply(_ representable: FileTableView) {
            guard let tableView else { return }

            let newRows = Self.makeRows(from: representable)
            let rowHeight = max(20, 22 * representable.zoomLevel)
            if renderedZoom != representable.zoomLevel {
                renderedZoom = representable.zoomLevel
                tableView.rowHeight = rowHeight
            }

            let needsReload = newRows != rows
                || renderedGitStatuses != representable.gitStatuses
                || renderedSizeMode != representable.directorySizeMode
            // Recargar en medio de una edición en línea la cortaría: se pospone.
            if needsReload && tableView.isRenaming { return }
            if needsReload {
                rows = newRows
                renderedGitStatuses = representable.gitStatuses
                renderedSizeMode = representable.directorySizeMode
                isApplyingSelection = true
                tableView.reloadData()
                isApplyingSelection = false
            }

            applySelection(representable.selection)
        }

        private static func makeRows(from representable: FileTableView) -> [Row] {
            if representable.showInGroups && !representable.groups.isEmpty {
                return representable.groups.flatMap { group in
                    [Row.header("\(group.title) (\(group.items.count))")] + group.items.map(Row.item)
                }
            }
            return representable.items.map(Row.item)
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
            let ids = Set(tableView.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].item?.id : nil })
            DebugEventLog.log("selección", "Lista (NSTableView): \(DebugEventLog.names(ids))")
            if ids != parent.selection {
                parent.selection = ids
            }
        }

        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard rows.indices.contains(row), let item = rows[row].item else { return }
            DebugEventLog.log("lista", "doble clic en \(item.name)")
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
            let selectedIDs = Set(tableView.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].item?.id : nil })
            let targets = rows.compactMap(\.item).filter { selectedIDs.contains($0.id) }
            return parent.menuForItems(targets.isEmpty ? [item] : targets)
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
                let identifier = NSUserInterfaceItemIdentifier("FileTableHeader")
                let field = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField) ?? {
                    let label = NSTextField(labelWithString: "")
                    label.identifier = identifier
                    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
                    label.textColor = .secondaryLabelColor
                    return label
                }()
                field.stringValue = title
                return field
            case .item(let item):
                let cell = (tableView.makeView(withIdentifier: FileRowCellView.identifier, owner: nil) as? FileRowCellView)
                    ?? FileRowCellView()
                cell.configure(
                    with: item,
                    gitStatus: parent.gitStatuses[item.name],
                    zoomLevel: parent.zoomLevel,
                    directorySizeMode: parent.directorySizeMode
                )
                return cell
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
            let names = rowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].item?.url : nil }
            DebugEventLog.log("drag", "Lista (NSTableView): empieza arrastre de \(DebugEventLog.names(names))")
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            DebugEventLog.log("drag", "Lista (NSTableView): termina arrastre operación=\(operation.rawValue)")
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
                source: "Lista (NSTableView)",
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

// MARK: - NSTableView con menú por fila

final class FileNSTableView: NSTableView, FileViewResponder, QuickLookSourceProviding {
    var menuProvider: ((Int) -> NSMenu?)?
    /// Ítem de una fila (`nil` en encabezados de grupo); lo provee el coordinator.
    var itemAtRow: (Int) -> FileItem? = { _ in nil }
    /// Se llama al terminar una edición en línea (para aplicar recargas pospuestas).
    var onRenamingEnded: (() -> Void)?
    /// El arrastre salió de la tabla o terminó.
    var onDragLeft: (() -> Void)?
    private(set) var isRenaming = false
    private(set) var interaction = FileViewInteraction()
    private var isActivePane = true

    // MARK: Foco y panel activo

    func update(interaction: FileViewInteraction, isActivePane: Bool) {
        let becameActive = isActivePane && !self.isActivePane
        self.interaction = interaction
        self.isActivePane = isActivePane
        if becameActive {
            claimFocusIfIdle()
        }
        if let id = interaction.renamingItemID, !isRenaming {
            beginRenaming(id)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isActivePane {
            claimFocusIfIdle()
        }
    }

    /// Toma el foco de teclado solo si nadie lo tiene o lo tiene otra vista de
    /// archivos (el otro panel): nunca se lo saca a un campo de texto.
    private func claimFocusIfIdle() {
        guard let window, window.firstResponder !== self else { return }
        let current = window.firstResponder
        if current == nil || current === window || current is FileViewResponder {
            window.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            QuickLookPreviewController.shared.sourceProvider = self
            if !isActivePane {
                interaction.onActivate()
            }
        }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        if !isActivePane {
            interaction.onActivate()
        }
        super.mouseDown(with: event)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        super.draggingExited(sender)
        onDragLeft?()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        super.draggingEnded(sender)
        onDragLeft?()
    }

    // MARK: Teclado

    /// Espacio = Vista rápida, Intro = renombrar (como Finder). Flechas,
    /// ⇧+flechas, Av/Re Pág y búsqueda al tipear quedan en `NSTableView`.
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            switch event.keyCode {
            case 49: // Espacio
                interaction.onQuickLook()
                return
            case 36, 76: // Intro / Enter
                if !selectedRowIndexes.isEmpty {
                    interaction.onRequestRename()
                    return
                }
            case 53: // Esc
                if QuickLookPreviewController.shared.isVisible {
                    QuickLookPreviewController.shared.close()
                    return
                }
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    /// ⌘A sin los encabezados de grupo.
    override func selectAll(_ sender: Any?) {
        let indexes = IndexSet((0..<numberOfRows).filter { itemAtRow($0) != nil })
        selectRowIndexes(indexes, byExtendingSelection: false)
    }

    // MARK: Renombrar en línea

    private func beginRenaming(_ id: FileItem.ID) {
        guard window != nil,
              let row = (0..<numberOfRows).first(where: { itemAtRow($0)?.id == id })
        else { return }
        scrollRowToVisible(row)
        guard let cell = view(atColumn: 0, row: row, makeIfNecessary: true) as? FileRowCellView else { return }
        isRenaming = true
        cell.beginEditingName { [weak self] newName in
            guard let self else { return }
            self.isRenaming = false
            self.window?.makeFirstResponder(self)
            self.interaction.onEndRename(id, newName)
            self.onRenamingEnded?()
        }
    }

    // MARK: Quick Look

    func quickLookSourceFrame(for url: URL) -> NSRect? {
        let target = url.standardizedFileURL
        let visibleRows = rows(in: visibleRect)
        guard let window,
              let row = (visibleRows.location..<NSMaxRange(visibleRows)).first(where: {
                  itemAtRow($0)?.url.standardizedFileURL == target
              }),
              let cell = view(atColumn: 0, row: row, makeIfNecessary: false) as? FileRowCellView
        else { return nil }
        return window.convertToScreen(cell.convert(cell.iconRect, to: nil))
    }

    func quickLookForwardKeyDown(_ event: NSEvent) {
        super.keyDown(with: event)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        MainActor.assumeIsolated {
            QuickLookPreviewController.shared.beginControl(of: panel)
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        MainActor.assumeIsolated {
            QuickLookPreviewController.shared.endControl(of: panel)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return menuProvider?(row(at: point)) ?? super.menu(for: event)
    }

    /// Como la vista de lista de Finder: el arrastre de archivos solo empieza
    /// sobre el ícono o el nombre. Desde el resto de la fila (o desde las otras
    /// columnas) arrastrar extiende la selección fila por fila.
    override func canDragRows(with rowIndexes: IndexSet, at mouseDownPoint: NSPoint) -> Bool {
        let row = row(at: mouseDownPoint)
        let column = column(at: mouseDownPoint)
        guard row >= 0, column >= 0,
              let cell = view(atColumn: column, row: row, makeIfNecessary: false) as? FileRowCellView
        else { return false }
        return cell.dragHitRect.contains(convert(mouseDownPoint, to: cell))
    }
}

// MARK: - Celda

/// Celda de AppKit puro (sin `NSHostingView` por fila, que según axiom-macos
/// traba el scroll): ícono, nombre, etiqueta de color, git y tamaño.
final class FileRowCellView: NSTableCellView, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("FileRowCellView")

    /// Sangría + triángulo de expansión para la vista Detalles.
    struct Outline {
        let depth: Int
        /// `nil` = la fila no se expande (se reserva el hueco del triángulo).
        let isExpanded: Bool?
        let onToggle: () -> Void
    }

    private let disclosureButton = NSButton()
    private var onToggleDisclosure: (() -> Void)?
    private var leadingConstraint: NSLayoutConstraint?
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let colorTagDot = DotView()
    private let gitDot = DotView()
    private let sizeField = NSTextField(labelWithString: "")
    private var iconSizeConstraints: [NSLayoutConstraint] = []
    private var sizeTask: Task<Void, Never>?
    private var representedID: FileItem.ID?
    private var renameCompletion: ((String?) -> Void)?
    private var editingWidthConstraint: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        imageView = iconView
        textField = nameField

        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameField.font = .systemFont(ofSize: 13)
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sizeField.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        sizeField.textColor = .secondaryLabelColor
        sizeField.alignment = .right
        sizeField.setContentCompressionResistancePriority(.required, for: .horizontal)

        disclosureButton.isBordered = false
        disclosureButton.imagePosition = .imageOnly
        disclosureButton.contentTintColor = .secondaryLabelColor
        disclosureButton.target = self
        disclosureButton.action = #selector(toggleDisclosure)
        disclosureButton.isHidden = true

        let stack = NSStackView(views: [disclosureButton, iconView, nameField, colorTagDot, gitDot, NSView(), sizeField])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        iconSizeConstraints = [
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
        ]
        let leading = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        leadingConstraint = leading
        NSLayoutConstraint.activate(iconSizeConstraints + [
            leading,
            disclosureButton.widthAnchor.constraint(equalToConstant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            sizeField.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        sizeTask?.cancel()
        sizeTask = nil
        representedID = nil
    }

    /// Zona desde la que arranca un arrastre: ícono + texto del nombre (no el
    /// ancho completo del campo, que se estira hasta el borde de la columna).
    var dragHitRect: NSRect {
        layoutSubtreeIfNeeded()
        var nameRect = convert(nameField.bounds, from: nameField)
        nameRect.size.width = min(nameRect.width, nameField.attributedStringValue.size().width + 6)
        return convert(iconView.bounds, from: iconView).union(nameRect).insetBy(dx: -2, dy: -4)
    }

    var iconRect: NSRect {
        layoutSubtreeIfNeeded()
        return convert(iconView.bounds, from: iconView)
    }

    // MARK: Renombrar en línea

    /// Vuelve editable el nombre, con el nombre sin extensión seleccionado como
    /// en Finder. `completion` recibe el texto nuevo, o `nil` si se canceló (Esc).
    func beginEditingName(completion: @escaping (String?) -> Void) {
        renameCompletion = completion
        nameField.isEditable = true
        nameField.drawsBackground = true
        nameField.backgroundColor = .textBackgroundColor
        nameField.textColor = .labelColor
        nameField.lineBreakMode = .byClipping
        nameField.delegate = self
        let width = nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        width.priority = .defaultHigh
        width.isActive = true
        editingWidthConstraint = width
        layoutSubtreeIfNeeded()

        guard window?.makeFirstResponder(nameField) == true else {
            endEditingName(with: nil)
            return
        }
        let name = nameField.stringValue as NSString
        let stem = name.deletingPathExtension as NSString
        let stemLength = (stem.length > 0 && stem.length < name.length) ? stem.length : name.length
        nameField.currentEditor()?.selectedRange = NSRange(location: 0, length: stemLength)
    }

    private func endEditingName(with newName: String?) {
        guard let completion = renameCompletion else { return }
        renameCompletion = nil
        editingWidthConstraint?.isActive = false
        editingWidthConstraint = nil
        nameField.delegate = nil
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.drawsBackground = false
        nameField.lineBreakMode = .byTruncatingMiddle
        completion(newName)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Intro o clic afuera: confirmar, como Finder.
        endEditingName(with: nameField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        nameField.abortEditing()
        endEditingName(with: nil)
        return true
    }

    @objc private func toggleDisclosure() {
        onToggleDisclosure?()
    }

    func configure(
        with item: FileItem,
        gitStatus: GitFileStatus?,
        zoomLevel: Double,
        directorySizeMode: DirectorySizeMode,
        showsSize: Bool = true,
        outline: Outline? = nil
    ) {
        representedID = item.id

        leadingConstraint?.constant = 4 + CGFloat(outline?.depth ?? 0) * 16
        onToggleDisclosure = outline?.onToggle
        disclosureButton.isHidden = outline == nil
        if let outline {
            let symbol = outline.isExpanded.map { $0 ? "chevron.down" : "chevron.right" }
            disclosureButton.image = symbol.flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: outline.isExpanded == true ? "Contraer" : "Expandir")?
                    .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
            }
            disclosureButton.isEnabled = symbol != nil
        }
        let formatter = FileMetadataFormatter()

        let iconSide = CGFloat(max(16, 18 * zoomLevel))
        if iconSizeConstraints.first?.constant != iconSide {
            iconSizeConstraints.forEach { $0.constant = iconSide }
        }
        iconView.image = ThumbnailLoader.icon(for: item)
        nameField.stringValue = item.name
        alphaValue = item.isHiddenItem ? 0.58 : 1.0
        toolTip = formatter.hoverTooltip(for: item)

        if let color = item.colorTag.nsColor {
            colorTagDot.configure(color: color, diameter: 8, label: String(localized: "Etiqueta: \(item.colorTag.title)", bundle: #bundle))
        } else {
            colorTagDot.isHidden = true
        }
        if let gitStatus {
            gitDot.configure(color: Self.color(for: gitStatus), diameter: 6, label: gitStatus.accessibilityDescription)
        } else {
            gitDot.isHidden = true
        }

        sizeTask?.cancel()
        sizeField.isHidden = !showsSize
        guard showsSize else { return }
        if let cached = formatter.cachedSizeDisplayText(for: item, directorySizeMode: directorySizeMode) {
            sizeField.stringValue = cached
        } else {
            // Contar/sumar una carpeta va en segundo plano (ver DirectorySizeText).
            sizeField.stringValue = "…"
            sizeTask = Task { [weak self] in
                let text = await formatter.computedSizeDisplayText(for: item, directorySizeMode: directorySizeMode)
                guard !Task.isCancelled, let self, self.representedID == item.id else { return }
                self.sizeField.stringValue = text
            }
        }
    }

    private static func color(for status: GitFileStatus) -> NSColor {
        switch status {
        case .modified: return .systemOrange
        case .added: return .systemGreen
        case .deleted: return .systemRed
        case .untracked: return .systemGray
        case .renamed: return .systemBlue
        }
    }
}

/// Punto de color (etiqueta de Finder / estado de git) con etiqueta de accesibilidad.
final class DotView: NSView {
    private var color: NSColor = .clear
    private var diameter: CGFloat = 6

    override var intrinsicContentSize: NSSize {
        NSSize(width: diameter, height: diameter)
    }

    func configure(color: NSColor, diameter: CGFloat, label: String) {
        isHidden = false
        self.color = color
        if self.diameter != diameter {
            self.diameter = diameter
            invalidateIntrinsicContentSize()
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(label)
        toolTip = label
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        let side = min(bounds.width, bounds.height, diameter)
        let rect = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        NSBezierPath(ovalIn: rect).fill()
    }
}
