import XCTest
import AppKit
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

    func testPreparedRowsRetainPairingIDsAndVisibleMetadata() throws {
        let prepared = try XCTUnwrap(section().textPresentation)
        XCTAssertEqual(prepared.visibleLines.map(\.id), [19, 22, 25, 28, 31, 34, 37, 40])
        XCTAssertEqual(Array(prepared.visibleLines.indices), Array(0..<8))
        XCTAssertEqual(prepared.visibleLines.indices.map { prepared.visibleLines[$0].id }, [19, 22, 25, 28, 31, 34, 37, 40])
        XCTAssertEqual(prepared.splitRows.map(\.id), [19, 22, 28, 31, 34, 40])
        let pair = prepared.splitRows[1]
        XCTAssertEqual(prepared.lines[try XCTUnwrap(pair.oldIndex)].text, "-old")
        XCTAssertEqual(prepared.lines[try XCTUnwrap(pair.newIndex)].text, "+new")
        XCTAssertEqual(prepared.lines[try XCTUnwrap(prepared.splitRows.last?.fullIndex)].text,
                       "\\ No newline at end of file")
    }

    func testPreparedRowsAreSharedAcrossSnapshotsAndLayoutChoices() throws {
        let section = section()
        let copy = section
        let prepared = try XCTUnwrap(section.textPresentation)
        XCTAssertTrue(prepared === copy.textPresentation)
        XCTAssertEqual(RepositoryDiffPresentation(text: prepared, preferred: .unified).layout, .unified)
        XCTAssertEqual(RepositoryDiffPresentation(text: prepared, preferred: .split).layout, .split)
        // Line selection lives in the view; both layouts read the same immutable geometry.
        XCTAssertTrue(prepared === section.textPresentation)
        let patch = RepositoryCommitPatch(commitID: "commit", fileID: "file", content: section.content)
        let patchCopy = patch
        XCTAssertTrue(patch.textPresentation === patchCopy.textPresentation)
        XCTAssertEqual(patch.textPresentation?.visibleLines.map(\.id), prepared.visibleLines.map(\.id))
    }

    func testSameLengthRefreshReplacesPreparedWorkingTreeAndRevisionContent() throws {
        let oldLine = RepositoryDiff.Line(id: 12, kind: .addition, oldLineNumber: nil, newLineNumber: 9, text: "+old")
        let newLine = RepositoryDiff.Line(id: 12, kind: .addition, oldLineNumber: nil, newLineNumber: 999, text: "+new")
        let old = RepositoryDiff.Section(scope: .unstaged, content: .text([oldLine]))
        let new = RepositoryDiff.Section(scope: .unstaged, content: .text([newLine]))
        XCTAssertFalse(old.textPresentation === new.textPresentation)
        XCTAssertEqual(new.textPresentation?.visibleLines.first?.text, "+new")
        XCTAssertEqual(new.textPresentation?.largestLineNumber, 999)
        XCTAssertEqual(RepositoryDiffPresentation(text: new.textPresentation, preferred: .split).layout, .unified)
        let oldPatch = RepositoryCommitPatch(commitID: "same", fileID: "same", content: old.content)
        let newPatch = RepositoryCommitPatch(commitID: "same", fileID: "same", content: new.content)
        XCTAssertFalse(oldPatch.textPresentation === newPatch.textPresentation)
        XCTAssertEqual(newPatch.textPresentation?.visibleLines.first?.text, "+new")
        XCTAssertEqual(newPatch.textPresentation?.largestLineNumber, 999)
    }

    func testPreparedGeometryKeepsBothUnmatchedSidesAndFontIndependentNumbers() {
        let lines: [RepositoryDiff.Line] = [
            .init(id: 10, kind: .deletion, oldLineNumber: 100, newLineNumber: nil, text: "-one"),
            .init(id: 20, kind: .deletion, oldLineNumber: 101, newLineNumber: nil, text: "-two"),
            .init(id: 30, kind: .addition, oldLineNumber: nil, newLineNumber: 900, text: "+new")
        ]
        let prepared = RepositoryDiffTextPresentation(lines: lines)
        XCTAssertEqual(prepared.splitRows.map(\.id), [10, 20])
        XCTAssertEqual(prepared.splitRows[0].newIndex, 2)
        XCTAssertNil(prepared.splitRows[1].newIndex)
        XCTAssertEqual(prepared.largestLineNumber, 900)
        XCTAssertTrue(prepared.canSplit)
        let small = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let large = NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)
        XCTAssertEqual(diffNumberWidth(largestLineNumber: prepared.largestLineNumber, font: small),
                       diffNumberWidth(for: lines, font: small))
        XCTAssertGreaterThan(diffNumberWidth(largestLineNumber: prepared.largestLineNumber, font: large),
                             diffNumberWidth(largestLineNumber: prepared.largestLineNumber, font: small))
    }

    func testGeneratedDataOnlyGraphHasNoReferencesAndRetainsCounts() throws {
        let files: [VisualDiffGenerator.File] = [
            .init(path: "config.json", originalPath: nil, state: .modified, content: .text([
                .init(id: 0, kind: .deletion, oldLineNumber: 1, newLineNumber: nil, text: "-{\"enabled\": false}"),
                .init(id: 1, kind: .addition, oldLineNumber: nil, newLineNumber: 1, text: "+{\"enabled\": true}")
            ]))
        ]
        let document = try VisualDiffGenerator.makeDocument(files: files, repositoryName: "fixture", title: "Changes",
                                                            base: "Index", head: "Working tree", fallbackSHA: "1111111")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(document.json.utf8)) as? [String: Any])
        XCTAssertEqual((json["edges"] as? [Any])?.count, 0)
        XCTAssertEqual((json["nodes"] as? [Any])?.count, 1)
        let stats = try XCTUnwrap(json["stats"] as? [String: Int])
        XCTAssertEqual(stats["additions"], 1)
        XCTAssertEqual(stats["deletions"], 1)
    }

    func testExactly512ReferencesDoesNotClaimTruncation() throws {
        let fixture = referenceLimitFixture(edgeCount: 512)
        let document = try referenceLimitDocument(files: fixture.files)
        let graph = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(document.json.utf8)) as? [String: Any])
        let edges = try XCTUnwrap(graph["edges"] as? [[String: Any]])
        XCTAssertEqual(edges.count, 512)
        XCTAssertEqual(edges.map { edgeIdentity($0) }, fixture.expectedEdges)
        XCTAssertFalse(document.sourceDescription.contains("Showing first 512 references"))
        try assertReferenceLimitNodesAndStats(graph, edgeCount: 512)
    }

    func test513ReferencesKeepsExpectedPrefixAndAllFileMetadata() throws {
        let fixture = referenceLimitFixture(edgeCount: 513)
        let document = try referenceLimitDocument(files: fixture.files)
        let graph = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(document.json.utf8)) as? [String: Any])
        let edges = try XCTUnwrap(graph["edges"] as? [[String: Any]])
        XCTAssertEqual(edges.count, 512)
        XCTAssertEqual(edges.map { edgeIdentity($0) }, Array(fixture.expectedEdges.prefix(512)))
        XCTAssertTrue(document.sourceDescription.contains("Showing first 512 references"))
        try assertReferenceLimitNodesAndStats(graph, edgeCount: 513)
    }

    func testReferenceGenerationHonorsAlreadyCancelledTask() async {
        let files = referenceLimitFixture(edgeCount: 513).files
        let generation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try VisualDiffGenerator.makeDocument(files: files, repositoryName: "fixture", title: "Changes",
                                                        base: "Index", head: "Working tree", fallbackSHA: "1111111")
        }
        do {
            _ = try await generation.value
            XCTFail("Expected cancellation before graph generation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func referenceLimitFixture(edgeCount: Int) -> (files: [VisualDiffGenerator.File], expectedEdges: [[String: String]]) {
        var bodies = (0..<25).map { index in
            [RepositoryDiff.Line(id: 0, kind: .context, oldLineNumber: 1, newLineNumber: 1,
                                 text: " struct Symbol\(index) {}")]
        }
        var expected: [[String: String]] = []
        for from in 0..<25 {
            for to in 0..<25 where from != to && expected.count < edgeCount {
                let ordinal = expected.count
                let kind: RepositoryDiff.Line.Kind = ordinal % 3 == 0 ? .addition : (ordinal % 3 == 1 ? .deletion : .context)
                let prefix = kind == .addition ? "+" : (kind == .deletion ? "-" : " ")
                bodies[from].append(.init(id: bodies[from].count, kind: kind, oldLineNumber: nil, newLineNumber: nil,
                                          text: "\(prefix)use(Symbol\(to))"))
                expected.append(["id": "ref\(from)-\(to)", "from": "file\(from)", "to": "file\(to)",
                                 "delta": ordinal % 3 == 0 ? "added" : (ordinal % 3 == 1 ? "removed" : "unchanged")])
            }
        }
        // This file comes after the edge limit is encountered. Its node and counts must remain.
        bodies[24].append(.init(id: 1, kind: .addition, oldLineNumber: nil, newLineNumber: 2, text: "+let tail = 2"))
        bodies[24].append(.init(id: 2, kind: .deletion, oldLineNumber: 2, newLineNumber: nil, text: "-let tail = 1"))
        return (bodies.enumerated().map { index, lines in
            .init(path: String(format: "file%02d.swift", index), originalPath: nil, state: .modified, content: .text(lines))
        }, expected)
    }

    private func referenceLimitDocument(files: [VisualDiffGenerator.File]) throws -> VisualDiffDocument {
        try VisualDiffGenerator.makeDocument(files: files, repositoryName: "fixture", title: "Changes",
                                             base: "Index", head: "Working tree", fallbackSHA: "1111111")
    }

    private func edgeIdentity(_ edge: [String: Any]) -> [String: String] {
        edge.compactMapValues { $0 as? String }.filter { ["id", "from", "to", "delta"].contains($0.key) }
    }

    private func assertReferenceLimitNodesAndStats(_ graph: [String: Any], edgeCount: Int) throws {
        let nodes = try XCTUnwrap(graph["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.count, 25)
        XCTAssertEqual(nodes.last?["label"] as? String, "file24.swift")
        XCTAssertEqual(nodes.last?["badges"] as? [String], ["+1 −1"])
        let stats = try XCTUnwrap(graph["stats"] as? [String: Int])
        XCTAssertEqual(stats["filesChanged"], 25)
        XCTAssertEqual(stats["additions"], (0..<edgeCount).filter { $0 % 3 == 0 }.count + 1)
        XCTAssertEqual(stats["deletions"], (0..<edgeCount).filter { $0 % 3 == 1 }.count + 1)
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
