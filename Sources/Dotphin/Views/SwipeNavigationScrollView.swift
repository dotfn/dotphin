import AppKit
import SwiftUI

/// Atrás / adelante del historial del panel, para el gesto de deslizar del trackpad.
struct SwipeNavigation {
    var canGoBack: @MainActor () -> Bool
    var canGoForward: @MainActor () -> Bool
    var goBack: @MainActor () -> Void
    var goForward: @MainActor () -> Void
}

private struct SwipeNavigationKey: EnvironmentKey {
    static let defaultValue: SwipeNavigation? = nil
}

extension EnvironmentValues {
    /// Lo pone `BrowserView`; lo usan las vistas de archivos de AppKit.
    var swipeNavigation: SwipeNavigation? {
        get { self[SwipeNavigationKey.self] }
        set { self[SwipeNavigationKey.self] = newValue }
    }
}

enum SwipeDirection: Equatable {
    case back
    case forward

    /// Tres dedos (`swipe(with:)`): `deltaX` positivo es atrás, como en Safari (WebKit).
    init?(swipeDeltaX deltaX: CGFloat) {
        if deltaX > 0 {
            self = .back
        } else if deltaX < 0 {
            self = .forward
        } else {
            return nil
        }
    }

    /// Dos dedos (`trackSwipeEvent`): al terminar, la cantidad positiva es atrás.
    init?(gestureAmount amount: CGFloat) {
        if amount > 0.5 {
            self = .back
        } else if amount < -0.5 {
            self = .forward
        } else {
            return nil
        }
    }
}

/// Scroll view de las vistas de archivos con el gesto de Safari para el
/// historial: deslizar con dos dedos (o tres, según Ajustes del Sistema →
/// Trackpad → «Deslizar entre páginas») va atrás o adelante, con el rebote y la
/// animación del sistema (`trackSwipeEvent`).
final class SwipeNavigationScrollView: NSScrollView {
    var navigation: SwipeNavigation?
    private var indicator: NSImageView?

    /// ¿Este evento de desplazamiento empieza un gesto de historial? Solo si es
    /// horizontal y el contenido no puede desplazarse más hacia ese lado (en
    /// Detalles con columnas anchas, primero se desplaza la tabla).
    static func startsHistorySwipe(
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase,
        deltaX: CGFloat,
        deltaY: CGFloat,
        canScrollTowardDelta: Bool
    ) -> Bool {
        phase == .began
            && momentumPhase == []
            && deltaX != 0
            && abs(deltaX) > abs(deltaY)
            && !canScrollTowardDelta
    }

    /// `deltaX` positivo desplaza hacia el borde izquierdo del contenido.
    private func canScrollHorizontally(towardDelta deltaX: CGFloat) -> Bool {
        guard let document = documentView else { return false }
        let visible = contentView.bounds
        let content = document.frame
        guard content.width > visible.width + 1 else { return false }
        return deltaX > 0 ? visible.minX > content.minX + 1 : visible.maxX < content.maxX - 1
    }

    override func scrollWheel(with event: NSEvent) {
        guard let navigation,
              NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              Self.startsHistorySwipe(
                phase: event.phase,
                momentumPhase: event.momentumPhase,
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                canScrollTowardDelta: canScrollHorizontally(towardDelta: event.scrollingDeltaX)
              )
        else {
            super.scrollWheel(with: event)
            return
        }
        let canGoBack = navigation.canGoBack()
        let canGoForward = navigation.canGoForward()
        guard canGoBack || canGoForward else {
            super.scrollWheel(with: event)
            return
        }
        // Hacia un lado sin historial, el gesto rebota sin llegar a navegar.
        event.trackSwipeEvent(
            options: [.lockDirection, .clampGestureAmount],
            dampenAmountThresholdMin: canGoForward ? -1 : 0,
            max: canGoBack ? 1 : 0
        ) { [weak self] amount, _, isComplete, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.showIndicator(for: amount)
                guard isComplete else { return }
                self.hideIndicator()
                switch SwipeDirection(gestureAmount: amount) {
                case .back: navigation.goBack()
                case .forward: navigation.goForward()
                case nil: break
                }
            }
        }
    }

    override func swipe(with event: NSEvent) {
        guard let navigation, let direction = SwipeDirection(swipeDeltaX: event.deltaX) else {
            super.swipe(with: event)
            return
        }
        switch direction {
        case .back where navigation.canGoBack(): navigation.goBack()
        case .forward where navigation.canGoForward(): navigation.goForward()
        default: super.swipe(with: event)
        }
    }

    // MARK: Indicador

    /// Flecha en el borde hacia donde se va, que entra con el gesto y se
    /// completa cuando soltar ya navega.
    private func showIndicator(for amount: CGFloat) {
        guard amount != 0 else {
            hideIndicator()
            return
        }
        let indicator = self.indicator ?? makeIndicator()
        let goingBack = amount > 0
        indicator.image = NSImage(
            systemSymbolName: goingBack ? "chevron.backward.circle.fill" : "chevron.forward.circle.fill",
            accessibilityDescription: nil
        )
        let progress = min(abs(amount), 1)
        let side: CGFloat = 40
        let travel = side + 16
        let y = bounds.midY - side / 2
        let x = goingBack
            ? -side + travel * progress
            : bounds.maxX - travel * progress
        indicator.frame = NSRect(x: x, y: y, width: side, height: side)
        indicator.alphaValue = 0.35 + 0.65 * progress
        indicator.contentTintColor = progress >= 0.99 ? .controlAccentColor : .secondaryLabelColor
    }

    private func makeIndicator() -> NSImageView {
        let view = NSImageView()
        view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        view.imageScaling = .scaleProportionallyUpOrDown
        addSubview(view)
        indicator = view
        return view
    }

    private func hideIndicator() {
        indicator?.removeFromSuperview()
        indicator = nil
    }
}
