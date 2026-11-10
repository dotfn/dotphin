import AppKit
import Quartz
import SwiftUI

enum FileGridStyle {
    case icons
    case compact
}

/// Vistas "Iconos" y "Compacta". La grilla es `FileCollectionView`
/// (`NSCollectionView` nativo); acá solo se arman los menús contextuales.
struct FileGridView: View {
    let style: FileGridStyle
    let items: [FileItem]
    var groups: [FileItemGroup] = []
    var showInGroups: Bool = false
    var showPreviews: Bool = true
    var isSelectionModeActive: Bool = false
    let zoomLevel: Double
    @Binding var selection: Set<FileItem.ID>
    let gitStatuses: [String: GitFileStatus]
    let currentURL: URL
    let onOpen: (FileItem) -> Void
    var onRename: ((FileItem) -> Void)? = nil
    var onBatchRename: (() -> Void)? = nil
    let onDelete: (FileItem) -> Void
    let onDeleteSelection: () -> Void
    let onMoveDropped: ([URL], URL) -> Void
    var contextMenuActions: BrowserContextMenuActions? = nil

    private var sections: [FileCollectionView.Section] {
        if showInGroups && !groups.isEmpty {
            return groups.map { FileCollectionView.Section(title: $0.title, items: $0.items) }
        }
        return [FileCollectionView.Section(title: nil, items: items)]
    }

    var body: some View {
        FileCollectionView(
            style: style,
            sections: sections,
            showPreviews: showPreviews,
            isSelectionModeActive: isSelectionModeActive,
            zoomLevel: zoomLevel,
            selection: $selection,
            gitStatuses: gitStatuses,
            currentURL: currentURL,
            onOpen: onOpen,
            onMoveDropped: onMoveDropped,
            menuForItems: { targetItems in
                makeFileItemsMenu(
                    for: targetItems,
                    actions: contextMenuActions,
                    onRename: onRename,
                    onBatchRename: onBatchRename,
                    onDelete: onDelete,
                    onDeleteSelection: onDeleteSelection
                )
            }
        )
    }
}

/// Grilla de archivos sobre `NSCollectionView`, como la vista de íconos de
/// Finder: recuadro de selección desde el fondo, clic/⌘/⇧, flechas en 2D,
/// arrastre de toda la selección y drop sobre carpetas, todo de AppKit.
///
/// Las celdas reutilizan las vistas SwiftUI existentes (`IconGridCell`,
/// `CompactGridCell`) dentro de un `NSHostingView` que se crea una vez por
/// celda y después solo cambia su `rootView` (axiom-macos, appkit-interop).
struct FileCollectionView: NSViewRepresentable {
    struct Section: Equatable {
        let title: String?
        let items: [FileItem]
    }

    let style: FileGridStyle
    let sections: [Section]
    let showPreviews: Bool
    let isSelectionModeActive: Bool
    let zoomLevel: Double
    @Binding var selection: Set<FileItem.ID>
    let gitStatuses: [String: GitFileStatus]
    let currentURL: URL
    let onOpen: (FileItem) -> Void
    let onMoveDropped: ([URL], URL) -> Void
    /// Menú contextual para los ítems clickeados; vacío = fondo de la grilla.
    let menuForItems: ([FileItem]) -> NSMenu?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = FileGridFlowLayout()
        layout.sectionHeadersPinToVisibleBounds = true

        let collectionView = FileNSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(FileGridItem.self, forItemWithIdentifier: FileGridItem.identifier)
        collectionView.register(
            FileGridHeaderView.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: FileGridHeaderView.identifier
        )
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator

        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask([.move, .copy, .generic], forLocal: true)
        collectionView.setDraggingSourceOperationMask([.copy, .generic], forLocal: false)

