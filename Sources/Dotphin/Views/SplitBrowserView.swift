import AppKit
import SwiftUI

/// Los paneles de una pestaña. Siempre es el mismo `NSSplitView` con dos
/// paneles: sin vista dividida el segundo se oculta, así el primero no se
/// vuelve a crear (ni a leer su carpeta) al dividir o volver a un panel.
/// Cada panel lleva su propia ruta, también cuando está solo.
struct SplitBrowserView: View {
    let tab: Tab
    var editableLocationByDefault = false
    var onOpenInNewTab: ((URL) -> Void)? = nil
    var onOpenInSplitView: ((URL) -> Void)? = nil
    var onOpenTerminal: ((URL) -> Void)? = nil
    let onFocusPane: (Int) -> Void

    var body: some View {
        // Divisor nativo: arrastre, cursor y límites son los de AppKit.
        PaneSplitView(minPaneWidth: 180, showsTrailing: tab.isSplit) {
            paneView(viewModel: tab.primary, index: 0)
        } trailing: {
            if let secondary = tab.secondary {
                paneView(viewModel: secondary, index: 1)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(tab.id)
    }

    private func paneView(viewModel: BrowserViewModel, index: Int) -> some View {
        let otherPane = index == 0 ? tab.secondary : tab.primary
        let isSplit = tab.isSplit
        let isFocused = tab.focusedPaneIndex == index
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                // El punto marca el panel activo; solo hace falta con dos.
                if isSplit {
                    Circle()
                        .fill(isFocused ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }

                BreadcrumbView(
                    url: viewModel.currentURL,
                    editableByDefault: editableLocationByDefault,
                    onNavigate: { viewModel.navigate(to: $0) },
                    onOpenInNewTab: onOpenInNewTab,
                    onOpenInSplitView: onOpenInSplitView
                )
            }
            .padding(.horizontal, isSplit ? 8 : 10)
            .padding(.vertical, 3)
            .background {
                if isSplit {
                    isFocused ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.02)
                } else {
                    Rectangle().fill(.bar)
                }
            }
            Divider()

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
        .opacity(isSplit && !isFocused ? 0.92 : 1.0)
        .overlay(alignment: .top) {
            if isSplit {
                Rectangle()
                    .fill(isFocused ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
        }
        // El panel activo lo decide el foco de teclado: la vista de archivos
        // avisa cuando recibe el foco o un clic.
        .environment(\.isActiveBrowserPane, !isSplit || isFocused)
        .environment(\.fileViewInteraction, FileViewInteraction(onActivate: { onFocusPane(index) }))
        .onChange(of: viewModel.currentURL) { _, _ in
            onFocusPane(index)
        }
        .onChange(of: viewModel.selectedIDs) { _, _ in
            onFocusPane(index)
        }
    }
}

/// Dos paneles lado a lado en un `NSSplitView` propio. Con `showsTrailing`
/// en falso el segundo se oculta: `NSSplitView` lo trata como plegado, sin
/// divisor, y el primero ocupa todo.
///
/// El `HSplitView` de SwiftUI informa mal su tamaño mínimo (la ventana no se
/// dejaba achicar) y, corregido con `GeometryReader` o `frame(minWidth:)`,
/// entra en bucle de "Update Constraints" junto al `.inspector` (#10). Acá el
/// tamaño lo decide SwiftUI (`sizeThatFits`) y el reparto, AppKit.
struct PaneSplitView<Leading: View, Trailing: View>: NSViewRepresentable {
    var minPaneWidth: CGFloat
    var showsTrailing = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    func makeCoordinator() -> Coordinator {
        Coordinator(minPaneWidth: minPaneWidth)
    }

    func makeNSView(context: Context) -> EvenSplitView {
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
        splitView.arrangedSubviews[1].isHidden = !showsTrailing
        return splitView
    }

    func updateNSView(_ splitView: EvenSplitView, context: Context) {
        context.coordinator.minPaneWidth = minPaneWidth
        for (host, root) in zip(splitView.arrangedSubviews, roots(context)) {
            (host as? NSHostingView<AnyView>)?.rootView = root
        }
        splitView.setShowsTrailing(showsTrailing)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EvenSplitView, context: Context) -> CGSize? {
        let minWidth = showsTrailing ? minPaneWidth * 2 + nsView.dividerThickness : minPaneWidth
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

        /// Con un solo panel no queda la línea del divisor en el borde.
        func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
            splitView.arrangedSubviews.contains { splitView.isSubviewCollapsed($0) }
        }
    }
}

/// `NSSplitView` que reparte los paneles a la mitad cada vez que aparece el segundo.
final class EvenSplitView: NSSplitView {
    private var needsEvenPosition = true

    func setShowsTrailing(_ showsTrailing: Bool) {
        guard arrangedSubviews.count == 2, arrangedSubviews[1].isHidden == showsTrailing else { return }
        arrangedSubviews[1].isHidden = !showsTrailing
        needsEvenPosition = showsTrailing
        // Ocultar o mostrar un panel no reparte el espacio ni mueve la capa
        // del divisor por sí solo: sin el pase de layout quedaba la línea
        // vieja a la mitad del panel que queda.
        adjustSubviews()
        evenOutIfNeeded()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        evenOutIfNeeded()
    }

    private func evenOutIfNeeded() {
        guard needsEvenPosition, bounds.width > 0, arrangedSubviews.count == 2,
              !arrangedSubviews[1].isHidden else { return }
        needsEvenPosition = false
        setPosition((bounds.width - dividerThickness) / 2, ofDividerAt: 0)
    }
}
