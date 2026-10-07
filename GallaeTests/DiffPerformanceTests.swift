import XCTest
@testable import Gallae

final class DiffPerformanceTests: XCTestCase {
    private func section(scope: RepositoryDiff.Scope = .unstaged) -> RepositoryDiff.Section {
        let raw: [(RepositoryDiff.Line.Kind, String)] = [
            (.metadata, "diff --git a/file b/file"), (.metadata, "--- a/file"), (.metadata, "+++ b/file"),
            (.hunk, "@@ -1,2 +1,2 @@ first"), (.deletion, "-old"), (.addition, "+new"), (.context, " same"),
            (.hunk, "@@ -20,1 +20,1 @@ second"), (.deletion, "-before"), (.addition, "+after"),
            (.metadata, "\\ No newline at end of file")
        ]
        // IDs deliberately differ from offsets: indices describe storage, IDs describe selection.
        return .init(scope: scope, content: .text(raw.enumerated().map { offset, value in
            .init(id: offset * 3 + 10, kind: value.0, oldLineNumber: nil, newLineNumber: nil, text: value.1)
        }))
    }

    func testIndexedHunksKeepHeadersBoundariesAndNoNewlineMarker() throws {
        let section = section()
        XCTAssertEqual(section.hunkIndex.orderedIDs, [19, 31])
        XCTAssertEqual(section.hunkIndex.entries[19]?.changedLineIDs, [22, 25])
        XCTAssertEqual(section.hunkIndex.entries[31]?.changedLineIDs, [34, 37])
        XCTAssertEqual(try XCTUnwrap(section.hunk(id: 31)).patchText,
                       "diff --git a/file b/file\n--- a/file\n+++ b/file\n@@ -20,1 +20,1 @@ second\n-before\n+after\n\\ No newline at end of file\n")
        XCTAssertEqual(section.hunks.map(\.id), [19, 31])
        XCTAssertFalse(try XCTUnwrap(section.hunk(id: 19)).patchText.contains("second"))
        XCTAssertNil(section.hunk(id: 10))
        XCTAssertNil(section.hunk(id: 999))
    }

    func testIndexedPartialPatchRetainsStageAndRevertSemantics() throws {
        for scope in [RepositoryDiff.Scope.unstaged, .staged] {
            let section = section(scope: scope)
            let apply = try XCTUnwrap(section.partialHunk(id: 31, keeping: [37], direction: .apply))
            XCTAssertEqual(apply.scope, scope)
            XCTAssertTrue(apply.patchText.contains("@@ -20,1 +20,2 @@ second\n before\n+after\n\\ No newline"))
            let revert = try XCTUnwrap(section.partialHunk(id: 31, keeping: [37], direction: .revert))
            XCTAssertTrue(revert.patchText.contains("@@ -20,0 +20,1 @@ second\n+after\n\\ No newline"))
            XCTAssertNil(section.partialHunk(id: 31, keeping: [25], direction: .apply))
        }
    }

    func testNonTextAndMetadataOnlySectionsHaveNoHunks() {
        for content in [RepositoryDiff.Section.Content.binary, .text([]),
                        .text([.init(id: 0, kind: .metadata, oldLineNumber: nil, newLineNumber: nil, text: "old mode 100644")])] {
            let section = RepositoryDiff.Section(scope: .unstaged, content: content)
            XCTAssertTrue(section.hunkIndex.entries.isEmpty)
            XCTAssertTrue(section.hunks.isEmpty)
            XCTAssertNil(section.hunk(id: 0))
        }
    }

    func testVisualCollectionIsBoundedAndPreservesInputOrder() async throws {
        let probe = ReadProbe()
        let files = try await VisualDiffGenerator.collectFiles(Array(0..<12)) { index in
            try await probe.read(index, delay: .milliseconds((4 - index % 4) * 5))
        }
        XCTAssertEqual(files.map(\.path), (0..<12).map { "file\($0)" })
        let state = await probe.state()
        XCTAssertEqual(state.peak, 4)
        XCTAssertEqual(state.active, 0)
        XCTAssertEqual(state.started, 12)
    }

    func testVisualCollectionCancelsOutstandingReadsOnError() async {
        let probe = ReadProbe()
        do {
            _ = try await VisualDiffGenerator.collectFiles(Array(0..<12)) { index in
                try await probe.read(index, delay: index == 0 ? .milliseconds(10) : .seconds(30), fail: index == 0)
            }
            XCTFail("Expected read error")
        } catch {
            XCTAssertTrue(error is ReadProbe.ReadError)
        }
        let state = await probe.state()
        XCTAssertEqual(state.started, 4)
        XCTAssertEqual(state.active, 0)
    }

    func testVisualCollectionPropagatesParentCancellation() async {
        let probe = ReadProbe()
        let started = expectation(description: "First four reads started")
        started.expectedFulfillmentCount = 4
        let collection = Task {
            try await VisualDiffGenerator.collectFiles(Array(0..<12)) { index in
                started.fulfill()
                return try await probe.read(index, delay: .seconds(30))
            }
        }
        await fulfillment(of: [started], timeout: 2)
        collection.cancel()
        do {
            _ = try await collection.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let state = await probe.state()
        XCTAssertEqual(state.started, 4)
        XCTAssertEqual(state.active, 0)
    }

    func testVisualCollectionRejectsOversizedInputBeforeReading() async {
        let probe = ReadProbe()
        do {
            _ = try await VisualDiffGenerator.collectFiles(Array(0..<257)) { index in
                try await probe.read(index, delay: .zero)
            }
            XCTFail("Expected file limit")
        } catch {
            guard case VisualDiffGenerator.GenerationError.tooManyFiles = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let state = await probe.state()
        XCTAssertEqual(state.started, 0)
    }
}

private actor ReadProbe {
    enum ReadError: Error { case failed }
    private var active = 0
    private var peak = 0
    private var started = 0

    func read(_ index: Int, delay: Duration, fail: Bool = false) async throws -> VisualDiffGenerator.File {
        active += 1
        peak = max(peak, active)
        started += 1
        defer { active -= 1 }
        try await Task.sleep(for: delay)
        if fail { throw ReadError.failed }
        return .init(path: "file\(index)", originalPath: nil, state: .modified, content: .text([]))
    }

    func state() -> (peak: Int, active: Int, started: Int) { (peak, active, started) }
}
