import Foundation
import Observation

struct ClosedTabRecord: Identifiable, Equatable {
    let id: UUID
    let primaryURL: URL
    let secondaryURL: URL?
    let title: String
}

struct TabSessionEntry: Codable, Equatable {
    let primaryPath: String
    let secondaryPath: String?
    let focusedPaneIndex: Int
}

struct TabSessionSnapshot: Codable, Equatable {
    let entries: [TabSessionEntry]
    let selectedIndex: Int
}

/// Sesiones de pestañas guardadas, una por ventana. Antes había una sola
/// clave para toda la app: con dos ventanas, cada una pisaba a la otra y al
/// reabrir todas restauraban lo mismo.
struct TabSessionStore {
    private struct Entry: Codable {
        var snapshot: TabSessionSnapshot
        var savedAt: Date
    }

    private struct Stored: Codable {
        var sessions: [String: Entry] = [:]
        var lastActiveID: String?
    }

    private static let key = "tabsSessions.v2"
    /// La clave única de antes: sirve de sesión inicial la primera vez.
    private static let legacyKey = "tabsSessionSnapshot.v1"
    /// Las ventanas cerradas no avisan: se conservan solo las sesiones más recientes.
    private static let maxSessions = 12

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func stored() -> Stored {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(Stored.self, from: data) else {
            return Stored()
        }
        return decoded
    }

    func snapshot(for sessionID: String) -> TabSessionSnapshot? {
        stored().sessions[sessionID]?.snapshot
    }

    /// La sesión de la última ventana que se usó.
    func lastActiveSnapshot() -> TabSessionSnapshot? {
        let stored = stored()
        if let id = stored.lastActiveID, let entry = stored.sessions[id] {
            return entry.snapshot
        }
        guard let data = defaults.data(forKey: Self.legacyKey) else { return nil }
        return try? JSONDecoder().decode(TabSessionSnapshot.self, from: data)
    }

    func save(_ snapshot: TabSessionSnapshot, for sessionID: String, now: Date = Date()) {
        var stored = stored()
        stored.sessions[sessionID] = Entry(snapshot: snapshot, savedAt: now)
        stored.lastActiveID = sessionID
        if stored.sessions.count > Self.maxSessions {
            let oldest = stored.sessions.sorted { $0.value.savedAt < $1.value.savedAt }
                .prefix(stored.sessions.count - Self.maxSessions)
            for (id, _) in oldest {
                stored.sessions.removeValue(forKey: id)
            }
        }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Solo la primera ventana del proceso retoma la última sesión; las que
    /// se abren después (⌘N) empiezan de cero.
    @MainActor private static var launchSessionClaimed = false

    @MainActor
    static func claimLaunchSession() -> Bool {
        guard !launchSessionClaimed else { return false }
        launchSessionClaimed = true
        return true
    }
}

@MainActor
@Observable
final class TabsViewModel {
    private(set) var tabs: [Tab]
    private(set) var selectedTabID: Tab.ID
    private(set) var recentlyClosedTabs: [ClosedTabRecord] = []
    private let sessionStore: TabSessionStore
    private let rememberOpenedTabs: Bool
    /// Bajo qué sesión guarda esta ventana sus pestañas.
    private(set) var sessionID: String

    var selectedTab: Tab? { tabs.first { $0.id == selectedTabID } }

    init(
        startingAt url: URL,
        startInSplitView: Bool = false,
        rememberOpenedTabs: Bool = false,
        restoresSession: Bool = true,
        defaults: UserDefaults = .standard
    ) {
        self.sessionStore = TabSessionStore(defaults: defaults)
        self.rememberOpenedTabs = rememberOpenedTabs
        self.sessionID = UUID().uuidString

        // La ventana de la app pasa `restoresSession: false` y retoma la suya
        // con `beginSession` cuando ya sabe cuál es.
        if rememberOpenedTabs, restoresSession,
           let snapshot = sessionStore.lastActiveSnapshot(),
           let restored = Self.makeTabs(from: snapshot, fallback: url) {
            self.tabs = restored.tabs
            self.selectedTabID = restored.selectedTabID
            return
        }

        let secondary = startInSplitView ? BrowserViewModel(startingAt: url, loadsInBackground: true) : nil
        let first = Tab(id: UUID(), primary: BrowserViewModel(startingAt: url, loadsInBackground: true), secondary: secondary, focusedPaneIndex: 0)
        self.tabs = [first]
        self.selectedTabID = first.id
    }

