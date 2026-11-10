import AppKit
import SwiftUI

struct TabOverviewView: View {
    let viewModel: TabsViewModel
    let places: [PlaceItem]
    let onSelectTab: (Tab.ID) -> Void
    let onAddTab: () -> Void
    let onCloseOverview: () -> Void

    @State private var hoveredTabID: Tab.ID?
    @State private var isHoveringNewTabCard = false

    private let columns = [
        GridItem(.adaptive(minimum: 340, maximum: 460), spacing: 46)
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Esc cierra la vista (acción de cancelar estándar).
            Button("Cerrar vista de pestañas", action: onCloseOverview)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)

            // Full-window dark backdrop matching native macOS Tab Overview
            Color(red: 0.15, green: 0.165, blue: 0.17)
                .ignoresSafeArea()
                .onTapGesture {
                    onCloseOverview()
                }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 40) {
                    ForEach(viewModel.tabs) { tab in
                        WindowTabPreviewCard(
                            tab: tab,
                            places: places,
                            isSelected: tab.id == viewModel.selectedTabID,
                            canClose: viewModel.tabs.count > 1,
                            isHovered: hoveredTabID == tab.id,
                            onSelect: {
                                onSelectTab(tab.id)
                            },
                            onClose: {
                                withAnimation(.spring(duration: 0.28, bounce: 0.06)) {
                                    viewModel.closeTab(tab.id)
                                }
                            }
                        )
                        .onHover { hovering in
                            hoveredTabID = hovering ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID)
                        }
                    }

                    NewTabOverviewCard(
                        isHovered: isHoveringNewTabCard,
                        onAddTab: onAddTab
                    )
                    .onHover { hovering in
                        isHoveringNewTabCard = hovering
                    }
                }
                .padding(.horizontal, 68)
                .padding(.top, 56)
                .padding(.bottom, 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WindowTabPreviewCard: View {
    let tab: Tab
    let places: [PlaceItem]
    let isSelected: Bool
    let canClose: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    private var currentURL: URL {
        tab.focused.currentURL
    }

    private var pathComponents: [String] {
        let parts = currentURL.pathComponents
        return Array(parts.suffix(4))
    }

    private var bookmarks: [PlaceItem] {
        places.filter { $0.kind == .bookmark }
    }

    private var volumes: [PlaceItem] {
        places.filter { $0.kind == .volume }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                // Miniature Places Sidebar
                miniatureSidebar
                    .frame(width: 72)
                    .background(Color(red: 0.09, green: 0.11, blue: 0.115))

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 0.5)

                // Miniature Browser Detail Area
                VStack(spacing: 0) {
                    // Miniature Header & Breadcrumb
                    VStack(spacing: 3) {
                        HStack(spacing: 4) {
                            ForEach(Array(pathComponents.enumerated()), id: \.offset) { idx, part in
                                if idx > 0 {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 5, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 2) {
                                    Image(systemName: part == "/" ? "internaldrive.fill" : "folder.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(part == "/" ? Color.secondary : Color.cyan)
                                    Text(part)
                                        .font(.system(size: 6.5, weight: idx == pathComponents.count - 1 ? .bold : .medium))
                                        .foregroundStyle(idx == pathComponents.count - 1 ? .primary : .secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .background(Color(red: 0.12, green: 0.145, blue: 0.15))

                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 0.5)

                    // Miniature File Grid / Split Panes
                    HStack(spacing: 0) {
                        miniatureFolderGrid(for: tab.primary)

                        if let secondary = tab.secondary {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 0.5)
                            miniatureFolderGrid(for: secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.10, green: 0.125, blue: 0.13))

                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 0.5)

                    // Miniature Status Bar
                    HStack {
                        Text("\(tab.focused.filteredItems.count) ítems")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("Zoom:")
                                .font(.system(size: 5.5))
                                .foregroundStyle(.secondary)
                            Capsule()
                                .fill(Color.accentColor.opacity(0.8))
                                .frame(width: 24, height: 2.5)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.11, green: 0.135, blue: 0.14))
                }
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color(nsColor: .controlAccentColor)
                            : Color.white.opacity(isHovered ? 0.28 : 0.10),
                        lineWidth: isSelected ? 3.5 : 1.2
                    )
            )
            .shadow(color: .black.opacity(0.38), radius: 14, y: 6)

            if canClose && isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 20, height: 20)
                        .background(Color.black.opacity(0.68), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .padding(8)
                .help("Cerrar pestaña")
            }
        }
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.snappy(duration: 0.16), value: isHovered)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private var miniatureSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lugares")
                .font(.system(size: 5.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(bookmarks) { place in
                    let active = place.url.standardizedFileURL.path == currentURL.standardizedFileURL.path
                    HStack(spacing: 4) {
                        Image(systemName: place.systemImage)
                            .font(.system(size: 6.5))
                            .foregroundStyle( Color(nsColor: .controlAccentColor))
                            .frame(width: 8)
                        Text(place.name)
                            .font(.system(size: 6, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? .white : .secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        active ? Color(nsColor: .controlAccentColor).opacity(0.28) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 3)
                    )
                }
            }
            .padding(.horizontal, 3)

            if !volumes.isEmpty {
                Text("Dispositivos")
                    .font(.system(size: 5.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.top, 3)

                ForEach(volumes.prefix(1)) { vol in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: vol.systemImage)
                                .font(.system(size: 6.5))
                                .foregroundStyle(Color(nsColor: .controlAccentColor))
                            Text(vol.name)
                                .font(.system(size: 6))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Capsule()
                            .fill(Color.white.opacity(0.55))
                            .frame(height: 2.5)
                            .padding(.leading, 10)
                    }
                    .padding(.horizontal, 5)
                }
            }

            Text("Carpetas")
                .font(.system(size: 5.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.top, 3)

            HStack(spacing: 3) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 4.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Image(systemName: "folder.fill")
                    .font(.system(size: 6.5))
                    .foregroundStyle(Color.cyan)
                Text(currentURL.lastPathComponent.isEmpty ? "/" : currentURL.lastPathComponent)
                    .font(.system(size: 6))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 5)

            Spacer(minLength: 0)
        }
    }

    private func miniatureFolderGrid(for vm: BrowserViewModel) -> some View {
        let previewItems = Array(vm.filteredItems.prefix(21))
        let gridCols = Array(repeating: GridItem(.flexible(minimum: 24), spacing: 6), count: tab.isSplit ? 4 : 7)

        return VStack(alignment: .leading, spacing: 0) {
            if previewItems.isEmpty {
                VStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(columns: gridCols, spacing: 8) {
                    ForEach(previewItems) { item in
                        VStack(spacing: 2) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                            Text(item.name)
                                .font(.system(size: 5.5))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(1)
                                .frame(maxWidth: 34)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct NewTabOverviewCard: View {
    let isHovered: Bool
    let onAddTab: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.22 : 0.17))

            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(isHovered ? 0.82 : 0.65))
                    .frame(width: 68, height: 3)
                Rectangle()
                    .fill(Color.white.opacity(isHovered ? 0.82 : 0.65))
                    .frame(width: 3, height: 68)
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.snappy(duration: 0.16), value: isHovered)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onAddTab)
        .help("Nueva pestaña")
        .accessibilityLabel("Nueva pestaña")
    }
}

