import AppKit
import CryptoKit
import Foundation
import SwiftUI

enum FileDiffLineKind: Equatable, Sendable {
    case unchanged
    case removed
    case added
}

struct FileDiffLine: Identifiable, Equatable, Sendable {
    let id: Int
    let kind: FileDiffLineKind
    let leftLineNumber: Int?
    let rightLineNumber: Int?
    let text: String
}

enum DirectoryComparisonEntryStatus: String, Equatable, Sendable {
    case onlyLeft = "Solo en izquierdo"
    case onlyRight = "Solo en derecho"
    case modified = "Diferente"
    case identical = "Idéntico"
}

struct DirectoryComparisonEntry: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let isDirectory: Bool
    let leftSize: Int64?
    let rightSize: Int64?
    let status: DirectoryComparisonEntryStatus
}

struct FileComparisonReport: Equatable, Sendable {
    let leftURL: URL
    let rightURL: URL
    let isDirectoryComparison: Bool
    let leftSize: Int64?
    let rightSize: Int64?
    let leftModified: Date?
    let rightModified: Date?
    let leftSHA256: String?
    let rightSHA256: String?
    let areIdentical: Bool
    let isTextComparison: Bool
    let diffLines: [FileDiffLine]
    let addedLineCount: Int
    let removedLineCount: Int
    let directoryEntries: [DirectoryComparisonEntry]
}

enum FileComparisonService {
    static func compare(left leftURL: URL, right rightURL: URL) -> FileComparisonReport {
        let fm = FileManager.default
        var leftIsDir: ObjCBool = false
        var rightIsDir: ObjCBool = false
        _ = fm.fileExists(atPath: leftURL.path, isDirectory: &leftIsDir)
        _ = fm.fileExists(atPath: rightURL.path, isDirectory: &rightIsDir)

        let leftAttrs = try? fm.attributesOfItem(atPath: leftURL.path)
        let rightAttrs = try? fm.attributesOfItem(atPath: rightURL.path)
        let leftSize = (leftAttrs?[.size] as? NSNumber)?.int64Value
        let rightSize = (rightAttrs?[.size] as? NSNumber)?.int64Value
        let leftModified = leftAttrs?[.modificationDate] as? Date
        let rightModified = rightAttrs?[.modificationDate] as? Date

        if leftIsDir.boolValue && rightIsDir.boolValue {
            let entries = compareDirectories(left: leftURL, right: rightURL)
            let allIdentical = entries.allSatisfy { $0.status == .identical }
            return FileComparisonReport(
                leftURL: leftURL,
                rightURL: rightURL,
                isDirectoryComparison: true,
                leftSize: nil,
                rightSize: nil,
                leftModified: leftModified,
                rightModified: rightModified,
                leftSHA256: nil,
                rightSHA256: nil,
                areIdentical: allIdentical,
                isTextComparison: false,
                diffLines: [],
                addedLineCount: entries.filter { $0.status == .onlyRight }.count,
                removedLineCount: entries.filter { $0.status == .onlyLeft }.count,
                directoryEntries: entries
            )
        }

        let leftData = try? Data(contentsOf: leftURL, options: .mappedIfSafe)
        let rightData = try? Data(contentsOf: rightURL, options: .mappedIfSafe)
        let leftHash = leftData.map { sha256Hex(of: $0) }
        let rightHash = rightData.map { sha256Hex(of: $0) }
        let identical = (leftHash != nil && leftHash == rightHash && leftSize == rightSize)

        if let lData = leftData, let rData = rightData,
           lData.count <= 2_000_000, rData.count <= 2_000_000,
           !lData.prefix(4096).contains(0), !rData.prefix(4096).contains(0),
           let leftText = String(data: lData, encoding: .utf8),
           let rightText = String(data: rData, encoding: .utf8) {
            let diff = computeLineDiff(left: leftText, right: rightText)
            let added = diff.filter { $0.kind == .added }.count
            let removed = diff.filter { $0.kind == .removed }.count
            return FileComparisonReport(
                leftURL: leftURL,
                rightURL: rightURL,
                isDirectoryComparison: false,
                leftSize: leftSize,
                rightSize: rightSize,
                leftModified: leftModified,
                rightModified: rightModified,
                leftSHA256: leftHash,
                rightSHA256: rightHash,
                areIdentical: identical,
                isTextComparison: true,
                diffLines: diff,
                addedLineCount: added,
                removedLineCount: removed,
                directoryEntries: []
            )
        }

        return FileComparisonReport(
            leftURL: leftURL,
            rightURL: rightURL,
            isDirectoryComparison: false,
            leftSize: leftSize,
            rightSize: rightSize,
            leftModified: leftModified,
            rightModified: rightModified,
            leftSHA256: leftHash,
            rightSHA256: rightHash,
            areIdentical: identical,
            isTextComparison: false,
            diffLines: [],
            addedLineCount: 0,
            removedLineCount: 0,
            directoryEntries: []
        )
    }

