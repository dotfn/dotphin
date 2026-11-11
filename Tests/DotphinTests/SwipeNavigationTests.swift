import AppKit
import SwiftUI
import XCTest
@testable import Dotphin

/// Deslizar con el trackpad para ir atrás / adelante, como Safari.
@MainActor
final class SwipeNavigationTests: XCTestCase {
    func test_directions_matchSafari() {
        XCTAssertEqual(SwipeDirection(swipeDeltaX: 1), .back)
        XCTAssertEqual(SwipeDirection(swipeDeltaX: -1), .forward)
        XCTAssertNil(SwipeDirection(swipeDeltaX: 0))
        XCTAssertEqual(SwipeDirection(gestureAmount: 1), .back)
        XCTAssertEqual(SwipeDirection(gestureAmount: -1), .forward)
        XCTAssertNil(SwipeDirection(gestureAmount: 0), "gesto soltado a mitad: no navega")
    }

    func test_onlyAHorizontalStart_withNothingToScroll_beginsASwipe() {
        func starts(_ phase: NSEvent.Phase = .began, momentum: NSEvent.Phase = [], dx: CGFloat, dy: CGFloat = 0, canScroll: Bool = false) -> Bool {
            SwipeNavigationScrollView.startsHistorySwipe(phase: phase, momentumPhase: momentum, deltaX: dx, deltaY: dy, canScrollTowardDelta: canScroll)
        }
        XCTAssertTrue(starts(dx: 6))
        XCTAssertTrue(starts(dx: -6))
        XCTAssertFalse(starts(dx: 2, dy: 8), "vertical: es desplazar la lista")
        XCTAssertFalse(starts(.changed, dx: 6), "solo al empezar el gesto")
        XCTAssertFalse(starts(momentum: .began, dx: 6), "la inercia de un desplazamiento no navega")
        XCTAssertFalse(starts(dx: 6, canScroll: true), "si el contenido todavía se desplaza hacia ese lado, se desplaza")
        XCTAssertFalse(starts(dx: 0))
    }

    func test_fileViews_getTheirPanesHistory() throws {
        struct Host: View {
            let tabs: TabsViewModel
            var body: some View {
                if let tab = tabs.selectedTab {
                    SplitBrowserView(tab: tab, onFocusPane: { _ in })
                }
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "test.swipe.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let tabs = TabsViewModel(startingAt: root, defaults: defaults)
        let window = NSWindow(contentViewController: NSHostingController(rootView: Host(tabs: tabs).frame(width: 800, height: 500)))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let vm = try XCTUnwrap(tabs.selectedTab?.primary)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        vm.navigate(to: sub)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        func scrollViews(in view: NSView) -> [SwipeNavigationScrollView] {
            ((view as? SwipeNavigationScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
        }
        let scrollView = try XCTUnwrap(scrollViews(in: try XCTUnwrap(window.contentView)).first, "la vista de archivos no usa el scroll con gestos")
        let navigation = try XCTUnwrap(scrollView.navigation, "sin navegación conectada")

        XCTAssertTrue(navigation.canGoBack())
        XCTAssertFalse(navigation.canGoForward())
        navigation.goBack()
        XCTAssertEqual(vm.currentURL.standardizedFileURL, root.standardizedFileURL)
        XCTAssertTrue(navigation.canGoForward())
        navigation.goForward()
        XCTAssertEqual(vm.currentURL.standardizedFileURL, sub.standardizedFileURL)
    }
}