        let coordinator = context.coordinator
        collectionView.itemAtIndexPath = { [weak coordinator] in coordinator?.item(at: $0) }
        collectionView.indexPathForID = { [weak coordinator] in coordinator?.indexPath(for: $0) }
        collectionView.menuProvider = { [weak coordinator] in coordinator?.menu(forClickedIndexPath: $0) }
        collectionView.onOpenItem = { [weak coordinator] in coordinator?.open(at: $0) }
        collectionView.onUserChangedSelection = { [weak coordinator] in coordinator?.pushSelection() }
        collectionView.onRenamingEnded = { [weak coordinator] in
            guard let coordinator else { return }
            coordinator.apply(coordinator.parent)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        coordinator.collectionView = collectionView
        coordinator.apply(self)
        collectionView.update(
            interaction: context.environment.fileViewInteraction,
            isActivePane: context.environment.isActiveBrowserPane
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(self)
        context.coordinator.collectionView?.update(
            interaction: context.environment.fileViewInteraction,
            isActivePane: context.environment.isActiveBrowserPane
        )
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        var parent: FileCollectionView
        weak var collectionView: FileNSCollectionView?

        private var sections: [Section] = []
        private var renderedAppearance: Appearance?
        /// Evita reenviar a SwiftUI una selección que pusimos nosotros.
        private var isApplyingSelection = false

        /// Todo lo que, al cambiar, obliga a redibujar las celdas.
        private struct Appearance: Equatable {
            let style: FileGridStyle
            let zoomLevel: Double
            let showPreviews: Bool
            let isSelectionModeActive: Bool
            let gitStatuses: [String: GitFileStatus]
        }

        init(parent: FileCollectionView) {
            self.parent = parent
        }

        func item(at indexPath: IndexPath) -> FileItem? {
            guard sections.indices.contains(indexPath.section),
                  sections[indexPath.section].items.indices.contains(indexPath.item)
            else { return nil }
            return sections[indexPath.section].items[indexPath.item]
        }

        func indexPath(for id: FileItem.ID) -> IndexPath? {
            for (sectionIndex, section) in sections.enumerated() {
                if let itemIndex = section.items.firstIndex(where: { $0.id == id }) {
                    return IndexPath(item: itemIndex, section: sectionIndex)
                }
            }
            return nil
        }

        // MARK: SwiftUI → AppKit

        func apply(_ representable: FileCollectionView) {
            guard let collectionView else { return }
            let appearance = Appearance(
                style: representable.style,
                zoomLevel: representable.zoomLevel,
                showPreviews: representable.showPreviews,
                isSelectionModeActive: representable.isSelectionModeActive,
                gitStatuses: representable.gitStatuses
            )
            let needsReload = sections != representable.sections || renderedAppearance != appearance
            // Recargar en medio de una edición en línea la cortaría: se pospone.
            if needsReload && collectionView.isRenaming { return }

            collectionView.isSelectionModeActive = representable.isSelectionModeActive
            collectionView.metrics = FileGridMetrics(style: representable.style, zoomLevel: representable.zoomLevel)
            if needsReload {
                let metricsChanged = renderedAppearance?.style != appearance.style
                    || renderedAppearance?.zoomLevel != appearance.zoomLevel
                sections = representable.sections
                renderedAppearance = appearance
                if metricsChanged, let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
                    let metrics = collectionView.metrics
                    layout.minimumInteritemSpacing = metrics.interitemSpacing
                    layout.minimumLineSpacing = metrics.lineSpacing
                    layout.sectionInset = NSEdgeInsets(
                        top: metrics.inset, left: metrics.inset, bottom: metrics.inset, right: metrics.inset
                    )
                }
                isApplyingSelection = true
                collectionView.reloadData()
                isApplyingSelection = false
            }
            applySelection(representable.selection)
        }

        private func applySelection(_ selection: Set<FileItem.ID>) {
            guard let collectionView else { return }
            var desired = Set<IndexPath>()
            for (sectionIndex, section) in sections.enumerated() {
                for (itemIndex, item) in section.items.enumerated() where selection.contains(item.id) {
                    desired.insert(IndexPath(item: itemIndex, section: sectionIndex))
                }
            }
            guard desired != collectionView.selectionIndexPaths else { return }
            isApplyingSelection = true
            collectionView.selectionIndexPaths = desired
            isApplyingSelection = false
            if desired.count == 1 {
                collectionView.scrollToItems(at: desired, scrollPosition: .nearestHorizontalEdge)
            }
        }

        // MARK: AppKit → SwiftUI

        func pushSelection() {
            guard !isApplyingSelection, let collectionView else { return }
            let ids = Set(collectionView.selectionIndexPaths.compactMap { item(at: $0)?.id })
            DebugEventLog.log("selección", "Grilla (NSCollectionView): \(DebugEventLog.names(ids))")
            if ids != parent.selection {
                parent.selection = ids
            }
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            pushSelection()
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            pushSelection()
        }

        func open(at indexPath: IndexPath) {
            guard let item = item(at: indexPath) else { return }
            DebugEventLog.log("grilla", "doble clic en \(item.name)")
            parent.onOpen(item)
        }

        /// Clic derecho: como Finder, si el ítem no estaba seleccionado pasa a
        /// ser la selección antes de armar el menú.
        func menu(forClickedIndexPath indexPath: IndexPath?) -> NSMenu? {
            guard let collectionView else { return nil }
            guard let indexPath, let item = item(at: indexPath) else {
                return parent.menuForItems([])
            }
            if !collectionView.selectionIndexPaths.contains(indexPath) {
                collectionView.selectionIndexPaths = [indexPath]
                pushSelection()
            }
            let targets = collectionView.selectionIndexPaths.sorted().compactMap { self.item(at: $0) }
            return parent.menuForItems(targets.isEmpty ? [item] : targets)
        }

        // MARK: Data source

        func numberOfSections(in collectionView: NSCollectionView) -> Int {
            sections.count
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            sections[section].items.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let gridItem = collectionView.makeItem(withIdentifier: FileGridItem.identifier, for: indexPath)
            guard let cell = gridItem as? FileGridItem, let item = item(at: indexPath) else { return gridItem }
            cell.configure(FileGridCellContent(
                style: parent.style,
                item: item,
                zoomLevel: parent.zoomLevel,
                showPreviews: parent.showPreviews,
                isSelectionModeActive: parent.isSelectionModeActive,
                gitStatus: parent.gitStatuses[item.name]
            ))
            return cell
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
            at indexPath: IndexPath
        ) -> NSView {
            let view = collectionView.makeSupplementaryView(
                ofKind: kind,
                withIdentifier: FileGridHeaderView.identifier,
                for: indexPath
            )
            if let header = view as? FileGridHeaderView, sections.indices.contains(indexPath.section) {
                let section = sections[indexPath.section]
                header.configure(title: section.title ?? "", count: section.items.count)
            }
            return view
        }

        // MARK: Layout

        func collectionView(
            _ collectionView: NSCollectionView,
            layout collectionViewLayout: NSCollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> NSSize {
            FileGridMetrics(style: parent.style, zoomLevel: parent.zoomLevel)
                .itemSize(forContainerWidth: collectionView.bounds.width)
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            layout collectionViewLayout: NSCollectionViewLayout,
            referenceSizeForHeaderInSection section: Int
        ) -> NSSize {
            guard sections.indices.contains(section), sections[section].title != nil else { return .zero }
            return NSSize(width: collectionView.bounds.width, height: 28)
        }

        // MARK: Arrastrar (origen)

        /// Un ítem → un `NSURL`. Arrastrar un ítem seleccionado lleva toda la selección.
        func collectionView(
            _ collectionView: NSCollectionView,
            pasteboardWriterForItemAt indexPath: IndexPath
        ) -> (any NSPasteboardWriting)? {
            guard let item = item(at: indexPath) else { return nil }
            return item.url as NSURL
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forItemsAt indexPaths: Set<IndexPath>
        ) {
            let urls = indexPaths.compactMap { item(at: $0)?.url }
            DebugEventLog.log("drag", "Grilla (NSCollectionView): empieza arrastre de \(DebugEventLog.names(urls))")
        }

        // MARK: Soltar (destino)

        func collectionView(
            _ collectionView: NSCollectionView,
            validateDrop draggingInfo: any NSDraggingInfo,
            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
        ) -> NSDragOperation {
            let urls = Self.fileURLs(from: draggingInfo)
            guard !urls.isEmpty else { return [] }

            // Sobre una carpeta (que no sea una de las arrastradas): ahí.
            if proposedDropOperation.pointee == .on,
               let item = item(at: proposedDropIndexPath.pointee as IndexPath), item.isDirectory,
               !urls.contains(where: { $0.standardizedFileURL == item.url.standardizedFileURL }) {
                return .move
            }

            // En cualquier otro lugar: la carpeta actual.
            let currentURL = parent.currentURL.standardizedFileURL
            let alreadyHere = urls.allSatisfy {
                $0.deletingLastPathComponent().standardizedFileURL == currentURL
            }
            guard !alreadyHere else { return [] }
            proposedDropOperation.pointee = .before
            return .move
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            acceptDrop draggingInfo: any NSDraggingInfo,
            indexPath: IndexPath,
            dropOperation: NSCollectionView.DropOperation
        ) -> Bool {
            let urls = Self.fileURLs(from: draggingInfo)
            let destination: URL
            if dropOperation == .on, let item = item(at: indexPath), item.isDirectory {
                destination = item.url
            } else {
                destination = parent.currentURL
            }
            DebugEventLog.log("drop", "Grilla (NSCollectionView): soltar \(DebugEventLog.names(urls)) → \(destination.lastPathComponent)")
            guard !urls.isEmpty else { return false }
            parent.onMoveDropped(urls, destination)
            return true
        }

        private static func fileURLs(from info: any NSDraggingInfo) -> [URL] {
            let objects = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) ?? []
            return objects.compactMap { $0 as? URL }
        }
    }
}

