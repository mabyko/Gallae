import Foundation
import XCTest
@testable import Gallae

final class RepositoryInspectorTests: XCTestCase {
    func testInspectsUnbornRepositoryWithoutChangingHead() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try runGit(["init", "--quiet", repositoryURL.path])
        let headURL = repositoryURL.appending(path: ".git/HEAD")
        let headBeforeInspection = try Data(contentsOf: headURL)

        let repository = try await RepositoryInspector().inspect(at: repositoryURL)

        XCTAssertEqual(repository.rootURL.resolvingSymlinksInPath(), repositoryURL.resolvingSymlinksInPath())
        guard case .branch(let name) = repository.head else {
            return XCTFail("An unborn Repository should still have a symbolic branch")
        }
        XCTAssertFalse(name.isEmpty)
        XCTAssertTrue(repository.isUnborn)
        XCTAssertNil(repository.upstream)
        XCTAssertTrue(repository.changes.isEmpty)
        XCTAssertEqual(try Data(contentsOf: headURL), headBeforeInspection)

        let activity = try await RepositoryInspector().activity(in: repository)
        XCTAssertEqual(activity, .init(commitCount: 0, recentCommits: []))
    }

    func testReportsWorkingTreeChangesAndSpecialPaths() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "both.txt", in: repositoryURL)
        try write("delete me\n", to: "deleted.txt", in: repositoryURL)
        try write("rename me\n", to: "old name.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")

        try write("staged\n", to: "both.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "both.txt"])
        try write("unstaged\n", to: "both.txt", in: repositoryURL)
        try FileManager.default.removeItem(at: repositoryURL.appending(path: "deleted.txt"))
        try runGit(["-C", repositoryURL.path, "mv", "old name.txt", "새 이름 [1].txt"])
        try write("untracked\n", to: " 한글 file [1].txt", in: repositoryURL)
        try write("first\n", to: "Sources/Feature/First.swift", in: repositoryURL)
        try write("second\n", to: "Sources/Feature/Second.swift", in: repositoryURL)

        let repository = try await RepositoryInspector().inspect(at: repositoryURL)
        let changes = Dictionary(uniqueKeysWithValues: repository.changes.map { ($0.path, $0) })

        let both = try XCTUnwrap(changes["both.txt"])
        XCTAssertEqual(both.staged, .modified)
        XCTAssertEqual(both.unstaged, .modified)

        let deleted = try XCTUnwrap(changes["deleted.txt"])
        XCTAssertNil(deleted.staged)
        XCTAssertEqual(deleted.unstaged, .deleted)

        let renamed = try XCTUnwrap(changes["새 이름 [1].txt"])
        XCTAssertEqual(renamed.originalPath, "old name.txt")
        XCTAssertEqual(renamed.staged, .renamed)
        XCTAssertNil(renamed.unstaged)

        let untracked = try XCTUnwrap(changes[" 한글 file [1].txt"])
        XCTAssertEqual(untracked.unstaged, .untracked)

        let hierarchy = RepositoryChangeHierarchyNode.make(repository.changes)
        let sources = try XCTUnwrap(hierarchy.first { $0.name == "Sources" })
        XCTAssertEqual(sources.changeCount, 2)
        let feature = try XCTUnwrap(sources.children?.first)
        XCTAssertEqual(feature.name, "Feature")
        XCTAssertEqual(feature.children?.map(\.name), ["First.swift", "Second.swift"])

        let statusGroups = RepositoryChangeStatusGroup.make(repository.changes)
        XCTAssertEqual(statusGroups.map(\.id), [.changes, .untracked])
        XCTAssertEqual(statusGroups.map { $0.changes.count }, [3, 3])

        let inspector = RepositoryInspector()
        let bothDiff = try await inspector.diff(for: both, in: repository)
        XCTAssertEqual(bothDiff.sections.map(\.scope), [.staged, .unstaged])

        let stagedLines = try textLines(in: bothDiff, scope: .staged)
        XCTAssertTrue(stagedLines.contains {
            $0.kind == .addition && $0.newLineNumber == 1 && $0.text == "+staged"
        })

        let unstagedLines = try textLines(in: bothDiff, scope: .unstaged)
        XCTAssertTrue(unstagedLines.contains {
            $0.kind == .addition && $0.newLineNumber == 1 && $0.text == "+unstaged"
        })

        let untrackedDiff = try await inspector.diff(for: untracked, in: repository)
        let untrackedLines = try textLines(in: untrackedDiff, scope: .untracked)
        XCTAssertTrue(untrackedLines.contains {
            $0.kind == .addition && $0.newLineNumber == 1 && $0.text == "+untracked"
        })
    }

    func testReadsStagedDiffOnUnbornBranch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("first\nsecond\n", to: "new file.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "new file.txt"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first)
        let diff = try await inspector.diff(for: change, in: repository)
        let lines = try textLines(in: diff, scope: .staged)

        XCTAssertEqual(
            lines.filter { $0.kind == .addition }.compactMap(\.newLineNumber),
            [1, 2]
        )
    }

    func testDistinguishesBinaryUnsupportedEncodingAndLargeDiff() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write(Data([0x00, 0x01, 0x02]), to: "binary.dat", in: repositoryURL)
        try write(Data([0xFF, 0xFE, 0x41, 0x0A]), to: "legacy.txt", in: repositoryURL)
        try write(
            Data(repeating: 0x61, count: RepositoryInspector.maximumDisplayedDiffBytes + 1),
            to: "large.txt",
            in: repositoryURL
        )

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let changes = Dictionary(uniqueKeysWithValues: repository.changes.map { ($0.path, $0) })

        let binaryDiff = try await inspector.diff(
            for: XCTUnwrap(changes["binary.dat"]),
            in: repository
        )
        guard case .binary = try XCTUnwrap(binaryDiff.sections.first).content else {
            return XCTFail("Expected binary diff content")
        }

        let unsupportedDiff = try await inspector.diff(
            for: XCTUnwrap(changes["legacy.txt"]),
            in: repository
        )
        guard case .unsupportedEncoding = try XCTUnwrap(unsupportedDiff.sections.first).content else {
            return XCTFail("Expected unsupported encoding content")
        }

        let largeDiff = try await inspector.diff(
            for: XCTUnwrap(changes["large.txt"]),
            in: repository
        )
        guard case .tooLarge(let limit) = try XCTUnwrap(largeDiff.sections.first).content else {
            return XCTFail("Expected large diff content")
        }
        XCTAssertEqual(limit, RepositoryInspector.maximumDisplayedDiffBytes)

        let expandedDiff = try await inspector.diff(
            for: XCTUnwrap(changes["large.txt"]),
            in: repository,
            maximumOutputBytes: RepositoryInspector.maximumExpandedDiffBytes
        )
        XCTAssertFalse(try textLines(in: expandedDiff, scope: .untracked).isEmpty)
    }

    func testReportsDetachedHead() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("content\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "--detach"])

        let repository = try await RepositoryInspector().inspect(at: repositoryURL)

        guard case .detached(let commit) = repository.head else {
            return XCTFail("Expected detached HEAD")
        }
        XCTAssertFalse(commit.isEmpty)
    }

    func testReportsLocallyKnownUpstreamDivergence() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        let remoteURL = fixtureURL.appending(path: "remote.git", directoryHint: .isDirectory)
        try runGit(["init", "--bare", "--quiet", remoteURL.path])
        try initializeRepository(at: repositoryURL)
        try write("initial\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "remote", "add", "origin", remoteURL.path])
        try runGit(["-C", repositoryURL.path, "push", "--quiet", "--set-upstream", "origin", "main"])
        try write("ahead\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Ahead")

        let repository = try await RepositoryInspector().inspect(at: repositoryURL)

        XCTAssertEqual(repository.upstream, .init(name: "origin/main", ahead: 1, behind: 0))
    }

    func testReadsRepositoryActivity() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("first\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("second\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Second")

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let activity = try await inspector.activity(in: repository)

        XCTAssertFalse(repository.isUnborn)
        XCTAssertEqual(activity.commitCount, 2)
        XCTAssertEqual(activity.recentCommits.map(\.subject), ["Second", "Initial"])
        XCTAssertTrue(activity.recentCommits.allSatisfy { !$0.id.isEmpty })
    }

    func testReadsCurrentHistoryAndSelectedCommitPatch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("first\n", to: "notes [한글].txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--all"])
        try runGit([
            "-C", repositoryURL.path, "commit", "--quiet",
            "-m", "Initial subject", "-m", "Initial body"
        ])
        let initialID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try write("second\n", to: "notes [한글].txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--all"])
        try runGit([
            "-C", repositoryURL.path, "commit", "--quiet",
            "-m", "Second subject", "-m", "Second body\n\nMore details."
        ])
        let secondID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repository)

        XCTAssertEqual(history.commits.map(\.id), [secondID, initialID])
        let latest = try XCTUnwrap(history.commits.first)
        XCTAssertEqual(latest.parentIDs, [initialID])
        XCTAssertEqual(latest.authorName, "Gallae Tests")
        XCTAssertEqual(latest.authorEmail, "tests@gallae.local")
        XCTAssertEqual(latest.subject, "Second subject")
        XCTAssertEqual(latest.body, "Second body\n\nMore details.")
        XCTAssertGreaterThan(latest.committedAt, Date(timeIntervalSince1970: 0))

        let patch = try await inspector.patch(for: latest, in: repository)
        XCTAssertEqual(patch.commitID, secondID)
        guard case .text(let lines) = patch.content else {
            return XCTFail("Expected text commit patch")
        }
        XCTAssertTrue(lines.contains { $0.kind == .deletion && $0.text == "-first" })
        XCTAssertTrue(lines.contains { $0.kind == .addition && $0.text == "+second" })

        let initial = try XCTUnwrap(history.commits.last)
        let initialPatch = try await inspector.patch(for: initial, in: repository)
        guard case .text(let initialLines) = initialPatch.content else {
            return XCTFail("Expected text root commit patch")
        }
        XCTAssertTrue(initialLines.contains { $0.kind == .addition && $0.text == "+first" })
    }

    func testFiltersHistoryByMessageAuthorAndSHA() {
        let commit = RepositoryHistory.Commit(
            id: "abc123def456",
            parentIDs: [],
            authorName: "Gallae Tester",
            authorEmail: "tester@gallae.local",
            committedAt: Date(timeIntervalSince1970: 0),
            subject: "Fix Library selection",
            body: "Keep the selected Repository visible.",
        )

        XCTAssertTrue(commit.matches(search: ""))
        XCTAssertTrue(commit.matches(search: "library tester"))
        XCTAssertTrue(commit.matches(search: "VISIBLE abc123"))
        XCTAssertFalse(commit.matches(search: "remote branch"))
    }

    func testScannerStaysInsideAllowedFolderAndSkipsRepositoryDescendants() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let libraryURL = fixtureURL.appending(path: "Library", directoryHint: .isDirectory)
        let firstRepositoryURL = libraryURL.appending(path: "Alpha", directoryHint: .isDirectory)
        let nestedRepositoryURL = firstRepositoryURL.appending(path: "Nested", directoryHint: .isDirectory)
        let secondRepositoryURL = libraryURL.appending(
            path: "Group/Team/Beta",
            directoryHint: .isDirectory
        )
        let hiddenRepositoryURL = libraryURL.appending(path: ".hidden/Hidden", directoryHint: .isDirectory)
        let packagedRepositoryURL = libraryURL.appending(path: "Archive.app/Packaged", directoryHint: .isDirectory)
        let linkedMetadataRepositoryURL = libraryURL.appending(path: "LinkedMetadata", directoryHint: .isDirectory)
        let externalMetadataURL = fixtureURL.appending(path: "LinkedMetadata.git", directoryHint: .isDirectory)
        let outsideRepositoryURL = fixtureURL.appending(path: "Outside", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try initializeRepository(at: firstRepositoryURL)
        try initializeRepository(at: nestedRepositoryURL)
        try initializeRepository(at: secondRepositoryURL)
        try initializeRepository(at: hiddenRepositoryURL)
        try initializeRepository(at: packagedRepositoryURL)
        try initializeRepository(at: linkedMetadataRepositoryURL)
        try initializeRepository(at: outsideRepositoryURL)
        try FileManager.default.moveItem(
            at: linkedMetadataRepositoryURL.appending(path: ".git", directoryHint: .isDirectory),
            to: externalMetadataURL
        )
        try FileManager.default.createSymbolicLink(
            at: linkedMetadataRepositoryURL.appending(path: ".git", directoryHint: .isDirectory),
            withDestinationURL: externalMetadataURL
        )
        try runGit([
            "init", "--bare", "--quiet",
            libraryURL.appending(path: "Bare.git", directoryHint: .isDirectory).path
        ])
        try FileManager.default.createSymbolicLink(
            at: libraryURL.appending(path: "Linked", directoryHint: .isDirectory),
            withDestinationURL: outsideRepositoryURL
        )

        var found: Set<URL> = []
        for await event in RepositoryScanner().scan(in: libraryURL) {
            if case .found(let repository) = event {
                found.insert(repository.rootURL.standardizedFileURL)
            }
        }

        XCTAssertEqual(found, [
            firstRepositoryURL.standardizedFileURL,
            secondRepositoryURL.standardizedFileURL
        ])
        XCTAssertFalse(found.contains(nestedRepositoryURL.standardizedFileURL))
        XCTAssertFalse(found.contains(hiddenRepositoryURL.standardizedFileURL))
        XCTAssertFalse(found.contains(packagedRepositoryURL.standardizedFileURL))
        XCTAssertFalse(found.contains(linkedMetadataRepositoryURL.standardizedFileURL))
        XCTAssertFalse(found.contains(outsideRepositoryURL.standardizedFileURL))

        let hierarchy = RepositoryHierarchyNode.make(
            found.map(RepositoryLocation.init(rootURL:)),
            relativeTo: libraryURL
        )
        XCTAssertEqual(hierarchy.map(\.name), ["Alpha", "Group"])
        XCTAssertEqual(hierarchy.first?.repository?.rootURL, firstRepositoryURL.standardizedFileURL)
        let group = try XCTUnwrap(hierarchy.last)
        XCTAssertEqual(group.repositoryCount, 1)
        let team = try XCTUnwrap(group.children?.first)
        XCTAssertEqual(team.name, "Team")
        XCTAssertEqual(team.children?.map(\.name), ["Beta"])
        XCTAssertEqual(team.children?.first?.repository?.rootURL, secondRepositoryURL.standardizedFileURL)
        XCTAssertEqual(
            group.node(matching: secondRepositoryURL)?.repository?.rootURL,
            secondRepositoryURL.standardizedFileURL
        )
    }

    func testScannerKeepsResultsWhenOnePathIsUnreadable() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let libraryURL = fixtureURL.appending(path: "Library", directoryHint: .isDirectory)
        let repositoryURL = libraryURL.appending(path: "Readable", directoryHint: .isDirectory)
        let unreadableURL = libraryURL.appending(path: "Unreadable", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try initializeRepository(at: repositoryURL)
        try FileManager.default.createDirectory(at: unreadableURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadableURL.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: unreadableURL.path
            )
        }

        var found: [RepositoryLocation] = []
        var failures: [RepositoryScanFailure] = []
        for await event in RepositoryScanner().scan(in: libraryURL) {
            switch event {
            case .found(let repository): found.append(repository)
            case .failed(let failure): failures.append(failure)
            }
        }

        XCTAssertEqual(found.map(\.rootURL), [repositoryURL.standardizedFileURL])
        XCTAssertTrue(failures.contains { $0.url.standardizedFileURL == unreadableURL.standardizedFileURL })
    }

    func testHandlesLargeLibraryAndWorkingTreeFixtures() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let libraryURL = fixtureURL.appending(path: "Library", directoryHint: .isDirectory)
        var expectedRepositories: Set<URL> = []
        for index in 0..<32 {
            let repositoryURL = libraryURL.appending(
                path: "Group-\(index % 4)/Repository-\(index)",
                directoryHint: .isDirectory
            )
            try runGit(["init", "--quiet", "--initial-branch=main", repositoryURL.path])
            expectedRepositories.insert(repositoryURL.standardizedFileURL)
        }

        var foundRepositories: Set<URL> = []
        for await event in RepositoryScanner().scan(in: libraryURL) {
            if case .found(let repository) = event {
                foundRepositories.insert(repository.rootURL.standardizedFileURL)
            }
        }
        XCTAssertEqual(foundRepositories, expectedRepositories)

        let workingTreeURL = fixtureURL.appending(path: "WorkingTree", directoryHint: .isDirectory)
        try initializeRepository(at: workingTreeURL)
        for index in 0..<500 {
            try write("change \(index)\n", to: "Changes/file-\(index).txt", in: workingTreeURL)
        }
        let largeLineCount = 12_000
        let largeText = (0..<largeLineCount)
            .map { "line \($0)" }
            .joined(separator: "\n") + "\n"
        try write(largeText, to: "large-lines.txt", in: workingTreeURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: workingTreeURL)
        XCTAssertEqual(repository.changes.count, 501)

        let largeChange = try XCTUnwrap(
            repository.changes.first { $0.path == "large-lines.txt" }
        )
        let diff = try await inspector.diff(for: largeChange, in: repository)
        let lines = try textLines(in: diff, scope: .untracked)
        XCTAssertEqual(lines.filter { $0.kind == .addition }.count, largeLineCount)
    }

    func testReportsConflict() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "conflict.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "-b", "side"])
        try write("side\n", to: "conflict.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Side")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "main"])
        try write("main\n", to: "conflict.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main")
        try runGit(["-C", repositoryURL.path, "merge", "--no-edit", "side"], expectedStatus: 1)

        let repository = try await RepositoryInspector().inspect(at: repositoryURL)

        let change = try XCTUnwrap(repository.changes.first { $0.path == "conflict.txt" })
        XCTAssertTrue(change.isConflicted)
        XCTAssertEqual(RepositoryChangeStatusGroup.make(repository.changes).map(\.id), [.conflicts])

        let diff = try await RepositoryInspector().diff(for: change, in: repository)
        XCTAssertFalse(try textLines(in: diff, scope: .conflict).isEmpty)
    }

    func testRejectsRegularDirectory() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        do {
            _ = try await RepositoryInspector().inspect(at: directoryURL)
            XCTFail("Expected a regular directory to be rejected")
        } catch let error as RepositoryInspectionError {
            guard case .notWorkingTree = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsBareRepository() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try runGit(["init", "--bare", "--quiet", repositoryURL.path])

        do {
            _ = try await RepositoryInspector().inspect(at: repositoryURL)
            XCTFail("Expected a bare Repository to be rejected")
        } catch let error as RepositoryInspectionError {
            XCTAssertEqual(error, .bareRepository)
        }
    }

    @MainActor
    func testFolderChoiceOpensRepositoryOrRegistersLibraryFolder() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let repositoryURL = fixtureURL.appending(path: "Repository", directoryHint: .isDirectory)
        let libraryURL = fixtureURL.appending(path: "Library", directoryHint: .isDirectory)
        let nestedRepositoryURL = libraryURL.appending(
            path: "Nested",
            directoryHint: .isDirectory
        )
        let invalidRepositoryURL = fixtureURL.appending(
            path: "Invalid Repository",
            directoryHint: .isDirectory
        )
        try initializeRepository(at: repositoryURL)
        try initializeRepository(at: nestedRepositoryURL)
        try FileManager.default.createDirectory(
            at: invalidRepositoryURL.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let suiteName = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(store: LibraryStore(defaults: defaults))
        defer { model.cancelLibraryScan() }

        await model.openOrAddFolder(at: repositoryURL)
        XCTAssertEqual(model.screen, .workspace)
        XCTAssertEqual(model.repository?.rootURL, repositoryURL.standardizedFileURL)
        XCTAssertEqual(model.recentRepositories.map(\.rootURL), [repositoryURL.standardizedFileURL])
        XCTAssertTrue(model.libraryFolders.isEmpty)

        model.showLibrary()
        await model.openOrAddFolder(at: libraryURL)
        XCTAssertEqual(model.screen, .library)
        XCTAssertEqual(model.selectedLibrarySource, .folder(libraryURL.standardizedFileURL))
        XCTAssertTrue(model.libraryFolders.contains { $0.id == libraryURL.standardizedFileURL })

        await model.openOrAddFolder(at: invalidRepositoryURL)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.libraryFolders.contains {
            $0.id == invalidRepositoryURL.standardizedFileURL
        })
    }

    @MainActor
    func testRescanKeepsExistingResultsUntilItRemovesMissingRepositories() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let libraryURL = fixtureURL.appending(path: "Library", directoryHint: .isDirectory)
        let firstRepositoryURL = libraryURL.appending(path: "First", directoryHint: .isDirectory)
        let removedRepositoryURL = libraryURL.appending(path: "Removed", directoryHint: .isDirectory)
        try initializeRepository(at: firstRepositoryURL)
        try initializeRepository(at: removedRepositoryURL)

        let suiteName = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(store: LibraryStore(defaults: defaults))
        defer { model.cancelLibraryScan() }

        model.addLibraryFolder(at: libraryURL)
        guard await waitForLibraryScan(in: model) else {
            return XCTFail("Initial Library scan timed out")
        }
        XCTAssertEqual(
            Set(model.selectedLibraryFolder?.repositories.map(\.rootURL) ?? []),
            Set([firstRepositoryURL, removedRepositoryURL].map(\.standardizedFileURL))
        )

        model.selectLibraryRepository(removedRepositoryURL)
        try FileManager.default.removeItem(at: removedRepositoryURL)
        model.rescanSelectedLibraryFolder()

        XCTAssertEqual(model.selectedLibraryFolder?.scanState, .scanning)
        XCTAssertEqual(model.selectedLibraryFolder?.repositories.count, 2)
        XCTAssertEqual(model.selectedLibraryRepositoryID, removedRepositoryURL.standardizedFileURL)

        guard await waitForLibraryScan(in: model) else {
            return XCTFail("Repeated Library scan timed out")
        }
        XCTAssertEqual(
            model.selectedLibraryFolder?.repositories.map(\.rootURL),
            [firstRepositoryURL.standardizedFileURL]
        )
        XCTAssertEqual(model.selectedLibraryRepositoryID, firstRepositoryURL.standardizedFileURL)
    }

    @MainActor
    func testRestoresLibraryRecentAndFreshWorkspaceState() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        try initializeRepository(at: repositoryURL)

        let suiteName = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LibraryStore(defaults: defaults)
        try store.addLibraryFolder(fixtureURL)
        try store.rememberOpenedRepository(repositoryURL)
        try write("new\n", to: "after-save.txt", in: repositoryURL)

        let model = AppModel(store: store)
        await model.restoreState()

        XCTAssertEqual(model.screen, .workspace)
        XCTAssertEqual(model.repository?.rootURL, repositoryURL.standardizedFileURL)
        XCTAssertEqual(model.repository?.changes.map(\.path), ["after-save.txt"])
        XCTAssertTrue(model.libraryFolders.contains { $0.id == fixtureURL.standardizedFileURL })
        XCTAssertEqual(model.recentRepositories.map(\.rootURL), [repositoryURL.standardizedFileURL])
        model.cancelLibraryScan()
    }

    @MainActor
    func testFailedWorkspaceRestoreWaitsForReconnectAndCanBeRemoved() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let missingURL = fixtureURL.appending(path: "missing", directoryHint: .isDirectory)
        let replacementURL = fixtureURL.appending(path: "replacement", directoryHint: .isDirectory)
        try initializeRepository(at: missingURL)
        try initializeRepository(at: replacementURL)

        let suiteName = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LibraryStore(defaults: defaults)
        try store.rememberOpenedRepository(replacementURL)
        try store.rememberOpenedRepository(missingURL)
        try FileManager.default.removeItem(at: missingURL)

        let failedRestore = AppModel(store: store)
        await failedRestore.restoreState()

        XCTAssertEqual(failedRestore.screen, .library)
        XCTAssertNil(failedRestore.errorMessage)
        XCTAssertEqual(
            Set(failedRestore.recentRepositories.map(\.rootURL.path)),
            Set([missingURL.path, replacementURL.path])
        )
        let failedID = try XCTUnwrap(
            failedRestore.recentRepositories.first { $0.rootURL.path == missingURL.path }?.id
        )
        XCTAssertNotNil(failedRestore.libraryRepositorySummaryErrors[failedID])
        XCTAssertNil(store.restoreLastWorkspace())

        let nextLaunch = AppModel(store: store)
        await nextLaunch.restoreState()
        XCTAssertEqual(nextLaunch.screen, .library)
        XCTAssertNil(nextLaunch.repository)
        XCTAssertEqual(
            Set(nextLaunch.recentRepositories.map(\.rootURL.path)),
            Set([missingURL.path, replacementURL.path])
        )

        await nextLaunch.reconnectRecentRepository(failedID, to: replacementURL)
        XCTAssertEqual(nextLaunch.screen, .workspace)
        XCTAssertEqual(store.restoreLastWorkspace()?.url.path, replacementURL.path)

        nextLaunch.showLibrary()
        nextLaunch.removeRecentRepository(try XCTUnwrap(nextLaunch.recentRepositories.first?.id))
        XCTAssertTrue(store.restoreRecentRepositories().isEmpty)
        XCTAssertNil(store.restoreLastWorkspace())
    }

    @MainActor
    func testRetriesRecentActivityAfterRepositoryReturns() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        let movedURL = fixtureURL.appending(path: "repository-moved", directoryHint: .isDirectory)
        try initializeRepository(at: repositoryURL)
        try write("content\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")

        let model = AppModel()
        let repository = RepositoryLocation(rootURL: repositoryURL)
        model.libraryFolders = [.init(url: fixtureURL, repositories: [repository])]
        model.selectLibrarySource(.folder(fixtureURL))
        await model.loadLibraryRepositorySummary(at: repositoryURL)

        try FileManager.default.moveItem(at: repositoryURL, to: movedURL)
        await model.loadLibraryRepositoryActivity(at: repositoryURL)
        XCTAssertNotNil(model.libraryRepositoryActivityErrors[repositoryURL])

        try FileManager.default.moveItem(at: movedURL, to: repositoryURL)
        await model.retryLibraryRepositoryActivity(at: repositoryURL)
        XCTAssertNil(model.libraryRepositoryActivityErrors[repositoryURL])
        XCTAssertEqual(model.libraryRepositoryActivities[repositoryURL]?.commitCount, 1)
    }

    @MainActor
    func testStagesSelectedWorkingTreeChangeAndRefreshesWorkspace() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("before\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("after\n", to: "file.txt", in: repositoryURL)

        let suiteName = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(store: LibraryStore(defaults: defaults))
        await model.openRepository(at: repositoryURL)
        XCTAssertEqual(model.selectedChangeID, "file.txt")
        let contentBeforeStage = try Data(
            contentsOf: repositoryURL.appending(path: "file.txt")
        )

        await model.stageSelectedChange()

        let change = try XCTUnwrap(model.repository?.changes.first)
        XCTAssertEqual(change.path, "file.txt")
        XCTAssertEqual(change.staged, .modified)
        XCTAssertNil(change.unstaged)
        XCTAssertEqual(model.selectedChangeID, "file.txt")
        XCTAssertEqual(
            try Data(contentsOf: repositoryURL.appending(path: "file.txt")),
            contentBeforeStage
        )
    }

    @MainActor
    func testKeepsWorkspaceAndFileWhenStageFails() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("before\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("after\n", to: "file.txt", in: repositoryURL)

        let suiteName = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(store: LibraryStore(defaults: defaults))
        await model.openRepository(at: repositoryURL)
        let fileURL = repositoryURL.appending(path: "file.txt")
        let contentBeforeStage = try Data(contentsOf: fileURL)
        try FileManager.default.removeItem(at: repositoryURL.appending(path: ".git"))

        await model.stageSelectedChange()

        XCTAssertEqual(model.repository?.changes.first?.unstaged, .modified)
        XCTAssertEqual(try Data(contentsOf: fileURL), contentBeforeStage)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isWritingRepository)
    }

    @MainActor
    func testUnstagesSelectedIndexChangeAndRefreshesWorkspace() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("before\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("after\n", to: "file.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "file.txt"])

        let suiteName = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(store: LibraryStore(defaults: defaults))
        await model.openRepository(at: repositoryURL)
        XCTAssertEqual(model.selectedChangeID, "file.txt")
        let contentBeforeUnstage = try Data(
            contentsOf: repositoryURL.appending(path: "file.txt")
        )

        await model.unstageSelectedChange()

        let change = try XCTUnwrap(model.repository?.changes.first)
        XCTAssertEqual(change.path, "file.txt")
        XCTAssertNil(change.staged)
        XCTAssertEqual(change.unstaged, .modified)
        XCTAssertEqual(model.selectedChangeID, "file.txt")
        XCTAssertEqual(
            try Data(contentsOf: repositoryURL.appending(path: "file.txt")),
            contentBeforeUnstage
        )
    }

    @MainActor
    func testUnstagesRenamedPathWithoutTouchingWorkingTree() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("content\n", to: "old name.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        let destinationURL = repositoryURL.appending(path: "새 이름 [1].txt")
        try runGit([
            "-C", repositoryURL.path,
            "mv", "--", "old name.txt", "새 이름 [1].txt"
        ])

        let suiteName = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(store: LibraryStore(defaults: defaults))
        await model.openRepository(at: repositoryURL)
        let renamed = try XCTUnwrap(model.repository?.changes.first)
        XCTAssertEqual(renamed.originalPath, "old name.txt")
        XCTAssertEqual(renamed.path, "새 이름 [1].txt")
        XCTAssertEqual(renamed.staged, .renamed)

        await model.unstageSelectedChange()

        XCTAssertTrue(model.repository?.changes.allSatisfy { $0.staged == nil } == true)
        XCTAssertEqual(try String(contentsOf: destinationURL, encoding: .utf8), "content\n")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryURL.appending(path: "old name.txt").path
        ))
    }

    @MainActor
    func testUnstagesInitialCommitPathWithoutDeletingWorkingTreeFile() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("draft\n", to: "new file.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "new file.txt"])
        try write("working draft\n", to: "new file.txt", in: repositoryURL)

        let suiteName = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(store: LibraryStore(defaults: defaults))
        await model.openRepository(at: repositoryURL)
        XCTAssertEqual(model.repository?.isUnborn, true)
        XCTAssertEqual(model.repository?.changes.first?.staged, .added)
        let fileURL = repositoryURL.appending(path: "new file.txt")
        let contentBeforeUnstage = try Data(contentsOf: fileURL)

        await model.unstageSelectedChange()

        let change = try XCTUnwrap(model.repository?.changes.first)
        XCTAssertNil(change.staged)
        XCTAssertEqual(change.unstaged, .untracked)
        XCTAssertEqual(try Data(contentsOf: fileURL), contentBeforeUnstage)
        XCTAssertNil(model.errorMessage)
    }

    func testDiscardsOnlySelectedUnstagedChanges() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        let path = "file [한글].txt"
        try write("before\n", to: path, in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("staged\n", to: path, in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", path])
        try write("working\n", to: path, in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first)

        let updatedRepository = try await inspector.discard(change, in: repository)

        let updatedChange = try XCTUnwrap(updatedRepository.changes.first)
        XCTAssertEqual(updatedChange.staged, .modified)
        XCTAssertNil(updatedChange.unstaged)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: path), encoding: .utf8),
            "staged\n"
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "show", ":\(path)"]),
            "staged\n"
        )
    }

    func testCommitsSubjectAndBodyUsingOnlyStagedChanges() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("before\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("staged\n", to: "file.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "file.txt"])
        try write("working\n", to: "file.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let updatedRepository = try await inspector.commit(
            subject: "Record staged change",
            body: "Keep the working copy for the next commit.",
            in: repository
        )

        let change = try XCTUnwrap(updatedRepository.changes.first)
        XCTAssertNil(change.staged)
        XCTAssertEqual(change.unstaged, .modified)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "file.txt"), encoding: .utf8),
            "working\n"
        )
        let activity = try await inspector.activity(in: updatedRepository)
        XCTAssertEqual(activity.commitCount, 2)
        XCTAssertEqual(activity.recentCommits.first?.subject, "Record staged change")
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path,
                "log", "-1", "--format=%B"
            ]).trimmingCharacters(in: .newlines),
            "Record staged change\n\nKeep the working copy for the next commit."
        )
    }

    func testAmendsLatestCommitUsingOnlyStagedChanges() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("before\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        let originalHead = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
        try write("staged\n", to: "file.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "file.txt"])
        try write("working\n", to: "file.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let updatedRepository = try await inspector.commit(
            subject: "Amended commit",
            body: "Replace the latest commit.",
            amend: true,
            in: repository
        )

        let change = try XCTUnwrap(updatedRepository.changes.first)
        XCTAssertNil(change.staged)
        XCTAssertEqual(change.unstaged, .modified)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "file.txt"), encoding: .utf8),
            "working\n"
        )
        let activity = try await inspector.activity(in: updatedRepository)
        XCTAssertEqual(activity.commitCount, 1)
        XCTAssertEqual(activity.recentCommits.first?.subject, "Amended commit")
        XCTAssertNotEqual(try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"]), originalHead)
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "show", "HEAD:file.txt"])
                .trimmingCharacters(in: .newlines),
            "staged"
        )
    }

    func testStagesAndUnstagesOnlySelectedTextHunk() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        let original = (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try write(original, to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        var editedLines = (1...20).map { "line \($0)" }
        editedLines[1] = "changed two"
        editedLines[17] = "changed eighteen"
        let edited = editedLines.joined(separator: "\n") + "\n"
        try write(edited, to: "file.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first)
        let diff = try await inspector.diff(for: change, in: repository)
        let workingSection = try XCTUnwrap(diff.sections.first { $0.scope == .unstaged })
        XCTAssertEqual(workingSection.hunks.count, 2)

        let stagedRepository = try await inspector.stage(
            try XCTUnwrap(workingSection.hunks.first),
            for: change,
            in: repository
        )

        let stagedChange = try XCTUnwrap(stagedRepository.changes.first)
        XCTAssertEqual(stagedChange.staged, .modified)
        XCTAssertEqual(stagedChange.unstaged, .modified)
        let stagedDiff = try await inspector.diff(for: stagedChange, in: stagedRepository)
        let stagedLines = try textLines(in: stagedDiff, scope: .staged)
        XCTAssertTrue(stagedLines.contains { $0.text == "+changed two" })
        XCTAssertFalse(stagedLines.contains { $0.text == "+changed eighteen" })
        let remainingLines = try textLines(in: stagedDiff, scope: .unstaged)
        XCTAssertFalse(remainingLines.contains { $0.text == "+changed two" })
        XCTAssertTrue(remainingLines.contains { $0.text == "+changed eighteen" })
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "file.txt"), encoding: .utf8),
            edited
        )

        let stagedSection = try XCTUnwrap(stagedDiff.sections.first { $0.scope == .staged })
        let unstagedRepository = try await inspector.unstage(
            try XCTUnwrap(stagedSection.hunks.first),
            for: stagedChange,
            in: stagedRepository
        )

        let unstagedChange = try XCTUnwrap(unstagedRepository.changes.first)
        XCTAssertNil(unstagedChange.staged)
        XCTAssertEqual(unstagedChange.unstaged, .modified)
        let unstagedDiff = try await inspector.diff(for: unstagedChange, in: unstagedRepository)
        XCTAssertEqual(
            try textLines(in: unstagedDiff, scope: .unstaged)
                .filter { $0.kind == .addition }
                .map(\.text),
            ["+changed two", "+changed eighteen"]
        )
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "file.txt"), encoding: .utf8),
            edited
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "GallaeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private func waitForLibraryScan(in model: AppModel) async -> Bool {
        for _ in 0..<500 {
            guard let folder = model.selectedLibraryFolder else { return false }
            if case .completed = folder.scanState {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func initializeRepository(at url: URL) throws {
        try runGit(["init", "--quiet", "--initial-branch=main", url.path])
        try runGit(["-C", url.path, "config", "user.name", "Gallae Tests"])
        try runGit(["-C", url.path, "config", "user.email", "tests@gallae.local"])
    }

    private func commitAll(in repositoryURL: URL, message: String) throws {
        try runGit(["-C", repositoryURL.path, "add", "--all"])
        try runGit(["-C", repositoryURL.path, "commit", "--quiet", "-m", message])
    }

    private func write(_ value: String, to path: String, in repositoryURL: URL) throws {
        try write(Data(value.utf8), to: path, in: repositoryURL)
    }

    private func write(_ value: Data, to path: String, in repositoryURL: URL) throws {
        let fileURL = repositoryURL.appending(path: path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try value.write(to: fileURL)
    }

    private func textLines(
        in diff: RepositoryDiff,
        scope: RepositoryDiff.Scope
    ) throws -> [RepositoryDiff.Line] {
        let section = try XCTUnwrap(diff.sections.first { $0.scope == scope })
        guard case .text(let lines) = section.content else {
            throw GitFixtureError.unexpectedDiffContent
        }
        return lines
    }

    private func runGit(_ arguments: [String], expectedStatus: Int32 = 0) throws {
        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == expectedStatus else {
            let message = String(
                decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw GitFixtureError.failed(status: process.terminationStatus, message: message)
        }
    }

    private func gitOutput(_ arguments: [String]) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw GitFixtureError.failed(status: process.terminationStatus, message: message)
        }
        return String(
            decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
    }
}

private enum GitFixtureError: LocalizedError {
    case failed(status: Int32, message: String)
    case unexpectedDiffContent

    var errorDescription: String? {
        switch self {
        case .failed(let status, let message):
            "git fixture command failed with status \(status): \(message)"
        case .unexpectedDiffContent:
            "expected text diff content"
        }
    }
}
