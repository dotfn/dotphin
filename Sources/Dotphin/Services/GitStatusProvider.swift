import Foundation

enum GitFileStatus: Equatable, Sendable {
    case modified, added, deleted, untracked, renamed

    var accessibilityDescription: String {
        switch self {
        case .modified: return String(localized: "Modificado", bundle: #bundle)
        case .added: return String(localized: "Agregado", bundle: #bundle)
        case .deleted: return String(localized: "Eliminado", bundle: #bundle)
        case .untracked: return String(localized: "Sin seguimiento", bundle: #bundle)
        case .renamed: return String(localized: "Renombrado", bundle: #bundle)
        }
    }
}

struct GitCommitEntry: Identifiable, Equatable, Sendable {
    let id: String
    let shortHash: String
    let author: String
    let relativeDate: String
    let subject: String
}

struct GitStatusProvider {
    /// Fast filesystem check walking ancestor directories for `.git` without spawning any subprocess (`0.01 ms`).
    static func gitRepositoryRoot(for directory: URL) -> URL? {
        let fm = FileManager.default
        var current = directory.standardizedFileURL
        var depth = 0
        while depth < 64 {
            let dotGit = current.appendingPathComponent(".git").path
            if fm.fileExists(atPath: dotGit) {
                return current
            }
            if current.path == "/" || current.path.isEmpty || current.pathComponents.count <= 1 {
                return nil
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                return nil
            }
            current = parent
            depth += 1
        }
        return nil
    }

    static func hasGitRepositoryInAncestors(of directory: URL) -> Bool {
        gitRepositoryRoot(for: directory) != nil
    }

    func isGitRepository(in directory: URL) -> Bool {
        Self.gitRepositoryRoot(for: directory) != nil
    }

    func currentBranch(in directory: URL) -> String? {
        guard let root = Self.gitRepositoryRoot(for: directory) else { return nil }
        let headURL = root.appendingPathComponent(".git/HEAD")
        if let raw = try? String(contentsOf: headURL, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("ref: refs/heads/") {
                let branch = String(trimmed.dropFirst("ref: refs/heads/".count))
                if !branch.isEmpty {
                    return branch
                }
            } else if trimmed.hasPrefix("ref: ") {
                let refPath = String(trimmed.dropFirst("ref: ".count))
                if let last = refPath.split(separator: "/").last {
                    return String(last)
                }
            } else if trimmed.count >= 7 {
                return String(trimmed.prefix(7))
            }
        }
        if let branch = run(["symbolic-ref", "--short", "HEAD"], in: directory)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !branch.isEmpty {
            return branch
        }
        return run(["rev-parse", "--short", "HEAD"], in: directory)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func stage(urls: [URL], in directory: URL) -> Bool {
        guard !urls.isEmpty else { return false }
        let paths = urls.map(\.path)
        return run(["add", "--"] + paths, in: directory) != nil
    }

    @discardableResult
    func unstage(urls: [URL], in directory: URL) -> Bool {
        guard !urls.isEmpty else { return false }
        let paths = urls.map(\.path)
        if run(["restore", "--staged", "--"] + paths, in: directory) != nil {
            return true
        }
        return run(["reset", "HEAD", "--"] + paths, in: directory) != nil
    }

    @discardableResult
    func discardChanges(urls: [URL], in directory: URL) -> Bool {
        guard !urls.isEmpty else { return false }
        let paths = urls.map(\.path)
        return run(["checkout", "--"] + paths, in: directory) != nil
    }

    @discardableResult
    func commit(message: String, in directory: URL) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return run(["commit", "-m", trimmed], in: directory) != nil
    }

    func diff(for urls: [URL] = [], in directory: URL) -> String {
        let args: [String]
        if urls.isEmpty {
            args = ["diff"]
        } else {
            args = ["diff", "--"] + urls.map(\.path)
        }
        return run(args, in: directory) ?? ""
    }

    func recentCommits(in directory: URL, limit: Int = 25) -> [GitCommitEntry] {
        guard let output = run(
            ["log", "-n", "\(limit)", "--pretty=format:%H%x09%h%x09%an%x09%cr%x09%s"],
            in: directory
        ) else {
            return []
        }
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> GitCommitEntry? in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 5 else { return nil }
                return GitCommitEntry(
                    id: parts[0],
                    shortHash: parts[1],
                    author: parts[2],
                    relativeDate: parts[3],
                    subject: parts[4]
                )
            }
    }
    /// Estados + rama fuera del main actor: `git status` lanza un proceso que en
    /// repos grandes tarda cientos de ms y antes se esperaba en cada navegación.
    @concurrent
    func snapshot(in directory: URL) async -> (statuses: [String: GitFileStatus], branch: String?) {
        let statuses = statuses(in: directory)
        guard !Task.isCancelled else { return ([:], nil) }
        return (statuses, currentBranch(in: directory))
    }

    func statuses(in directory: URL) -> [String: GitFileStatus] {
        guard let repoRoot = Self.gitRepositoryRoot(for: directory) else { return [:] }
        guard let statusOutput = run(["status", "--porcelain=v1", "-z", "--", "."], in: directory) else { return [:] }

        let resolvedRoot = repoRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedDir = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix: String
        if resolvedDir == resolvedRoot {
            prefix = ""
        } else if resolvedDir.hasPrefix(resolvedRoot + "/") {
            prefix = String(resolvedDir.dropFirst(resolvedRoot.count + 1)) + "/"
        } else {
            prefix = (run(["rev-parse", "--show-prefix"], in: directory) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var result: [String: GitFileStatus] = [:]
        let tokens = statusOutput.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var iterator = tokens.makeIterator()
        while let record = iterator.next() {
            guard record.count > 3 else { continue }
            let code = record.prefix(2)
            var path = String(record.dropFirst(3))

            let isRenameOrCopy = code.contains("R") || code.contains("C")
            if isRenameOrCopy {
                _ = iterator.next() // el path viejo viene como su propio token, se descarta
            }

            if !prefix.isEmpty {
                guard path.hasPrefix(prefix) else { continue }
                path.removeFirst(prefix.count)
            }
            if path.hasSuffix("/") {
                path.removeLast()
            }
            guard !path.isEmpty else { continue }

            let status: GitFileStatus
            if code.contains("?") {
                status = .untracked
            } else if code.contains("A") {
                status = .added
            } else if code.contains("D") {
                status = .deleted
            } else if isRenameOrCopy {
                status = .renamed
            } else if code.contains("M") {
                status = .modified
            } else {
                continue
            }

            if let slashIndex = path.firstIndex(of: "/") {
                let folderName = String(path[path.startIndex..<slashIndex])
                if result[folderName] == nil {
                    result[folderName] = .modified
                }
            } else {
                result[path] = status
            }
        }
        return result
    }

    private func run(_ args: [String], in directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + args
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        // Leer el pipe ANTES de esperar a que termine el proceso: si la
        // salida supera el buffer del pipe (~64KB), git se bloquea
        // escribiendo mientras nosotros estaríamos bloqueados esperando a
        // que termine — deadlock. Leer primero drena el pipe en paralelo.
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