// MARK: - Medidas

/// Tamaños de celda de cada estilo; los mismos números que usaban las
/// grillas de SwiftUI (`IconGridCell` / `CompactGridCell`).
struct FileGridMetrics: Equatable {
    var style: FileGridStyle = .icons
    var zoomLevel: Double = 1.0

    var inset: CGFloat { style == .icons ? 16 : 14 }
    var interitemSpacing: CGFloat { style == .icons ? 14 : 10 }
    var lineSpacing: CGFloat { style == .icons ? 16 : 4 }

    var iconSide: CGFloat {
        style == .icons ? 58 * zoomLevel : max(18, 22 * zoomLevel)
    }

    func columnCount(forContainerWidth width: CGFloat) -> Int {
        let minWidth = minimumItemWidth
        let innerWidth = max(minWidth, width - inset * 2)
        return max(1, Int(floor((innerWidth + interitemSpacing) / (minWidth + interitemSpacing))))
    }

    private var minimumItemWidth: CGFloat {
        style == .icons ? max(72, round(96 * zoomLevel)) + 4 : max(150, round(195 * zoomLevel))
    }

    func itemSize(forContainerWidth width: CGFloat) -> NSSize {
        switch style {
        case .icons:
            // Placa del ícono + nombre de hasta dos líneas.
            return NSSize(width: minimumItemWidth, height: iconSide + 14 + 4 + 36 + 8)
        case .compact:
            // Las columnas se reparten todo el ancho, como hacía `LazyVGrid`.
            let columns = CGFloat(columnCount(forContainerWidth: width))
            let available = max(minimumItemWidth, width - inset * 2 - (columns - 1) * interitemSpacing)
            return NSSize(width: floor(available / columns), height: iconSide + 10)
        }
    }

