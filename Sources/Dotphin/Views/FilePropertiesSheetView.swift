import AppKit
import CryptoKit
import SwiftUI

struct FileChecksums: Equatable, Sendable {
    let md5: String
    let sha1: String
    let sha256: String

    func matches(_ candidate: String) -> String? {
        let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        if normalized == sha256.lowercased() { return "SHA-256" }
        if normalized == sha1.lowercased() { return "SHA-1" }
        if normalized == md5.lowercased() { return "MD5" }
        return nil
    }
}

struct FilePropertiesSheetView: View {
    let url: URL
    var onNavigateToSymlinkTarget: ((URL) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    enum PropertiesTab: String, CaseIterable, Identifiable {
        case general
        case checksums
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return String(localized: "General y permisos", bundle: #bundle)
            case .checksums: return String(localized: "Sumas de verificación", bundle: #bundle)
            }
        }
    }

    @State private var selectedTab: PropertiesTab = .general
    @State private var posixPermissions: Int?
    @State private var ownerName: String = "—"
    @State private var groupName: String = "—"
    @State private var creationDateText: String = "—"
    @State private var modifiedDateText: String = "—"
    @State private var calculatedSizeText: String = String(localized: "Calculando…", bundle: #bundle)
    @State private var isDirectory: Bool = false
    @State private var isSymbolicLink: Bool = false
    @State private var symlinkDestination: String?
    @State private var permissionError: String?
    @State private var applyPermissionsRecursively = false
    @State private var checksums: FileChecksums?
    @State private var isComputingChecksums: Bool = false
    @State private var verificationInput: String = ""

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            if !isDirectory {
                Picker(String(localized: "", bundle: #bundle), selection: $selectedTab) {
                    ForEach(PropertiesTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            if selectedTab == .general || isDirectory {
                generalAndPermissionsContent
            } else {
                checksumsContent
            }

            Spacer(minLength: 0)

            HStack {
                Button(String(localized: "Mostrar en Finder", bundle: #bundle)) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                if isSymbolicLink, let onNavigateToSymlinkTarget,
                   let resolved = FileOperationsService().resolvedSymbolicLinkTarget(of: url) {
                    Button(String(localized: "Ir al destino del enlace", bundle: #bundle)) {
                        dismiss()
                        onNavigateToSymlinkTarget(resolved)
                    }
                }
                Spacer()
                Button(String(localized: "Cerrar", bundle: #bundle)) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 460, height: isDirectory ? 400 : 450)
        .task(id: url) {
            loadMetadata()
            let targetURL = url
            let totalBytes = await Task.detached(priority: .utility) {
                Self.computeTotalSize(of: targetURL)
            }.value
            guard !Task.isCancelled else { return }
            if let totalBytes {
                calculatedSizeText = "\(Self.byteFormatter.string(fromByteCount: totalBytes)) (\(totalBytes.formatted()) B)"
            } else {
                calculatedSizeText = "—"
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .checksums && checksums == nil && !isDirectory {
                computeChecksumsAsync()
            }
        }
    }

    private var generalAndPermissionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    Text(String(localized: "Tipo:", bundle: #bundle))
                        .foregroundStyle(.secondary)
                    Text(isSymbolicLink ? String(localized: "Enlace simbólico", bundle: #bundle) : (isDirectory ? String(localized: "Carpeta", bundle: #bundle) : String(localized: "Archivo", bundle: #bundle)))
                }
                if let symlinkDestination {
                    GridRow {
                        Text(String(localized: "Apunta a:", bundle: #bundle))
                            .foregroundStyle(.secondary)
                        Text(symlinkDestination)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                GridRow {
                    Text(String(localized: "Tamaño:", bundle: #bundle))
                        .foregroundStyle(.secondary)
                    Text(calculatedSizeText)
                        .monospacedDigit()
                }
                GridRow {
                    Text(String(localized: "Creado:", bundle: #bundle))
                        .foregroundStyle(.secondary)
                    Text(creationDateText)
                }
                GridRow {
                    Text(String(localized: "Modificado:", bundle: #bundle))
                        .foregroundStyle(.secondary)
                    Text(modifiedDateText)
                }
                GridRow {
                    Text(String(localized: "Propietario:", bundle: #bundle))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "\(ownerName) : \(groupName)", bundle: #bundle))
                }
                if let perms = posixPermissions {
                    GridRow {
                        Text(String(localized: "Permisos:", bundle: #bundle))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text(Self.symbolicPermissions(perms))
                                .font(.system(.body, design: .monospaced))
                            Text(String(format: "(%03o)", perms & 0o777))
                                .foregroundStyle(.secondary)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            .font(.subheadline)

            if let perms = posixPermissions {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Permisos de acceso POSIX", bundle: #bundle))
                        .font(.subheadline.weight(.semibold))

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        GridRow {
                            Text(String(localized: "Rol", bundle: #bundle))
                                .foregroundStyle(.secondary)
                            Text(String(localized: "Lectura (r)", bundle: #bundle))
                                .foregroundStyle(.secondary)
                            Text(String(localized: "Escritura (w)", bundle: #bundle))
                                .foregroundStyle(.secondary)
                            Text(String(localized: "Ejecución (x)", bundle: #bundle))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption.weight(.medium))

                        permissionRow(label: String(localized: "Propietario", bundle: #bundle), perms: perms, rBit: 0o400, wBit: 0o200, xBit: 0o100)
                        permissionRow(label: String(localized: "Grupo", bundle: #bundle), perms: perms, rBit: 0o040, wBit: 0o020, xBit: 0o010)
                        permissionRow(label: String(localized: "Otros", bundle: #bundle), perms: perms, rBit: 0o004, wBit: 0o002, xBit: 0o001)
                    }
                    .font(.caption)

                    if isDirectory {
                        Toggle(String(localized: "Aplicar a subcarpetas y su contenido", bundle: #bundle), isOn: $applyPermissionsRecursively)
                            .font(.caption)
                        if applyPermissionsRecursively {
                            Text(String(localized: "Se aplicará el mismo modo a todo el contenido, incluyendo el bit de ejecución en archivos.", bundle: #bundle))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let permissionError {
                        Text(permissionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func permissionRow(label: String, perms: Int, rBit: Int, wBit: Int, xBit: Int) -> some View {
        GridRow {
            Text(label)
            Toggle(String(localized: "", bundle: #bundle), isOn: Binding(get: { (perms & rBit) != 0 }, set: { _ in togglePermissionBit(rBit) }))
                .labelsHidden()
            Toggle(String(localized: "", bundle: #bundle), isOn: Binding(get: { (perms & wBit) != 0 }, set: { _ in togglePermissionBit(wBit) }))
                .labelsHidden()
            Toggle(String(localized: "", bundle: #bundle), isOn: Binding(get: { (perms & xBit) != 0 }, set: { _ in togglePermissionBit(xBit) }))
                .labelsHidden()
        }
    }

    private var checksumsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isComputingChecksums {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Calculando sumas SHA-256, SHA-1 y MD5…", bundle: #bundle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            } else if let checksums {
                checksumRow(title: "SHA-256", value: checksums.sha256)
                checksumRow(title: "SHA-1", value: checksums.sha1)
                checksumRow(title: "MD5", value: checksums.md5)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Verificar suma de control (pegar hash esperado):", bundle: #bundle))
                        .font(.caption.weight(.semibold))
                    TextField(String(localized: "Pegar SHA-256, SHA-1 o MD5 para comparar…", bundle: #bundle), text: $verificationInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))

                    let trimmed = verificationInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if let matchedAlgo = checksums.matches(trimmed) {
                            Label(String(localized: "Coincide exactamente con \(matchedAlgo)", bundle: #bundle), systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        } else {
                            Label(String(localized: "No coincide con ninguna suma calculada", bundle: #bundle), systemImage: "xmark.octagon.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                }
            } else {
                Button(String(localized: "Calcular sumas de verificación", bundle: #bundle)) {
                    computeChecksumsAsync()
                }
            }
        }
    }

    private func checksumRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Label(String(localized: "Copiar", bundle: #bundle), systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func computeChecksumsAsync() {
        isComputingChecksums = true
        let targetURL = url
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.computeChecksums(for: targetURL)
            }.value
            await MainActor.run {
                self.checksums = result
                self.isComputingChecksums = false
            }
        }
    }

    nonisolated static func computeChecksums(for url: URL) -> FileChecksums? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sha1 = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return FileChecksums(md5: md5, sha1: sha1, sha256: sha256)
    }

    private func loadMetadata() {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: url.path) {
            posixPermissions = (attrs[.posixPermissions] as? NSNumber)?.intValue
            ownerName = (attrs[.ownerAccountName] as? String) ?? "—"
            groupName = (attrs[.groupOwnerAccountName] as? String) ?? "—"
            if let created = attrs[.creationDate] as? Date {
                creationDateText = Self.dateFormatter.string(from: created)
            }
            if let modified = attrs[.modificationDate] as? Date {
                modifiedDateText = Self.dateFormatter.string(from: modified)
            }
            let fileType = attrs[.type] as? FileAttributeType
            isDirectory = (fileType == .typeDirectory)
            isSymbolicLink = (fileType == .typeSymbolicLink)
        }
        if isSymbolicLink {
            symlinkDestination = try? fm.destinationOfSymbolicLink(atPath: url.path)
        }
    }

    private func togglePermissionBit(_ bit: Int) {
        guard let current = posixPermissions else { return }
        let updated = (current & bit) != 0 ? (current & ~bit) : (current | bit)
        if isDirectory && applyPermissionsRecursively {
            let failures = Self.applyPermissionsRecursively(updated, under: url)
            if !failures.contains(url) {
                posixPermissions = updated
            }
            permissionError = failures.isEmpty
                ? nil
                : String(localized: "No se pudo aplicar a \(failures.count) elemento(s); el resto quedó con el modo nuevo.", bundle: #bundle)
            return
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: updated], ofItemAtPath: url.path)
            posixPermissions = updated
            permissionError = nil
        } catch {
            permissionError = error.localizedDescription
        }
    }

    /// Applies `mode` to `url` and every descendant. Mirrors the exact POSIX mode, including
    /// the execute bit on regular files (unlike Finder's simplified "Apply to enclosed items").
    /// Symlinks are skipped: chmod follows them, so they'd change files outside the folder.
    /// The whole tree is listed before anything changes, then applied deepest-first with `url`
    /// last, so removing a folder's x/r bits can't make the rest of the tree unreachable.
    /// Returns every item that couldn't be listed or changed, `url` included.
    @discardableResult
    nonisolated static func applyPermissionsRecursively(_ mode: Int, under url: URL) -> [URL] {
        var failures: [URL] = []
        var targets: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            errorHandler: { failedURL, _ in
                failures.append(failedURL)
                return true
            }
        )
        while let childURL = enumerator?.nextObject() as? URL {
            if (try? childURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                continue
            }
            targets.append(childURL)
        }
        for target in targets.reversed() + [url] {
            do {
                try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path)
            } catch {
                failures.append(target)
            }
        }
        return failures
    }

    nonisolated static func symbolicPermissions(_ mode: Int) -> String {
        let chars: [(Int, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x"),
        ]
        return String(chars.map { (mode & $0.0) != 0 ? $0.1 : "-" })
    }

    nonisolated static func computeTotalSize(of url: URL) -> Int64? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return nil }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
