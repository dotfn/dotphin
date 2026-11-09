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

extension Notification.Name {
    static let toggleTabOverview = Notification.Name("Dotphin.toggleTabOverview")
}

@MainActor
enum NativeTabOverviewController {
    static func toggle(in targetWindow: NSWindow? = nil) {
        NotificationCenter.default.post(name: .toggleTabOverview, object: targetWindow)
    }
}

struct TrackpadTouchSample: Sendable {
    let id: Int
    let position: CGPoint
}

enum ThreeFingerGestureAction: Equatable, Sendable {
    case showOverview
    case hideOverview
}

/// Recognizes intentional 3-finger vertical trackpad swipes while strictly filtering out:
/// - 4-finger / 5-finger system gestures (Mission Control, App Exposé, Spaces switch), including
///   transient 3-finger frames during finger touchdown or liftoff.
/// - Downward swipes when Tab Overview is closed (and upward swipes when Tab Overview is open).
/// - Horizontal 3-finger swipes and finger rebounds at the end of a stroke.
struct ThreeFingerSwipeRecognizer: Sendable {
    var minStableDuration: TimeInterval = 0.055
    var minThreeFingerSamples: Int = 4
    var fourFingerCooldown: TimeInterval = 0.45
    var triggerCooldown: TimeInterval = 0.50
    var minShowVerticalDelta: CGFloat = 0.095
    var minHideVerticalDelta: CGFloat = 0.085
    var minPerFingerVerticalDelta: CGFloat = 0.065
    var verticalDominanceRatio: CGFloat = 1.80
    var maxSpreadDeviation: CGFloat = 0.085

    private var startPositions: [Int: CGPoint] = [:]
    private var startCentroid: CGPoint?
    private var startSpread: CGFloat = 0
    private var startTimestamp: TimeInterval?
    private var sampleCount: Int = 0
    private var isSequenceDisqualified: Bool = false
    private var hasTriggeredInSequence: Bool = false
    private var lastFourFingerTimestamp: TimeInterval = -.infinity
    private var lastTriggerTimestamp: TimeInterval = -.infinity

    mutating func reset() {
        startPositions.removeAll()
        startCentroid = nil
        startSpread = 0
        startTimestamp = nil
        sampleCount = 0
        isSequenceDisqualified = false
        hasTriggeredInSequence = false
    }

    mutating func processFrame(
        touches: [TrackpadTouchSample],
        timestamp: TimeInterval,
        isOverviewVisible: Bool
    ) -> ThreeFingerGestureAction? {
        if touches.isEmpty {
            reset()
            return nil
        }

        // Any 4+ finger contact immediately disqualifies the entire touch sequence
        if touches.count >= 4 {
            isSequenceDisqualified = true
            lastFourFingerTimestamp = timestamp
            startPositions.removeAll()
            startCentroid = nil
            startTimestamp = nil
            sampleCount = 0
            return nil
        }

        if isSequenceDisqualified || hasTriggeredInSequence {
            return nil
        }

        // Cooldown after a 4-finger gesture or recent trigger
        if timestamp - lastFourFingerTimestamp < fourFingerCooldown {
            return nil
        }
        if timestamp - lastTriggerTimestamp < triggerCooldown {
            return nil
        }

        guard touches.count == 3 else {
            // 1 or 2 fingers on trackpad: clear 3-finger baseline until 3 fingers are stably down
            startPositions.removeAll()
            startCentroid = nil
            startSpread = 0
            startTimestamp = nil
            sampleCount = 0
            return nil
        }

        let avgX = touches.map(\.position.x).reduce(0, +) / 3.0
        let avgY = touches.map(\.position.y).reduce(0, +) / 3.0
        let centroid = CGPoint(x: avgX, y: avgY)
        let spread = touches.map { hypot($0.position.x - avgX, $0.position.y - avgY) }.reduce(0, +) / 3.0

        let sameIdentities = touches.allSatisfy { startPositions[$0.id] != nil } && startPositions.count == 3
        if !sameIdentities || startTimestamp == nil || startCentroid == nil {
            startPositions = Dictionary(uniqueKeysWithValues: touches.map { ($0.id, $0.position) })
            startCentroid = centroid
            startSpread = spread
            startTimestamp = timestamp
            sampleCount = 1
            return nil
        }

        sampleCount += 1
        guard let initialTimestamp = startTimestamp,
              let initialCentroid = startCentroid else {
            return nil
        }

        let deltaX = centroid.x - initialCentroid.x
        let deltaY = centroid.y - initialCentroid.y

        // Immediately disqualify the sequence if the user commits to the wrong direction
        // (prevents end-of-stroke rebound from triggering the opposite action).
        if abs(deltaX) > 0.065 && abs(deltaX) > abs(deltaY) {
            isSequenceDisqualified = true
            return nil
        }
        if !isOverviewVisible && deltaY < -0.045 {
            isSequenceDisqualified = true
            return nil
        }
        if isOverviewVisible && deltaY > 0.045 {
            isSequenceDisqualified = true
            return nil
        }

        // Wait until 3 fingers have been stably on the trackpad (prevents catching the start of a 4-finger gesture)
        guard timestamp - initialTimestamp >= minStableDuration,
              sampleCount >= minThreeFingerSamples else {
            return nil
        }

        // Reject if fingers are pinching/spreading rather than swiping together
        if abs(spread - startSpread) > maxSpreadDeviation {
            return nil
        }

        // Require clear vertical dominance over horizontal motion
        guard abs(deltaY) > abs(deltaX) * verticalDominanceRatio else {
            return nil
        }

        // Check individual finger coherence
        let fingerDeltasY = touches.compactMap { sample -> CGFloat? in
            guard let startPos = startPositions[sample.id] else { return nil }
            return sample.position.y - startPos.y
        }
        guard fingerDeltasY.count == 3 else { return nil }

        if !isOverviewVisible {
            // Only a deliberate 3-finger swipe UP opens Tab Overview
            let allMovedUp = fingerDeltasY.allSatisfy { $0 >= minPerFingerVerticalDelta }
            if deltaY >= minShowVerticalDelta && allMovedUp {
                hasTriggeredInSequence = true
                lastTriggerTimestamp = timestamp
                return .showOverview
            }
        } else {
            // Only a deliberate 3-finger swipe DOWN closes Tab Overview
            let allMovedDown = fingerDeltasY.allSatisfy { $0 <= -minPerFingerVerticalDelta }
            if deltaY <= -minHideVerticalDelta && allMovedDown {
                hasTriggeredInSequence = true
                lastTriggerTimestamp = timestamp
                return .hideOverview
            }
        }

        return nil
    }
}