    /// Pasa a guardar bajo `id` y, si esa sesión existe, retoma sus pestañas.
    /// Con `fallingBackToLastSession`, una ventana sin sesión propia retoma la
    /// de la última ventana que se usó.
    func beginSession(id: String, fallingBackToLastSession: Bool) {
        sessionID = id
        guard rememberOpenedTabs else { return }
        let snapshot = sessionStore.snapshot(for: id)
            ?? (fallingBackToLastSession ? sessionStore.lastActiveSnapshot() : nil)
        guard let snapshot,
              let fallback = tabs.first?.primary.currentURL,
              let restored = Self.makeTabs(from: snapshot, fallback: fallback) else { return }
        tabs = restored.tabs
        selectedTabID = restored.selectedTabID
    }

    /// Las pestañas de `snapshot`; una carpeta que ya no existe se cambia por `url`.
    private static func makeTabs(from snapshot: TabSessionSnapshot, fallback url: URL) -> (tabs: [Tab], selectedTabID: Tab.ID)? {
        var restoredTabs: [Tab] = []
        for entry in snapshot.entries {
            var isDir: ObjCBool = false
            let primaryURL: URL
            if FileManager.default.fileExists(atPath: entry.primaryPath, isDirectory: &isDir), isDir.boolValue {
                primaryURL = URL(fileURLWithPath: entry.primaryPath, isDirectory: true)
            } else {
                primaryURL = url
            }
            var secondaryVM: BrowserViewModel? = nil
            if let secPath = entry.secondaryPath,
               FileManager.default.fileExists(atPath: secPath, isDirectory: &isDir), isDir.boolValue {
                secondaryVM = BrowserViewModel(startingAt: URL(fileURLWithPath: secPath, isDirectory: true), loadsInBackground: true)
            }
            restoredTabs.append(
                Tab(
                    id: UUID(),
                    primary: BrowserViewModel(startingAt: primaryURL, loadsInBackground: true),
                    secondary: secondaryVM,
                    focusedPaneIndex: secondaryVM != nil ? min(1, max(0, entry.focusedPaneIndex)) : 0
                )
            )
        }
        guard !restoredTabs.isEmpty else { return nil }
        let clampedIdx = min(restoredTabs.count - 1, max(0, snapshot.selectedIndex))
        return (restoredTabs, restoredTabs[clampedIdx].id)
    }

    /// Saves the current open tabs and split panes of this window (`DolphinMainWindow::slotSaveSession`).
    func saveSessionSnapshot() {
        let entries = tabs.map { tab in
            TabSessionEntry(
                primaryPath: tab.primary.currentURL.path,
                secondaryPath: tab.secondary?.currentURL.path,
                focusedPaneIndex: tab.focusedPaneIndex
            )
        }
        let selectedIdx = tabs.firstIndex(where: { $0.id == selectedTabID }) ?? 0
        let snapshot = TabSessionSnapshot(entries: entries, selectedIndex: selectedIdx)
        sessionStore.save(snapshot, for: sessionID)
    }

    func addTab(startingAt url: URL, afterCurrentTab: Bool = false, splitView: Bool = false) {
        let secondary = splitView ? BrowserViewModel(startingAt: url, loadsInBackground: true) : nil
        let tab = Tab(id: UUID(), primary: BrowserViewModel(startingAt: url, loadsInBackground: true), secondary: secondary, focusedPaneIndex: 0)
        if afterCurrentTab, let currentIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) {
            tabs.insert(tab, at: currentIndex + 1)
        } else {
            tabs.append(tab)
        }
        selectedTabID = tab.id
        saveSessionSnapshot()
    }

    func duplicateTab(_ id: Tab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let source = tabs[index]
        let primaryVM = BrowserViewModel(startingAt: source.primary.currentURL, loadsInBackground: true)
        let secondaryVM = source.secondary.map { BrowserViewModel(startingAt: $0.currentURL, loadsInBackground: true) }
        let duplicated = Tab(
            id: UUID(),
            primary: primaryVM,
            secondary: secondaryVM,
            focusedPaneIndex: source.focusedPaneIndex
        )
        tabs.insert(duplicated, at: index + 1)
        selectedTabID = duplicated.id
        saveSessionSnapshot()
    }

    func closeOtherTabs(keeping id: Tab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        let others = tabs.filter { $0.id != id }.map(\.id)
        for otherID in others {
            closeTab(otherID)
        }
        selectedTabID = id
        saveSessionSnapshot()
    }