    /// Rect del ícono dentro del frame de una celda.
    func iconRect(inItemFrame frame: NSRect) -> NSRect {
        switch style {
        case .icons:
            return NSRect(x: frame.midX - iconSide / 2, y: frame.minY + 11, width: iconSide, height: iconSide)
        case .compact:
            return NSRect(x: frame.minX + 8, y: frame.midY - iconSide / 2, width: iconSide, height: iconSide)
        }
    }

    /// Rect del campo de edición del nombre sobre una celda.
    func nameRect(inItemFrame frame: NSRect) -> NSRect {
        switch style {
        case .icons:
            return NSRect(x: frame.minX - 12, y: frame.minY + iconSide + 20, width: frame.width + 24, height: 22)
        case .compact:
            let x = frame.minX + 8 + iconSide + 4
            return NSRect(x: x, y: frame.midY - 11, width: max(80, frame.maxX - x - 2), height: 22)
        }
    }
}

/// Recalcula el layout cuando cambia el ancho (las columnas de "Compacta"
/// dependen del ancho disponible).
final class FileGridFlowLayout: NSCollectionViewFlowLayout {
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        guard let collectionView else { return false }
        return newBounds.width != collectionView.bounds.width
            || super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }
}

// MARK: - NSCollectionView

final class FileNSCollectionView: NSCollectionView, FileViewResponder, QuickLookSourceProviding, NSTextFieldDelegate {
    var itemAtIndexPath: (IndexPath) -> FileItem? = { _ in nil }
    var indexPathForID: (FileItem.ID) -> IndexPath? = { _ in nil }
    var menuProvider: ((IndexPath?) -> NSMenu?)?
    var onOpenItem: ((IndexPath) -> Void)?
    /// Selección cambiada a mano por esta vista (modo de selección).
    var onUserChangedSelection: (() -> Void)?
    /// Se llama al terminar una edición en línea (para aplicar recargas pospuestas).
    var onRenamingEnded: (() -> Void)?
    var isSelectionModeActive = false
    var metrics = FileGridMetrics()
    var isRenaming: Bool { renameField != nil }

