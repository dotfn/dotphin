import Foundation
import Observation

@Observable
final class BrowserViewModel {
    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    private(set) var error: DirectoryReadError?

    private let reader: DirectoryReader

    init(startingAt url: URL, reader: DirectoryReader = DirectoryReader()) {
        self.currentURL = url
        self.reader = reader
        load(url)
    }

    func navigate(to url: URL) {
        currentURL = url
        load(url)
    }

    func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent.path != currentURL.path else { return }
        navigate(to: parent)
    }

    func refresh() {
        load(currentURL)
    }

    private func load(_ url: URL) {
        do {
            items = try reader.contents(of: url)
            error = nil
        } catch let readError as DirectoryReadError {
            items = []
            error = readError
        } catch {
            items = []
            self.error = .other(error.localizedDescription)
        }
    }
}