    func closeTabsToTheRight(of id: Tab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), index + 1 < tabs.count else { return }
        let rightIDs = tabs[(index + 1)...].map(\.id)
        for rightID in rightIDs {
            closeTab(rightID)
        }
        saveSessionSnapshot()
    }

    func selectNextTab() {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let nextIndex = (index + 1) % tabs.count
        selectedTabID = tabs[nextIndex].id
        saveSessionSnapshot()
    }

    func selectPreviousTab() {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let prevIndex = (index - 1 + tabs.count) % tabs.count
        selectedTabID = tabs[prevIndex].id
        saveSessionSnapshot()
    }

    func selectTab(atIndex index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedTabID = tabs[index].id
        saveSessionSnapshot()
    }

    func closeTab(_ id: Tab.ID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing = tabs[index]
        let rawName = closing.focused.currentURL.lastPathComponent
        let title = (rawName.isEmpty || rawName == "/") ? closing.focused.currentURL.path : rawName
        let record = ClosedTabRecord(
            id: UUID(),
            primaryURL: closing.primary.currentURL,
            secondaryURL: closing.secondary?.currentURL,
            title: title
        )
        recentlyClosedTabs.insert(record, at: 0)
        if recentlyClosedTabs.count > 10 {
            recentlyClosedTabs.removeLast(recentlyClosedTabs.count - 10)
        }

        tabs.remove(at: index)
        closing.primary.close()
        closing.secondary?.close()
        if selectedTabID == id {
            let newIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[newIndex].id
        }
        saveSessionSnapshot()
    }

    /// La ventana se cerró: ningún panel puede seguir esperando una respuesta.
    func closeAllPanes() {
        for tab in tabs {
            tab.primary.close()
            tab.secondary?.close()
        }
    }

    func reopenLastClosedTab() {
        guard let first = recentlyClosedTabs.first else { return }
        reopenClosedTab(first.id)
    }

    func reopenClosedTab(_ recordID: ClosedTabRecord.ID) {
        guard let idx = recentlyClosedTabs.firstIndex(where: { $0.id == recordID }) else { return }
        let record = recentlyClosedTabs.remove(at: idx)
        let primaryVM = BrowserViewModel(startingAt: record.primaryURL, loadsInBackground: true)
        let secondaryVM = record.secondaryURL.map { BrowserViewModel(startingAt: $0, loadsInBackground: true) }
        let restored = Tab(
            id: UUID(),
            primary: primaryVM,
            secondary: secondaryVM,
            focusedPaneIndex: 0
        )
        tabs.append(restored)
        selectedTabID = restored.id
        saveSessionSnapshot()
    }

    func clearRecentlyClosedTabs() {
        recentlyClosedTabs.removeAll()
    }

    func selectTab(_ id: Tab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        saveSessionSnapshot()
    }

    func toggleSplit(for id: Tab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if tabs[index].isSplit {
            tabs[index].secondary?.close()
            tabs[index].secondary = nil
            tabs[index].focusedPaneIndex = 0
        } else {
            tabs[index].secondary = BrowserViewModel(startingAt: tabs[index].primary.currentURL, loadsInBackground: true)
        }
        saveSessionSnapshot()
    }

    func setFocusedPane(_ index: Int, for id: Tab.ID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        guard tabs[tabIndex].isSplit || index == 0 else { return }
        tabs[tabIndex].focusedPaneIndex = index
        saveSessionSnapshot()
    }

    /// Toggles focus between primary and secondary split panes (`DolphinTabWidget::focusInactiveSplitView`).
    func focusOtherPane(for id: Tab.ID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }), tabs[tabIndex].isSplit else { return }
        tabs[tabIndex].focusedPaneIndex = (tabs[tabIndex].focusedPaneIndex == 0) ? 1 : 0
        saveSessionSnapshot()
    }

    /// Opens `url` in the secondary split pane of tab `id` (`DolphinMainWindow::openInSplitView`).
    func openInSplitView(_ url: URL, for id: Tab.ID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        if let secondary = tabs[tabIndex].secondary {
            secondary.navigate(to: url)
        } else {
            tabs[tabIndex].secondary = BrowserViewModel(startingAt: url, loadsInBackground: true)
        }
        tabs[tabIndex].focusedPaneIndex = 1
        saveSessionSnapshot()
    }

    /// Moves the secondary pane of a split view into its own tab and closes split view (`DolphinMainWindow::moveSplitViewToTabs`).
    func moveSplitViewToTabs(for id: Tab.ID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }),
              let secondary = tabs[tabIndex].secondary else { return }
        tabs[tabIndex].secondary = nil
        tabs[tabIndex].focusedPaneIndex = 0
        let newTab = Tab(id: UUID(), primary: secondary, secondary: nil, focusedPaneIndex: 0)
        tabs.insert(newTab, at: tabIndex + 1)
        selectedTabID = newTab.id
        saveSessionSnapshot()
    }

    /// Swaps the left and right panes of a split tab.
    func swapSplitPanes(for id: Tab.ID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }),
              let secondary = tabs[tabIndex].secondary else { return }
        let primary = tabs[tabIndex].primary
        tabs[tabIndex].primary = secondary
        tabs[tabIndex].secondary = primary
        tabs[tabIndex].focusedPaneIndex = (tabs[tabIndex].focusedPaneIndex == 0) ? 1 : 0
        saveSessionSnapshot()
    }
}
