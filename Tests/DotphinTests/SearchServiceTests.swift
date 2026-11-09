import XCTest
@testable import Dotphin

final class SearchServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_search_withEmptyQuery_returnsEmptyWithoutScanning() {
        XCTAssertEqual(SearchService().search(for: "", in: tempDir), [])
    }

    func test_search_findsMatchInNestedSubfolder() throws {
        let sub = tempDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "x".write(to: sub.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)
        let results = SearchService().search(for: "report", in: tempDir)
        XCTAssertEqual(results.map(\.name), ["Report.txt"])
    }

    func test_search_capsAtMaxResults() throws {
        for i in 0..<10 {
            try "x".write(to: tempDir.appendingPathComponent("match\(i).txt"), atomically: true, encoding: .utf8)
        }
        let results = SearchService().search(for: "match", in: tempDir, maxResults: 3)
        XCTAssertEqual(results.count, 3)
    }
}
