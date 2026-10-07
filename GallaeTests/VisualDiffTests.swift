import XCTest
@testable import Gallae

final class VisualDiffTests: XCTestCase {
    private var example: Data {
        Data("""
        {"kind":"graph","title":"Change overview","lenses":["architecture","data-flow"],
         "provenance":{"repo":{"owner":"team","name":"project"},
         "base":{"sha":"0123456789abcdef"},"head":{"sha":"abcdef0123456789"}}}
        """.utf8)
    }

    func testImportRetainsSourceAndAvailableLenses() throws {
        let graph = try VisualDiffDocument(data: example)
        XCTAssertEqual(graph.title, "Change overview")
        XCTAssertEqual(graph.lenses, ["architecture", "data-flow"])
        XCTAssertEqual(graph.sourceDescription, "team/project · 01234567 → abcdef01")
        XCTAssertEqual(Data(graph.json.utf8), example)
    }

    func testRejectsManifestInvalidJSONAndUnsupportedEncoding() {
        for data in [Data("{\"kind\":\"render-manifest\"}".utf8), Data("not JSON".utf8), Data([0xff, 0xfe])] {
            XCTAssertThrowsError(try VisualDiffDocument(data: data))
        }
    }

    func testOversizedImportIsRejectedBeforeParsing() {
        XCTAssertThrowsError(try VisualDiffDocument(data: Data(repeating: 32, count: VisualDiffDocument.maximumBytes + 1))) { error in
            XCTAssertEqual(error as? VisualDiffDocument.ImportError, .tooLarge)
        }
    }

    func testUnknownLensesAreSkippedButKnownViewIsRequired() throws {
        let json = String(decoding: example, as: UTF8.self)
        let future = json.replacingOccurrences(of: "\"architecture\",\"data-flow\"", with: "\"future\",\"architecture\"")
        XCTAssertEqual(try VisualDiffDocument(data: Data(future.utf8)).lenses, ["architecture"])
        let unsupported = json.replacingOccurrences(of: "\"architecture\",\"data-flow\"", with: "\"future\"")
        XCTAssertThrowsError(try VisualDiffDocument(data: Data(unsupported.utf8)))
    }

