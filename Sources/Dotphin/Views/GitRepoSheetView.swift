import AppKit
import SwiftUI

enum GitRepoSheetTab: String, CaseIterable, Identifiable {
    case diff = "Diferencias (git diff)"
    case commits = "Historial (git log)"
    case commit = "Crear commit"

    var id: String { rawValue }
}

struct GitRepoSheetView: View {
    let viewModel: BrowserViewModel
    let targetItems: [FileItem]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: GitRepoSheetTab = .diff
    @State private var diffText: String = ""
    @State private var commits: [GitCommitEntry] = []
    @State private var commitMessage: String = ""
    @State private var stageAllBeforeCommit: Bool = true
    @State private var statusBanner: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Control de versiones Git")
                            .font(.headline)
                        if let branch = viewModel.gitBranchName {
                            Text(branch)
                                .font(.caption.monospaced().weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(viewModel.currentURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            Picker("Sección", selection: $selectedTab) {
                ForEach(GitRepoSheetTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch selectedTab {
                case .diff:
                    diffSection
                case .commits:
                    commitsSection
                case .commit:
                    commitSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let statusBanner {
                Text(statusBanner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Actualizar") {
                    reloadGitData()
                }
                Spacer()
                Button("Cerrar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 680, height: 480)
        .onAppear {
            reloadGitData()
        }
    }

    private var diffSection: some View {
        Group {
            if diffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "Sin diferencias en el árbol de trabajo",
                    systemImage: "checkmark.seal",
                    description: Text("No hay cambios sin preparar (git diff) para los elementos seleccionados.")
                )
            } else {
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(diffText.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(colorForDiffLine(line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1)
                                .background(backgroundForDiffLine(line))
                        }
                    }
                    .textSelection(.enabled)
                    .padding(6)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
            }
        }
    }

    private var commitsSection: some View {
        Group {
            if commits.isEmpty {
                ContentUnavailableView(
                    "Sin historial de commits",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Este repositorio aún no tiene commits registrados.")
                )
            } else {
                List(commits) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(entry.shortHash)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 68, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.subject)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text("\(entry.author) · \(entry.relativeDate)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.bordered)
            }
        }
    }

    private var commitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mensaje del commit:")
                .font(.subheadline.weight(.medium))
            TextEditor(text: $commitMessage)
                .font(.system(.body, design: .monospaced))
                .frame(height: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )

            Toggle("Preparar automáticamente los elementos modificados/seleccionados (git add)", isOn: $stageAllBeforeCommit)
                .font(.subheadline)

            HStack {
                Spacer()
                Button("Crear commit") {
                    if stageAllBeforeCommit {
                        let toStage = targetItems.isEmpty ? viewModel.items : targetItems
                        viewModel.gitStageItems(toStage)
                    }
                    if viewModel.gitCommit(message: commitMessage) {
                        commitMessage = ""
                        statusBanner = "Commit creado correctamente."
                        reloadGitData()
                        selectedTab = .commits
                    } else {
                        statusBanner = "No se pudo crear el commit (verificá que haya cambios preparados)."
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer()
        }
    }

    private func reloadGitData() {
        diffText = viewModel.gitDiff(for: targetItems)
        commits = viewModel.gitRecentCommits(limit: 30)
    }

    private func colorForDiffLine(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return .green
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return .red
        } else if line.hasPrefix("@@") {
            return .cyan
        }
        return .primary
    }

    private func backgroundForDiffLine(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return Color.green.opacity(0.10)
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return Color.red.opacity(0.10)
        }
        return .clear
    }
}
