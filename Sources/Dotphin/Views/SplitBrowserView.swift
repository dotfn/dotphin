import AppKit
import SwiftUI

struct SplitBrowserView: View {
    let tab: Tab
    var onOpenInNewTab: ((URL) -> Void)? = nil
    var onOpenInSplitView: ((URL) -> Void)? = nil
    var onOpenTerminal: ((URL) -> Void)? = nil
    let onFocusPane: (Int) -> Void

    var body: some View {
        Group {
            if tab.isSplit, let secondary = tab.secondary {
                // Divisor nativo: arrastre, cursor y límites son los de AppKit.
                HSplitView {
                    paneView(viewModel: tab.primary, index: 0, showSplitHeader: true)
                        .frame(minWidth: 180, idealWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                    paneView(viewModel: secondary, index: 1, showSplitHeader: true)
                        .frame(minWidth: 180, idealWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                }
                .fillingAvailableSpaceExactly()
            } else {
                paneView(viewModel: tab.primary, index: 0, showSplitHeader: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(tab.id)
    }

    private func paneView(viewModel: BrowserViewModel, index: Int, showSplitHeader: Bool) -> some View {
        let otherPane = index == 0 ? tab.secondary : tab.primary
        let isFocused = tab.focusedPaneIndex == index
        return VStack(spacing: 0) {
            if showSplitHeader {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isFocused ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)

                    BreadcrumbView(
                        url: viewModel.currentURL,
                        editableByDefault: false,
                        onNavigate: { viewModel.navigate(to: $0) },
                        onOpenInNewTab: onOpenInNewTab,
                        onOpenInSplitView: onOpenInSplitView
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isFocused ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.02))
                Divider()
            }

            BrowserView(
                viewModel: viewModel,
                otherPaneURL: otherPane?.currentURL,
                onFilesMoved: { otherPane?.refresh() },
                onOpenInNewTab: onOpenInNewTab,
                onOpenInSplitView: onOpenInSplitView,
                onOpenTerminal: onOpenTerminal
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
        .opacity(showSplitHeader && !isFocused ? 0.92 : 1.0)
        .overlay(alignment: .top) {
            if showSplitHeader {
                Rectangle()
                    .fill(isFocused ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
        }
        // El panel activo lo decide el foco de teclado: la vista de archivos
        // avisa cuando recibe el foco o un clic.
        .environment(\.isActiveBrowserPane, !showSplitHeader || isFocused)
        .environment(\.fileViewInteraction, FileViewInteraction(onActivate: { onFocusPane(index) }))
        .onChange(of: viewModel.currentURL) { _, _ in
            onFocusPane(index)
        }
        .onChange(of: viewModel.selectedIDs) { _, _ in
            onFocusPane(index)
        }
    }
}

extension View {
    /// Para `HSplitView`/`VSplitView`: con un ancho máximo no redistribuyen los
    /// paneles cuando el espacio es justo (quedaban más angostos que la ventana,
    /// o más anchos y cortados en los dos bordes); con un tamaño exacto, sí.
    func fillingAvailableSpaceExactly() -> some View {
        GeometryReader { proxy in
            frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
