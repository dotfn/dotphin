import XCTest
@testable import DolphinForMacOS

final class GitStatusProviderTests: XCTestCase {
    private var repoDir: URL!

    override func setUpWithError() throws {
        repoDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try run("git", ["init", "-q"], in: repoDir)
        try run("git", ["config", "user.email", "test@example.com"], in: repoDir)
        try run("git", ["config", "user.name", "Test"], in: repoDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoDir)
    }

    private func run(_ bin: String, _ args: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [bin] + args
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
    }

    func test_statuses_onNonGitFolder_returnsEmpty() {
        let notARepo = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: notARepo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: notARepo) }
        XCTAssertEqual(GitStatusProvider().statuses(in: notARepo), [:])
    }

    func test_statuses_detectsUntrackedFile() throws {
        try "x".write(to: repoDir.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let statuses = GitStatusProvider().statuses(in: repoDir)
        XCTAssertEqual(statuses["new.txt"], .untracked)
    }

    func test_statuses_detectsModifiedTrackedFile() throws {
        let fileURL = repoDir.appendingPathComponent("tracked.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        try run("git", ["add", "."], in: repoDir)
        try run("git", ["commit", "-q", "-m", "initial"], in: repoDir)
        try "y".write(to: fileURL, atomically: true, encoding: .utf8)
        let statuses = GitStatusProvider().statuses(in: repoDir)
        XCTAssertEqual(statuses["tracked.txt"], .modified)
    }

    func test_statuses_aggregatesNestedChangeOnContainingFolder() throws {
        let sub = repoDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "x".write(to: sub.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)
        let statuses = GitStatusProvider().statuses(in: repoDir)
        XCTAssertEqual(statuses["sub"], .modified)
    }
}
