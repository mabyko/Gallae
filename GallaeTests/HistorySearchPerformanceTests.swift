import XCTest
@testable import Gallae

final class HistorySearchPerformanceTests: XCTestCase {
    @MainActor
    func testSearchSnapshotReusesResultAcrossSelectionChanges() throws {
        let suite = "GallaeHistorySearchTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: .init(defaults: defaults))
        model.historyState = .loaded(RepositoryHistory(commits: [commit("a"), commit("b")]))
        let initial = model.historySearchResults(matching: "developer")
        for id in ["a", "b", "a"] {
            model.selectedHistoryCommitID = id
            XCTAssertTrue(model.historySearchResults(matching: "developer") === initial)
        }
        XCTAssertEqual(initial.ids, ["a", "b"])
        XCTAssertEqual(initial.positions, ["a": 0, "b": 1])
    }

    @MainActor
    func testNewHistoryWithSameIDsInvalidatesSearchAndReleasesOldResult() throws {
        let suite = "GallaeHistorySearchTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: .init(defaults: defaults))
        model.historyState = .loaded(RepositoryHistory(commits: [commit("a", subject: "Old message")]))
        weak var prior: RepositoryHistorySearchResults?
        do {
            let result = model.historySearchResults(matching: "old")
            XCTAssertEqual(result.ids, ["a"])
            prior = result
        }
        XCTAssertNotNil(prior)
        model.historyState = .loaded(RepositoryHistory(commits: [commit("a", subject: "New message")]))
        XCTAssertNil(prior)
        XCTAssertTrue(model.historySearchResults(matching: "old").ids.isEmpty)
        XCTAssertEqual(model.historySearchResults(matching: "new").ids, ["a"])
        model.historyState = .notLoaded
        XCTAssertTrue(model.historySearchResults(matching: "new").ids.isEmpty)
    }

    @MainActor
    func testQueryChangesPreserveANDSearchAndReferenceMatching() {
        let commits = [commit("a", subject: "Fix navigation"), commit("b", subject: "Update storage")]
        let cache = RepositoryHistorySearchCache(commits: commits)
        let all = cache.results(matching: "  ")
        XCTAssertEqual(all.ids, ["a", "b"])
        XCTAssertTrue(cache.results(matching: "  ") === all)
        let filtered = cache.results(matching: "NAVIGATION developer")
        XCTAssertEqual(filtered.ids, ["a"])
        XCTAssertEqual(filtered.positions, ["a": 0])
        XCTAssertTrue(cache.results(matching: "NAVIGATION developer") === filtered)
        XCTAssertEqual(cache.results(matching: "feature/search").ids, ["a", "b"])
        XCTAssertTrue(cache.results(matching: "missing").ids.isEmpty)
    }

    private func commit(_ id: String, subject: String = "Fix navigation") -> RepositoryHistory.Commit {
        .init(id: id, parentIDs: [], authorName: "Developer", authorEmail: "developer@example.com",
              committedAt: Date(timeIntervalSince1970: 0), subject: subject, body: "Description",
              references: [.init(name: "feature/search", kind: .branch)])
    }
}
