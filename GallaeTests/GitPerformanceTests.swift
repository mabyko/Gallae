import XCTest
@testable import Gallae

final class GitPerformanceTests: XCTestCase {
    func testOutputLimitStopsProducerBeforeItFinishes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appending(path: "finished")
        let result = try CommandRunner.run(
            ["-c", "i=0; while [ $i -lt 10000 ]; do printf '0123456789abcdef'; i=$((i+1)); done; : > \"$1\"", "producer", marker.path],
            executableURL: URL(fileURLWithPath: "/bin/sh"), maximumOutputBytes: 32
        )
        XCTAssertTrue(result.standardOutputExceededLimit)
        XCTAssertTrue(result.standardOutput.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testLimitedReadStopsProducerThatIgnoresTermination() throws {
        let start = ContinuousClock.now
        let result = try CommandRunner.run(
            ["-c", "trap '' TERM PIPE; while :; do printf '0123456789abcdef' 2>/dev/null || :; done"],
            executableURL: URL(fileURLWithPath: "/bin/sh"), maximumOutputBytes: 32
        )
        XCTAssertTrue(result.standardOutputExceededLimit)
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
    }

    func testExactLimitAndRealFailureRemainDistinct() throws {
        let shell = URL(fileURLWithPath: "/bin/sh")
        let exact = try CommandRunner.run(["-c", "printf 1234"], executableURL: shell, maximumOutputBytes: 4)
        XCTAssertEqual(exact.standardOutput, Data("1234".utf8))
        XCTAssertFalse(exact.standardOutputExceededLimit)
        XCTAssertEqual(exact.status, 0)
        let failed = try CommandRunner.run(["-c", "printf error >&2; exit 7"], executableURL: shell, maximumOutputBytes: 4)
        XCTAssertEqual(failed.status, 7)
        XCTAssertEqual(failed.standardError, "error")
        XCTAssertFalse(failed.standardOutputExceededLimit)
    }

    func testLargeStderrDoesNotBlockLimitedStdout() throws {
        let result = try CommandRunner.run(
            ["-c", "i=0; while [ $i -lt 10000 ]; do printf '0123456789abcdef' >&2; i=$((i+1)); done; printf done"],
            executableURL: URL(fileURLWithPath: "/bin/sh"), maximumOutputBytes: 8
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.standardOutput, Data("done".utf8))
        XCTAssertEqual(result.standardError.count, 160_000)
    }

    func testCancellationOfPipeReadThrowsCancellation() async throws {
        let task = Task {
            try await CommandRunner.read {
                try CommandRunner.run(["10"], executableURL: URL(fileURLWithPath: "/bin/sleep"), maximumOutputBytes: 32)
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled read must not produce a successful or too-large result")
        } catch is CancellationError { }
    }

    func testLargePathspecInputStagesAndUnstagesLiteralNames() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try git(["init", "-q", "-b", "main"], in: directory)
        // Unique literal paths exceed macOS ARG_MAX; include pathspec metacharacters and
        // newlines to ensure stdin is NUL-delimited rather than shell- or line-parsed.
        let names = (0..<5_000).map { String(repeating: "x", count: 220) + " \($0) [*]\n.txt" }
        for name in names {
            try Data("contents\n".utf8).write(to: directory.appending(path: name))
        }
        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: directory)
        XCTAssertGreaterThan(names.reduce(0) { $0 + $1.utf8.count + 11 }, 1_048_576)
        let staged = try await inspector.stage(repository.changes, in: repository)
        XCTAssertEqual(staged.changes.count, names.count)
        XCTAssertTrue(staged.changes.allSatisfy { $0.staged == .added })
        let unstaged = try await inspector.unstage(staged.changes, in: staged)
        XCTAssertTrue(unstaged.changes.allSatisfy { $0.unstaged == .untracked })
        XCTAssertEqual(Set(unstaged.changes.map(\.path)), Set(names))
    }

