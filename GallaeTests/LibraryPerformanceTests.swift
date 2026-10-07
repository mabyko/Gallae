import XCTest
@testable import Gallae

final class LibraryPerformanceTests: XCTestCase {
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