    func testGeneratedGraphTracksReferencesAddedAndRemovedFromRealDiffLines() throws {
        let files: [VisualDiffGenerator.File] = [
            .init(path: "Sources/Store.swift", originalPath: nil, state: .modified,
                  content: .text([line(.context, "struct Store {}", 0)])),
            .init(path: "Sources/View.swift", originalPath: nil, state: .modified,
                  content: .text([line(.deletion, "let value = Store()", 0), line(.addition, "let value = 1", 1)])),
            .init(path: "Tests/New.swift", originalPath: nil, state: .untracked,
                  content: .text([line(.addition, "let value = Store()", 0)]))
        ]
        let doc = try generate(files)
        let graph = try object(doc)
        XCTAssertTrue(doc.isGenerated)
        XCTAssertTrue(doc.sourceDescription.contains("Index → Working tree"))
        let nodes = try XCTUnwrap(graph["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(nodes[2]["delta"] as? String, "added")
        let edges = try XCTUnwrap(graph["edges"] as? [[String: Any]])
        XCTAssertEqual(edges.count, 2)
        XCTAssertEqual(edges.first { $0["from"] as? String == "file1" }?["delta"] as? String, "removed")
        XCTAssertEqual(edges.first { $0["from"] as? String == "file2" }?["delta"] as? String, "added")
        XCTAssertEqual(edges.first?["to"] as? String, "file0")
    }

    func testAmbiguousDeclarationsDoNotInventConnections() throws {
        let files = ["A.swift", "B.swift", "Caller.swift"].enumerated().map { i, path in
            VisualDiffGenerator.File(path: path, originalPath: nil, state: .modified,
                                     content: .text([line(.addition, i == 2 ? "let x = Store()" : "struct Store {}", 0)]))
        }
        XCTAssertEqual((try object(generate(files))["edges"] as? [[String: Any]])?.count, 0)
    }

    func testBinaryRenamesUnicodeAndManyDirectoriesRemainRepresentable() throws {
        let files = (0..<20).map { i in
            VisualDiffGenerator.File(path: "folder\(i)/긴 이름 <\"\(i)\">.png", originalPath: i == 0 ? "old.png" : nil,
                                     state: i == 0 ? .renamed : .added, content: .binary)
        }
        let doc = try generate(files)
        let graph = try object(doc)
        XCTAssertEqual((graph["lanes"] as? [[String: Any]])?.count, 16)
        XCTAssertEqual((graph["nodes"] as? [[String: Any]])?.count, 20)
        XCTAssertTrue(doc.sourceDescription.contains("20 files without text analysis"))
        XCTAssertTrue(doc.json.contains("old.png"))
    }

    func testWorkingTreeAndIndexUseTheirOwnDiffAndIncludeUntrackedFiles() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("struct Store {}\n", "Store.swift", root)
        try git(root, ["add", "."])
        try git(root, ["commit", "-qm", "Base"])
        try write("struct Store { let staged = true }\nlet second = 1\n", "Store.swift", root)
        try git(root, ["add", "."])
        let workingText = "struct Store { let staged = true }\nlet second = 1\nlet third = 2\nlet fourth = 3\n"
        try write(workingText, "Store.swift", root)
        try write("let store = Store()\n", "New.swift", root)
        let repository = try await RepositoryInspector().inspect(at: root)
        let staged = try await VisualDiffGenerator.generate(.init(repository: repository, comparison: .staged, revision: 1))
        let working = try await VisualDiffGenerator.generate(.init(repository: repository, comparison: .workingTree, revision: 1))
        let stagedNodes = try XCTUnwrap(object(staged)["nodes"] as? [[String: Any]])
        let workingNodes = try XCTUnwrap(object(working)["nodes"] as? [[String: Any]])
        XCTAssertEqual(stagedNodes.count, 1)
        XCTAssertEqual(workingNodes.count, 2)
        let stagedStats = try XCTUnwrap(object(staged)["stats"] as? [String: Int])
        let workingStats = try XCTUnwrap(object(working)["stats"] as? [String: Int])
        XCTAssertEqual(stagedStats["additions"], 2)
        XCTAssertEqual(stagedStats["deletions"], 1)
        XCTAssertEqual(workingStats["additions"], 3)
        XCTAssertEqual(workingStats["deletions"], 0)
        XCTAssertTrue(staged.sourceDescription.contains("HEAD → Index"))
        XCTAssertTrue(working.sourceDescription.contains("Index → Working tree"))
        XCTAssertEqual((try object(working)["edges"] as? [[String: Any]])?.count, 1)
        // Generation never stages, discards, or changes the repository.
        let afterGeneration = try await RepositoryInspector().inspect(at: root)
        XCTAssertEqual(afterGeneration, repository)
        XCTAssertEqual(try String(contentsOf: root.appending(path: "Store.swift"), encoding: .utf8), workingText)
    }

    func testCommitAndStashAnalyzeTheirSavedRevisionsInsteadOfCurrentWorktree() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("struct Store {}\n", "Store.swift", root)
        try git(root, ["add", "."]); try git(root, ["commit", "-qm", "Base"])
        let inspector = RepositoryInspector()
        var repository = try await inspector.inspect(at: root)
        let history = try await inspector.history(in: repository)
        let initial = try XCTUnwrap(history.commits.first)
        let initialGraph = try await VisualDiffGenerator.generate(.init(repository: repository, comparison: .commit(initial), revision: 0))
        XCTAssertTrue(initialGraph.sourceDescription.contains("Empty tree"))
        try write("let saved = Store()\n", "Saved.swift", root)
        try git(root, ["add", "."]); try git(root, ["commit", "-qm", "Saved change"])
        repository = try await inspector.inspect(at: root)
        let updatedHistory = try await inspector.history(in: repository)
        let commit = try XCTUnwrap(updatedHistory.commits.first)
        try write("let stash = Store()\n", "Untracked.swift", root)
        try git(root, ["stash", "push", "-u", "-m", "Saved stash"])
        let stashes = try await inspector.stashes(in: repository)
        let stash = try XCTUnwrap(stashes.first)
        try write("unrelated current code\n", "Current.swift", root)
        let commitGraph = try await VisualDiffGenerator.generate(.init(repository: repository, comparison: .commit(commit), revision: 1))
        let stashGraph = try await VisualDiffGenerator.generate(.init(repository: repository, comparison: .stash(stash), revision: 1))
        XCTAssertTrue(commitGraph.json.contains("Saved.swift"))
        XCTAssertFalse(commitGraph.json.contains("Current.swift"))
        XCTAssertTrue(stashGraph.json.contains("Untracked.swift"))
        XCTAssertFalse(stashGraph.json.contains("Current.swift"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "Current.swift").path))
    }

    @MainActor
    func testEmbeddedEscapeReturnsToDiff() {
        let session = VisualDiffSession()
        var returned = false
        session.returnToDiff = { returned = true }
        session.escape()
        XCTAssertTrue(returned)
    }

    private func line(_ kind: RepositoryDiff.Line.Kind, _ text: String, _ id: Int) -> RepositoryDiff.Line {
        .init(id: id, kind: kind, oldLineNumber: nil, newLineNumber: nil,
              text: (kind == .addition ? "+" : kind == .deletion ? "-" : " ") + text)
    }
    private func generate(_ files: [VisualDiffGenerator.File]) throws -> VisualDiffDocument {
        try VisualDiffGenerator.makeDocument(files: files, repositoryName: "Test", title: "Working Tree Changes",
                                             base: "Index", head: "Working tree", fallbackSHA: "1234567")
    }
    private func object(_ document: VisualDiffDocument) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(document.json.utf8)) as? [String: Any])
    }
    private func makeRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "GallaeGraphTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(root, ["init", "-q", "-b", "main"])
        try git(root, ["config", "user.name", "Test"])
        try git(root, ["config", "user.email", "test@example.com"])
        try git(root, ["config", "commit.gpgsign", "false"])
        return root
    }
    private func write(_ text: String, _ path: String, _ root: URL) throws {
        try Data(text.utf8).write(to: root.appending(path: path))
    }
    private func git(_ root: URL, _ arguments: [String]) throws {
        let result = try RepositoryInspector.runGit(["-C", root.path] + arguments)
        XCTAssertEqual(result.status, 0, result.standardError)
        guard result.status == 0 else { throw RepositoryInspectionError.invalidGitOutput }
    }
}