    static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func computeLineDiff(left: String, right: String) -> [FileDiffLine] {
        let leftLines = left.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let rightLines = right.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        // Guard against quadratic blowup on huge files
        let m = leftLines.count
        let n = rightLines.count
        if m * n > 400_000 {
            let diff = rightLines.difference(from: leftLines)
            var removedIndices = Set<Int>()
            var addedIndices = Set<Int>()
            for change in diff {
                switch change {
                case .remove(let offset, _, _):
                    removedIndices.insert(offset)
                case .insert(let offset, _, _):
                    addedIndices.insert(offset)
                }
            }
            var result: [FileDiffLine] = []
            var nextID = 0
            var i = 0
            var j = 0
            while i < m || j < n {
                if i < m && removedIndices.contains(i) {
                    result.append(FileDiffLine(id: nextID, kind: .removed, leftLineNumber: i + 1, rightLineNumber: nil, text: leftLines[i]))
                    nextID += 1
                    i += 1
                } else if j < n && addedIndices.contains(j) {
                    result.append(FileDiffLine(id: nextID, kind: .added, leftLineNumber: nil, rightLineNumber: j + 1, text: rightLines[j]))
                    nextID += 1
                    j += 1
                } else if i < m && j < n {
                    result.append(FileDiffLine(id: nextID, kind: .unchanged, leftLineNumber: i + 1, rightLineNumber: j + 1, text: leftLines[i]))
                    nextID += 1
                    i += 1
                    j += 1
                } else if i < m {
                    result.append(FileDiffLine(id: nextID, kind: .removed, leftLineNumber: i + 1, rightLineNumber: nil, text: leftLines[i]))
                    nextID += 1
                    i += 1
                } else if j < n {
                    result.append(FileDiffLine(id: nextID, kind: .added, leftLineNumber: nil, rightLineNumber: j + 1, text: rightLines[j]))
                    nextID += 1
                    j += 1
                }
            }
            return result
        }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                if leftLines[i] == rightLines[j] {
                    dp[i][j] = 1 + dp[i + 1][j + 1]
                } else {
                    dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var result: [FileDiffLine] = []
        var i = 0
        var j = 0
        var nextID = 0
        while i < m && j < n {
            if leftLines[i] == rightLines[j] {
                result.append(FileDiffLine(id: nextID, kind: .unchanged, leftLineNumber: i + 1, rightLineNumber: j + 1, text: leftLines[i]))
                nextID += 1
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                result.append(FileDiffLine(id: nextID, kind: .removed, leftLineNumber: i + 1, rightLineNumber: nil, text: leftLines[i]))
                nextID += 1
                i += 1
            } else {
                result.append(FileDiffLine(id: nextID, kind: .added, leftLineNumber: nil, rightLineNumber: j + 1, text: rightLines[j]))
                nextID += 1
                j += 1
            }
        }
        while i < m {
            result.append(FileDiffLine(id: nextID, kind: .removed, leftLineNumber: i + 1, rightLineNumber: nil, text: leftLines[i]))
            nextID += 1
            i += 1
        }
        while j < n {
            result.append(FileDiffLine(id: nextID, kind: .added, leftLineNumber: nil, rightLineNumber: j + 1, text: rightLines[j]))
            nextID += 1
            j += 1
        }
        return result
    }

    private static func compareDirectories(left: URL, right: URL) -> [DirectoryComparisonEntry] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let leftURLs = (try? fm.contentsOfDirectory(at: left, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let rightURLs = (try? fm.contentsOfDirectory(at: right, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []

        var leftMap: [String: (isDir: Bool, size: Int64?, url: URL)] = [:]
        for u in leftURLs {
            let vals = try? u.resourceValues(forKeys: Set(keys))
            leftMap[u.lastPathComponent] = (vals?.isDirectory ?? false, vals?.fileSize.map(Int64.init), u)
        }
        var rightMap: [String: (isDir: Bool, size: Int64?, url: URL)] = [:]
        for u in rightURLs {
            let vals = try? u.resourceValues(forKeys: Set(keys))
            rightMap[u.lastPathComponent] = (vals?.isDirectory ?? false, vals?.fileSize.map(Int64.init), u)
        }

        let allNames = Set(leftMap.keys).union(rightMap.keys).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }

        return allNames.map { name in
            let l = leftMap[name]
            let r = rightMap[name]
            if let l, let r {
                let same: Bool
                if l.isDir && r.isDir {
                    same = true
                } else if l.isDir != r.isDir || l.size != r.size {
                    same = false
                } else {
                    let lData = try? Data(contentsOf: l.url, options: .mappedIfSafe)
                    let rData = try? Data(contentsOf: r.url, options: .mappedIfSafe)
                    same = (lData == rData)
                }
                return DirectoryComparisonEntry(
                    name: name,
                    isDirectory: l.isDir || r.isDir,
                    leftSize: l.size,
                    rightSize: r.size,
                    status: same ? .identical : .modified
                )
            } else if let l {
                return DirectoryComparisonEntry(
                    name: name,
                    isDirectory: l.isDir,
                    leftSize: l.size,
                    rightSize: nil,
                    status: .onlyLeft
                )
            } else if let r {
                return DirectoryComparisonEntry(
                    name: name,
                    isDirectory: r.isDir,
                    leftSize: nil,
                    rightSize: r.size,
                    status: .onlyRight
                )
            }
            return DirectoryComparisonEntry(name: name, isDirectory: false, leftSize: nil, rightSize: nil, status: .identical)
        }
    }
}

/// KDE Dolphin's "Compare Files" (`compare_files` in `dolphinmainwindow.cpp`), adapted natively for macOS.
struct FileCompareSheetView: View {
    let leftURL: URL
    let rightURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var report: FileComparisonReport?
    @State private var showOnlyChanges: Bool = false

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.left.and.right.doc.vertical")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Comparar: «\(leftURL.lastPathComponent)» vs «\(rightURL.lastPathComponent)»")
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(leftURL.path)  ↔  \(rightURL.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if let report {
                    HStack(spacing: 6) {
                        Image(systemName: report.areIdentical ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        Text(report.areIdentical ? "Idénticos" : "Diferentes")
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        (report.areIdentical ? Color.green : Color.orange).opacity(0.16),
                        in: Capsule()
                    )
                    .foregroundStyle(report.areIdentical ? Color.green : Color.orange)
                }
            }

            Divider()

            if let report {
                HStack(spacing: 16) {
                    fileMetadataCard(title: "Izquierdo", url: report.leftURL, size: report.leftSize, sha256: report.leftSHA256)
                    fileMetadataCard(title: "Derecho", url: report.rightURL, size: report.rightSize, sha256: report.rightSHA256)
                }

                if report.isDirectoryComparison {
                    directoryComparisonTable(report: report)
                } else if report.isTextComparison {
                    HStack {
                        Text("Diferencias de líneas: +\(report.addedLineCount) añadidas, −\(report.removedLineCount) eliminadas")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Mostrar solo líneas modificadas", isOn: $showOnlyChanges)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            let visibleLines = showOnlyChanges
                                ? report.diffLines.filter { $0.kind != .unchanged }
                                : report.diffLines
                            ForEach(visibleLines) { line in
                                diffRow(line)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                } else {
                    ContentUnavailableView(
                        report.areIdentical ? "Archivos binarios idénticos" : "Archivos binarios distintos",
                        systemImage: report.areIdentical ? "checkmark.circle.fill" : "doc.badge.gearshape",
                        description: Text(
                            report.areIdentical
                                ? "Ambos archivos tienen exactamente el mismo tamaño y suma SHA-256."
                                : "Los archivos difieren en tamaño o contenido binario (ver sumas SHA-256 arriba)."
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView("Comparando archivos…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Button("Abrir en FileMerge (opendiff)") {
                    launchOpenDiff()
                }
                .controlSize(.small)

                Spacer()

                Button("Cerrar") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 760, height: 540)
        .task(id: "\(leftURL.path)|\(rightURL.path)") {
            let l = leftURL
            let r = rightURL
            let computed = await Task.detached(priority: .userInitiated) {
                FileComparisonService.compare(left: l, right: r)
            }.value
            guard !Task.isCancelled else { return }
            report = computed
        }
    }

    private func fileMetadataCard(title: String, url: URL, size: Int64?, sha256: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let size {
                    Text(Self.sizeFormatter.string(fromByteCount: size))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(url.lastPathComponent)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let sha256 {
                Text("SHA-256: \(sha256.prefix(16))…\(sha256.suffix(8))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func diffRow(_ line: FileDiffLine) -> some View {
        let prefixChar: String
        let bgColor: Color
        let fgColor: Color
        switch line.kind {
        case .unchanged:
            prefixChar = " "
            bgColor = .clear
            fgColor = .primary.opacity(0.85)
        case .removed:
            prefixChar = "−"
            bgColor = Color.red.opacity(0.14)
            fgColor = Color.red
        case .added:
            prefixChar = "+"
            bgColor = Color.green.opacity(0.14)
            fgColor = Color.green
        }

        return HStack(spacing: 8) {
            Text(line.leftLineNumber.map(String.init) ?? "")
                .frame(width: 32, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(line.rightLineNumber.map(String.init) ?? "")
                .frame(width: 32, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(prefixChar)
                .frame(width: 12, alignment: .center)
                .foregroundStyle(fgColor)
                .fontWeight(.bold)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(fgColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(bgColor, in: RoundedRectangle(cornerRadius: 3))
    }

    private func directoryComparisonTable(report: FileComparisonReport) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(report.directoryEntries) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                            .frame(width: 16)
                        Text(entry.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(entry.status.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusBadgeColor(entry.status).opacity(0.15), in: Capsule())
                            .foregroundStyle(statusBadgeColor(entry.status))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusBadgeColor(_ status: DirectoryComparisonEntryStatus) -> Color {
        switch status {
        case .identical: return .green
        case .modified: return .orange
        case .onlyLeft: return .red
        case .onlyRight: return .blue
        }
    }

    private func launchOpenDiff() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/opendiff")
        process.arguments = [leftURL.path, rightURL.path]
        try? process.run()
    }
}