    private var interaction = FileViewInteraction()
    private var isActivePane = true
    private var renameField: NSTextField?
    private var renamingID: FileItem.ID?

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

    /// Igual que en `FileNSTableView`: nunca le saca el foco a un campo de texto.
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

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if !isActivePane {
            interaction.onActivate()
        }
        let hit = indexPathForItem(at: convert(event.locationInWindow, from: nil))

        // Modo de selección: cada clic alterna el ítem, sin teclas modificadoras.
        if isSelectionModeActive, let hit, event.modifierFlags.intersection([.command, .shift]).isEmpty {
            window?.makeFirstResponder(self)
            if selectionIndexPaths.contains(hit) {
                deselectItems(at: [hit])
            } else {
                selectItems(at: [hit], scrollPosition: [])
            }
            onUserChangedSelection?()
            return
        }

        super.mouseDown(with: event)
        if event.clickCount == 2, let hit, !isSelectionModeActive {
            onOpenItem?(hit)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let hit = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        return menuProvider?(hit) ?? super.menu(for: event)
    }

    // MARK: Teclado

    /// Espacio = Vista rápida, Intro = renombrar, letras = saltar al ítem.
    /// Las flechas (también con ⇧) son las de `NSCollectionView`.
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            switch event.keyCode {
            case 49: // Espacio
                interaction.onQuickLook()
                return
            case 36, 76: // Intro / Enter
                if !selectionIndexPaths.isEmpty {
                    interaction.onRequestRename()
                    return
                }
            case 53: // Esc
                if QuickLookPreviewController.shared.isVisible {
                    QuickLookPreviewController.shared.close()
                    return
                }
            default:
                if let characters = event.charactersIgnoringModifiers, characters.count == 1,
                   let scalar = characters.unicodeScalars.first,
                   CharacterSet.alphanumerics.contains(scalar) || CharacterSet.punctuationCharacters.contains(scalar) {
                    interaction.onTypeAhead(characters)
                    return
                }
            }
        }
        super.keyDown(with: event)
    }

    // MARK: Renombrar en línea

    /// Como Finder: un campo de texto encima del nombre, con el nombre sin
    /// extensión seleccionado. Intro o clic afuera confirma; Esc cancela.
    private func beginRenaming(_ id: FileItem.ID) {
        guard window != nil,
              let indexPath = indexPathForID(id),
              let item = itemAtIndexPath(indexPath),
              let frame = layoutAttributesForItem(at: indexPath)?.frame
        else { return }
        scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)

        let field = NSTextField(string: item.name)
        field.font = .systemFont(ofSize: 12)
        field.alignment = metrics.style == .icons ? .center : .left
        field.lineBreakMode = .byClipping
        field.frame = metrics.nameRect(inItemFrame: frame).intersection(bounds)
        field.delegate = self
        addSubview(field)
        renameField = field
        renamingID = id

        guard window?.makeFirstResponder(field) == true else {
            endRenaming(with: nil)
            return
        }
        let name = item.name as NSString
        let stem = name.deletingPathExtension as NSString
        let stemLength = (stem.length > 0 && stem.length < name.length) ? stem.length : name.length
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: stemLength)
    }

    private func endRenaming(with newName: String?) {
        guard let field = renameField, let id = renamingID else { return }
        renameField = nil
        renamingID = nil
        field.delegate = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        interaction.onEndRename(id, newName)
        onRenamingEnded?()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endRenaming(with: renameField?.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        renameField?.abortEditing()
        endRenaming(with: nil)
        return true
    }

    // MARK: Quick Look

    func quickLookSourceFrame(for url: URL) -> NSRect? {
        let target = url.standardizedFileURL
        guard let window,
              let indexPath = indexPathsForVisibleItems().first(where: {
                  itemAtIndexPath($0)?.url.standardizedFileURL == target
              }),
              let frame = layoutAttributesForItem(at: indexPath)?.frame
        else { return nil }
        let iconRect = metrics.iconRect(inItemFrame: frame)
        guard visibleRect.intersects(iconRect) else { return nil }
        return window.convertToScreen(convert(iconRect, to: nil))
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
}

// MARK: - Celda

/// Contenido SwiftUI de una celda; `isSelected` lo maneja `FileGridItem`.
struct FileGridCellContent: View {
    let style: FileGridStyle
    let item: FileItem
    let zoomLevel: Double
    let showPreviews: Bool
    let isSelectionModeActive: Bool
    let gitStatus: GitFileStatus?
    var isSelected = false
    var isDropTarget = false

    var body: some View {
        Group {
            switch style {
            case .icons:
                IconGridCell(
                    item: item,
                    zoomLevel: zoomLevel,
                    showPreviews: showPreviews,
                    isSelected: isSelected,
                    isSelectionModeActive: isSelectionModeActive,
                    gitStatus: gitStatus
                )
            case .compact:
                CompactGridCell(
                    item: item,
                    zoomLevel: zoomLevel,
                    isSelected: isSelected,
                    isSelectionModeActive: isSelectionModeActive,
                    gitStatus: gitStatus
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style == .icons ? .top : .leading)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
    }
}

final class FileGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FileGridItem")

    private var hostingView: NSHostingView<FileGridCellContent>?
    private var content: FileGridCellContent?

    override func loadView() {
        view = FileGridItemView()
    }

    func configure(_ content: FileGridCellContent) {
        self.content = content
        view.toolTip = FileMetadataFormatter().hoverTooltip(for: content.item)
        render()
    }

    override var isSelected: Bool {
        didSet { render() }
    }

    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet { render() }
    }

    private func render() {
        guard var content else { return }
        // El resaltado adelanta la selección mientras dura el clic o el recuadro.
        switch highlightState {
        case .forSelection: content.isSelected = true
        case .forDeselection: content.isSelected = false
        default: content.isSelected = isSelected
        }
        content.isDropTarget = highlightState == .asDropTarget

        if let hostingView {
            hostingView.rootView = content
        } else {
            let hostingView = NSHostingView(rootView: content)
            hostingView.sizingOptions = []
            hostingView.frame = view.bounds
            hostingView.autoresizingMask = [.width, .height]
            view.addSubview(hostingView)
            self.hostingView = hostingView
        }
    }
}

/// Los clics y arrastres son de `NSCollectionView`: la celda no deja que el
/// `NSHostingView` de adentro se quede con los eventos de mouse.
private final class FileGridItemView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
}

final class FileGridHeaderView: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("FileGridHeaderView")

    private var hostingView: NSHostingView<DotphinGroupSectionHeader>?

    func configure(title: String, count: Int) {
        let header = DotphinGroupSectionHeader(title: title, count: count)
        if let hostingView {
            hostingView.rootView = header
        } else {
            let hostingView = NSHostingView(rootView: header)
            hostingView.sizingOptions = []
            hostingView.frame = bounds
            hostingView.autoresizingMask = [.width, .height]
            addSubview(hostingView)
            self.hostingView = hostingView
        }
    }
}
