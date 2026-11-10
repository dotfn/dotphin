import SwiftUI

/// KDE Dolphin's `FilterBar` (`src/filterbar/filterbar.cpp`):
/// Provides inline real-time filtering for the current folder with Lock, Case Sensitivity,
/// Filter Mode (`PlainText`, `Glob`, `Regex`), and invalid regex indicator.
struct FilterBarView: View {
    let viewModel: BrowserViewModel
    @FocusState private var isInputFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Lock button (`m_lockButton` in `filterbar.cpp`: "Keep Filter When Changing Folders")
            Button {
                viewModel.isFilterLocked.toggle()
            } label: {
                Image(systemName: viewModel.isFilterLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(viewModel.isFilterLocked ? Color.accentColor : .secondary)
                    .frame(width: 24, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(viewModel.isFilterLocked ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help(String(localized: "Mantener filtro al cambiar de carpeta", bundle: #bundle))
            .accessibilityLabel(String(localized: "Mantener filtro al cambiar de carpeta", bundle: #bundle))

            // Filter text field (`m_filterInput` in `filterbar.cpp`)
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField(
                    String(localized: "Filtrar elementos…", bundle: #bundle),
                    text: Binding(
                        get: { viewModel.filterText },
                        set: { viewModel.filterText = $0 }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isInputFocused)
                .onExitCommand {
                    closeFilterBar()
                }

                if !viewModel.isFilterPatternValid {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .help(String(localized: "Expresión regular no válida", bundle: #bundle))
                }

                if !viewModel.filterText.isEmpty {
                    Button {
                        viewModel.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Limpiar texto de filtro", bundle: #bundle))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(!viewModel.isFilterPatternValid ? Color.orange : Color.primary.opacity(0.14), lineWidth: 1)
            )

            // Case sensitivity toggle (`m_caseSensitiveButton` in `filterbar.cpp`: "Match case")
            Button {
                viewModel.isFilterCaseSensitive.toggle()
            } label: {
                Text(String(localized: "Aa", bundle: #bundle))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(viewModel.isFilterCaseSensitive ? Color.accentColor : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(viewModel.isFilterCaseSensitive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .help(String(localized: "Distinguir mayúsculas y minúsculas", bundle: #bundle))
            .accessibilityLabel(String(localized: "Distinguir mayúsculas y minúsculas", bundle: #bundle))

            // Filter mode picker (`m_filterModeComboBox` in `filterbar.cpp`: Plain Text, Glob Pattern, Regular Expression)
            Picker(
                String(localized: "", bundle: #bundle),
                selection: Binding(
                    get: { viewModel.filterMode },
                    set: { viewModel.filterMode = $0 }
                )
            ) {
                ForEach(FilterPatternMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 150)
            .help(String(localized: "Modo de coincidencia del filtro", bundle: #bundle))

            // Close button (`closeFilterBar()` in `filterbar.cpp`)
            Button {
                closeFilterBar()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Ocultar barra de filtro (Esc)", bundle: #bundle))
            .accessibilityLabel(String(localized: "Ocultar barra de filtro", bundle: #bundle))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
        .onAppear {
            isInputFocused = true
        }
    }

    private func closeFilterBar() {
        viewModel.isFilterBarVisible = false
        viewModel.filterText = ""
        viewModel.isFilterLocked = false
    }
}
