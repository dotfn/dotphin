import Foundation

enum GitFileStatus: Equatable {
    case modified, added, deleted, untracked, renamed

    var accessibilityDescription: String {
        switch self {
        case .modified: return "Modificado"
        case .added: return "Agregado"
        case .deleted: return "Eliminado"
        case .untracked: return "Sin seguimiento"
        case .renamed: return "Renombrado"
        }
    }
}

struct GitStatusProvider {
    func statuses(in directory: URL) -> [String: GitFileStatus] {
        guard let prefixOutput = run(["rev-parse", "--show-prefix"], in: directory) else { return [:] }
        guard let statusOutput = run(["status", "--porcelain=v1", "-z", "--", "."], in: directory) else { return [:] }

        let prefix = prefixOutput.trimmingCharacters(in: .whitespacesAndNewlines)

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
