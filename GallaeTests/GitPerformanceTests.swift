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
