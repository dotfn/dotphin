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
                PaneSplitView(minPaneWidth: 180) {
                    paneView(viewModel: tab.primary, index: 0, showSplitHeader: true)
                } trailing: {
                    paneView(viewModel: secondary, index: 1, showSplitHeader: true)
                }
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

/// Dos paneles lado a lado en un `NSSplitView` propio.
///
/// El `HSplitView` de SwiftUI informa mal su tamaño mínimo (la ventana no se
/// dejaba achicar) y, corregido con `GeometryReader` o `frame(minWidth:)`,
/// entra en bucle de "Update Constraints" junto al `.inspector` (#10). Acá el
/// tamaño lo decide SwiftUI (`sizeThatFits`) y el reparto, AppKit.
struct PaneSplitView<Leading: View, Trailing: View>: NSViewRepresentable {
    var minPaneWidth: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    func makeCoordinator() -> Coordinator {
        Coordinator(minPaneWidth: minPaneWidth)
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = EvenSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator
        for root in roots(context) {
            let host = NSHostingView(rootView: root)
            // El tamaño lo manda el divisor, no el contenido de cada panel.
            host.sizingOptions = []
            splitView.addArrangedSubview(host)
        }
        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.minPaneWidth = minPaneWidth
        for (host, root) in zip(splitView.arrangedSubviews, roots(context)) {
            (host as? NSHostingView<AnyView>)?.rootView = root
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSplitView, context: Context) -> CGSize? {
        let minWidth = minPaneWidth * 2 + nsView.dividerThickness
        return CGSize(
            width: max(minWidth, proposal.width ?? minWidth * 2),
            height: max(0, proposal.height ?? 400)
        )
    }

    /// Los paneles viven en su propio `NSHostingView`: el entorno de SwiftUI
    /// (panel activo, pedidos de la ventana…) se les pasa a mano.
    private func roots(_ context: Context) -> [AnyView] {
        [
            AnyView(leading.environment(\.self, context.environment)),
            AnyView(trailing.environment(\.self, context.environment)),
        ]
    }

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        var minPaneWidth: CGFloat

        init(minPaneWidth: CGFloat) {
            self.minPaneWidth = minPaneWidth
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            proposedMinimumPosition + minPaneWidth
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            proposedMaximumPosition - minPaneWidth
        }
    }
}

/// `NSSplitView` que arranca con los paneles a la mitad.
final class EvenSplitView: NSSplitView {
    private var didSetInitialPosition = false

    override func layout() {
        super.layout()
        guard !didSetInitialPosition, bounds.width > 0, arrangedSubviews.count == 2 else { return }
        didSetInitialPosition = true
        setPosition((bounds.width - dividerThickness) / 2, ofDividerAt: 0)
    }
}
