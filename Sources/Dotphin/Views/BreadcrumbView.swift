import AppKit
import SwiftUI

/// Dolphin's URL navigator: breadcrumb mode by default; click on empty space, the edit button, or ⌘L
/// switches to an editable path field (Return navigates, Esc cancels, Tab completes).
struct BreadcrumbView: View {
    let url: URL
    var editableByDefault: Bool = false
    let onNavigate: (URL) -> Void
    var onOpenInNewTab: ((URL) -> Void)? = nil
    var onOpenInSplitView: ((URL) -> Void)? = nil

    @State private var isEditing = false
    @State private var text = ""
    @State private var hoveredAncestor: URL?
    @State private var isEditButtonHovered = false
    @FocusState private var isFieldFocused: Bool
    @Environment(\.locationEditRequest) private var locationEditRequest
    @Environment(\.isActiveBrowserPane) private var isActivePane

    private var ancestors: [URL] {
        var result: [URL] = [url]
        var current = url
        while current.pathComponents.count > 1 {
            current = current.deletingLastPathComponent()
            result.append(current)
        }
        return result.reversed()
    }

    var body: some View {
        Group {
            if isEditing || editableByDefault {
                editor
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                crumbs
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.18), value: isEditing)
        .animation(.snappy(duration: 0.2), value: url)
        .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            text = url.path
        }
        .onChange(of: isEditing) { _, editing in
            // El campo ya existe cuando corre este onChange: el foco prende sin demoras.
            if editing { isFieldFocused = true }
        }
        .onChange(of: locationEditRequest) { _, _ in
            if isActivePane { beginEditing() }
        }
        .onChange(of: url) { _, newURL in
            text = newURL.path
            withAnimation(.snappy(duration: 0.18)) {
                isEditing = false
            }
        }
    }

    private var editor: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(String(localized: "Ubicación", bundle: #bundle), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isFieldFocused)
                .onSubmit(commit)
                .onExitCommand { isEditing = false }
                .onKeyPress(.tab) {
                    complete()
                    return .handled
                }
                .onChange(of: isFieldFocused) { _, focused in
                    if !focused { isEditing = false }
                }
                .accessibilityLabel(String(localized: "Ubicación", bundle: #bundle))

            Button {
                commit()
            } label: {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Ir a la ruta (Intro)", bundle: #bundle))

            Button {
                isEditing = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Cancelar edición (Esc)", bundle: #bundle))
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1.2)
        )
    }

    private var crumbRow: some View {
        HStack(spacing: 2) {
            ForEach(Array(ancestors.enumerated()), id: \.element) { idx, ancestor in
                let isCurrent = ancestor == ancestors.last
                let isHovered = hoveredAncestor == ancestor
                let isRoot = ancestor.lastPathComponent.isEmpty || ancestor.path == "/"
                Button {
                    onNavigate(ancestor)
                } label: {
                    HStack(spacing: 5) {
                        Image(nsImage: ThumbnailLoader.icon(forFile: ancestor.path))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                        Text(isRoot ? (FileManager.default.displayName(atPath: "/").isEmpty ? "/" : FileManager.default.displayName(atPath: "/")) : ancestor.lastPathComponent)
                            .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        isCurrent
                            ? Color.primary.opacity(0.10)
                            : (isHovered ? Color.primary.opacity(0.06) : Color.clear),
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                    .animation(.easeOut(duration: 0.14), value: isHovered)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
                .onHover { hovering in
                    hoveredAncestor = hovering ? ancestor : (hoveredAncestor == ancestor ? nil : hoveredAncestor)
                }
                .contextMenu {
                    Button(String(localized: "Abrir", bundle: #bundle), menuIcon: "arrow.up.forward.square") {
                        onNavigate(ancestor)
                    }
                    if let onOpenInNewTab {
                        Button(String(localized: "Abrir en una pestaña nueva", bundle: #bundle), menuIcon: "plus.square.on.square") {
                            onOpenInNewTab(ancestor)
                        }
                    }
                    if let onOpenInSplitView {
                        Button(String(localized: "Abrir en vista dividida", bundle: #bundle), menuIcon: "rectangle.split.2x1") {
                            onOpenInSplitView(ancestor)
                        }
                    }
                    Divider()
                    Button(String(localized: "Copiar ubicación", bundle: #bundle), menuIcon: "link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ancestor.path, forType: .string)
                    }
                    Button(String(localized: "Añadir a Lugares", bundle: #bundle), menuIcon: "bookmark") {
                        PlacesProvider().addBookmark(for: ancestor)
                    }
                    Button(String(localized: "Mostrar en Finder", bundle: #bundle), menuIcon: "macwindow") {
                        NSWorkspace.shared.activateFileViewerSelecting([ancestor])
                    }
                }

                if !isCurrent {
                    let nextAncestor = (idx + 1 < ancestors.count) ? ancestors[idx + 1] : nil
                    subfolderChevronMenu(for: ancestor, activeChild: nextAncestor)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private var crumbs: some View {
        HStack(spacing: 4) {
            // Si las migas entran, se muestran a su ancho natural; si no, se
            // desplazan en horizontal. (Un `ScrollView` con `fixedSize` acá
            // entraba en bucle de layout junto al inspector.)
            //
            // Las migas son lo único flexible de la fila y el espacio clicable va
            // de fondo: como dos vistas flexibles lado a lado, el HStack les
            // repartía el ancho a medias y en paneles medianos las migas pasaban a
            // desplazarse aunque sobrara lugar. (Darles `layoutPriority` hacía que
            // el panel exigiera su ancho y dejaba un hueco al borde de la ventana.)
            ViewThatFits(in: .horizontal) {
                crumbRow
                ScrollView(.horizontal, showsIndicators: false) {
                    crumbRow
                }
                // Si no entra, se ve el final: la carpeta actual.
                .defaultScrollAnchor(.trailing)
                .defaultScrollAnchor(.trailing, for: .sizeChanges)
            }
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing() }
                    .help(String(localized: "Clic para editar la ruta (⌘L)", bundle: #bundle))
            }

            Button {
                beginEditing()
            } label: {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isEditButtonHovered ? .primary : .secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isEditButtonHovered ? Color.primary.opacity(0.08) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isEditButtonHovered = $0 }
            .help(String(localized: "Editar ubicación (⌘L)", bundle: #bundle))
            .accessibilityLabel(String(localized: "Editar ubicación", bundle: #bundle))
        }
    }

    @ViewBuilder
    private func subfolderChevronMenu(for parentURL: URL, activeChild: URL?) -> some View {
        let subfolders = LocationParser.subdirectories(of: parentURL)
        if subfolders.isEmpty {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 1)
        } else {
            Menu {
                // Marca la subcarpeta por la que pasa la ruta actual.
                Picker(selection: Binding(
                    get: { activeChild.flatMap { child in subfolders.first { $0.standardizedFileURL == child.standardizedFileURL } } },
                    set: { if let sub = $0 { onNavigate(sub) } }
                )) {
                    ForEach(subfolders, id: \.self) { sub in
                        Text(sub.lastPathComponent).tag(Optional(sub))
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "Subcarpetas de \(parentURL.lastPathComponent.isEmpty ? "/" : parentURL.lastPathComponent)", bundle: #bundle))
        }
    }

    private func beginEditing() {
        text = url.path
        withAnimation(.snappy(duration: 0.18)) {
            isEditing = true
        }
    }

    private func commit() {
        guard let destination = LocationParser.directoryURL(from: text) else {
            NSSound.beep()
            return
        }
        withAnimation(.snappy(duration: 0.18)) {
            isEditing = false
        }
        onNavigate(destination)
    }

    private func complete() {
        text = LocationParser.completed(text)
    }
}

/// Pure path-text helpers for the editable location bar.
enum LocationParser {
    nonisolated(unsafe) private static let subdirectoriesCache: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 128
        return cache
    }()
    /// Expands `~`, resolves relative-to-nothing paths, and returns the URL only if it is an existing directory.
    static func directoryURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    /// Tab completion: extends the last path component to the longest common prefix of
    /// matching sub-directories (a unique match also gets a trailing "/").
    static func completed(_ input: String) -> String {
        let expanded = (input as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return input }
        let parent: String
        let partial: String
        if expanded.hasSuffix("/") {
            parent = expanded
            partial = ""
        } else {
            parent = (expanded as NSString).deletingLastPathComponent
            partial = (expanded as NSString).lastPathComponent
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: parent) else { return input }
        let matches = entries
            .filter { name in
                var isDir: ObjCBool = false
                let full = (parent as NSString).appendingPathComponent(name)
                return FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
                    && isDir.boolValue
                    && name.lowercased().hasPrefix(partial.lowercased())
                    && (partial.hasPrefix(".") || !name.hasPrefix("."))
            }
            .sorted()
        guard !matches.isEmpty else { return input }
        let prefix = matches.dropFirst().reduce(matches[0]) { common, next in
            String(zip(common, next).prefix(while: { $0.lowercased() == $1.lowercased() }).map { $0.0 })
        }
        var result = (parent as NSString).appendingPathComponent(prefix)
        if matches.count == 1 { result += "/" }
        return result
    }

    /// Lists up to 40 visible subdirectories of `url` sorted naturally (`KUrlNavigatorButton` popup).
    static func subdirectories(of url: URL) -> [URL] {
        let modStamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        let cacheKey = "\(url.standardizedFileURL.path)|\(modStamp)" as NSString
        if let cached = subdirectoriesCache.object(forKey: cacheKey) as? [URL] {
            return cached
        }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let result = urls
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(40)
            .map { $0 }
        subdirectoriesCache.setObject(result as NSArray, forKey: cacheKey)
        return result
    }
}