struct TrackpadTabGestureMonitorView: NSViewRepresentable {
    var isOverviewVisible: Bool = false
    var onShowOverview: (() -> Void)? = nil
    var onHideOverview: (() -> Void)? = nil
    let onToggleOverview: () -> Void

    func makeNSView(context: Context) -> GestureNSView {
        let view = GestureNSView()
        view.updateCallbacks(
            isOverviewVisible: isOverviewVisible,
            onShowOverview: onShowOverview,
            onHideOverview: onHideOverview,
            onToggleOverview: onToggleOverview
        )
        return view
    }

    func updateNSView(_ nsView: GestureNSView, context: Context) {
        nsView.updateCallbacks(
            isOverviewVisible: isOverviewVisible,
            onShowOverview: onShowOverview,
            onHideOverview: onHideOverview,
            onToggleOverview: onToggleOverview
        )
    }

    final class GestureNSView: NSView {
        private var isOverviewVisible = false
        private var onShowOverview: (() -> Void)?
        private var onHideOverview: (() -> Void)?
        private var onToggleOverview: (() -> Void)?
        private var eventMonitor: Any?
        private var recognizer = ThreeFingerSwipeRecognizer()

        func updateCallbacks(
            isOverviewVisible: Bool,
            onShowOverview: (() -> Void)?,
            onHideOverview: (() -> Void)?,
            onToggleOverview: @escaping () -> Void
        ) {
            self.isOverviewVisible = isOverviewVisible
            self.onShowOverview = onShowOverview
            self.onHideOverview = onHideOverview
            self.onToggleOverview = onToggleOverview
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            allowedTouchTypes = [.indirect]
            wantsRestingTouches = false
            if let window {
                if let rootView = window.contentView {
                    enableIndirectTouchesRecursively(in: rootView)
                }
                if eventMonitor == nil {
                    installMonitor()
                }
            } else if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }

        private func enableIndirectTouchesRecursively(in view: NSView) {
            if !view.allowedTouchTypes.contains(.indirect) {
                view.allowedTouchTypes.insert(.indirect)
            }
            for subview in view.subviews {
                enableIndirectTouchesRecursively(in: subview)
            }
        }

        private func enableIndirectTouchesAlongHitChain(at windowPoint: CGPoint, in window: NSWindow) {
            var current = window.contentView?.hitTest(windowPoint) ?? window.contentView
            while let view = current {
                if !view.allowedTouchTypes.contains(.indirect) {
                    view.allowedTouchTypes.insert(.indirect)
                }
                current = view.superview
            }
        }

        private func performAction(_ action: ThreeFingerGestureAction) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            switch action {
            case .showOverview:
                if let onShowOverview {
                    onShowOverview()
                } else if !isOverviewVisible {
                    onToggleOverview?()
                }
            case .hideOverview:
                if let onHideOverview {
                    onHideOverview()
                } else if isOverviewVisible {
                    onToggleOverview?()
                }
            }
        }

        private func installMonitor() {
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.gesture, .keyDown]
            ) { [weak self] event in
                guard let self else { return event }
                let targetWindow = event.window ?? self.window ?? NSApp.keyWindow

                switch event.type {
                case .gesture:
                    if let targetWindow {
                        self.enableIndirectTouchesAlongHitChain(at: event.locationInWindow, in: targetWindow)
                    }
                    let activeTouches = event.touches(matching: .touching, in: nil)
                    let samples = activeTouches.map { touch in
                        TrackpadTouchSample(
                            id: ObjectIdentifier(touch.identity).hashValue,
                            position: touch.normalizedPosition
                        )
                    }
                    if let action = self.recognizer.processFrame(
                        touches: samples,
                        timestamp: event.timestamp,
                        isOverviewVisible: self.isOverviewVisible
                    ) {
                        self.performAction(action)
                    }
                    return event

                case .keyDown:
                    // Allow closing Tab Overview with the Escape key (keyCode 53)
                    if self.isOverviewVisible && event.keyCode == 53 {
                        self.performAction(.hideOverview)
                        return nil
                    }
                    return event

                default:
                    return event
                }
            }
        }
    }
}
