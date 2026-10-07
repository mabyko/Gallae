import XCTest
@testable import Gallae

final class LibraryPerformanceTests: XCTestCase {
    @MainActor
    func testBatchRecentRemovalPreservesOrderSelectionAndSharedLibraryCache() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = LibraryStore(defaults: fixture.defaults)
        let repositories = fixture.repositories(["Retained", "Shared", "Removed"])
        for repository in repositories {
            try FileManager.default.createDirectory(at: repository.rootURL, withIntermediateDirectories: true)
            try store.rememberOpenedRepository(repository.rootURL)
        }
        let model = fixture.model
        model.recentRepositories = store.restoreRecentRepositories().map { .init(rootURL: $0.url) }
        model.libraryFolders = [.init(url: fixture.root, repositories: [repositories[1]])]
        model.selectLibrarySource(.recent)
        model.recordFailure("shared cache", at: model.recentRepositories[1].id)
        let removedID = model.recentRepositories[0].id
        model.recordFailure("removed cache", at: removedID)
        let sharedID = model.recentRepositories[1].id
        model.removeRecentRepositories([
            sharedID,
            fixture.root.appending(path: "Placeholder/../Removed")
        ])
        XCTAssertEqual(model.recentRepositories.map(\.name), ["Retained"])
        XCTAssertEqual(model.selectedLibraryRepositoryID?.lastPathComponent, "Retained")
        XCTAssertEqual(store.restoreRecentRepositories().map { $0.url.lastPathComponent }, ["Retained"])
        XCTAssertNil(store.restoreLastWorkspace())
        XCTAssertEqual(model.libraryRepositorySummaryErrors[sharedID], "shared cache")
        XCTAssertNil(model.libraryRepositorySummaryErrors[removedID])
        model.removeRecentRepositories(Set(model.recentRepositories.map(\.id)))
        XCTAssertEqual(model.selectedLibrarySource, .folder(fixture.root))
        XCTAssertEqual(model.selectedLibraryRepositoryID?.lastPathComponent, "Shared")
        XCTAssertEqual(model.libraryRepositorySummaryErrors[sharedID], "shared cache")
    }

    @MainActor
    func testBatchRecentRemovalKeepsUnselectedWorkspaceAndEmptyBatchIsNoOp() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = LibraryStore(defaults: fixture.defaults)
        let repositories = fixture.repositories(["Other", "Workspace"])
        for repository in repositories {
            try FileManager.default.createDirectory(at: repository.rootURL, withIntermediateDirectories: true)
            try store.rememberOpenedRepository(repository.rootURL)
        }
        let before = fixture.defaults.data(forKey: "recentRepositoryBookmarks.v1")
        store.removeRecentRepositories([])
        XCTAssertEqual(fixture.defaults.data(forKey: "recentRepositoryBookmarks.v1"), before)
        store.removeRecentRepositories([repositories[0].rootURL])
        XCTAssertEqual(store.restoreLastWorkspace()?.url.lastPathComponent, "Workspace")
        XCTAssertEqual(store.restoreRecentRepositories().map { $0.url.lastPathComponent }, ["Workspace"])
    }

    @MainActor
    func testBatchRecentRemovalMatchesResolvedBookmarkWhenSavedPathIsStale() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        struct SavedRecord: Encodable { let bookmark: Data; let lastKnownPath: String }
        // A valid bookmark with an older saved path is the state left by a moved directory.
        let data = try PropertyListEncoder().encode([SavedRecord(
            bookmark: fixture.root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
            lastKnownPath: fixture.root.appending(path: "OldLocation").path
        )])
        fixture.defaults.set(data, forKey: "recentRepositoryBookmarks.v1")
        fixture.defaults.set(data, forKey: "lastWorkspaceBookmark.v1")
        let store = LibraryStore(defaults: fixture.defaults)
        store.removeRecentRepositories([fixture.root])
        XCTAssertTrue(store.restoreRecentRepositories().isEmpty)
        XCTAssertNil(store.restoreLastWorkspace())
    }

    func testHierarchyDeduplicatesNormalizedPathsAndIndexesNestedFolders() {
        let root = URL(fileURLWithPath: "/tmp/Library")
        let repositories = ["Group/Team/Beta", "Alpha", "Group/Team/../Team/Beta", "Repo10", "Repo2"]
            .map { RepositoryLocation(rootURL: root.appending(path: $0)) }
        let snapshot = RepositoryHierarchySnapshot(repositories: repositories, relativeTo: root)
        XCTAssertEqual(snapshot.nodes.map(\.name), ["Alpha", "Group", "Repo2", "Repo10"])
        XCTAssertEqual(snapshot.node(matching: root.appending(path: "Group"))?.repositoryCount, 1)
        XCTAssertEqual(snapshot.node(matching: root.appending(path: "Group/Team"))?.children?.map(\.name), ["Beta"])
        XCTAssertEqual(snapshot.node(matching: root.appending(path: "Group/Team/Beta"))?.repository?.name, "Beta")
        XCTAssertNil(snapshot.node(matching: root.appending(path: "Missing")))
    }

    func testNestedRepositorySharesItsFolderNodeWithoutDuplicateIDs() throws {
        let root = URL(fileURLWithPath: "/tmp/Library")
        let repositories = ["Team", "Team/Child", "Team/Child/Grandchild"]
            .map { RepositoryLocation(rootURL: root.appending(path: $0)) }
        for input in [repositories, repositories.reversed().map { $0 }] {
            let snapshot = RepositoryHierarchySnapshot(repositories: input, relativeTo: root)
            XCTAssertEqual(snapshot.nodes.count, 1)
            let team = try XCTUnwrap(snapshot.nodes.first)
            XCTAssertEqual(team.repository?.name, "Team")
            XCTAssertEqual(team.repositoryCount, 3)
            XCTAssertEqual(team.children?.map(\.name), ["Child"])
            XCTAssertEqual(snapshot.node(matching: root.appending(path: "Team/Child"))?.repository?.name, "Child")
            var ids = Set<URL>()
            func checkUniqueIDs(_ nodes: [RepositoryHierarchyNode]) {
                for node in nodes {
                    XCTAssertTrue(ids.insert(node.id).inserted)
                    checkUniqueIDs(node.children ?? [])
                }
            }
            checkUniqueIDs(snapshot.nodes)
            XCTAssertEqual(ids.count, 3)
        }
    }

    @MainActor
    func testHierarchySnapshotReusedForSelectionAndScanStateChanges() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.libraryFolders = [.init(url: fixture.root, repositories: fixture.repositories(["Team/A", "B"]))]
        let original = try XCTUnwrap(model.libraryHierarchies[fixture.root])
        model.selectLibrarySource(.folder(fixture.root))
        model.selectLibraryRepository(fixture.root.appending(path: "B"))
        model.libraryFolders[0].scanState = .scanning
        XCTAssertTrue(model.libraryHierarchies[fixture.root] === original)

        model.libraryFolders[0].repositories.append(contentsOf: fixture.repositories(["Team/C"]))
        let updated = try XCTUnwrap(model.libraryHierarchies[fixture.root])
        XCTAssertFalse(updated === original)
        XCTAssertEqual(updated.node(matching: fixture.root.appending(path: "Team"))?.repositoryCount, 2)
        model.libraryFolders.removeAll()
        XCTAssertNil(model.libraryHierarchies[fixture.root])
    }

    @MainActor
    func testBatchedScanPublishesDuringPauseAndDeduplicatesResults() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.model.addLibraryFolder(at: fixture.root)
        await waitUntil { fixture.feed.count == 1 }
        let stream = fixture.feed.continuation(at: 0)
        stream.yield(.found(fixture.repositories(["First"])[0]))
        await waitUntil { fixture.model.selectedLibraryFolder?.repositories.count == 1 }
        for repository in fixture.repositories(["Team/Beta", "Team/../Team/Beta", "Alpha"]) {
            stream.yield(.found(repository))
        }
        // The stream remains open: a timer must publish this batch without another Git result.
        await waitUntil { fixture.model.selectedLibraryFolder?.repositories.count == 3 }
        XCTAssertEqual(fixture.model.selectedLibraryFolder?.scanState, .scanning)
        stream.finish()
        await waitUntil { fixture.model.selectedLibraryFolder?.scanState == .completed(partialFailureCount: 0) }
        XCTAssertEqual(fixture.model.selectedLibraryFolder?.repositories.map(\.name), ["Alpha", "First", "Beta"])
        XCTAssertEqual(fixture.model.libraryHierarchies[fixture.model.selectedLibraryFolder!.id]?.nodes.map(\.name), ["Alpha", "First", "Team"])
    }

    @MainActor
    func testCancelFlushesPendingResultsAndRejectsOldScanEvents() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.model.addLibraryFolder(at: fixture.root)
        await waitUntil { fixture.feed.count == 1 }
        let old = fixture.feed.continuation(at: 0)
        old.yield(.found(fixture.repositories(["First"])[0]))
        await waitUntil { fixture.model.selectedLibraryFolder?.repositories.count == 1 }
        old.yield(.found(fixture.repositories(["Pending"])[0]))
        // A following observable event acknowledges consumption of the preceding pending result.
        old.yield(.failed(.init(url: fixture.root.appending(path: "Checkpoint"), message: "checkpoint")))
        await waitUntil { fixture.model.selectedLibraryFolder?.firstFailure?.message == "checkpoint" }
        fixture.model.cancelLibraryScan()
        XCTAssertEqual(fixture.model.selectedLibraryFolder?.scanState, .cancelled)
        XCTAssertEqual(fixture.model.selectedLibraryFolder?.repositories.map(\.name), ["First", "Pending"])

        fixture.model.rescanSelectedLibraryFolder()
        await waitUntil { fixture.feed.count == 2 }
        old.yield(.found(fixture.repositories(["Stale"])[0]))
        old.finish()
        let replacement = fixture.feed.continuation(at: 1)
        replacement.yield(.found(fixture.repositories(["Replacement"])[0]))
        replacement.finish()
        await waitUntil { fixture.model.selectedLibraryFolder?.scanState == .completed(partialFailureCount: 0) }
        XCTAssertEqual(fixture.model.selectedLibraryFolder?.repositories.map(\.name), ["Replacement"])
        XCTAssertEqual(fixture.model.selectedLibraryRepositoryID?.lastPathComponent, "Replacement")
    }

    @MainActor
    func testRootFailurePreservesPreviousSnapshotAndPartialFailureReconciles() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.model.libraryFolders = [.init(url: fixture.root, repositories: fixture.repositories(["Existing"]))]
        fixture.model.selectLibrarySource(.folder(fixture.root))
        let original = fixture.model.libraryHierarchies[fixture.root]
        fixture.model.rescanSelectedLibraryFolder()
        await waitUntil { fixture.feed.count == 1 }
        let failed = fixture.feed.continuation(at: 0)
        failed.yield(.failed(.init(url: fixture.root, message: "Unavailable")))
        failed.finish()
        await waitUntil { fixture.model.selectedLibraryFolder?.scanState == .failed("Unavailable") }
        XCTAssertTrue(fixture.model.libraryHierarchies[fixture.root] === original)
        XCTAssertEqual(fixture.model.selectedLibraryFolder?.repositories.map(\.name), ["Existing"])

        fixture.model.rescanSelectedLibraryFolder()
        await waitUntil { fixture.feed.count == 2 }
        let partial = fixture.feed.continuation(at: 1)
        partial.yield(.failed(.init(url: fixture.root.appending(path: "Unreadable"), message: "Denied")))
        partial.yield(.found(fixture.repositories(["Readable"])[0]))
        partial.finish()
        await waitUntil { fixture.model.selectedLibraryFolder?.scanState == .completed(partialFailureCount: 1) }
        XCTAssertEqual(fixture.model.selectedLibraryFolder?.repositories.map(\.name), ["Readable"])
        XCTAssertEqual(fixture.model.selectedLibraryFolder?.firstFailure?.message, "Denied")
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock().now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock().now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(predicate(), "Library update timed out", file: file, line: line)
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let suite: String
        let defaults: UserDefaults
        let feed: ScanFeed
        let model: RepositoryLibraryModel

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "GallaeLibraryTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            suite = "GallaeLibraryTests-\(UUID().uuidString)"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            feed = ScanFeed()
            let feed = feed
            model = RepositoryLibraryModel(store: .init(defaults: defaults), scan: { _ in feed.makeStream() })
        }

        func repositories(_ paths: [String]) -> [RepositoryLocation] {
            paths.map { .init(rootURL: root.appending(path: $0)) }
        }

        func cleanUp() {
            model.cancelLibraryScan()
            feed.finishAll()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// The injected scanner can be invoked from a Sendable closure; protect its test controls.
    private final class ScanFeed: @unchecked Sendable {
        private let lock = NSLock()
        private var continuations: [AsyncStream<RepositoryScanEvent>.Continuation] = []

        var count: Int { lock.withLock { continuations.count } }

        func makeStream() -> AsyncStream<RepositoryScanEvent> {
            let pair = AsyncStream<RepositoryScanEvent>.makeStream()
            lock.withLock { continuations.append(pair.continuation) }
            return pair.stream
        }

        func continuation(at index: Int) -> AsyncStream<RepositoryScanEvent>.Continuation {
            lock.withLock { continuations[index] }
        }

        func finishAll() {
            let all = lock.withLock { continuations }
            all.forEach { $0.finish() }
        }
    }
}
