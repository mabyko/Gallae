import XCTest
@testable import Gallae

final class ChangeHierarchyPerformanceTests: XCTestCase {
    @MainActor
    func testRepeatedRenderingReusesTreeAndStatusChangesInvalidateIt() {
        var builds = 0
        let cache = RepositoryChangeHierarchyCache { changes in
            builds += 1
            return RepositoryChangeHierarchyNode.make(changes)
        }
        let changes = (0..<13_000).map { index in
            RepositorySummary.Change(path: "files/file-\(index).txt", originalPath: nil,
                                     staged: nil, unstaged: .untracked, isConflicted: false)
        }
        let first = cache.nodes(for: changes)
        for _ in 0..<20 {
            XCTAssertEqual(cache.nodes(for: changes).count, first.count)
        }
        XCTAssertEqual(builds, 1, "Selection/focus redraws must not rebuild all 13,000 paths")
        XCTAssertEqual(first.first?.changeCount, 13_000)

        var staged = changes
        staged[0] = RepositorySummary.Change(path: changes[0].path, originalPath: nil,
                                              staged: .added, unstaged: nil, isConflicted: false)
        let updated = cache.nodes(for: staged)
        XCTAssertEqual(builds, 2)
        XCTAssertEqual(updated.first?.children?.first?.change?.staged, .added)
        XCTAssertEqual(updated.first?.changeCount, 13_000)
        XCTAssertTrue(cache.nodes(for: []).isEmpty)
        XCTAssertEqual(builds, 3)
    }
}
