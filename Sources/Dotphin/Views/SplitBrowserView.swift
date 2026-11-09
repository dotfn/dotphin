import AppKit
import SwiftUI

struct SplitBrowserView: View {
    let tab: Tab
    var onOpenInNewTab: ((URL) -> Void)? = nil
    var onOpenInSplitView: ((URL) -> Void)? = nil
    var onOpenTerminal: ((URL) -> Void)? = nil
    let onFocusPane: (Int) -> Void

    @State private var splitFraction: CGFloat = 0.5
    @State private var dragStartFraction: CGFloat? = nil

    var body: some View {
        GeometryReader { proxy in
            if tab.isSplit, let secondary = tab.secondary {
                let totalWidth = max(360, proxy.size.width)
                let dividerWidth: CGFloat = 7
                let usableWidth = max(350, totalWidth - dividerWidth)
                let leftWidth = max(180, min(usableWidth - 180, usableWidth * splitFraction))
                let rightWidth = max(180, usableWidth - leftWidth)

                HStack(spacing: 0) {
                    paneView(viewModel: tab.primary, index: 0, showSplitHeader: true)
                        .frame(width: leftWidth)
                        .frame(maxHeight: .infinity)

                    splitDivider(usableWidth: usableWidth)

                    paneView(viewModel: secondary, index: 1, showSplitHeader: true)
                        .frame(width: rightWidth)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                paneView(viewModel: tab.primary, index: 0, showSplitHeader: false)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .animation(.snappy(duration: 0.22), value: tab.isSplit)
        .animation(.snappy(duration: 0.18), value: tab.focusedPaneIndex)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(tab.id)
    }

    private func splitDivider(usableWidth: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 7)
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 3, height: 26)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onTapGesture(count: 2) {
            withAnimation(.snappy(duration: 0.2)) {
                splitFraction = 0.5
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStartFraction ?? splitFraction
                    if dragStartFraction == nil {
                        dragStartFraction = start
                    }
                    let delta = value.translation.width / max(1, usableWidth)
                    splitFraction = min(0.8, max(0.2, start + delta))
                }
                .onEnded { _ in
                    dragStartFraction = nil
                }
        )
        .help("Arrastrá para redimensionar la vista dividida (doble clic para centrar 50/50)")
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
                        onNavigate: viewModel.navigate,
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
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onFocusPane(index) })
        .onChange(of: viewModel.currentURL) { _, _ in
            onFocusPane(index)
        }
        .onChange(of: viewModel.selectedIDs) { _, _ in
            onFocusPane(index)
        }
    }
}
