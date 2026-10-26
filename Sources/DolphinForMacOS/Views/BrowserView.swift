import SwiftUI

struct BrowserView: View {
    let viewModel: BrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(url: viewModel.currentURL, onNavigate: viewModel.navigate)
                .padding(8)

            Divider()

            if let error = viewModel.error {
                switch error {
                case .permissionDenied(let url):
                    PermissionDeniedView(url: url)
                case .notFound(let url):
                    Text("No se encontró \(url.path)")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .other(let message):
                    Text(message)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                FileListView(items: viewModel.items) { item in
                    if item.isDirectory {
                        viewModel.navigate(to: item.url)
                    }
                }
            }
        }
    }
}