    func testScopeSpecificDiffAndOversizedPatch() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try git(["init", "-q", "-b", "main"], in: directory)
        let file = directory.appending(path: "file.txt")
        try Data("staged\n".utf8).write(to: file)
        _ = try git(["add", "file.txt"], in: directory)
        try Data("unstaged\n".utf8).write(to: file)
        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: directory)
        let change = try XCTUnwrap(repository.changes.first)
        let staged = try await inspector.diff(for: change, in: repository, scope: .staged)
        XCTAssertEqual(staged.sections.map(\.scope), [.staged])
        let unstaged = try await inspector.diff(for: change, in: repository, scope: .unstaged)
        XCTAssertEqual(unstaged.sections.map(\.scope), [.unstaged])
        let both = try await inspector.diff(for: change, in: repository)
        XCTAssertEqual(both.sections.map(\.scope), [.staged, .unstaged])
        let limited = try await inspector.diff(for: change, in: repository, scope: .unstaged, maximumOutputBytes: 1)
        XCTAssertEqual(limited.sections.first?.content, .tooLarge(byteLimit: 1))
    }

    func testFirstParentCacheReusesTipAndInvalidatesAncestryChanges() throws {
        let cache = HistoryFirstParentCache()
        let key = HistoryFirstParentCache.Key(rootURL: URL(fileURLWithPath: "/test"), tip: "head")
        var reads = 0
        func load() -> Set<String> { reads += 1; return ["head", "parent", "root"] }
        XCTAssertEqual(cache.value(for: key, load: load), ["head", "parent", "root"])
        XCTAssertEqual(cache.value(for: key, load: load), ["head", "parent", "root"])
        XCTAssertEqual(reads, 1)
        var shallow = key
        shallow.boundaries = [Data("parent".utf8)]
        _ = cache.value(for: shallow, load: load)
        XCTAssertEqual(reads, 2)
        var replaced = key
        replaced.replacementRefs = ["replacement refs/replace/parent"]
        _ = cache.value(for: replaced, load: load)
        XCTAssertEqual(reads, 3)
        let newTip = HistoryFirstParentCache.Key(rootURL: key.rootURL, tip: "new")
        _ = cache.value(for: newTip, load: load)
        XCTAssertEqual(reads, 4)
    }

    func testFirstParentCacheBoundsRetainedIDsAndDoesNotCacheFailures() throws {
        let cache = HistoryFirstParentCache(maximumCommitIDs: 3)
        let first = HistoryFirstParentCache.Key(rootURL: URL(fileURLWithPath: "/test"), tip: "first")
        let second = HistoryFirstParentCache.Key(rootURL: first.rootURL, tip: "second")
        var reads = 0
        func load() -> Set<String> { reads += 1; return ["one", "two"] }
        _ = cache.value(for: first, load: load)
        _ = cache.value(for: second, load: load)
        _ = cache.value(for: first, load: load)
        XCTAssertEqual(reads, 3)
        enum Failure: Error { case expected }
        XCTAssertThrowsError(try cache.value(for: second) { throw Failure.expected })
        _ = cache.value(for: second, load: load)
        XCTAssertEqual(reads, 4)
    }

    func testRemoteReadsPreserveOrderAndBoundConcurrency() async throws {
        let probe = GitReadConcurrencyProbe()
        let names = (0..<24).map { "remote\($0)" }
        let result = try await RepositoryInspector.readRemotes(named: names) { name in
            probe.begin()
            defer { probe.end() }
            Thread.sleep(forTimeInterval: name.hasSuffix("0") ? 0.04 : 0.01)
            return RepositoryRemote(name: name, fetchURL: "fetch-" + name, pushURL: "push-" + name)
        }
        XCTAssertEqual(result.map(\.name), names)
        XCTAssertEqual(probe.started, names.count)
        XCTAssertLessThanOrEqual(probe.peak, 4)
        XCTAssertGreaterThan(probe.peak, 1)
    }

    func testCancelledRemoteReadsStopProcessesAndDoNotStartMoreWork() async throws {
        let probe = GitReadConcurrencyProbe()
        let task = Task {
            try await RepositoryInspector.readRemotes(named: (0..<20).map(String.init)) { name in
                probe.begin()
                defer { probe.end() }
                _ = try CommandRunner.run(["5"], executableURL: URL(fileURLWithPath: "/bin/sleep"))
                return RepositoryRemote(name: name, fetchURL: name, pushURL: name)
            }
        }
        for _ in 0..<200 where probe.started == 0 { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertGreaterThan(probe.started, 0)
        let start = ContinuousClock.now
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
        XCTAssertLessThanOrEqual(probe.started, 4)
        XCTAssertEqual(probe.active, 0)
    }

    func testRemoteQueriesRetainGitURLRewriteAndFirstURLSemantics() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try git(["init", "-q"], in: directory)
        _ = try git(["config", "url.https://fetch.example/.insteadOf", "shortcut:"], in: directory)
        _ = try git(["config", "url.ssh://push.example/.pushInsteadOf", "shortcut:"], in: directory)
        _ = try git(["config", "--add", "remote.zeta.url", "shortcut:first"], in: directory)
        _ = try git(["config", "--add", "remote.zeta.url", "shortcut:second"], in: directory)
        _ = try git(["config", "remote.alpha.url", "shortcut:alpha"], in: directory)
        _ = try git(["config", "remote.alpha.pushurl", "ssh://explicit.example/alpha"], in: directory)
        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: directory)
        let remotes = try await inspector.remotes(in: repository)
        XCTAssertEqual(remotes.map(\.name), ["alpha", "zeta"])
        for remote in remotes {
            let fetch = try git(["remote", "get-url", remote.name], in: directory)
            let push = try git(["remote", "get-url", "--push", remote.name], in: directory)
            XCTAssertEqual(remote.fetchURL, String(decoding: fetch.standardOutput, as: UTF8.self).trimmingCharacters(in: .newlines))
            XCTAssertEqual(remote.pushURL, String(decoding: push.standardOutput, as: UTF8.self).trimmingCharacters(in: .newlines))
        }
    }

    func testScannerPublishesWhileItsNextFilesystemTraversalIsStillWaiting() async {
        let traversal = WaitingCandidateTraversal()
        let (stream, continuation) = AsyncStream<RepositoryScanEvent>.makeStream()
        let task = Task.detached {
            _ = await RepositoryScanner.validateCandidates(
                nextCandidate: traversal.next, continuation: continuation, workingTreeRoot: { $0 }
            )
            continuation.finish()
        }
        var didFind = false
        for await event in stream {
            if case .found(let repository) = event {
                didFind = true
                XCTAssertEqual(repository.rootURL.path, "/scanner-first")
                XCTAssertFalse(traversal.finished)
                traversal.release()
                break
            }
        }
        traversal.release()
        await task.value
        XCTAssertTrue(didFind)
    }

    func testScannerBoundsValidationAndCancelsOutstandingGitReads() async throws {
        let probe = GitReadConcurrencyProbe()
        let candidates = NumberedCandidateTraversal(count: 40)
        let (stream, continuation) = AsyncStream<RepositoryScanEvent>.makeStream()
        let task = Task.detached {
            await RepositoryScanner.validateCandidates(nextCandidate: candidates.next, continuation: continuation) { url in
                probe.begin()
                defer { probe.end() }
                _ = try CommandRunner.run(["5"], executableURL: URL(fileURLWithPath: "/bin/sleep"))
                return url
            }
        }
        for _ in 0..<200 where probe.started == 0 { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertGreaterThan(probe.started, 0)
        let start = ContinuousClock.now
        task.cancel()
        _ = await task.value
        continuation.finish()
        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
        XCTAssertLessThanOrEqual(probe.peak, 4)
        XCTAssertLessThanOrEqual(candidates.visited, 4)
        XCTAssertEqual(probe.active, 0)
        var events: [RepositoryScanEvent] = []
        for await event in stream { events.append(event) }
        XCTAssertTrue(events.isEmpty)
    }

    func testScannerDescendsPastInvalidMarkerAndSkipsSymlinkAndPackage() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let wrapper = root.appending(path: "wrapper")
        let nested = wrapper.appending(path: "nested")
        let package = root.appending(path: "Hidden.app")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("not a Git marker".utf8).write(to: wrapper.appending(path: ".git"))
        _ = try git(["init", "-q"], in: nested)
        _ = try git(["init", "-q"], in: package)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "linked"), withDestinationURL: nested)
        var found: [URL] = []
        for await event in RepositoryScanner().scan(in: root) {
            if case .found(let repository) = event { found.append(repository.rootURL.standardizedFileURL) }
        }
        XCTAssertEqual(found, [nested.standardizedFileURL])
        var rootFound: [URL] = []
        for await event in RepositoryScanner().scan(in: nested) {
            if case .found(let repository) = event { rootFound.append(repository.rootURL.standardizedFileURL) }
        }
        XCTAssertEqual(rootFound, [nested.standardizedFileURL])
    }

    func testHistoryFocusOnCurrentTipKeepsFirstPageAndGraph() async throws {
        let (directory, ids) = try historyFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: directory)
        let ordinary = try await inspector.history(in: repository, limit: 3)
        let focused = try await inspector.history(in: repository, focusReference: "refs/heads/main", limit: 3)
        XCTAssertEqual(focused.focusedCommitID, ids.last)
        XCTAssertEqual(focused.commits, ordinary.commits)
        XCTAssertEqual(focused.graphRows, ordinary.graphRows)
        XCTAssertEqual(focused.headGraphRows, ordinary.headGraphRows)
        XCTAssertEqual(focused.commits.count, 3)
        XCTAssertTrue(focused.hasMoreCommits)
    }

    func testHistoryFocusExpandsLookaheadAndOlderTipsUsingMergeTopoOrder() async throws {
        let (directory, ids) = try historyFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try git(["switch", "-q", "-c", "side", ids[2]], in: directory)
        _ = try historyCommit("side commit", in: directory)
        _ = try git(["switch", "-q", "main"], in: directory)
        _ = try git(["-c", "user.name=Performance", "-c", "user.email=perf@example.invalid", "-c", "commit.gpgSign=false",
                     "merge", "--no-ff", "--no-edit", "side"], in: directory)
        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: directory)
        let all = try await inspector.history(in: repository, limit: 100)
        // Index 3 is the first page's lookahead, not a visible row. Also cover an old
        // tip and the root, whose expansion must switch hasMoreCommits to false.
        for index in [3, all.commits.count - 2, all.commits.count - 1] {
            let target = all.commits[index].id
            let focused = try await inspector.history(in: repository, focusReference: target, limit: 3)
            let ordinary = try await inspector.history(in: repository, limit: index + 1)
            XCTAssertEqual(focused.focusedCommitID, target)
            XCTAssertEqual(focused.commits.last?.id, target)
            XCTAssertEqual(focused.commits.count, index + 1)
            XCTAssertEqual(focused.commits, ordinary.commits)
            XCTAssertEqual(focused.graphRows, ordinary.graphRows)
            XCTAssertEqual(focused.headGraphRows, ordinary.headGraphRows)
            XCTAssertEqual(focused.hasMoreCommits, index + 1 < all.commits.count)
        }
    }

    func testHistoryFocusOutsideFilterPreservesPageAndUnavailableTargetID() async throws {
        let (directory, ids) = try historyFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: directory)
        let ordinary = try await inspector.history(in: repository, reference: ids[2], limit: 2)
        let focused = try await inspector.history(in: repository, reference: ids[2], focusReference: ids[7], limit: 2)
        XCTAssertEqual(focused.focusedCommitID, ids[7])
        XCTAssertFalse(focused.commits.contains { $0.id == ids[7] })
        XCTAssertEqual(focused.commits, ordinary.commits)
        XCTAssertEqual(focused.graphRows, ordinary.graphRows)
        XCTAssertEqual(focused.hasMoreCommits, ordinary.hasMoreCommits)
        XCTAssertEqual(focused.commits.count, 2)
    }

    private func historyFixture() throws -> (URL, [String]) {
        let directory = try temporaryDirectory()
        do {
            _ = try git(["init", "-q", "-b", "main"], in: directory)
            var ids: [String] = []
            for index in 0..<8 { ids.append(try historyCommit("Commit \(index)\n\nBody \(index)", in: directory)) }
            return (directory, ids)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func historyCommit(_ message: String, in directory: URL) throws -> String {
        _ = try git(["-c", "user.name=Performance", "-c", "user.email=perf@example.invalid", "-c", "commit.gpgSign=false",
                     "commit", "--allow-empty", "-q", "-m", message], in: directory)
        let result = try git(["rev-parse", "HEAD"], in: directory)
        return String(decoding: result.standardOutput, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "GallaeGitPerformance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func git(_ arguments: [String], in directory: URL) throws -> GitResult {
        let result = try CommandRunner.run(["-C", directory.path] + arguments, executableURL: CommandRunner.gitURL)
        XCTAssertEqual(result.status, 0, result.standardError)
        return result
    }
}

private final class GitReadConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private var highest = 0
    private var total = 0
    var active: Int { lock.withLock { current } }
    var peak: Int { lock.withLock { highest } }
    var started: Int { lock.withLock { total } }
    func begin() { lock.withLock { current += 1; total += 1; highest = max(highest, current) } }
    func end() { lock.withLock { current -= 1 } }
}

private final class WaitingCandidateTraversal: @unchecked Sendable {
    private let condition = NSCondition()
    private var calls = 0
    private var released = false
    private var completed = false
    var finished: Bool { condition.withLock { completed } }
    func next() -> URL? {
        condition.lock()
        defer { condition.unlock() }
        calls += 1
        if calls == 1 { return URL(fileURLWithPath: "/scanner-first") }
        let deadline = Date().addingTimeInterval(2)
        while !released, condition.wait(until: deadline) { }
        completed = true
        return nil
    }
    func release() { condition.withLock { released = true; condition.broadcast() } }
}

private final class NumberedCandidateTraversal: @unchecked Sendable {
    private let count: Int
    private let lock = NSLock()
    private var nextIndex = 0
    var visited: Int { lock.withLock { nextIndex } }
    init(count: Int) { self.count = count }
    func next() -> URL? {
        lock.withLock {
            guard nextIndex < count else { return nil }
            defer { nextIndex += 1 }
            return URL(fileURLWithPath: "/candidate-\(nextIndex)")
        }
    }
}
