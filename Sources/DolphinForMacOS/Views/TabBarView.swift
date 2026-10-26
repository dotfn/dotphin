import SwiftUI

struct TabBarView: View {
    let viewModel: TabsViewModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(viewModel.tabs) { tab in
                HStack(spacing: 4) {
                    Text(tab.focused.currentURL.lastPathComponent)
                        .lineLimit(1)
                    Button {
                        viewModel.closeTab(tab.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("Cerrar pestaña")
                    .accessibilityLabel("Cerrar pestaña")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    tab.id == viewModel.selectedTabID ? Color.accentColor.opacity(0.15) : Color.clear
                )
                .onTapGesture {
                    viewModel.selectTab(tab.id)
                }
            }

            Button {
                let url = viewModel.selectedTab?.primary.currentURL ?? FileManager.default.homeDirectoryForCurrentUser
                viewModel.addTab(startingAt: url)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("Nueva pestaña")
            .accessibilityLabel("Nueva pestaña")

            Spacer()
        }
        .padding(.horizontal, 8)
    }
}
