import Foundation

enum GitFileStatus: Equatable {
    case modified, added, deleted, untracked, renamed
}

struct GitStatusProvider {
    func statuses(in directory: URL) -> [String: GitFileStatus] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path, "status", "--porcelain=v1", "--untracked-files=all"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return [:]
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return [:] }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var result: [String: GitFileStatus] = [:]
        for line in output.split(separator: "\n") {
            guard line.count > 3 else { continue }
            let code = line.prefix(2)
            var path = String(line.dropFirst(3))
            if let arrowRange = path.range(of: " -> ") {
                path = String(path[arrowRange.upperBound...])
            }

            let status: GitFileStatus
            if code.contains("?") {
                status = .untracked
            } else if code.contains("A") {
                status = .added
            } else if code.contains("D") {
                status = .deleted
            } else if code.contains("R") {
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
}
