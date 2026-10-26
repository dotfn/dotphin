import SwiftUI

struct SplitBrowserView: View {
    let tab: Tab
    let onFocusPane: (Int) -> Void

    var body: some View {
        Group {
            if tab.isSplit {
                HSplitView {
                    paneView(viewModel: tab.primary, index: 0)
                    paneView(viewModel: tab.secondary!, index: 1)
                }
            } else {
                paneView(viewModel: tab.primary, index: 0)
            }
        }
        .id(tab.id)
    }

    private func paneView(viewModel: BrowserViewModel, index: Int) -> some View {
        let otherPane = index == 0 ? tab.secondary : tab.primary
        return BrowserView(viewModel: viewModel, onFilesMoved: { otherPane?.refresh() })
            .border(tab.focusedPaneIndex == index ? Color.accentColor : Color.clear, width: 2)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { onFocusPane(index) })
            .onChange(of: viewModel.currentURL) { _, _ in
                onFocusPane(index)
            }
    }
}
