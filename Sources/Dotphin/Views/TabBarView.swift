import SwiftUI

struct TabBarView: View {
    let viewModel: TabsViewModel
    var onShowTabOverview: (() -> Void)? = nil
    @Namespace private var tabSelectionNamespace

    var body: some View {
        GeometryReader { proxy in
            let hasOverview = onShowTabOverview != nil
            let hasRecentClosed = !viewModel.recentlyClosedTabs.isEmpty
            let extraRecentReserve: CGFloat = hasRecentClosed ? (28 + 6) : 0
            // 24pt horizontal padding (12*2) + 28pt (+) button + 6pt gap + optional overview + optional recent tabs
            let trailingButtonsReserve: CGFloat = (hasOverview ? (24 + 28 + 6 + 28 + 6) : (24 + 28 + 6)) + extraRecentReserve
            let availableForCapsule = max(120, proxy.size.width - trailingButtonsReserve)
            let tabCount = max(1, viewModel.tabs.count)
            let capsuleInternalOverhead: CGFloat = 4 + CGFloat(max(0, tabCount - 1)) * 2
            let rawTabWidth = floor((availableForCapsule - capsuleInternalOverhead) / CGFloat(tabCount))
            // Intelligently adapt: fill available width up to 240pt per tab, shrink down to 92pt before scrolling
            let minComfortableWidth: CGFloat = 92
            let maxTabWidth: CGFloat = 240
            let needsScrolling = rawTabWidth < minComfortableWidth
            let computedTabWidth = min(maxTabWidth, max(minComfortableWidth, rawTabWidth))

            HStack(spacing: 6) {
                if needsScrolling {
                    ScrollView(.horizontal, showsIndicators: false) {
                        tabsCapsule(tabWidth: computedTabWidth, fillWidth: false)
                    }
                    .frame(maxWidth: availableForCapsule)
                } else {
                    tabsCapsule(tabWidth: nil, fillWidth: true)
                        .frame(maxWidth: .infinity)
                }

                addTabButton
                    .fixedSize()
                    .layoutPriority(1)

                if hasRecentClosed {
                    recentlyClosedTabsMenuButton
                        .fixedSize()
                        .layoutPriority(1)
                }

                if let onShowTabOverview {
                    overviewButton(action: onShowTabOverview)
                        .fixedSize()
                        .layoutPriority(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: proxy.size.width, height: 28, alignment: .leading)
        }
        .frame(height: 28)
    }

    private func tabsCapsule(tabWidth: CGFloat?, fillWidth: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(viewModel.tabs) { tab in
                let isSelected = tab.id == viewModel.selectedTabID
                let rawName = tab.focused.currentURL.lastPathComponent
                let title = (rawName.isEmpty || rawName == "/")
                    ? (FileManager.default.displayName(atPath: tab.focused.currentURL.path).isEmpty
                        ? "/"
                        : FileManager.default.displayName(atPath: tab.focused.currentURL.path))
                    : rawName

                TabPillItem(
                    title: title,
                    isSelected: isSelected,
                    canClose: viewModel.tabs.count > 1,
                    fixedWidth: tabWidth,
                    fillWidth: fillWidth,
                    namespace: tabSelectionNamespace,
                    onSelect: {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.selectTab(tab.id)
                        }
                    },
                    onClose: {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.closeTab(tab.id)
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                    removal: .scale(scale: 0.92).combined(with: .opacity)
                ))
                .contextMenu {
                    Button("Duplicar pestaña") {
                        viewModel.duplicateTab(tab.id)
                    }
                    Button("Recargar pestaña") {
                        tab.primary.refresh()
                        tab.secondary?.refresh()
                    }
                    Button("Copiar ubicación") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tab.focused.currentURL.path, forType: .string)
                    }
                    Divider()
                    Button("Cerrar otras pestañas") {
                        viewModel.closeOtherTabs(keeping: tab.id)
                    }
                    .disabled(viewModel.tabs.count <= 1)

                    if let idx = viewModel.tabs.firstIndex(where: { $0.id == tab.id }),
                       idx + 1 < viewModel.tabs.count {
                        Button("Cerrar pestañas a la derecha") {
                            viewModel.closeTabsToTheRight(of: tab.id)
                        }
                    }

                    Button("Cerrar pestaña", role: .destructive) {
                        viewModel.closeTab(tab.id)
                    }
                    .disabled(viewModel.tabs.count <= 1)
                }
            }
        }
        .padding(2)
        .frame(maxWidth: fillWidth ? .infinity : nil)
        .animation(.snappy(duration: 0.22), value: viewModel.tabs.map(\.id))
        .animation(.snappy(duration: 0.22), value: viewModel.selectedTabID)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
        )
    }

    private var addTabButton: some View {
        Button {
            let url = viewModel.selectedTab?.focused.currentURL
                ?? viewModel.selectedTab?.primary.currentURL
                ?? FileManager.default.homeDirectoryForCurrentUser
            withAnimation(.snappy(duration: 0.22)) {
                viewModel.addTab(startingAt: url)
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Nueva pestaña (⌘T)")
        .accessibilityLabel("Nueva pestaña")
    }

    private var recentlyClosedTabsMenuButton: some View {
        Menu {
            Button("Vaciar pestañas cerradas recientemente") {
                viewModel.clearRecentlyClosedTabs()
            }
            Divider()
            ForEach(viewModel.recentlyClosedTabs) { record in
                Button {
                    viewModel.reopenClosedTab(record.id)
                } label: {
                    Label(record.title, systemImage: "folder")
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
                )
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26, height: 26)
        .help("Pestañas cerradas recientemente (⇧⌘T)")
        .accessibilityLabel("Pestañas cerradas recientemente")
    }

    private func overviewButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Ver todas las pestañas (Gesto de 3 dedos o ⇧⌘\\)")
        .accessibilityLabel("Ver todas las pestañas")
    }
}

private struct TabPillItem: View {
    let title: String
    let isSelected: Bool
    let canClose: Bool
    let fixedWidth: CGFloat?
    let fillWidth: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if canClose && isHovered {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .help("Cerrar pestaña")
                    .accessibilityLabel("Cerrar pestaña")
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 16, height: 16)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .frame(width: 16, height: 16)
            .animation(.easeOut(duration: 0.14), value: isHovered)

            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(width: fixedWidth, height: 24)
        .frame(maxWidth: fillWidth ? .infinity : nil)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .matchedGeometryEffect(id: "activeTabPill", in: namespace)
            } else if isHovered {
                Capsule()
                    .fill(Color.primary.opacity(0.05))
            }
        }
        .overlay {
            if isSelected {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                    .matchedGeometryEffect(id: "activeTabPillBorder", in: namespace)
            }
        }
        .contentShape(Capsule())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .onTapGesture(perform: onSelect)
    }
}