enum TabOverviewGestureAction: Equatable, Sendable {
    case showOverview
    case hideOverview
}

/// Decide cuándo un pellizco abre o cierra la vista de pestañas, como en
/// Safari: juntar los dedos la abre, separarlos la cierra. Dispara una sola
/// vez por gesto, al pasar el umbral.
struct TabOverviewPinchRecognizer: Sendable {
    /// Cambio de escala (0.2 = 20 %) a partir del cual el pellizco cuenta.
    var threshold: CGFloat = 0.2
    private var hasTriggered = false

    mutating func began() {
        hasTriggered = false
    }

    /// `magnification`: cambio acumulado desde que empezó el gesto
    /// (negativo = juntar los dedos), como lo entrega `NSMagnificationGestureRecognizer`.
    mutating func changed(magnification: CGFloat, isOverviewVisible: Bool) -> TabOverviewGestureAction? {
        guard !hasTriggered else { return nil }
        if magnification <= -threshold, !isOverviewVisible {
            hasTriggered = true
            return .showOverview
        }
        if magnification >= threshold, isOverviewVisible {
            hasTriggered = true
            return .hideOverview
        }
        return nil
    }
}

/// Pellizco del trackpad sobre la ventana, con el reconocedor nativo de AppKit
/// (`NSMagnificationGestureRecognizer`). Reemplaza al deslizamiento de tres
/// dedos, que leía toques crudos con un monitor global de eventos.
struct TabOverviewPinchGestureView: NSViewRepresentable {
    var isOverviewVisible: Bool
    let onShowOverview: () -> Void
    let onHideOverview: () -> Void

    func makeNSView(context: Context) -> GestureNSView {
        let view = GestureNSView()
        view.update(isOverviewVisible: isOverviewVisible, onShowOverview: onShowOverview, onHideOverview: onHideOverview)
        return view
    }

    func updateNSView(_ nsView: GestureNSView, context: Context) {
        nsView.update(isOverviewVisible: isOverviewVisible, onShowOverview: onShowOverview, onHideOverview: onHideOverview)
    }

    final class GestureNSView: NSView {
        private var isOverviewVisible = false
        private var onShowOverview: (() -> Void)?
        private var onHideOverview: (() -> Void)?
        private var pinch = TabOverviewPinchRecognizer()
        private var gestureRecognizer: NSMagnificationGestureRecognizer?
        private weak var gestureHost: NSView?

        func update(isOverviewVisible: Bool, onShowOverview: @escaping () -> Void, onHideOverview: @escaping () -> Void) {
            self.isOverviewVisible = isOverviewVisible
            self.onShowOverview = onShowOverview
            self.onHideOverview = onHideOverview
        }

        /// El reconocedor va en la vista raíz de la ventana: así el pellizco
        /// funciona sobre cualquier parte del contenido.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let gestureRecognizer {
                gestureHost?.removeGestureRecognizer(gestureRecognizer)
                self.gestureRecognizer = nil
            }
            guard let host = window?.contentView else { return }
            let recognizer = NSMagnificationGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            recognizer.delaysMagnificationEvents = false
            host.addGestureRecognizer(recognizer)
            gestureRecognizer = recognizer
            gestureHost = host
        }

        @objc private func handlePinch(_ recognizer: NSMagnificationGestureRecognizer) {
            switch recognizer.state {
            case .began:
                pinch.began()
                fallthrough
            case .changed:
                handle(magnification: recognizer.magnification)
            default:
                break
            }
        }

        func handle(magnification: CGFloat) {
            switch pinch.changed(magnification: magnification, isOverviewVisible: isOverviewVisible) {
            case .showOverview: onShowOverview?()
            case .hideOverview: onHideOverview?()
            case nil: break
            }
        }
    }
}
