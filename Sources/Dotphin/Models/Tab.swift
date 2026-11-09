import Foundation

struct Tab: Identifiable {
    let id: UUID
    var primary: BrowserViewModel
    var secondary: BrowserViewModel?
    var focusedPaneIndex: Int

    var isSplit: Bool { secondary != nil }

    var focused: BrowserViewModel {
        focusedPaneIndex == 1 ? (secondary ?? primary) : primary
    }
}
