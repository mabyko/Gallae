import AppKit
import Foundation
import XCTest
@testable import Gallae

final class RepositoryInspectorTests: XCTestCase {
    func testHistoryLayoutStaysWithinWindowAndPreservesHiddenHistorySize() {
        for size in [CGSize.zero, CGSize(width: 720, height: 640), CGSize(width: 1180.8, height: 760.5)] {
            for stacked in [false, true] {
                for preferred in [CGFloat(0), 260, 2000] {
                    let browsing = RepositoryHistoryFrames(
                        size: size, stacked: stacked, expanded: false,
                        preferredWidth: preferred, preferredHeight: preferred
                    )
                    let expanded = RepositoryHistoryFrames(
                        size: size, stacked: stacked, expanded: true,
                        preferredWidth: preferred, preferredHeight: preferred
                    )
                    for frame in [browsing.history, browsing.divider, browsing.review, expanded.review] {
                        XCTAssertGreaterThanOrEqual(frame.minX, 0)
                        XCTAssertGreaterThanOrEqual(frame.minY, 0)
                        XCTAssertGreaterThanOrEqual(frame.width, 0)
                        XCTAssertGreaterThanOrEqual(frame.height, 0)
                        XCTAssertLessThanOrEqual(frame.maxX, size.width)
                        XCTAssertLessThanOrEqual(frame.maxY, size.height)
                    }
                    XCTAssertEqual(expanded.history, browsing.history)
                    if stacked {
                        XCTAssertEqual(browsing.history.maxY, browsing.divider.minY)
                        XCTAssertEqual(browsing.divider.maxY, browsing.review.minY)
                        XCTAssertEqual(expanded.review, CGRect(x: 0, y: 0, width: size.width.rounded(.down), height: size.height.rounded(.down)))
                    } else {
                        XCTAssertEqual(browsing.history.maxX, browsing.divider.minX)
                        XCTAssertEqual(browsing.divider.maxX, browsing.review.minX)
                        XCTAssertEqual(expanded.review, browsing.review)
                    }
                }
            }
        }
    }

    func testHistoryReviewNavigationUsesOnlyVisibleCommits() {
        let filtered = ["newest", "older", "oldest"]
        XCTAssertEqual(RepositoryHistoryNavigation.adjacent(to: "newest", offset: 1, in: filtered), "older")
        XCTAssertEqual(RepositoryHistoryNavigation.adjacent(to: "older", offset: -1, in: filtered), "newest")
        XCTAssertNil(RepositoryHistoryNavigation.adjacent(to: "newest", offset: -1, in: filtered))
        XCTAssertNil(RepositoryHistoryNavigation.adjacent(to: "oldest", offset: 1, in: filtered))
        XCTAssertNil(RepositoryHistoryNavigation.adjacent(to: "excluded", offset: 1, in: filtered))
        XCTAssertNil(RepositoryHistoryNavigation.adjacent(to: nil, offset: 1, in: filtered))
        XCTAssertNil(RepositoryHistoryNavigation.adjacent(to: "newest", offset: 2, in: filtered))
        XCTAssertNil(RepositoryHistoryNavigation.adjacent(to: "newest", offset: 1, in: []))
    }

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
        XCTAssertEqual(
            RepositoryChangeStatusGroup.selectAllIDs(
                containing: both.id,
                in: repository.changes
            ),
            Set(["both.txt", "deleted.txt", "새 이름 [1].txt"])
        )
        XCTAssertEqual(
            RepositoryChangeStatusGroup.selectAllIDs(
                containing: untracked.id,
                in: repository.changes
            ),
            Set([
                " 한글 file [1].txt",
                "Sources/Feature/First.swift",
                "Sources/Feature/Second.swift"
            ])
        )

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

    func testListsCreatesAndSafelySwitchesLocalBranches() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("main\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature/topic"])
        try write("feature\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])

        let inspector = RepositoryInspector()
        let mainRepository = try await inspector.inspect(at: repositoryURL)
        let branches = try await inspector.localBranches(in: mainRepository)
        XCTAssertEqual(branches, ["feature/topic", "main"])

        let createdRepository = try await inspector.createBranch(
            named: "new/local",
            in: mainRepository
        )
        XCTAssertEqual(createdRepository.head, .branch("new/local"))
        let updatedBranches = try await inspector.localBranches(in: createdRepository)
        XCTAssertEqual(updatedBranches, ["feature/topic", "main", "new/local"])

        do {
            _ = try await inspector.createBranch(named: "new/local", in: createdRepository)
            XCTFail("Creating an existing branch should fail")
        } catch let error as RepositoryBranchError {
            guard case .creationFailed = error else {
                return XCTFail("Expected a branch-creation failure, got \(error)")
            }
        }

        let featureRepository = try await inspector.switchBranch(
            to: "feature/topic",
            in: createdRepository
        )
        XCTAssertEqual(featureRepository.head, .branch("feature/topic"))

        let restoredMain = try await inspector.switchBranch(to: "main", in: featureRepository)
        try write("local\n", to: "file.txt", in: repositoryURL)

        do {
            _ = try await inspector.switchBranch(to: "feature/topic", in: restoredMain)
            XCTFail("A conflicting local change should prevent the branch switch")
        } catch let error as RepositoryBranchError {
            guard case .switchFailed = error else {
                return XCTFail("Expected a safe branch-switch failure, got \(error)")
            }
        }

        let unchangedRepository = try await inspector.inspect(at: repositoryURL)
        XCTAssertEqual(unchangedRepository.head, .branch("main"))
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "file.txt"), encoding: .utf8),
            "local\n"
        )
    }

    func testMapsLocalBranchesToExistingWorktreeFolders() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let repositoryURL = fixtureURL.appending(path: "main repository", directoryHint: .isDirectory)
        let linkedURL = fixtureURL.appending(path: "연결 작업 폴더", directoryHint: .isDirectory)
        let detachedURL = fixtureURL.appending(path: "detached", directoryHint: .isDirectory)

        try initializeRepository(at: repositoryURL)
        try write("main\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main")
        try runGit([
            "-C", repositoryURL.path,
            "worktree", "add", "--quiet", "-b", "feature/topic", linkedURL.path
        ])
        try runGit([
            "-C", repositoryURL.path,
            "worktree", "add", "--quiet", "--detach", detachedURL.path, "main"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let worktrees = try await inspector.localBranchWorktrees(in: repository)

        XCTAssertEqual(worktrees["main"], repositoryURL.standardizedFileURL)
        XCTAssertEqual(worktrees["feature/topic"], linkedURL.standardizedFileURL)
        XCTAssertEqual(Set(worktrees.keys), ["main", "feature/topic"])
    }

    func testCreatesAndSafelySwitchesToRecoveryBranchAtReflogCommit() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("initial\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        let initialID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("recover me\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Recovery target")
        let targetID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["-C", repositoryURL.path, "reset", "--hard", "--quiet", initialID])

        let inspector = RepositoryInspector()
        let mainRepository = try await inspector.inspect(at: repositoryURL)
        let reflog = try await inspector.reflog(in: mainRepository)
        let target = try XCTUnwrap(reflog.first { $0.commitID == targetID })
        let recoveredRepository = try await inspector.createBranch(
            named: "recovery/latest",
            at: target.commitID,
            in: mainRepository
        )

        let recoveredHistory = try await inspector.history(in: recoveredRepository)
        let recoveredBranches = try await inspector.localBranches(in: recoveredRepository)
        XCTAssertEqual(recoveredRepository.head, .branch("recovery/latest"))
        XCTAssertEqual(recoveredHistory.headCommitID, targetID)
        XCTAssertTrue(recoveredBranches.contains("main"))

        let restoredMain = try await inspector.switchBranch(to: "main", in: recoveredRepository)
        let restoredHistory = try await inspector.history(in: restoredMain)
        XCTAssertEqual(restoredHistory.headCommitID, initialID)
        try write("local\n", to: "file.txt", in: repositoryURL)

        do {
            _ = try await inspector.createBranch(
                named: "recovery/conflict",
                at: target.commitID,
                in: restoredMain
            )
            XCTFail("A conflicting local change should prevent recovery branch creation")
        } catch let error as RepositoryBranchError {
            guard case .creationFailed = error else {
                return XCTFail("Expected a branch-creation failure, got \(error)")
            }
        }

        let unchangedRepository = try await inspector.inspect(at: repositoryURL)
        let unchangedBranches = try await inspector.localBranches(in: unchangedRepository)
        XCTAssertEqual(unchangedRepository.head, .branch("main"))
        XCTAssertFalse(unchangedBranches.contains("recovery/conflict"))
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "file.txt"), encoding: .utf8),
            "local\n"
        )
    }

    func testFastForwardsCurrentBranchAndRefusesDivergentMerge() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "local.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Base")
        let baseID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature")
        let featureID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "side", baseID])
        try write("side\n", to: "side.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Side")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])
        try write("local edit\n", to: "local.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let mainRepository = try await inspector.inspect(at: repositoryURL)
        let mergedRepository = try await inspector.mergeBranch("feature", in: mainRepository)
        let mergedHistory = try await inspector.history(in: mergedRepository)

        XCTAssertEqual(mergedRepository.head, .branch("main"))
        XCTAssertEqual(mergedHistory.headCommitID, featureID)
        XCTAssertEqual(mergedRepository.changes.map(\.path), ["local.txt"])
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "local.txt"), encoding: .utf8),
            "local edit\n"
        )

        do {
            _ = try await inspector.mergeBranch("side", in: mergedRepository)
            XCTFail("A divergent branch should not be merged")
        } catch let error as RepositoryBranchError {
            guard case .mergeFailed = error else {
                return XCTFail("Expected a fast-forward merge failure, got \(error)")
            }
        }

        let unchangedRepository = try await inspector.inspect(at: repositoryURL)
        let unchangedHistory = try await inspector.history(in: unchangedRepository)
        XCTAssertEqual(unchangedRepository.head, .branch("main"))
        XCTAssertEqual(unchangedHistory.headCommitID, featureID)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "local.txt"), encoding: .utf8),
            "local edit\n"
        )
    }

    func testCreatesMergeCommitForDivergentLocalBranch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "base.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Base")

        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature")
        let featureID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])
        try write("main\n", to: "main.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main")
        let mainID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let mergedRepository = try await inspector.mergeBranchCreatingCommit(
            "feature",
            in: repository
        )

        let parents = try gitOutput([
            "-C", repositoryURL.path, "rev-list", "--parents", "-n", "1", "HEAD",
        ]).split(whereSeparator: \.isWhitespace).map(String.init)
        XCTAssertEqual(mergedRepository.head, .branch("main"))
        XCTAssertTrue(mergedRepository.changes.isEmpty)
        XCTAssertEqual(parents.count, 3)
        XCTAssertEqual(Array(parents.dropFirst()), [mainID, featureID])
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "feature"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            featureID
        )
    }

    func testAbortsConflictingMergeCommitAndRestoresCurrentBranch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Base")

        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature")
        let featureID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])
        try write("main\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main")
        let mainID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        do {
            _ = try await inspector.mergeBranchCreatingCommit("feature", in: repository)
            XCTFail("A conflicting merge should be aborted")
        } catch let error as RepositoryBranchError {
            guard case .mergeCommitFailed = error else {
                return XCTFail("Expected an aborted merge failure, got \(error)")
            }
        }

        let restoredRepository = try await inspector.inspect(at: repositoryURL)
        let restoredHistory = try await inspector.history(in: restoredRepository)
        XCTAssertEqual(restoredRepository.head, .branch("main"))
        XCTAssertEqual(restoredHistory.headCommitID, mainID)
        XCTAssertTrue(restoredRepository.changes.isEmpty)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "shared.txt"), encoding: .utf8),
            "main\n"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryURL.appending(path: ".git/MERGE_HEAD").path
            )
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "feature"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            featureID
        )
    }

    func testRebasesCurrentBranchOntoAnotherLocalBranch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "base.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Base")

        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature")
        let originalFeatureID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])
        try write("main\n", to: "main.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main")
        let mainID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "feature"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let rebasedRepository = try await inspector.rebaseCurrentBranch(
            onto: "main",
            in: repository
        )
        let history = try await inspector.history(in: rebasedRepository)
        let parents = try gitOutput([
            "-C", repositoryURL.path, "rev-list", "--parents", "-n", "1", "HEAD",
        ]).split(whereSeparator: \.isWhitespace).map(String.init)

        XCTAssertEqual(rebasedRepository.head, .branch("feature"))
        XCTAssertTrue(rebasedRepository.changes.isEmpty)
        XCTAssertNotEqual(history.headCommitID, originalFeatureID)
        XCTAssertEqual(parents.count, 2)
        XCTAssertEqual(parents.last, mainID)
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            mainID
        )
    }

    func testAbortsConflictingRebaseAndRestoresCurrentBranch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Base")

        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature")
        let featureID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])
        try write("main\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main")
        let mainID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "feature"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        do {
            _ = try await inspector.rebaseCurrentBranch(onto: "main", in: repository)
            XCTFail("A conflicting rebase should be aborted")
        } catch let error as RepositoryBranchError {
            guard case .rebaseFailed = error else {
                return XCTFail("Expected an aborted rebase failure, got \(error)")
            }
        }

        let restoredRepository = try await inspector.inspect(at: repositoryURL)
        let restoredHistory = try await inspector.history(in: restoredRepository)
        XCTAssertEqual(restoredRepository.head, .branch("feature"))
        XCTAssertEqual(restoredHistory.headCommitID, featureID)
        XCTAssertTrue(restoredRepository.changes.isEmpty)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "shared.txt"), encoding: .utf8),
            "feature\n"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryURL.appending(path: ".git/rebase-merge").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryURL.appending(path: ".git/rebase-apply").path
            )
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            mainID
        )
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

    func testFetchesRemoteChangesWithoutChangingHeadOrWorkingTree() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let remoteURL = fixtureURL.appending(path: "remote.git", directoryHint: .isDirectory)
        let sourceURL = fixtureURL.appending(path: "source", directoryHint: .isDirectory)
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        try runGit(["init", "--bare", "--quiet", "--initial-branch=main", remoteURL.path])
        try initializeRepository(at: sourceURL)
        try write("initial\n", to: "file.txt", in: sourceURL)
        try commitAll(in: sourceURL, message: "Initial")
        try runGit(["-C", sourceURL.path, "remote", "add", "origin", remoteURL.path])
        try runGit(["-C", sourceURL.path, "push", "--quiet", "--set-upstream", "origin", "main"])
        try runGit(["clone", "--quiet", remoteURL.path, repositoryURL.path])

        try write("remote\n", to: "file.txt", in: sourceURL)
        try commitAll(in: sourceURL, message: "Remote")
        try runGit(["-C", sourceURL.path, "push", "--quiet"])
        let remoteHead = try gitOutput([
            "-C", sourceURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        let localHead = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("local change\n", to: "file.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let fetchedRepository = try await inspector.fetch(in: repository)

        XCTAssertEqual(fetchedRepository.head, .branch("main"))
        XCTAssertEqual(fetchedRepository.upstream, .init(name: "origin/main", ahead: 0, behind: 1))
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            localHead
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/remotes/origin/main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            remoteHead
        )
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "file.txt"), encoding: .utf8),
            "local change\n"
        )

        let delayedUploadPackURL = fixtureURL.appending(path: "delayed-upload-pack")
        try Data("#!/bin/sh\nsleep 30\nexec /usr/bin/git upload-pack \"$@\"\n".utf8)
            .write(to: delayedUploadPackURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: delayedUploadPackURL.path
        )
        try runGit([
            "-C", repositoryURL.path,
            "config", "remote.origin.uploadpack", delayedUploadPackURL.path
        ])
        let fetchTask = Task {
            try await inspector.fetch(in: fetchedRepository)
        }
        try await Task.sleep(for: .milliseconds(200))
        let cancellationStartedAt = Date()
        fetchTask.cancel()
        do {
            _ = try await fetchTask.value
            XCTFail("A cancelled Fetch should not return a Repository")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(cancellationStartedAt), 2)
        }

        let noRemoteURL = fixtureURL.appending(path: "no-remote", directoryHint: .isDirectory)
        try initializeRepository(at: noRemoteURL)
        let noRemoteRepository = try await inspector.inspect(at: noRemoteURL)
        do {
            _ = try await inspector.fetch(in: noRemoteRepository)
            XCTFail("Fetching without a remote should fail")
        } catch let error as RepositoryFetchError {
            XCTAssertEqual(error, .noRemote)
        }
    }

    func testFetchesOnlySelectedRemoteWithoutChangingLocalWork() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let originURL = fixtureURL.appending(path: "origin.git", directoryHint: .isDirectory)
        let backupURL = fixtureURL.appending(path: "backup.git", directoryHint: .isDirectory)
        let sourceURL = fixtureURL.appending(path: "source", directoryHint: .isDirectory)
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        for remoteURL in [originURL, backupURL] {
            try runGit(["init", "--bare", "--quiet", "--initial-branch=main", remoteURL.path])
        }
        try initializeRepository(at: sourceURL)
        try write("initial\n", to: "remote.txt", in: sourceURL)
        try write("initial\n", to: "local.txt", in: sourceURL)
        try commitAll(in: sourceURL, message: "Initial")
        try runGit(["-C", sourceURL.path, "remote", "add", "origin", originURL.path])
        try runGit(["-C", sourceURL.path, "remote", "add", "backup", backupURL.path])
        try runGit(["-C", sourceURL.path, "push", "--quiet", "origin", "main"])
        try runGit(["-C", sourceURL.path, "push", "--quiet", "backup", "main"])
        try runGit(["clone", "--quiet", originURL.path, repositoryURL.path])
        try runGit(["-C", repositoryURL.path, "remote", "add", "backup", backupURL.path])

        let originHead = try gitOutput([
            "--git-dir", originURL.path, "rev-parse", "refs/heads/main"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("backup\n", to: "remote.txt", in: sourceURL)
        try commitAll(in: sourceURL, message: "Backup only")
        try runGit(["-C", sourceURL.path, "push", "--quiet", "backup", "main"])
        let backupHead = try gitOutput([
            "--git-dir", backupURL.path, "rev-parse", "refs/heads/main"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("staged\n", to: "local.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "local.txt"])
        try write("working\n", to: "local.txt", in: repositoryURL)
        let localHead = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        let localStatus = try gitOutput([
            "-C", repositoryURL.path, "status", "--short"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        do {
            _ = try await inspector.fetch(in: repository)
            XCTFail("Fetching with multiple Remotes should require a selection")
        } catch let error as RepositoryFetchError {
            XCTAssertEqual(error, .remoteSelectionRequired(["backup", "origin"]))
        }
        _ = try await inspector.fetch(from: "backup", in: repository)

        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/remotes/backup/main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            backupHead
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/remotes/origin/main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            originHead
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            localHead
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "status", "--short"]),
            localStatus
        )
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "local.txt"), encoding: .utf8),
            "working\n"
        )
    }

    @MainActor
    func testAutomaticallyFetchesConfiguredDefaultWithoutChangingLocalWork() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let remoteURL = fixtureURL.appending(path: "remote.git", directoryHint: .isDirectory)
        let sourceURL = fixtureURL.appending(path: "source", directoryHint: .isDirectory)
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        try runGit(["init", "--bare", "--quiet", "--initial-branch=main", remoteURL.path])
        try initializeRepository(at: sourceURL)
        try write("initial\n", to: "remote.txt", in: sourceURL)
        try write("initial\n", to: "local.txt", in: sourceURL)
        try commitAll(in: sourceURL, message: "Initial")
        try runGit(["-C", sourceURL.path, "remote", "add", "origin", remoteURL.path])
        try runGit(["-C", sourceURL.path, "push", "--quiet", "--set-upstream", "origin", "main"])
        try runGit(["clone", "--quiet", remoteURL.path, repositoryURL.path])

        try write("remote\n", to: "remote.txt", in: sourceURL)
        try commitAll(in: sourceURL, message: "Remote")
        try runGit(["-C", sourceURL.path, "push", "--quiet"])
        let remoteHead = try gitOutput(["-C", sourceURL.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try write("staged\n", to: "local.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "local.txt"])
        try write("working\n", to: "local.txt", in: repositoryURL)
        let localHead = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
        let localStatus = try gitOutput(["-C", repositoryURL.path, "status", "--short"])

        let suiteName = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LibraryStore(defaults: defaults)
        let model = AppModel(store: store)
        XCTAssertFalse(model.automaticFetchEnabled)
        await model.openRepository(at: repositoryURL)

        model.setAutomaticFetchEnabled(true)
        XCTAssertTrue(AppModel(store: store).automaticFetchEnabled)
        let loop = Task {
            await model.runAutomaticFetchLoop(interval: .milliseconds(10))
        }
        for _ in 0..<500 where model.repository?.upstream?.behind != 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        model.setAutomaticFetchEnabled(false)
        loop.cancel()
        await loop.value

        XCTAssertEqual(model.repository?.upstream?.behind, 1)
        XCTAssertFalse(AppModel(store: store).automaticFetchEnabled)
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/remotes/origin/main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            remoteHead
        )
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"]), localHead)
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "status", "--short"]), localStatus)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "local.txt"), encoding: .utf8),
            "working\n"
        )
    }

    func testPruningFetchRemovesStaleTrackingRefsWithoutChangingLocalWork() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let remoteURL = fixtureURL.appending(path: "remote.git", directoryHint: .isDirectory)
        let sourceURL = fixtureURL.appending(path: "source", directoryHint: .isDirectory)
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        try runGit(["init", "--bare", "--quiet", "--initial-branch=main", remoteURL.path])
        try initializeRepository(at: sourceURL)
        try write("initial\n", to: "local.txt", in: sourceURL)
        try commitAll(in: sourceURL, message: "Initial")
        try runGit(["-C", sourceURL.path, "branch", "obsolete"])
        try runGit(["-C", sourceURL.path, "remote", "add", "origin", remoteURL.path])
        try runGit(["-C", sourceURL.path, "push", "--quiet", "origin", "main", "obsolete"])
        try runGit(["clone", "--quiet", remoteURL.path, repositoryURL.path])
        try runGit(["-C", repositoryURL.path, "config", "fetch.prune", "false"])
        try runGit(["-C", sourceURL.path, "push", "--quiet", "origin", "--delete", "obsolete"])

        try write("staged\n", to: "local.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "local.txt"])
        try write("working\n", to: "local.txt", in: repositoryURL)
        let localHead = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
        let localStatus = try gitOutput(["-C", repositoryURL.path, "status", "--short"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        _ = try await inspector.fetch(from: "origin", in: repository)
        try runGit([
            "-C", repositoryURL.path,
            "show-ref", "--verify", "--quiet", "refs/remotes/origin/obsolete"
        ])

        _ = try await inspector.fetch(from: "origin", pruning: true, in: repository)

        try runGit([
            "-C", repositoryURL.path,
            "show-ref", "--verify", "--quiet", "refs/remotes/origin/obsolete"
        ], expectedStatus: 1)
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"]), localHead)
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "status", "--short"]), localStatus)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "local.txt"), encoding: .utf8),
            "working\n"
        )
    }

    func testPullsFastForwardFromUpstreamWithoutReplacingLocalChanges() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let remoteURL = fixtureURL.appending(path: "remote.git", directoryHint: .isDirectory)
        let sourceURL = fixtureURL.appending(path: "source", directoryHint: .isDirectory)
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        try runGit(["init", "--bare", "--quiet", "--initial-branch=main", remoteURL.path])
        try initializeRepository(at: sourceURL)
        try write("initial\n", to: "remote.txt", in: sourceURL)
        try write("initial\n", to: "local.txt", in: sourceURL)
        try commitAll(in: sourceURL, message: "Initial")
        try runGit(["-C", sourceURL.path, "remote", "add", "origin", remoteURL.path])
        try runGit(["-C", sourceURL.path, "push", "--quiet", "--set-upstream", "origin", "main"])
        try runGit(["clone", "--quiet", remoteURL.path, repositoryURL.path])

        try write("remote\n", to: "remote.txt", in: sourceURL)
        try commitAll(in: sourceURL, message: "Remote")
        try runGit(["-C", sourceURL.path, "push", "--quiet"])
        let remoteHead = try gitOutput(["-C", sourceURL.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try write("local change\n", to: "local.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let pulledRepository = try await inspector.pull(in: repository)

        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            remoteHead
        )
        XCTAssertEqual(pulledRepository.upstream, .init(name: "origin/main", ahead: 0, behind: 0))
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "remote.txt"), encoding: .utf8),
            "remote\n"
        )
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "local.txt"), encoding: .utf8),
            "local change\n"
        )
        XCTAssertEqual(pulledRepository.changes.first?.unstaged, .modified)
    }

    func testPushesCurrentBranchWithoutChangingLocalState() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let remoteURL = fixtureURL.appending(path: "remote.git", directoryHint: .isDirectory)
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        try runGit(["init", "--bare", "--quiet", "--initial-branch=main", remoteURL.path])
        try initializeRepository(at: repositoryURL)
        try write("initial\n", to: "published.txt", in: repositoryURL)
        try write("initial\n", to: "local.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "remote", "add", "origin", remoteURL.path])
        try runGit([
            "-C", repositoryURL.path,
            "push", "--quiet", "--set-upstream", "origin", "main"
        ])

        try write("published\n", to: "published.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Publish")
        try write("local change\n", to: "local.txt", in: repositoryURL)
        let localHead = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        XCTAssertEqual(repository.upstream, .init(name: "origin/main", ahead: 1, behind: 0))

        let pushedRepository = try await inspector.push(in: repository)

        XCTAssertEqual(
            try gitOutput(["--git-dir", remoteURL.path, "rev-parse", "refs/heads/main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            localHead
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            localHead
        )
        XCTAssertEqual(pushedRepository.upstream, .init(name: "origin/main", ahead: 0, behind: 0))
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "local.txt"), encoding: .utf8),
            "local change\n"
        )
        XCTAssertEqual(
            pushedRepository.changes.first { $0.path == "local.txt" }?.unstaged,
            .modified
        )
    }

    func testPublishesCurrentBranchAndSetsUpstream() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let remoteURL = fixtureURL.appending(path: "remote.git", directoryHint: .isDirectory)
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        try runGit(["init", "--bare", "--quiet", "--initial-branch=main", remoteURL.path])
        try initializeRepository(at: repositoryURL)
        try write("published\n", to: "published.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature/publish"])
        try runGit(["-C", repositoryURL.path, "remote", "add", "origin", remoteURL.path])

        try write("staged\n", to: "staged.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "staged.txt"])
        try write("working\n", to: "working.txt", in: repositoryURL)
        let localHead = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let localStatus = try gitOutput([
            "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        XCTAssertEqual(repository.head, .branch("feature/publish"))
        XCTAssertNil(repository.upstream)

        let publishedRepository = try await inspector.push(in: repository)

        XCTAssertEqual(
            try gitOutput([
                "--git-dir", remoteURL.path,
                "rev-parse", "refs/heads/feature/publish"
            ]).trimmingCharacters(in: .whitespacesAndNewlines),
            localHead
        )
        XCTAssertEqual(
            publishedRepository.upstream,
            .init(name: "origin/feature/publish", ahead: 0, behind: 0)
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            localHead
        )
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
            ]),
            localStatus
        )
    }

    func testAddsRemoteAndPublishesCurrentBranch() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let remoteURL = fixtureURL.appending(path: "remote.git", directoryHint: .isDirectory)
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        try runGit(["init", "--bare", "--quiet", "--initial-branch=main", remoteURL.path])
        try initializeRepository(at: repositoryURL)
        try write("published\n", to: "published.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")

        try write("staged\n", to: "staged.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "staged.txt"])
        try write("working\n", to: "working.txt", in: repositoryURL)
        let localHead = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let localStatus = try gitOutput([
            "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        XCTAssertNil(repository.upstream)
        do {
            _ = try await inspector.push(in: repository)
            XCTFail("Expected Publish to request a remote")
        } catch let error as RepositoryPushError {
            XCTAssertEqual(error, .noRemote)
        }

        let publishedRepository = try await inspector.addRemoteAndPublish(
            named: "origin",
            url: remoteURL.path,
            in: repository
        )

        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "remote", "get-url", "origin"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            remoteURL.path
        )
        XCTAssertEqual(
            try gitOutput(["--git-dir", remoteURL.path, "rev-parse", "refs/heads/main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            localHead
        )
        XCTAssertEqual(publishedRepository.upstream, .init(name: "origin/main", ahead: 0, behind: 0))
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            localHead
        )
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
            ]),
            localStatus
        )
    }

    func testPublishesCurrentBranchToSelectedRemote() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let originURL = fixtureURL.appending(path: "origin.git", directoryHint: .isDirectory)
        let backupURL = fixtureURL.appending(path: "backup.git", directoryHint: .isDirectory)
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        try runGit(["init", "--bare", "--quiet", "--initial-branch=main", originURL.path])
        try runGit(["init", "--bare", "--quiet", "--initial-branch=main", backupURL.path])
        try initializeRepository(at: repositoryURL)
        try write("published\n", to: "published.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "remote", "add", "origin", originURL.path])
        try runGit(["-C", repositoryURL.path, "remote", "add", "backup", backupURL.path])

        try write("staged\n", to: "staged.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "staged.txt"])
        try write("working\n", to: "working.txt", in: repositoryURL)
        let localHead = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let localStatus = try gitOutput([
            "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        do {
            _ = try await inspector.push(in: repository)
            XCTFail("Expected Publish to request a remote selection")
        } catch let error as RepositoryPushError {
            XCTAssertEqual(error, .remoteSelectionRequired(["backup", "origin"]))
        }

        let publishedRepository = try await inspector.publish(to: "backup", in: repository)

        XCTAssertEqual(
            try gitOutput(["--git-dir", backupURL.path, "rev-parse", "refs/heads/main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            localHead
        )
        try runGit([
            "--git-dir", originURL.path,
            "show-ref", "--verify", "--quiet", "refs/heads/main"
        ], expectedStatus: 1)
        XCTAssertEqual(publishedRepository.upstream, .init(name: "backup/main", ahead: 0, behind: 0))
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            localHead
        )
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
            ]),
            localStatus
        )
    }

    func testReadsConfiguredRemotesWithoutChangingLocalState() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let originFetchURL = fixtureURL.appending(path: "origin-fetch.git")
        let originPushURL = fixtureURL.appending(path: "origin-push.git")
        let backupURL = fixtureURL.appending(path: "backup.git")
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        for remoteURL in [originFetchURL, originPushURL, backupURL] {
            try runGit(["init", "--bare", "--quiet", remoteURL.path])
        }
        try initializeRepository(at: repositoryURL)
        try write("initial\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "remote", "add", "origin", originFetchURL.path])
        try runGit([
            "-C", repositoryURL.path,
            "remote", "set-url", "--push", "origin", originPushURL.path
        ])
        try runGit(["-C", repositoryURL.path, "remote", "add", "backup", backupURL.path])
        try write("working\n", to: "working.txt", in: repositoryURL)
        let localHead = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
        let localStatus = try gitOutput([
            "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let remotes = try await inspector.remotes(in: repository)

        XCTAssertEqual(remotes, [
            .init(name: "backup", fetchURL: backupURL.path, pushURL: backupURL.path),
            .init(name: "origin", fetchURL: originFetchURL.path, pushURL: originPushURL.path)
        ])
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"]), localHead)
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
            ]),
            localStatus
        )
    }

    func testUpdatesConfiguredRemoteURLsWithoutChangingLocalState() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let oldFetchURL = fixtureURL.appending(path: "old-fetch.git")
        let oldPushURL = fixtureURL.appending(path: "old-push.git")
        let newFetchURL = fixtureURL.appending(path: "new-fetch.git")
        let newPushURL = fixtureURL.appending(path: "new-push.git")
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        for remoteURL in [oldFetchURL, oldPushURL, newFetchURL, newPushURL] {
            try runGit(["init", "--bare", "--quiet", remoteURL.path])
        }
        try initializeRepository(at: repositoryURL)
        try write("initial\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "remote", "add", "origin", oldFetchURL.path])
        try runGit([
            "-C", repositoryURL.path,
            "remote", "set-url", "--push", "origin", oldPushURL.path
        ])
        try write("working\n", to: "working.txt", in: repositoryURL)
        let localHead = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
        let localRefs = try gitOutput(["-C", repositoryURL.path, "show-ref"])
        let localStatus = try gitOutput([
            "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let remotes = try await inspector.updateRemote(
            named: "origin",
            renamingTo: "origin",
            fetchURL: newFetchURL.path,
            pushURL: newPushURL.path,
            in: repository
        )

        XCTAssertEqual(remotes, [
            .init(name: "origin", fetchURL: newFetchURL.path, pushURL: newPushURL.path)
        ])
        let reloadedRemotes = try await inspector.remotes(in: repository)
        XCTAssertEqual(reloadedRemotes, remotes)
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"]), localHead)
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "show-ref"]), localRefs)
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
            ]),
            localStatus
        )
    }

    func testRenamesConfiguredRemoteAndTrackingWithoutChangingLocalWork() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let remoteURL = fixtureURL.appending(path: "origin.git")
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        try runGit(["init", "--bare", "--quiet", remoteURL.path])
        try initializeRepository(at: repositoryURL)
        try write("initial\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "remote", "add", "origin", remoteURL.path])
        try runGit([
            "-C", repositoryURL.path,
            "push", "--quiet", "--set-upstream", "origin", "main"
        ])
        try write("staged\n", to: "staged.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "staged.txt"])
        try write("working\n", to: "working.txt", in: repositoryURL)

        let localHead = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
        let remoteHead = try gitOutput(["-C", remoteURL.path, "rev-parse", "refs/heads/main"])
        let trackingHead = try gitOutput([
            "-C", repositoryURL.path,
            "rev-parse", "refs/remotes/origin/main"
        ])
        let localStatus = try gitOutput([
            "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        XCTAssertEqual(repository.upstream?.name, "origin/main")

        let remotes = try await inspector.updateRemote(
            named: "origin",
            renamingTo: "primary",
            fetchURL: remoteURL.path,
            pushURL: remoteURL.path,
            in: repository
        )

        XCTAssertEqual(remotes, [
            .init(name: "primary", fetchURL: remoteURL.path, pushURL: remoteURL.path)
        ])
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "remote"]), "primary\n")
        try runGit([
            "-C", repositoryURL.path,
            "show-ref", "--verify", "--quiet", "refs/remotes/origin/main"
        ], expectedStatus: 1)
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path,
                "rev-parse", "refs/remotes/primary/main"
            ]),
            trackingHead
        )
        let updatedRepository = try await inspector.inspect(at: repositoryURL)
        XCTAssertEqual(updatedRepository.upstream?.name, "primary/main")
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"]), localHead)
        XCTAssertEqual(
            try gitOutput(["-C", remoteURL.path, "rev-parse", "refs/heads/main"]),
            remoteHead
        )
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
            ]),
            localStatus
        )
    }

    func testRemovesConfiguredRemoteWithoutChangingLocalWorkOrRemoteRepository() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let originURL = fixtureURL.appending(path: "origin.git")
        let backupURL = fixtureURL.appending(path: "backup.git")
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        for remoteURL in [originURL, backupURL] {
            try runGit(["init", "--bare", "--quiet", remoteURL.path])
        }
        try initializeRepository(at: repositoryURL)
        try write("initial\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "remote", "add", "origin", originURL.path])
        try runGit(["-C", repositoryURL.path, "remote", "add", "backup", backupURL.path])
        try runGit(["-C", repositoryURL.path, "push", "--quiet", "--set-upstream", "origin", "main"])
        try runGit(["-C", repositoryURL.path, "push", "--quiet", "backup", "main"])
        try runGit(["-C", repositoryURL.path, "fetch", "--quiet", "backup"])
        try write("staged\n", to: "staged.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "staged.txt"])
        try write("working\n", to: "working.txt", in: repositoryURL)

        let localHead = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
        let localBranch = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "refs/heads/main"
        ])
        let backupTrackingBranch = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "refs/remotes/backup/main"
        ])
        let remoteBranch = try gitOutput([
            "--git-dir", originURL.path, "rev-parse", "refs/heads/main"
        ])
        let localStatus = try gitOutput([
            "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        XCTAssertEqual(repository.upstream?.name, "origin/main")

        let updatedRepository = try await inspector.removeRemote(
            named: "origin",
            in: repository
        )

        XCTAssertNil(updatedRepository.upstream)
        let remainingRemotes = try await inspector.remotes(in: updatedRepository)
        XCTAssertEqual(
            remainingRemotes,
            [.init(name: "backup", fetchURL: backupURL.path, pushURL: backupURL.path)]
        )
        try runGit([
            "-C", repositoryURL.path,
            "show-ref", "--verify", "--quiet", "refs/remotes/origin/main"
        ], expectedStatus: 1)
        try runGit([
            "-C", repositoryURL.path,
            "config", "--get", "branch.main.remote"
        ], expectedStatus: 1)
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/remotes/backup/main"]),
            backupTrackingBranch
        )
        XCTAssertEqual(
            try gitOutput(["--git-dir", originURL.path, "rev-parse", "refs/heads/main"]),
            remoteBranch
        )
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"]), localHead)
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"]),
            localBranch
        )
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
            ]),
            localStatus
        )
    }

    func testTestsConfiguredRemoteFetchConnectionWithoutChangingLocalState() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let originURL = fixtureURL.appending(path: "origin.git")
        let missingURL = fixtureURL.appending(path: "missing.git")
        let repositoryURL = fixtureURL.appending(path: "repository", directoryHint: .isDirectory)
        try runGit(["init", "--bare", "--quiet", originURL.path])
        try initializeRepository(at: repositoryURL)
        try write("initial\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "remote", "add", "origin", originURL.path])
        try runGit([
            "-C", repositoryURL.path,
            "remote", "set-url", "--push", "origin", missingURL.path
        ])
        try write("staged\n", to: "staged.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "staged.txt"])
        try write("working\n", to: "working.txt", in: repositoryURL)

        let localHead = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
        let localRefs = try gitOutput(["-C", repositoryURL.path, "show-ref"])
        let localStatus = try gitOutput([
            "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
        ])
        let configuredURLs = try gitOutput(["-C", repositoryURL.path, "remote", "-v"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        try await inspector.testRemoteConnection(named: "origin", in: repository)

        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "remote", "-v"]), configuredURLs)
        try runGit(["-C", repositoryURL.path, "remote", "set-url", "origin", missingURL.path])
        let unreachableURLs = try gitOutput(["-C", repositoryURL.path, "remote", "-v"])
        do {
            try await inspector.testRemoteConnection(named: "origin", in: repository)
            XCTFail("Expected an unreachable Remote error")
        } catch let error as RepositoryRemoteError {
            guard case .connectionFailed = error else {
                return XCTFail("Expected connectionFailed, got \(error)")
            }
        }

        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "remote", "-v"]), unreachableURLs)
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"]), localHead)
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "show-ref"]), localRefs)
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path, "status", "--porcelain=v1", "--untracked-files=all"
            ]),
            localStatus
        )
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
        try runGit(["-C", repositoryURL.path, "branch", "feature/reference", initialID])
        try runGit(["-C", repositoryURL.path, "tag", "v-light", secondID])
        try runGit([
            "-C", repositoryURL.path, "tag", "-a", "v-annotated",
            "-m", "Annotated fixture", initialID
        ])
        try runGit([
            "-C", repositoryURL.path, "update-ref", "refs/remotes/origin/main", secondID
        ])
        try runGit([
            "-C", repositoryURL.path, "symbolic-ref",
            "refs/remotes/origin/HEAD", "refs/remotes/origin/main"
        ])

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
        XCTAssertEqual(latest.references, [
            .init(name: "main", kind: .branch),
            .init(name: "origin/main", kind: .remoteBranch),
            .init(name: "v-light", kind: .tag),
        ])

        let latestFiles = try await inspector.files(for: latest, in: repository)
        let latestFile = try XCTUnwrap(latestFiles.first)
        XCTAssertEqual(latestFile.path, "notes [한글].txt")
        XCTAssertEqual(latestFile.state, .modified)
        let patch = try await inspector.patch(
            for: latestFile,
            in: latest,
            repository: repository
        )
        XCTAssertEqual(patch.commitID, secondID)
        XCTAssertEqual(patch.fileID, latestFile.id)
        guard case .text(let lines) = patch.content else {
            return XCTFail("Expected text commit patch")
        }
        XCTAssertTrue(lines.contains { $0.kind == .deletion && $0.text == "-first" })
        XCTAssertTrue(lines.contains { $0.kind == .addition && $0.text == "+second" })

        let initial = try XCTUnwrap(history.commits.last)
        XCTAssertEqual(initial.references, [
            .init(name: "feature/reference", kind: .branch),
            .init(name: "v-annotated", kind: .tag),
        ])
        let initialFiles = try await inspector.files(for: initial, in: repository)
        let initialFile = try XCTUnwrap(initialFiles.first)
        XCTAssertEqual(initialFile.state, .added)
        let initialPatch = try await inspector.patch(
            for: initialFile,
            in: initial,
            repository: repository
        )
        guard case .text(let initialLines) = initialPatch.content else {
            return XCTFail("Expected text root commit patch")
        }
        XCTAssertTrue(initialLines.contains { $0.kind == .addition && $0.text == "+first" })
    }

    func testBuildsAndValidatesEditedInteractiveRebasePlanWithoutChangingRepository() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("initial\n", to: "notes.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("first\n", to: "notes.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "First change")
        let firstID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("second\n", to: "notes.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Second change")
        let secondID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("third\n", to: "notes.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Third change")
        let thirdID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        let inspector = RepositoryInspector()
        let repositoryBefore = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repositoryBefore)
        let firstCommit = try XCTUnwrap(history.commits.first { $0.id == firstID })
        let plan = try await inspector.interactiveRebasePlan(
            startingAt: firstCommit,
            in: repositoryBefore
        )
        var editedPlan = plan
        editedPlan.steps.swapAt(0, 2)
        editedPlan.steps[0].action = .pick
        editedPlan.steps[1].action = .reword
        editedPlan.steps[2].action = .squash

        var invalidPlan = plan
        invalidPlan.steps[0].action = .drop
        invalidPlan.steps[1].action = .fixup

        var emptyPlan = plan
        for index in emptyPlan.steps.indices {
            emptyPlan.steps[index].action = .drop
        }
        let repositoryAfter = try await inspector.inspect(at: repositoryURL)

        XCTAssertEqual(plan.steps.map(\.id), [firstID, secondID, thirdID])
        XCTAssertEqual(
            plan.steps.map(\.subject),
            ["First change", "Second change", "Third change"]
        )
        XCTAssertEqual(editedPlan.steps.map(\.id), [thirdID, secondID, firstID])
        XCTAssertEqual(editedPlan.steps.map(\.action), [.pick, .reword, .squash])
        XCTAssertNil(editedPlan.validationError)
        XCTAssertEqual(
            invalidPlan.validationError,
            .actionNeedsPreviousCommit(stepID: secondID)
        )
        XCTAssertEqual(emptyPlan.validationError, .noCommits)
        XCTAssertEqual(repositoryAfter, repositoryBefore)
    }

    func testExecutesEditedInteractiveRebasePlanWithoutMovingOtherBranches() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "base.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Base")
        try write("a\n", to: "a.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "A")
        let aID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("b\n", to: "b.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "B")
        let bID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("c\n", to: "c.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "C")
        let cID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("d\n", to: "d.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "D")
        let originalHead = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["-C", repositoryURL.path, "branch", "archive", originalHead])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repository)
        let startCommit = try XCTUnwrap(history.commits.first { $0.id == aID })
        var plan = try await inspector.interactiveRebasePlan(
            startingAt: startCommit,
            in: repository
        )
        let stepsByID = Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.id, $0) })
        plan.steps = try [cID, bID, originalHead, aID].map { try XCTUnwrap(stepsByID[$0]) }
        plan.steps[0].action = .pick
        plan.steps[1].action = .reword
        plan.steps[2].action = .squash
        plan.steps[3].action = .drop

        let updatedRepository: RepositorySummary
        do {
            updatedRepository = try await inspector.executeInteractiveRebase(
                plan,
                rewordMessages: [bID: "Renamed B's change\n\n한글 body"],
                startingAt: startCommit,
                in: repository
            )
        } catch {
            XCTFail(String(reflecting: error))
            return
        }

        XCTAssertEqual(updatedRepository.head, .branch("main"))
        XCTAssertNil(updatedRepository.operation)
        XCTAssertTrue(updatedRepository.changes.isEmpty)
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path,
                "log", "--reverse", "--format=%s", "HEAD~2..HEAD",
            ]).split(whereSeparator: \.isNewline).map(String.init),
            ["C", "Renamed B's change"]
        )
        let message = try gitOutput([
            "-C", repositoryURL.path, "log", "-1", "--format=%B",
        ])
        XCTAssertTrue(message.contains("한글 body"))
        XCTAssertTrue(message.contains("D"))
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path, "ls-tree", "-r", "--name-only", "HEAD",
            ]).split(whereSeparator: \.isNewline).map(String.init),
            ["b.txt", "base.txt", "c.txt", "d.txt"]
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "archive"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            originalHead
        )
    }

    func testLeavesConflictingInteractiveRebaseReadyToAbort() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "value.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Base")
        try write("one\n", to: "value.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "One")
        let oneID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("two\n", to: "value.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Two")
        let originalHead = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repository)
        let startCommit = try XCTUnwrap(history.commits.first { $0.id == oneID })
        var plan = try await inspector.interactiveRebasePlan(
            startingAt: startCommit,
            in: repository
        )
        plan.steps.swapAt(0, 1)

        let stopped = try await inspector.executeInteractiveRebase(
            plan,
            rewordMessages: [:],
            startingAt: startCommit,
            in: repository
        )

        XCTAssertEqual(stopped.operation?.kind, .rebase)
        XCTAssertGreaterThan(stopped.operation?.unresolvedConflictCount ?? 0, 0)
        XCTAssertTrue(stopped.changes.contains { $0.isConflicted })
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            originalHead
        )

        let restored = try await inspector.abortOperation(in: stopped)
        XCTAssertEqual(restored.head, .branch("main"))
        XCTAssertNil(restored.operation)
        XCTAssertTrue(restored.changes.isEmpty)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "value.txt"), encoding: .utf8),
            "two\n"
        )
    }

    func testReadsHeadReflogRecoveryPointsWithoutChangingRepository() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("initial\n", to: "notes.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        let initialID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try write("latest\n", to: "notes.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Latest")
        let latestID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "topic"])
        try runGit(["-C", repositoryURL.path, "reset", "--hard", "--quiet", initialID])

        let inspector = RepositoryInspector()
        let repositoryBefore = try await inspector.inspect(at: repositoryURL)
        let entries = try await inspector.reflog(in: repositoryBefore)
        let repositoryAfter = try await inspector.inspect(at: repositoryURL)

        XCTAssertEqual(repositoryAfter, repositoryBefore)
        XCTAssertEqual(entries.map(\.selector), [
            "HEAD@{0}", "HEAD@{1}", "HEAD@{2}", "HEAD@{3}",
        ])
        XCTAssertEqual(entries.map(\.commitID), [initialID, latestID, latestID, initialID])
        XCTAssertTrue(entries[0].action.contains("reset: moving to"))
        XCTAssertTrue(entries[1].action.contains("moving from main to topic"))
        XCTAssertEqual(entries[0].actorName, "Gallae Tests")
        XCTAssertEqual(entries[0].actorEmail, "tests@gallae.local")
        XCTAssertGreaterThan(entries[0].occurredAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
    }

    func testRevertsSelectedCommitAsNewCommit() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("enabled\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Enable feature")
        let selectedCommitID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("keep\n", to: "later.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Later work")
        let previousHeadID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repository)
        let selectedCommit = try XCTUnwrap(
            history.commits.first { $0.id == selectedCommitID }
        )

        let updatedRepository = try await inspector.revertCommit(
            selectedCommit,
            in: repository
        )

        let newHeadID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(newHeadID, previousHeadID)
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD^"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            previousHeadID
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "log", "-1", "--format=%s"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "Revert \"Enable feature\""
        )
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appending(path: "feature.txt"),
                encoding: .utf8
            ),
            "base\n"
        )
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appending(path: "later.txt"),
                encoding: .utf8
            ),
            "keep\n"
        )
        XCTAssertTrue(updatedRepository.changes.isEmpty)
        let updatedHistory = try await inspector.history(in: updatedRepository)
        XCTAssertEqual(updatedHistory.headCommitID, newHeadID)
        XCTAssertTrue(updatedHistory.commits.contains { $0.id == selectedCommitID })
    }

    func testRevertsMergeCommitAgainstSelectedMainline() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "base.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "branch", "feature"])

        try write("main\n", to: "main.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main work")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature work")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "main"])
        try runGit([
            "-C", repositoryURL.path,
            "merge", "--quiet", "--no-ff", "-m", "Merge feature", "feature"
        ])
        let mergeCommitID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repository)
        let mergeCommit = try XCTUnwrap(
            history.commits.first { $0.id == mergeCommitID }
        )

        let updatedRepository = try await inspector.revertCommit(
            mergeCommit,
            mainlineParent: 1,
            in: repository
        )

        XCTAssertTrue(updatedRepository.changes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryURL.appending(path: "main.txt").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryURL.appending(path: "feature.txt").path
        ))
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD^"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            mergeCommitID
        )
        let updatedHistory = try await inspector.history(in: updatedRepository)
        XCTAssertTrue(updatedHistory.commits.contains { $0.id == mergeCommitID })
    }

    func testMixedResetMovesCurrentBranchAndKeepsWorkingTreeFiles() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "notes.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("middle\n", to: "notes.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Middle")
        let targetID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("latest\n", to: "notes.txt", in: repositoryURL)
        try write("keep\n", to: "later.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Latest")

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repository)
        let target = try XCTUnwrap(history.commits.first { $0.id == targetID })

        let updatedRepository = try await inspector.resetCurrentBranch(
            to: target,
            mode: .mixed,
            in: repository
        )

        XCTAssertEqual(updatedRepository.head, .branch("main"))
        XCTAssertTrue(updatedRepository.changes.allSatisfy { $0.staged == nil })
        let notesChange = try XCTUnwrap(
            updatedRepository.changes.first { $0.path == "notes.txt" }
        )
        XCTAssertEqual(notesChange.unstaged, .modified)
        let laterChange = try XCTUnwrap(
            updatedRepository.changes.first { $0.path == "later.txt" }
        )
        XCTAssertEqual(laterChange.unstaged, .untracked)
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appending(path: "notes.txt"),
                encoding: .utf8
            ),
            "latest\n"
        )
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appending(path: "later.txt"),
                encoding: .utf8
            ),
            "keep\n"
        )
        let updatedHistory = try await inspector.history(in: updatedRepository)
        XCTAssertEqual(updatedHistory.headCommitID, targetID)
    }

    func testSoftResetMovesCurrentBranchAndKeepsChangesStaged() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "notes.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("middle\n", to: "notes.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Middle")
        let targetID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("latest\n", to: "notes.txt", in: repositoryURL)
        try write("keep\n", to: "later.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Latest")

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repository)
        let target = try XCTUnwrap(history.commits.first { $0.id == targetID })

        let updatedRepository = try await inspector.resetCurrentBranch(
            to: target,
            mode: .soft,
            in: repository
        )

        XCTAssertEqual(updatedRepository.head, .branch("main"))
        XCTAssertTrue(updatedRepository.changes.allSatisfy { $0.unstaged == nil })
        let notesChange = try XCTUnwrap(
            updatedRepository.changes.first { $0.path == "notes.txt" }
        )
        XCTAssertEqual(notesChange.staged, .modified)
        let laterChange = try XCTUnwrap(
            updatedRepository.changes.first { $0.path == "later.txt" }
        )
        XCTAssertEqual(laterChange.staged, .added)
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appending(path: "notes.txt"),
                encoding: .utf8
            ),
            "latest\n"
        )
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appending(path: "later.txt"),
                encoding: .utf8
            ),
            "keep\n"
        )
        let updatedHistory = try await inspector.history(in: updatedRepository)
        XCTAssertEqual(updatedHistory.headCommitID, targetID)
    }

    func testHardResetMovesCurrentBranchAndMatchesTargetFiles() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "notes.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("middle\n", to: "notes.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Middle")
        let targetID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("latest\n", to: "notes.txt", in: repositoryURL)
        try write("remove\n", to: "later.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Latest")

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repository)
        let target = try XCTUnwrap(history.commits.first { $0.id == targetID })

        let updatedRepository = try await inspector.resetCurrentBranch(
            to: target,
            mode: .hard,
            in: repository
        )

        XCTAssertEqual(updatedRepository.head, .branch("main"))
        XCTAssertTrue(updatedRepository.changes.isEmpty)
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appending(path: "notes.txt"),
                encoding: .utf8
            ),
            "middle\n"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryURL.appending(path: "later.txt").path
            )
        )
        let updatedHistory = try await inspector.history(in: updatedRepository)
        XCTAssertEqual(updatedHistory.headCommitID, targetID)
    }

    func testReadsStashesAndSelectedFilePatch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "notes [한글].txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")

        try write("stashed\n", to: "notes [한글].txt", in: repositoryURL)
        try write("draft\n", to: "new [한글].txt", in: repositoryURL)
        try runGit([
            "-C", repositoryURL.path, "stash", "push", "--include-untracked",
            "--message", "First recovery point"
        ])
        try write("newest\n", to: "notes [한글].txt", in: repositoryURL)
        try runGit([
            "-C", repositoryURL.path, "stash", "push",
            "--message", "Newest recovery point"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let stashes = try await inspector.stashes(in: repository)

        XCTAssertEqual(stashes.map(\.reference), ["stash@{0}", "stash@{1}"])
        XCTAssertTrue(stashes[0].subject.contains("Newest recovery point"))
        XCTAssertTrue(stashes[1].subject.contains("First recovery point"))
        XCTAssertTrue(stashes.allSatisfy { !$0.id.isEmpty })
        XCTAssertTrue(stashes.allSatisfy { $0.createdAt > Date(timeIntervalSince1970: 0) })

        let files = try await inspector.files(for: stashes[1], in: repository)
        XCTAssertEqual(Set(files.map(\.path)), Set(["new [한글].txt", "notes [한글].txt"]))

        let trackedFile = try XCTUnwrap(files.first { $0.path == "notes [한글].txt" })
        let trackedPatch = try await inspector.patch(
            for: trackedFile,
            in: stashes[1],
            repository: repository
        )
        guard case .text(let trackedLines) = trackedPatch.content else {
            return XCTFail("Expected text Stash patch")
        }
        XCTAssertTrue(trackedLines.contains { $0.kind == .deletion && $0.text == "-base" })
        XCTAssertTrue(trackedLines.contains { $0.kind == .addition && $0.text == "+stashed" })

        let untrackedFile = try XCTUnwrap(files.first { $0.path == "new [한글].txt" })
        let untrackedPatch = try await inspector.patch(
            for: untrackedFile,
            in: stashes[1],
            repository: repository
        )
        guard case .text(let untrackedLines) = untrackedPatch.content else {
            return XCTFail("Expected captured untracked file patch")
        }
        XCTAssertTrue(untrackedLines.contains { $0.kind == .addition && $0.text == "+draft" })
    }

    func testCreatesStashWithMessageAndOptionalUntrackedFiles() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("ignored.txt\n", to: ".gitignore", in: repositoryURL)
        try write("base\n", to: "tracked.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        let headID = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try write("tracked change\n", to: "tracked.txt", in: repositoryURL)
        try write("draft\n", to: "draft [한글].txt", in: repositoryURL)
        try write("ignored\n", to: "ignored.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "tracked.txt"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let trackedOnly = try await inspector.createStash(
            message: "Tracked checkpoint",
            includeUntracked: false,
            in: repository
        )

        XCTAssertEqual(trackedOnly.changes.map(\.path), ["draft [한글].txt"])
        XCTAssertEqual(trackedOnly.changes.first?.unstaged, .untracked)
        var stashes = try await inspector.stashes(in: trackedOnly)
        XCTAssertTrue(stashes[0].subject.contains("Tracked checkpoint"))
        let trackedFiles = try await inspector.files(for: stashes[0], in: trackedOnly)
        XCTAssertEqual(trackedFiles.map(\.path), ["tracked.txt"])

        try write("second change\n", to: "tracked.txt", in: repositoryURL)
        let everything = try await inspector.createStash(
            message: "Everything [한글]",
            includeUntracked: true,
            in: trackedOnly
        )

        XCTAssertTrue(everything.changes.isEmpty)
        stashes = try await inspector.stashes(in: everything)
        XCTAssertTrue(stashes[0].subject.contains("Everything [한글]"))
        let allFiles = try await inspector.files(for: stashes[0], in: everything)
        XCTAssertEqual(
            Set(allFiles.map(\.path)),
            Set(["draft [한글].txt", "tracked.txt"])
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryURL.appending(path: "ignored.txt").path
        ))
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            headID
        )
    }

    func testAppliesStashWithIndexAndKeepsEntry() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "tracked.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        let headID = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try write("staged\n", to: "tracked.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "tracked.txt"])
        try write("working\n", to: "tracked.txt", in: repositoryURL)
        try write("draft\n", to: "draft [한글].txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let stashedRepository = try await inspector.createStash(
            message: "Apply checkpoint",
            includeUntracked: true,
            in: repository
        )
        let stashes = try await inspector.stashes(in: stashedRepository)
        let stash = try XCTUnwrap(stashes.first)

        let appliedRepository = try await inspector.applyStash(stash, in: stashedRepository)

        let remainingStashes = try await inspector.stashes(in: appliedRepository)
        XCTAssertEqual(remainingStashes.map(\.id), [stash.id])
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            headID
        )
        let tracked = try XCTUnwrap(
            appliedRepository.changes.first { $0.path == "tracked.txt" }
        )
        XCTAssertEqual(tracked.staged, .modified)
        XCTAssertEqual(tracked.unstaged, .modified)
        let untracked = try XCTUnwrap(
            appliedRepository.changes.first { $0.path == "draft [한글].txt" }
        )
        XCTAssertEqual(untracked.unstaged, .untracked)
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appending(path: "tracked.txt"),
                encoding: .utf8
            ),
            "working\n"
        )
    }

    func testApplyStashFailureKeepsDirtyWorkingTreeAndStash() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "tracked.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("stashed\n", to: "tracked.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let stashedRepository = try await inspector.createStash(
            message: "Dirty failure",
            includeUntracked: false,
            in: repository
        )
        let stashes = try await inspector.stashes(in: stashedRepository)
        let stash = try XCTUnwrap(stashes.first)
        try write("local\n", to: "tracked.txt", in: repositoryURL)
        let dirtyRepository = try await inspector.inspect(at: repositoryURL)

        do {
            _ = try await inspector.applyStash(stash, in: dirtyRepository)
            XCTFail("Expected the overlapping local change to reject Stash Apply")
        } catch let error as RepositoryStashError {
            guard case .applyFailed = error else {
                return XCTFail("Expected an Apply failure, got \(error)")
            }
        }

        let refreshedRepository = try await inspector.inspect(at: repositoryURL)
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appending(path: "tracked.txt"),
                encoding: .utf8
            ),
            "local\n"
        )
        XCTAssertEqual(refreshedRepository.changes.first?.unstaged, .modified)
        let remainingStashes = try await inspector.stashes(in: refreshedRepository)
        XCTAssertEqual(remainingStashes.map(\.id), [stash.id])
    }

    func testApplyStashConflictKeepsStashAndReportsConflictState() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "tracked.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("stashed\n", to: "tracked.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let stashedRepository = try await inspector.createStash(
            message: "Conflict checkpoint",
            includeUntracked: false,
            in: repository
        )
        let stashes = try await inspector.stashes(in: stashedRepository)
        let stash = try XCTUnwrap(stashes.first)
        try write("new head\n", to: "tracked.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Move HEAD")
        let headID = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let movedRepository = try await inspector.inspect(at: repositoryURL)

        do {
            _ = try await inspector.applyStash(stash, in: movedRepository)
            XCTFail("Expected Stash Apply to report a conflict")
        } catch let error as RepositoryStashError {
            guard case .applyFailed = error else {
                return XCTFail("Expected an Apply failure, got \(error)")
            }
        }

        let conflictedRepository = try await inspector.inspect(at: repositoryURL)
        XCTAssertTrue(conflictedRepository.changes.contains(where: \.isConflicted))
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            headID
        )
        let remainingStashes = try await inspector.stashes(in: conflictedRepository)
        XCTAssertEqual(remainingStashes.map(\.id), [stash.id])
    }

    func testDropsSelectedStashWithoutChangingRepositoryState() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "tracked.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")

        let inspector = RepositoryInspector()
        var repository = try await inspector.inspect(at: repositoryURL)
        try write("first\n", to: "tracked.txt", in: repositoryURL)
        repository = try await inspector.createStash(
            message: "First checkpoint",
            includeUntracked: false,
            in: repository
        )
        try write("second\n", to: "tracked.txt", in: repositoryURL)
        repository = try await inspector.createStash(
            message: "Second checkpoint",
            includeUntracked: false,
            in: repository
        )
        let stashesAfterSecond = try await inspector.stashes(in: repository)
        let selectedStash = try XCTUnwrap(
            stashesAfterSecond.first { $0.subject.contains("First checkpoint") }
        )

        try write("third\n", to: "tracked.txt", in: repositoryURL)
        repository = try await inspector.createStash(
            message: "Third checkpoint",
            includeUntracked: false,
            in: repository
        )
        let stashesBeforeDrop = try await inspector.stashes(in: repository)
        try write("staged\n", to: "tracked.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "tracked.txt"])
        try write("working\n", to: "tracked.txt", in: repositoryURL)
        try write("draft\n", to: "draft.txt", in: repositoryURL)
        let dirtyRepository = try await inspector.inspect(at: repositoryURL)
        let headBeforeDrop = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
        let statusBeforeDrop = try gitOutput([
            "-C", repositoryURL.path,
            "status", "--porcelain=v2", "--untracked-files=all"
        ])

        let updatedRepository = try await inspector.dropStash(
            selectedStash,
            in: dirtyRepository
        )

        let remainingStashes = try await inspector.stashes(in: updatedRepository)
        XCTAssertEqual(
            remainingStashes.map(\.id),
            stashesBeforeDrop.filter { $0.id != selectedStash.id }.map(\.id)
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"]),
            headBeforeDrop
        )
        XCTAssertEqual(
            try gitOutput([
                "-C", repositoryURL.path,
                "status", "--porcelain=v2", "--untracked-files=all"
            ]),
            statusBeforeDrop
        )
    }

    func testReadsRenamedCommitFileAndOnlyItsPatch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write(
            "shared one\nshared two\nbefore\n",
            to: "old [한글].txt",
            in: repositoryURL
        )
        try write("other before\n", to: "other.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")

        try runGit([
            "-C", repositoryURL.path,
            "mv", "--", "old [한글].txt", "new [한글].txt"
        ])
        try write(
            "shared one\nshared two\nafter\n",
            to: "new [한글].txt",
            in: repositoryURL
        )
        try write("other after\n", to: "other.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Rename")

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repository)
        let commit = try XCTUnwrap(history.commits.first)
        let files = try await inspector.files(for: commit, in: repository)
        let renamed = try XCTUnwrap(files.first { $0.state == .renamed })

        XCTAssertEqual(renamed.path, "new [한글].txt")
        XCTAssertEqual(renamed.originalPath, "old [한글].txt")
        XCTAssertEqual(files.first { $0.path == "other.txt" }?.state, .modified)

        let patch = try await inspector.patch(
            for: renamed,
            in: commit,
            repository: repository
        )
        guard case .text(let lines) = patch.content else {
            return XCTFail("Expected text commit file patch")
        }
        XCTAssertEqual(lines.filter { $0.text.hasPrefix("diff --git ") }.count, 1)
        XCTAssertTrue(lines.contains { $0.kind == .addition && $0.text == "+after" })
        XCTAssertFalse(lines.contains { $0.text.contains("other after") })
    }

    func testDiffLineCountsExcludeHeadersAndContext() throws {
        let lines: [RepositoryDiff.Line] = [
            .init(id: 0, kind: .metadata, oldLineNumber: nil, newLineNumber: nil, text: "+++ b/file.txt"),
            .init(id: 1, kind: .hunk, oldLineNumber: nil, newLineNumber: nil, text: "@@ -1,2 +1,3 @@"),
            .init(id: 2, kind: .context, oldLineNumber: 1, newLineNumber: 1, text: " unchanged"),
            .init(id: 3, kind: .deletion, oldLineNumber: 2, newLineNumber: nil, text: "-old"),
            .init(id: 4, kind: .addition, oldLineNumber: nil, newLineNumber: 2, text: "+new"),
            .init(id: 5, kind: .addition, oldLineNumber: nil, newLineNumber: 3, text: "+more")
        ]
        let counts = try XCTUnwrap(RepositoryDiff.Section.Content.text(lines).lineChangeCounts)
        XCTAssertEqual(counts.added, 2)
        XCTAssertEqual(counts.removed, 1)
        XCTAssertNil(RepositoryDiff.Section.Content.binary.lineChangeCounts)
        XCTAssertEqual(RepositoryDiff.Section.Content.text([]).lineChangeCounts?.added, 0)
    }

    func testDiffPresentationUsesVisibleContentWithoutChangingPreference() {
        let addition = RepositoryDiff.Line(id: 0, kind: .addition, oldLineNumber: nil, newLineNumber: 1, text: "+new")
        let context = RepositoryDiff.Line(id: 1, kind: .context, oldLineNumber: 1, newLineNumber: 1, text: " old")
        let preferred = RepositoryDiffLayout.split
        let newFile = RepositoryDiffPresentation(content: .text([addition]), preferred: preferred)
        XCTAssertFalse(newFile.canSplit)
        XCTAssertEqual(newFile.layout, .unified)
        let edit = RepositoryDiffPresentation(content: .text([context, addition]), preferred: preferred)
        XCTAssertTrue(edit.canSplit)
        XCTAssertEqual(edit.layout, .split)
        XCTAssertEqual(RepositoryDiffPresentation(content: .binary, preferred: preferred).layout, .unified)
        XCTAssertFalse(RepositoryDiffPresentation(content: nil, preferred: preferred).canSplit)
        XCTAssertEqual(preferred, .split)
    }

    @MainActor
    func testRefreshPreservesSavedFileSelectionAndChangingRevisionResetsIt() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try initializeRepository(at: root)
        try write("first\n", to: "a.txt", in: root)
        try write("second\n", to: "b.txt", in: root)
        try commitAll(in: root, message: "Initial")
        try write("changed\n", to: "a.txt", in: root)
        try commitAll(in: root, message: "Edit")
        try write("stashed a\n", to: "a.txt", in: root)
        try write("stashed b\n", to: "b.txt", in: root)
        try runGit(["-C", root.path, "stash", "push", "-m", "Saved"])
        let suite = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: LibraryStore(defaults: defaults))
        await model.openRepository(at: root)
        await model.loadHistory()
        guard case .loaded(let history) = model.historyState else { return XCTFail("Expected history") }
        let initial = try XCTUnwrap(history.commits.last)
        model.selectedHistoryCommitID = initial.id
        await model.loadSelectedCommitFiles()
        model.selectedHistoryFileID = "b.txt"
        await model.loadSelectedCommitPatch()
        let originalPatch = model.commitPatchState
        await model.loadStashes()
        await model.loadSelectedStashFiles()
        model.selectedStashFileID = "b.txt"
        await model.loadSelectedStashPatch()
        let stashID = model.selectedStashID
        let originalStashPatch = model.stashPatchState

        await model.refreshRepository()
        XCTAssertEqual(model.commitPatchState, originalPatch)
        XCTAssertEqual(model.stashPatchState, originalStashPatch)
        await model.loadHistory()
        await model.loadSelectedCommitFiles()
        await model.loadSelectedCommitPatch()
        await model.loadStashes()
        await model.loadSelectedStashFiles()
        await model.loadSelectedStashPatch()
        XCTAssertEqual(model.selectedHistoryCommitID, initial.id)
        XCTAssertEqual(model.selectedHistoryFileID, "b.txt")
        XCTAssertEqual(model.commitPatchState, originalPatch)
        XCTAssertEqual(model.selectedStashID, stashID)
        XCTAssertEqual(model.selectedStashFileID, "b.txt")
        XCTAssertEqual(model.stashPatchState, originalStashPatch)

        // A vanished selection falls back to an existing file.
        model.selectedHistoryFileID = "missing.txt"
        await model.loadSelectedCommitFiles()
        XCTAssertEqual(model.selectedHistoryFileID, "a.txt")
        model.selectedHistoryCommitID = history.commits.first?.id
        XCTAssertNil(model.selectedHistoryFileID)
        XCTAssertEqual(model.commitPatchState, .noSelection)
        await model.loadSelectedCommitFiles()
        XCTAssertEqual(model.selectedHistoryFileID, "a.txt")

        // A deleted stash cannot keep the previous file or patch on screen.
        try runGit(["-C", root.path, "stash", "drop"])
        await model.refreshRepository()
        await model.loadStashes()
        XCTAssertNil(model.selectedStashID)
        XCTAssertNil(model.selectedStashFileID)
        XCTAssertEqual(model.stashPatchState, .noSelection)
    }

    func testResizableHSplitLeadingPaneYieldsThenBothShrink() {
        func width(_ preferred: CGFloat, total: CGFloat) -> CGFloat {
            ResizableHSplitLayout.leadingWidth(
                preferred: preferred, leadingMinimum: 320, leadingMaximum: nil, trailingMinimum: 400, total: total
            )
        }
        XCTAssertEqual(width(320, total: 1000), 320, "both minimums fit: the preferred width")
        XCTAssertEqual(width(100, total: 1000), 320, "never below the leading minimum while there is room")
        XCTAssertEqual(width(450, total: 801), 400, "too wide: the leading pane yields to keep the trailing minimum")
        XCTAssertEqual(width(320, total: 361), 160, "narrower than both minimums: 320:400 of the 360 left")
        XCTAssertEqual(width(340.6, total: 1000.8), 341, "whole points only, so lazy stacks accept the width")
        XCTAssertEqual(
            ResizableHSplitLayout.leadingWidth(
                preferred: 500, leadingMinimum: 160, leadingMaximum: 280, trailingMinimum: 230, total: 1000
            ),
            280,
            "the leading maximum caps the preferred width"
        )
    }

    func testPairsSplitDiffRowsAndKeepsFullWidthLines() {
        func line(_ id: Int, _ kind: RepositoryDiff.Line.Kind, old: Int? = nil, new: Int? = nil) -> RepositoryDiff.Line {
            .init(id: id, kind: kind, oldLineNumber: old, newLineNumber: new, text: "\(id)")
        }
        let lines = [
            line(0, .metadata),
            line(1, .hunk),
            line(2, .context, old: 1, new: 1),
            line(3, .deletion, old: 2),
            line(4, .deletion, old: 3),
            line(5, .addition, new: 2),
            line(6, .context, old: 4, new: 3),
            line(7, .addition, new: 4),
            line(8, .addition, new: 5),
            line(9, .deletion, old: 5)
        ]

        let rows = RepositoryDiffSplitRow.rows(from: lines)

        XCTAssertEqual(rows.map(\.id), [0, 1, 2, 3, 4, 6, 9, 8])
        XCTAssertEqual(rows[0].full?.id, 0)
        XCTAssertEqual(rows[1].full?.id, 1)
        XCTAssertEqual(rows[2].old?.id, 2)
        XCTAssertEqual(rows[2].new?.id, 2)
        // Two deletions followed by one addition pair in order; the second deletion faces an empty cell.
        XCTAssertEqual(rows[3].old?.id, 3)
        XCTAssertEqual(rows[3].new?.id, 5)
        XCTAssertEqual(rows[4].old?.id, 4)
        XCTAssertNil(rows[4].new)
        // Additions before a deletion in the same run still pair with it.
        XCTAssertEqual(rows[6].old?.id, 9)
        XCTAssertEqual(rows[6].new?.id, 7)
        XCTAssertNil(rows[7].old)
        XCTAssertEqual(rows[7].new?.id, 8)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }

    func testDiffNumberWidthFollowsTheLargestLineNumber() {
        func line(_ id: Int, old: Int?, new: Int?) -> RepositoryDiff.Line {
            .init(id: id, kind: .context, oldLineNumber: old, newLineNumber: new, text: "\(id)")
        }
        let digit = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular).maximumAdvancement.width

        // Metadata and hunk lines carry no number, so a diff of only those still reserves the two-digit floor.
        XCTAssertEqual(diffNumberWidth(for: [line(0, old: nil, new: nil)], fontSize: 13), (digit * 2).rounded(.up))
        XCTAssertEqual(diffNumberWidth(for: [line(0, old: 7, new: 7)], fontSize: 13), (digit * 2).rounded(.up))
        // The widest number wins whichever side it is on, so both halves of a split share one gutter.
        XCTAssertEqual(diffNumberWidth(for: [line(0, old: 999, new: 12)], fontSize: 13), (digit * 3).rounded(.up))
        XCTAssertEqual(diffNumberWidth(for: [line(0, old: 12, new: 999)], fontSize: 13), (digit * 3).rounded(.up))
        // Six digits fit instead of being truncated by a fixed column.
        XCTAssertEqual(diffNumberWidth(for: [line(0, old: 4, new: 123_456)], fontSize: 13), (digit * 6).rounded(.up))
        // The column tracks the font, not a constant.
        XCTAssertLessThan(
            diffNumberWidth(for: [line(0, old: 4, new: 123_456)], fontSize: 11),
            diffNumberWidth(for: [line(0, old: 4, new: 123_456)], fontSize: 13)
        )
    }

    func testDescribesNavigatorLocationForDestinationsAndObjects() {
        XCTAssertEqual(RepositoryNavigatorLocation(screen: .history, scope: nil).title, "History")
        XCTAssertEqual(RepositoryNavigatorLocation(screen: .stashes, scope: .branch("feature")).title, "Stashes", "only History reads the scope")
        XCTAssertEqual(RepositoryNavigatorLocation(screen: .stashes, scope: nil).systemImage, RepositoryWorkspaceSection.stashes.systemImage)
        XCTAssertEqual(RepositoryNavigatorLocation(screen: .history, scope: .branch("feature")).title, "feature · Local branch")
        XCTAssertEqual(RepositoryNavigatorLocation(screen: .history, scope: .remote("origin")).title, "origin · Remote")
        XCTAssertEqual(RepositoryNavigatorLocation(screen: .history, scope: .remoteBranch("origin/main")).title, "origin/main · Remote branch")
        XCTAssertEqual(RepositoryNavigatorLocation(screen: .history, scope: .tag("v0.1")).title, "v0.1 · Tag")
        XCTAssertEqual(RepositoryHistoryScope.tag("v0.1").historyReference, "refs/tags/v0.1")
        XCTAssertEqual(RepositoryHistoryScope.remoteBranch("origin/main").historyReference, "refs/remotes/origin/main")
        XCTAssertEqual(RepositoryHistoryScope.remote("origin").historyReference, "--remotes=origin/")
        XCTAssertEqual(RepositoryHistoryScope.remoteBranch("origin/feature/x").remoteName, "origin")
        XCTAssertNil(RepositoryHistoryScope.branch("main").remoteName)
        // Unknown stored values fall back to the default style instead of crashing the setting.
        XCTAssertNil(GallaeAppearanceSettings.NarrowNavigator(rawValue: "bogus"))
        XCTAssertEqual(GallaeAppearanceSettings.NarrowNavigator.allCases.first, .floatingPanel)
    }

    func testResolvesMaterialResponseFromSystemAndAppSettings() {
        XCTAssertEqual(
            GallaeMaterialResponse.resolve(reduceTransparency: false, increasedContrast: false, translucentChrome: true),
            .standard
        )
        XCTAssertEqual(
            GallaeMaterialResponse.resolve(reduceTransparency: false, increasedContrast: false, translucentChrome: false),
            .reducedTransparency
        )
        XCTAssertEqual(
            GallaeMaterialResponse.resolve(reduceTransparency: true, increasedContrast: false, translucentChrome: true),
            .reducedTransparency
        )
        // Increase Contrast wins even when the app setting asks for the material.
        XCTAssertEqual(
            GallaeMaterialResponse.resolve(reduceTransparency: false, increasedContrast: true, translucentChrome: true),
            .increasedContrast
        )

        let standard = GallaeTheme.resolve(response: .standard, compactRows: false)
        let contrast = GallaeTheme.resolve(response: .increasedContrast, compactRows: true)
        XCTAssertTrue(standard.materials.translucentChrome)
        XCTAssertFalse(contrast.materials.translucentChrome)
        XCTAssertEqual(standard.metrics.diffChangeBarWidth, 0)
        XCTAssertGreaterThan(contrast.metrics.diffChangeBarWidth, 0)
        XCTAssertLessThan(contrast.metrics.rowVerticalPadding, standard.metrics.rowVerticalPadding)
        XCTAssertLessThan(contrast.metrics.diffFontSize, standard.metrics.diffFontSize)
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
            references: [.init(name: "release-candidate", kind: .tag)],
        )

        XCTAssertTrue(commit.matches(search: ""))
        XCTAssertTrue(commit.matches(search: "library tester"))
        XCTAssertTrue(commit.matches(search: "VISIBLE abc123"))
        XCTAssertTrue(commit.matches(search: "release-candidate"))
        XCTAssertFalse(commit.matches(search: "remote branch"))
    }

    func testReadsHistoryAcrossBranchesRemoteBranchesAndTags() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "base.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Base")
        let baseID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try write("main\n", to: "main.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main")
        let headID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "-b", "feature", baseID])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature")
        let branchID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "-b", "remote-only", baseID])
        try write("remote\n", to: "remote.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Remote")
        let remoteID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["-C", repositoryURL.path, "update-ref", "refs/remotes/origin/archive", remoteID])

        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "-b", "tag-only", baseID])
        try write("tag\n", to: "tag.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Tag")
        let tagID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["-C", repositoryURL.path, "tag", "v-archive", tagID])

        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "main"])
        try runGit(["-C", repositoryURL.path, "branch", "-D", "remote-only", "tag-only"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repository)

        XCTAssertEqual(history.headCommitID, headID)
        XCTAssertEqual(
            Set(history.commits.map(\.id)),
            Set([baseID, headID, branchID, remoteID, tagID])
        )
        XCTAssertEqual(
            history.commits.first(where: { $0.id == branchID })?.references,
            [.init(name: "feature", kind: .branch)]
        )
        XCTAssertEqual(
            history.commits.first(where: { $0.id == remoteID })?.references,
            [.init(name: "origin/archive", kind: .remoteBranch)]
        )
        XCTAssertEqual(
            history.commits.first(where: { $0.id == tagID })?.references,
            [.init(name: "v-archive", kind: .tag)]
        )
    }

    func testReadsHistoryOfOneReferenceAndListsTagsAndRemoteBranches() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "base.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Base")
        let baseID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["-C", repositoryURL.path, "tag", "v1", baseID])

        try write("main\n", to: "main.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main")
        let headID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["-C", repositoryURL.path, "tag", "-a", "-m", "release", "v2", headID])

        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "-b", "feature", baseID])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature")
        let featureID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        // 같은 이름의 branch와 tag가 있어도 refs/heads·refs/tags로 서로 다른 ref를 읽는다.
        try runGit(["-C", repositoryURL.path, "tag", "feature", baseID])
        try runGit(["-C", repositoryURL.path, "update-ref", "refs/remotes/origin/main", headID])
        try runGit(["-C", repositoryURL.path, "update-ref", "refs/remotes/origin/feature", featureID])
        try runGit(["-C", repositoryURL.path, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"])
        try runGit(["-C", repositoryURL.path, "update-ref", "refs/remotes/upstream/main", baseID])
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "main"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)

        let featureHistory = try await inspector.history(in: repository, reference: "refs/heads/feature")
        XCTAssertEqual(featureHistory.commits.map(\.id), [featureID, baseID])
        XCTAssertEqual(featureHistory.headCommitID, headID)

        let featureTagHistory = try await inspector.history(in: repository, reference: "refs/tags/feature")
        XCTAssertEqual(featureTagHistory.commits.map(\.id), [baseID])

        // Creation dates tie within one second here, so only membership is stable.
        let tags = try await inspector.tags(in: repository)
        XCTAssertEqual(Set(tags), ["v1", "v2", "feature"])

        let originBranches = try await inspector.remoteBranches(of: "origin", in: repository)
        XCTAssertEqual(originBranches, ["origin/feature", "origin/main"])
        let upstreamBranches = try await inspector.remoteBranches(of: "upstream", in: repository)
        XCTAssertEqual(upstreamBranches, ["upstream/main"])
        let missingBranches = try await inspector.remoteBranches(of: "missing", in: repository)
        XCTAssertEqual(missingBranches, [])
    }

    func testBuildsHistoryGraphForMergeCommit() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "base.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Base")
        let baseID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["-C", repositoryURL.path, "branch", "feature"])

        try write("main\n", to: "main.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main work")
        let mainID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature work")
        let featureID = try gitOutput([
            "-C", repositoryURL.path, "rev-parse", "HEAD"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "main"])
        try runGit([
            "-C", repositoryURL.path, "merge", "--quiet", "--no-ff",
            "-m", "Merge feature", "feature"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repository)
        let merge = try XCTUnwrap(history.commits.first)
        let mergeRow = try XCTUnwrap(history.graphRows[merge.id])
        let baseRow = try XCTUnwrap(history.graphRows[baseID])
        let mergeFiles = try await inspector.files(for: merge, in: repository)

        XCTAssertEqual(Set(merge.parentIDs), Set([mainID, featureID]))
        XCTAssertEqual(history.commits.last?.id, baseID)
        XCTAssertEqual(history.graphLaneCount, 2)
        XCTAssertEqual(mergeRow.commitLane, 0)
        XCTAssertEqual(mergeRow.topLaneCount, 1)
        XCTAssertEqual(mergeRow.bottomLaneCount, 2)
        XCTAssertFalse(mergeRow.hasIncomingEdge)
        XCTAssertEqual(Set(mergeRow.parentEdges.map(\.toLane)), Set([0, 1]))
        XCTAssertEqual(baseRow.topLaneCount, 1)
        XCTAssertEqual(baseRow.bottomLaneCount, 0)
        XCTAssertTrue(baseRow.hasIncomingEdge)
        XCTAssertEqual(mergeFiles.map(\.path), ["feature.txt"])
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

    func testReportsMergeInProgressBeforeAndAfterResolvingConflict() async throws {
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

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        XCTAssertEqual(
            repository.operation,
            .init(kind: .merge, unresolvedConflictCount: 1)
        )
        XCTAssertFalse(try XCTUnwrap(repository.operation).canContinue)

        try write("combined\n", to: "conflict.txt", in: repositoryURL)
        let resolvedRepository = try await inspector.markConflictResolved(
            try XCTUnwrap(repository.changes.first),
            in: repository
        )

        XCTAssertEqual(
            resolvedRepository.operation,
            .init(kind: .merge, unresolvedConflictCount: 0)
        )
        XCTAssertTrue(try XCTUnwrap(resolvedRepository.operation).canContinue)
    }

    func testAbortsAndContinuesMergeOperation() async throws {
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

        let inspector = RepositoryInspector()
        let conflictedRepository = try await inspector.inspect(at: repositoryURL)
        let abortedRepository = try await inspector.abortOperation(in: conflictedRepository)

        XCTAssertNil(abortedRepository.operation)
        XCTAssertEqual(abortedRepository.head, .branch("main"))
        XCTAssertTrue(abortedRepository.changes.isEmpty)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "conflict.txt"), encoding: .utf8),
            "main\n"
        )

        try runGit(["-C", repositoryURL.path, "merge", "--no-edit", "side"], expectedStatus: 1)
        let restartedRepository = try await inspector.inspect(at: repositoryURL)
        do {
            _ = try await inspector.continueOperation(in: restartedRepository)
            XCTFail("An unresolved merge should not continue")
        } catch let error as RepositoryOperationError {
            XCTAssertEqual(error, .unresolvedConflicts)
        }

        try write("combined\n", to: "conflict.txt", in: repositoryURL)
        let resolvedRepository = try await inspector.markConflictResolved(
            try XCTUnwrap(restartedRepository.changes.first),
            in: restartedRepository
        )
        let continuedRepository = try await inspector.continueOperation(in: resolvedRepository)

        XCTAssertNil(continuedRepository.operation)
        XCTAssertEqual(continuedRepository.head, .branch("main"))
        XCTAssertTrue(continuedRepository.changes.isEmpty)
        let history = try await inspector.history(in: continuedRepository)
        let headCommit = try XCTUnwrap(
            history.commits.first { $0.id == history.headCommitID }
        )
        XCTAssertEqual(headCommit.parentIDs.count, 2)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "conflict.txt"), encoding: .utf8),
            "combined\n"
        )
    }

    func testReportsRebaseInProgressBeforeAndAfterResolvingConflict() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "conflict.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "-b", "feature"])
        try write("feature\n", to: "conflict.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "main"])
        try write("main\n", to: "conflict.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "feature"])
        try runGit(
            ["-C", repositoryURL.path, "rebase", "--no-update-refs", "main"],
            expectedStatus: 1
        )

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        XCTAssertEqual(
            repository.operation,
            .init(kind: .rebase, unresolvedConflictCount: 1)
        )
        XCTAssertFalse(try XCTUnwrap(repository.operation).canContinue)

        try write("combined\n", to: "conflict.txt", in: repositoryURL)
        let resolvedRepository = try await inspector.markConflictResolved(
            try XCTUnwrap(repository.changes.first),
            in: repository
        )

        XCTAssertEqual(
            resolvedRepository.operation,
            .init(kind: .rebase, unresolvedConflictCount: 0)
        )
        XCTAssertTrue(try XCTUnwrap(resolvedRepository.operation).canContinue)
    }

    func testAbortsAndContinuesRebaseOperation() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "conflict.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "-b", "feature"])
        try write("feature\n", to: "conflict.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "main"])
        try write("main\n", to: "conflict.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "feature"])
        try runGit(
            ["-C", repositoryURL.path, "rebase", "--no-update-refs", "main"],
            expectedStatus: 1
        )

        let inspector = RepositoryInspector()
        let conflictedRepository = try await inspector.inspect(at: repositoryURL)
        let abortedRepository = try await inspector.abortOperation(in: conflictedRepository)

        XCTAssertNil(abortedRepository.operation)
        XCTAssertEqual(abortedRepository.head, .branch("feature"))
        XCTAssertTrue(abortedRepository.changes.isEmpty)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "conflict.txt"), encoding: .utf8),
            "feature\n"
        )

        try runGit(
            ["-C", repositoryURL.path, "rebase", "--no-update-refs", "main"],
            expectedStatus: 1
        )
        let restartedRepository = try await inspector.inspect(at: repositoryURL)
        try write("combined\n", to: "conflict.txt", in: repositoryURL)
        let resolvedRepository = try await inspector.markConflictResolved(
            try XCTUnwrap(restartedRepository.changes.first),
            in: restartedRepository
        )
        let continuedRepository = try await inspector.continueOperation(in: resolvedRepository)

        XCTAssertNil(continuedRepository.operation)
        XCTAssertEqual(continuedRepository.head, .branch("feature"))
        XCTAssertTrue(continuedRepository.changes.isEmpty)
        let history = try await inspector.history(in: continuedRepository)
        let headCommit = try XCTUnwrap(
            history.commits.first { $0.id == history.headCommitID }
        )
        XCTAssertEqual(headCommit.subject, "Feature")
        XCTAssertEqual(
            history.commits.first { $0.id == headCommit.parentIDs.first }?.subject,
            "Main"
        )
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "conflict.txt"), encoding: .utf8),
            "combined\n"
        )
    }

    func testReadsConflictBaseOursAndTheirsWithoutChangingRepository() async throws {
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

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)

        let change = try XCTUnwrap(repository.changes.first { $0.path == "conflict.txt" })
        XCTAssertTrue(change.isConflicted)
        XCTAssertEqual(RepositoryChangeStatusGroup.make(repository.changes).map(\.id), [.conflicts])

        let conflictedFile = repositoryURL.appending(path: "conflict.txt")
        let workingTreeBeforeInspection = try Data(contentsOf: conflictedFile)
        let diff = try await inspector.diff(for: change, in: repository)

        XCTAssertEqual(try textLines(in: diff, scope: .base).map(\.text), ["base"])
        XCTAssertEqual(try textLines(in: diff, scope: .ours).map(\.text), ["main"])
        XCTAssertEqual(try textLines(in: diff, scope: .theirs).map(\.text), ["side"])
        let repositoryAfterInspection = try await inspector.inspect(at: repositoryURL)
        XCTAssertEqual(repositoryAfterInspection, repository)
        XCTAssertEqual(try Data(contentsOf: conflictedFile), workingTreeBeforeInspection)
    }

    func testResolvesConflictUsingOursWithoutChangingHead() async throws {
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
        let headBeforeResolution = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
        try runGit(["-C", repositoryURL.path, "merge", "--no-edit", "side"], expectedStatus: 1)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first { $0.path == "conflict.txt" })
        let resolvedRepository = try await inspector.resolveConflict(
            change,
            using: .ours,
            in: repository
        )

        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "conflict.txt"), encoding: .utf8),
            "main\n"
        )
        XCTAssertFalse(resolvedRepository.changes.contains { $0.path == "conflict.txt" })
        XCTAssertTrue(
            try gitOutput(["-C", repositoryURL.path, "ls-files", "--unmerged", "--", "conflict.txt"])
                .isEmpty
        )
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"]), headBeforeResolution)
    }

    func testResolvesConflictUsingTheirsAndStagesChosenVersion() async throws {
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

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first { $0.path == "conflict.txt" })
        let resolvedRepository = try await inspector.resolveConflict(
            change,
            using: .theirs,
            in: repository
        )

        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "conflict.txt"), encoding: .utf8),
            "side\n"
        )
        let resolvedChange = try XCTUnwrap(
            resolvedRepository.changes.first { $0.path == "conflict.txt" }
        )
        XCTAssertFalse(resolvedChange.isConflicted)
        XCTAssertEqual(resolvedChange.staged, .modified)
        XCTAssertNil(resolvedChange.unstaged)
        XCTAssertTrue(
            try gitOutput(["-C", repositoryURL.path, "ls-files", "--unmerged", "--", "conflict.txt"])
                .isEmpty
        )
    }

    func testMarksConflictResolvedUsingCurrentWorkingTreeContentWithoutChangingHead() async throws {
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
        let headBeforeResolution = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
        try runGit(["-C", repositoryURL.path, "merge", "--no-edit", "side"], expectedStatus: 1)
        try write("combined\n", to: "conflict.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first { $0.path == "conflict.txt" })
        let resolvedRepository = try await inspector.markConflictResolved(
            change,
            in: repository
        )

        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "conflict.txt"), encoding: .utf8),
            "combined\n"
        )
        let resolvedChange = try XCTUnwrap(
            resolvedRepository.changes.first { $0.path == "conflict.txt" }
        )
        XCTAssertFalse(resolvedChange.isConflicted)
        XCTAssertEqual(resolvedChange.staged, .modified)
        XCTAssertNil(resolvedChange.unstaged)
        XCTAssertTrue(
            try gitOutput(["-C", repositoryURL.path, "ls-files", "--unmerged", "--", "conflict.txt"])
                .isEmpty
        )
        XCTAssertEqual(try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"]), headBeforeResolution)
    }

    func testResolvesConflictAsDeletionWhenChosenSideHasNoFile() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "conflict.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "-b", "side"])
        try runGit(["-C", repositoryURL.path, "rm", "--quiet", "conflict.txt"])
        try commitAll(in: repositoryURL, message: "Side deletes")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "main"])
        try write("main\n", to: "conflict.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main modifies")
        try runGit(["-C", repositoryURL.path, "merge", "--no-edit", "side"], expectedStatus: 1)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first { $0.path == "conflict.txt" })
        let resolvedRepository = try await inspector.resolveConflict(
            change,
            using: .theirs,
            in: repository
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: repositoryURL.appending(path: "conflict.txt").path)
        )
        let resolvedChange = try XCTUnwrap(
            resolvedRepository.changes.first { $0.path == "conflict.txt" }
        )
        XCTAssertFalse(resolvedChange.isConflicted)
        XCTAssertEqual(resolvedChange.staged, .deleted)
        XCTAssertNil(resolvedChange.unstaged)
        XCTAssertTrue(
            try gitOutput(["-C", repositoryURL.path, "ls-files", "--unmerged", "--", "conflict.txt"])
                .isEmpty
        )
    }

    func testReportsMissingBaseForAddAddConflict() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("initial\n", to: "README.md", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "-b", "side"])
        try write("side\n", to: "added.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Side")
        try runGit(["-C", repositoryURL.path, "checkout", "--quiet", "main"])
        try write("main\n", to: "added.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main")
        try runGit(["-C", repositoryURL.path, "merge", "--no-edit", "side"], expectedStatus: 1)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first { $0.path == "added.txt" })
        let diff = try await inspector.diff(for: change, in: repository)

        XCTAssertEqual(diff.sections.first { $0.scope == .base }?.content, .missing)
        XCTAssertEqual(try textLines(in: diff, scope: .ours).map(\.text), ["main"])
        XCTAssertEqual(try textLines(in: diff, scope: .theirs).map(\.text), ["side"])
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
    func testRemovesMultipleRecentRepositoriesWithoutDeletingThem() async throws {
        let fixtureURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let firstURL = fixtureURL.appending(path: "first", directoryHint: .isDirectory)
        let secondURL = fixtureURL.appending(path: "second", directoryHint: .isDirectory)
        let thirdURL = fixtureURL.appending(path: "third", directoryHint: .isDirectory)
        try initializeRepository(at: firstURL)
        try initializeRepository(at: secondURL)
        try initializeRepository(at: thirdURL)

        let suiteName = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LibraryStore(defaults: defaults)
        try store.rememberOpenedRepository(firstURL)
        try store.rememberOpenedRepository(secondURL)
        try store.rememberOpenedRepository(thirdURL)

        let model = AppModel(store: store)
        await model.restoreState()
        model.showLibrary()
        model.selectLibrarySource(.recent)
        model.removeRecentRepositories(Set([firstURL, thirdURL].map(\.standardizedFileURL)))

        XCTAssertEqual(model.recentRepositories.map(\.rootURL), [secondURL.standardizedFileURL])
        XCTAssertEqual(model.selectedLibraryRepositoryID, secondURL.standardizedFileURL)
        XCTAssertEqual(store.restoreRecentRepositories().map(\.url), [secondURL.standardizedFileURL])
        XCTAssertNil(store.restoreLastWorkspace())
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thirdURL.path))
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
    func testStagesAndUnstagesMultipleSelectedChangesTogether() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("before one\n", to: "one.txt", in: repositoryURL)
        try write("before two\n", to: "two.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("after one\n", to: "one.txt", in: repositoryURL)
        try write("after two\n", to: "two.txt", in: repositoryURL)
        try write("new\n", to: "new.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--", "one.txt"])

        let suiteName = "GallaeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(store: LibraryStore(defaults: defaults))
        await model.openRepository(at: repositoryURL)
        let changeIDs: Set<RepositorySummary.Change.ID> = ["one.txt", "two.txt", "new.txt"]

        XCTAssertTrue(model.canStageChanges(ids: changeIDs))
        await model.stageChanges(ids: changeIDs)

        XCTAssertEqual(model.repository?.changes.count, 3)
        XCTAssertTrue(model.repository?.changes.allSatisfy { $0.staged != nil } == true)
        XCTAssertTrue(model.repository?.changes.allSatisfy { $0.unstaged == nil } == true)
        XCTAssertTrue(model.canUnstageChanges(ids: changeIDs))

        await model.unstageChanges(ids: changeIDs)

        let changes = try XCTUnwrap(model.repository?.changes)
        XCTAssertTrue(changes.allSatisfy { $0.staged == nil })
        XCTAssertEqual(changes.first { $0.id == "one.txt" }?.unstaged, .modified)
        XCTAssertEqual(changes.first { $0.id == "two.txt" }?.unstaged, .modified)
        XCTAssertEqual(changes.first { $0.id == "new.txt" }?.unstaged, .untracked)
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "one.txt"), encoding: .utf8),
            "after one\n"
        )
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "two.txt"), encoding: .utf8),
            "after two\n"
        )
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "new.txt"), encoding: .utf8),
            "new\n"
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

    /// Every setting here is one that changed Git's patch text enough to break parsing or `git apply`
    /// before the format was pinned. See `docs/research/git-diff-config.md`.
    func testHostileDiffConfigurationCannotBreakParsingOrStaging() async throws {
        let hostileSettings = [
            ("color.diff", "always"),
            ("color.ui", "always"),
            ("diff.noprefix", "true"),
            ("diff.mnemonicPrefix", "true"),
            ("diff.context", "0"),
            ("diff.suppressBlankEmpty", "true"),
            ("core.quotepath", "true")
        ]

        for (key, value) in hostileSettings {
            let repositoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: repositoryURL) }
            try initializeRepository(at: repositoryURL)
            // A blank line and a non-ASCII name are what suppressBlankEmpty and quotepath act on.
            let original = "머리\n\n하나\n\n둘\n"
            try write(original, to: "한글 파일.txt", in: repositoryURL)
            try commitAll(in: repositoryURL, message: "Initial")
            try write("머리\n\n하나\n\n바꾼둘\n", to: "한글 파일.txt", in: repositoryURL)
            try runGit(["-C", repositoryURL.path, "config", key, value])

            let inspector = RepositoryInspector()
            let repository = try await inspector.inspect(at: repositoryURL)
            let change = try XCTUnwrap(repository.changes.first, "\(key)=\(value)")
            let diff = try await inspector.diff(for: change, in: repository)
            let section = try XCTUnwrap(
                diff.sections.first { $0.scope == .unstaged },
                "\(key)=\(value)"
            )

            // The hunk header parses, so the gutter controls exist at all.
            XCTAssertEqual(section.hunks.count, 1, "\(key)=\(value)")
            let lines = try textLines(in: diff, scope: .unstaged)
            XCTAssertTrue(lines.contains { $0.kind == .hunk }, "\(key)=\(value)")
            XCTAssertTrue(lines.contains { $0.text == "+바꾼둘" }, "\(key)=\(value)")
            XCTAssertTrue(lines.contains { $0.text == "-둘" }, "\(key)=\(value)")

            // Blank context lines are counted, so every line number after one stays true.
            let changed = try XCTUnwrap(lines.first { $0.text == "-둘" }, "\(key)=\(value)")
            XCTAssertEqual(changed.oldLineNumber, 5, "\(key)=\(value)")

            // No escape sequence survives into what the reader sees.
            XCTAssertFalse(lines.contains { $0.text.contains("\u{1B}") }, "\(key)=\(value)")
            // The path is readable rather than octal-escaped.
            XCTAssertTrue(
                lines.contains { $0.kind == .metadata && $0.text.contains("한글 파일.txt") },
                "\(key)=\(value)"
            )

            // And the patch Git produced still applies to the index.
            let staged = try await inspector.stage(
                try XCTUnwrap(section.hunks.first, "\(key)=\(value)"),
                for: change,
                in: repository
            )
            XCTAssertEqual(try XCTUnwrap(staged.changes.first).staged, .modified, "\(key)=\(value)")
        }
    }

    func testNewFileModeIsHiddenFromViewButKeptInTheAppliedPatch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("one\n", to: "kept.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("added\n", to: "new.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "new.txt"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let added = try XCTUnwrap(repository.changes.first { $0.path == "new.txt" })
        let diff = try await inspector.diff(for: added, in: repository)
        let section = try XCTUnwrap(diff.sections.first { $0.scope == .staged })
        guard case .text(let lines) = section.content else { return XCTFail("expected text content") }

        // The file list already badges this Added, so the mode line only repeats it.
        XCTAssertTrue(lines.contains { $0.text.hasPrefix("new file mode ") })
        XCTAssertFalse(lines.filter { !$0.isPatchHeader }.contains { $0.text.hasPrefix("new file mode ") })
        // Still in what Git is handed back.
        XCTAssertTrue(try XCTUnwrap(section.hunks.first).patchText.contains("new file mode "))
    }

    func testPatchHeaderIsHiddenFromViewButKeptInTheAppliedPatch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("one\ntwo\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("one\nchanged\n", to: "file.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first)
        let diff = try await inspector.diff(for: change, in: repository)
        let section = try XCTUnwrap(diff.sections.first { $0.scope == .unstaged })
        let lines = try textLines(in: diff, scope: .unstaged)

        // Hidden from the reader.
        let shown = lines.filter { !$0.isPatchHeader }
        XCTAssertFalse(shown.contains { $0.text.hasPrefix("diff --git ") })
        XCTAssertFalse(shown.contains { $0.text.hasPrefix("index ") })
        XCTAssertFalse(shown.contains { $0.text.hasPrefix("--- ") })
        XCTAssertFalse(shown.contains { $0.text.hasPrefix("+++ ") })
        // A deletion whose text begins with the same characters is content, not a header.
        XCTAssertFalse(try XCTUnwrap(lines.first { $0.text == "-two" }).isPatchHeader)

        // Still in the patch Git is handed back.
        let patch = try XCTUnwrap(section.hunks.first).patchText
        XCTAssertTrue(patch.contains("diff --git "))
        XCTAssertTrue(patch.contains("--- "))
        XCTAssertTrue(patch.contains("+++ "))

        let staged = try await inspector.stage(
            try XCTUnwrap(section.hunks.first),
            for: change,
            in: repository
        )
        XCTAssertEqual(try XCTUnwrap(staged.changes.first).staged, .modified)
    }

    func testSectionPatchTextReproducesWhatGitWrote() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("one\ntwo\nthree\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("one\nchanged\nthree\n", to: "file.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first)
        let diff = try await inspector.diff(for: change, in: repository)
        let section = try XCTUnwrap(diff.sections.first { $0.scope == .unstaged })
        let patch = try XCTUnwrap(section.patchText)

        XCTAssertTrue(patch.hasPrefix("diff --git a/file.txt b/file.txt\n"))
        XCTAssertTrue(patch.contains("\n-two\n"))
        XCTAssertTrue(patch.contains("\n+changed\n"))
        XCTAssertTrue(patch.hasSuffix("\n"))
        // What it reproduces is a patch Git accepts.
        let applied = try await inspector.stage(try XCTUnwrap(section.hunks.first), for: change, in: repository)
        XCTAssertEqual(try XCTUnwrap(applied.changes.first).staged, .modified)
    }

    func testDiffLineReadsWithoutPatchSyntax() throws {
        func line(_ kind: RepositoryDiff.Line.Kind, _ text: String) -> RepositoryDiff.Line {
            .init(id: 0, kind: kind, oldLineNumber: nil, newLineNumber: nil, text: text)
        }

        // The prefix goes, so context and changed lines start in the same column.
        XCTAssertEqual(line(.context, " hello").displayText, "hello")
        XCTAssertEqual(line(.addition, "+hello").displayText, "hello")
        XCTAssertEqual(line(.deletion, "-hello").displayText, "hello")
        // A line whose content begins with a dash keeps it.
        XCTAssertEqual(line(.addition, "+--option").displayText, "--option")
        // A blank context line survives as empty rather than losing a character it does not have.
        XCTAssertEqual(line(.context, " ").displayText, "")
        // Headers carry no prefix, so they are left alone.
        XCTAssertEqual(line(.metadata, "new file mode 100644").displayText, "new file mode 100644")

        // The hunk header reads as a place, taken from the new side.
        XCTAssertEqual(line(.hunk, "@@ -0,0 +1 @@").hunkLocation, "Line 1")
        XCTAssertEqual(line(.hunk, "@@ -1 +1,2 @@").hunkLocation, "Lines 1–2")
        XCTAssertEqual(line(.hunk, "@@ -10,7 +12,7 @@ func body()").hunkLocation, "Lines 12–18")
        // A hunk that only removes lines has no new line to point at.
        XCTAssertEqual(line(.hunk, "@@ -5,3 +4,0 @@").hunkLocation, "After line 4")
        XCTAssertNil(line(.context, " hello").hunkLocation)
    }

    func testOneSidedSectionIsDetectedForNewAndDeletedFiles() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("one\ntwo\n", to: "kept.txt", in: repositoryURL)
        try write("gone\n", to: "removed.txt", in: repositoryURL)
        try write("one\ntwo\n", to: "grown.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("one\nchanged\n", to: "kept.txt", in: repositoryURL)
        try FileManager.default.removeItem(at: repositoryURL.appending(path: "removed.txt"))
        try write("fresh\n", to: "added.txt", in: repositoryURL)
        try write("one\ntwo\nthree\nfour\n", to: "grown.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)

        func section(_ path: String) async throws -> RepositoryDiff.Section {
            let change = try XCTUnwrap(repository.changes.first { $0.path == path }, path)
            let diff = try await inspector.diff(for: change, in: repository)
            return try XCTUnwrap(diff.sections.first { $0.scope != .staged }, path)
        }

        // A replaced line has both sides, so Split still compares.
        let modified = try await section("kept.txt")
        XCTAssertFalse(modified.isOneSided)
        // A new file and a deleted file have nothing to compare against.
        let added = try await section("added.txt")
        XCTAssertTrue(added.isOneSided)
        let removed = try await section("removed.txt")
        XCTAssertTrue(removed.isOneSided)
        // An ordinary edit that only adds lines still has context to line the two columns up against, so
        // Split keeps comparing. Only a file with no opposite version collapses to one column.
        let grown = try await section("grown.txt")
        XCTAssertFalse(grown.isOneSided)
    }

    func testUnstagesSelectedLinesOfANewlyAddedFile() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "base.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("one\ntwo\nthree\n", to: "new.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "new.txt"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first { $0.path == "new.txt" })
        XCTAssertEqual(change.staged, .added)

        let diff = try await inspector.diff(for: change, in: repository)
        let staged = try XCTUnwrap(diff.sections.first { $0.scope == .staged })
        let lines = try textLines(in: diff, scope: .staged)
        let two = try XCTUnwrap(lines.first { $0.text == "+two" })
        let hunk = try XCTUnwrap(staged.hunks.first)

        // Taking one line back out of the index rewrites the header: a patch with context lines cannot
        // still claim to create the file, or Git answers "new file … depends on old contents".
        let partial = try XCTUnwrap(
            staged.partialHunk(id: hunk.id, keeping: [two.id], direction: .revert)
        )
        XCTAssertFalse(partial.patchText.contains("new file mode"))
        XCTAssertFalse(partial.patchText.contains("--- /dev/null"))
        XCTAssertTrue(partial.patchText.contains("--- a/new.txt"))

        let after = try await inspector.unstage(partial, for: change, in: repository)
        let left = try XCTUnwrap(after.changes.first { $0.path == "new.txt" })
        // Still staged as an addition, now without the line that was taken back.
        XCTAssertEqual(left.staged, .added)
        XCTAssertEqual(left.unstaged, .modified)
        let indexed = try gitOutput(["-C", repositoryURL.path, "show", ":new.txt"])
        XCTAssertEqual(indexed, "one\nthree\n")
        // The file on disk is untouched.
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "new.txt"), encoding: .utf8),
            "one\ntwo\nthree\n"
        )
    }

    func testPartialMetadataLeavesAWholeFilePatchAlone() {
        let newFile = ["diff --git a/x b/x", "new file mode 100644", "index 0000000..1", "--- /dev/null", "+++ b/x"]
        // Every line chosen means no context, so the patch really does still create the file.
        XCTAssertEqual(RepositoryDiff.Section.partialMetadata(newFile, oldCount: 0, newCount: 3), newFile)
        // Keeping some lines makes it a modification.
        XCTAssertEqual(
            RepositoryDiff.Section.partialMetadata(newFile, oldCount: 2, newCount: 3),
            ["diff --git a/x b/x", "index 0000000..1", "--- a/x", "+++ b/x"]
        )
        // The same the other way round for a deletion.
        let deleted = ["diff --git a/x b/x", "deleted file mode 100644", "--- a/x", "+++ /dev/null"]
        XCTAssertEqual(RepositoryDiff.Section.partialMetadata(deleted, oldCount: 3, newCount: 0), deleted)
        XCTAssertEqual(
            RepositoryDiff.Section.partialMetadata(deleted, oldCount: 3, newCount: 2),
            ["diff --git a/x b/x", "--- a/x", "+++ b/x"]
        )
    }

    func testChangedLineCountCountsOnlyChanges() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("one\ntwo\nthree\nfour\nfive\n", to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        // One line replaced and one added: two changed lines among four context lines and a header.
        try write("one\nCHANGED\nthree\nfour\nfive\nsix\n", to: "file.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first)
        let diff = try await inspector.diff(for: change, in: repository)
        let section = try XCTUnwrap(diff.sections.first { $0.scope == .unstaged })

        XCTAssertEqual(section.changedLineCount, 3, "one deletion, two additions")
        let lines = try textLines(in: diff, scope: .unstaged)
        XCTAssertGreaterThan(lines.count, section.changedLineCount, "headers and context are not changes")
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

    func testBuildsPartialHunkForEachDirection() throws {
        typealias Line = RepositoryDiff.Line
        let lines: [Line] = [
            .init(id: 0, kind: .metadata, oldLineNumber: nil, newLineNumber: nil, text: "diff --git a/f b/f"),
            .init(id: 1, kind: .metadata, oldLineNumber: nil, newLineNumber: nil, text: "--- a/f"),
            .init(id: 2, kind: .metadata, oldLineNumber: nil, newLineNumber: nil, text: "+++ b/f"),
            .init(id: 3, kind: .hunk, oldLineNumber: nil, newLineNumber: nil, text: "@@ -1,4 +1,4 @@ head"),
            .init(id: 4, kind: .context, oldLineNumber: 1, newLineNumber: 1, text: " one"),
            .init(id: 5, kind: .deletion, oldLineNumber: 2, newLineNumber: nil, text: "-two"),
            .init(id: 6, kind: .addition, oldLineNumber: nil, newLineNumber: 2, text: "+TWO"),
            .init(id: 7, kind: .context, oldLineNumber: 3, newLineNumber: 3, text: " three"),
            .init(id: 8, kind: .deletion, oldLineNumber: 4, newLineNumber: nil, text: "-four"),
            .init(id: 9, kind: .addition, oldLineNumber: nil, newLineNumber: 4, text: "+FOUR"),
            .init(id: 10, kind: .metadata, oldLineNumber: nil, newLineNumber: nil, text: "\\ No newline at end of file"),
        ]
        let section = RepositoryDiff.Section(scope: .unstaged, content: .text(lines))

        let staging = try XCTUnwrap(section.partialHunk(id: 3, keeping: [5, 6], direction: .apply))
        XCTAssertEqual(
            staging.patchText,
            "diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1,4 +1,4 @@ head\n one\n-two\n+TWO\n three\n four\n",
            "an unchosen deletion stays as context, an unchosen addition and its no-newline marker drop out"
        )

        let unstaging = try XCTUnwrap(section.partialHunk(id: 3, keeping: [8, 9], direction: .revert))
        XCTAssertEqual(
            unstaging.patchText,
            "diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1,4 +1,4 @@ head\n one\n TWO\n three\n-four\n+FOUR\n\\ No newline at end of file\n",
            "reversed: an unchosen addition stays as context, an unchosen deletion drops out, the marker stays with FOUR"
        )

        let additionOnly = try XCTUnwrap(section.partialHunk(id: 3, keeping: [6], direction: .apply))
        XCTAssertTrue(additionOnly.patchText.contains("@@ -1,4 +1,5 @@ head\n one\n two\n+TWO\n"), "\(additionOnly.patchText)")

        XCTAssertNil(section.partialHunk(id: 3, keeping: [4, 7], direction: .apply), "context alone is not a change")
        XCTAssertNil(section.partialHunk(id: 99, keeping: [5], direction: .apply))
        XCTAssertEqual(RepositoryDiff.Section.hunkHeader("@@ -0,0 +1,3 @@", oldCount: 0, newCount: 1), "@@ -0,0 +1,1 @@")
        XCTAssertEqual(RepositoryDiff.Section.hunkHeader("@@ -7 +7 @@", oldCount: 1, newCount: 2), "@@ -7,1 +7,2 @@")
    }

    func testStagesAndUnstagesOnlyChosenLines() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        let original = (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try write(original, to: "file.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        var editedLines = (1...10).map { "line \($0)" }
        editedLines[1] = "changed two"
        editedLines[3] = "changed four"
        let edited = editedLines.joined(separator: "\n") + "\n"
        try write(edited, to: "file.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first)
        let diff = try await inspector.diff(for: change, in: repository)
        let workingSection = try XCTUnwrap(diff.sections.first { $0.scope == .unstaged })
        XCTAssertEqual(workingSection.hunks.count, 1, "both edits sit in one hunk")
        let workingLines = try textLines(in: diff, scope: .unstaged)
        let chosen = Set(workingLines.filter { $0.text == "-line 2" || $0.text == "+changed two" }.map(\.id))
        let hunkID = try XCTUnwrap(workingLines.first { $0.kind == .hunk }?.id)
        let partial = try XCTUnwrap(workingSection.partialHunk(id: hunkID, keeping: chosen, direction: .apply))

        let stagedRepository = try await inspector.stage(partial, for: change, in: repository)
        let stagedChange = try XCTUnwrap(stagedRepository.changes.first)
        XCTAssertEqual(stagedChange.staged, .modified)
        XCTAssertEqual(stagedChange.unstaged, .modified)
        let stagedDiff = try await inspector.diff(for: stagedChange, in: stagedRepository)
        XCTAssertEqual(
            try textLines(in: stagedDiff, scope: .staged).filter { $0.kind == .addition }.map(\.text),
            ["+changed two"]
        )
        XCTAssertEqual(
            try textLines(in: stagedDiff, scope: .unstaged).filter { $0.kind == .addition }.map(\.text),
            ["+changed four"]
        )
        XCTAssertEqual(try String(contentsOf: repositoryURL.appending(path: "file.txt"), encoding: .utf8), edited)

        let stagedSection = try XCTUnwrap(stagedDiff.sections.first { $0.scope == .staged })
        let stagedLines = try textLines(in: stagedDiff, scope: .staged)
        let chosenStaged = Set(stagedLines.filter { $0.text == "-line 2" || $0.text == "+changed two" }.map(\.id))
        let stagedHunkID = try XCTUnwrap(stagedLines.first { $0.kind == .hunk }?.id)
        let reverse = try XCTUnwrap(stagedSection.partialHunk(id: stagedHunkID, keeping: chosenStaged, direction: .revert))

        let unstagedRepository = try await inspector.unstage(reverse, for: stagedChange, in: stagedRepository)
        let unstagedChange = try XCTUnwrap(unstagedRepository.changes.first)
        XCTAssertNil(unstagedChange.staged)
        XCTAssertEqual(unstagedChange.unstaged, .modified)
        let unstagedDiff = try await inspector.diff(for: unstagedChange, in: unstagedRepository)
        XCTAssertEqual(
            try textLines(in: unstagedDiff, scope: .unstaged).filter { $0.kind == .addition }.map(\.text),
            ["+changed two", "+changed four"]
        )
    }

    func testStagesChosenLinesOfUntrackedFile() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "base.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("one\ntwo\nthree\n", to: "new.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first { $0.path == "new.txt" })
        XCTAssertEqual(change.unstaged, .untracked)
        let diff = try await inspector.diff(for: change, in: repository)
        let section = try XCTUnwrap(diff.sections.first { $0.scope == .untracked })
        let lines = try textLines(in: diff, scope: .untracked)
        let hunkID = try XCTUnwrap(lines.first { $0.kind == .hunk }?.id)
        let chosen = Set(lines.filter { $0.text == "+two" }.map(\.id))
        let partial = try XCTUnwrap(section.partialHunk(id: hunkID, keeping: chosen, direction: .apply))

        let staged = try await inspector.stage(partial, for: change, in: repository)
        let stagedChange = try XCTUnwrap(staged.changes.first { $0.path == "new.txt" })
        XCTAssertEqual(stagedChange.staged, .added)
        XCTAssertEqual(stagedChange.unstaged, .modified)
        let stagedDiff = try await inspector.diff(for: stagedChange, in: staged)
        XCTAssertEqual(try textLines(in: stagedDiff, scope: .staged).filter { $0.kind == .addition }.map(\.text), ["+two"])
        XCTAssertEqual(
            try textLines(in: stagedDiff, scope: .unstaged).filter { $0.kind == .addition }.map(\.text),
            ["+one", "+three"]
        )
        XCTAssertEqual(try String(contentsOf: repositoryURL.appending(path: "new.txt"), encoding: .utf8), "one\ntwo\nthree\n")
    }

    func testDiscardsOnlyChosenLines() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try initializeRepository(at: repositoryURL)
        try write("a\nb\nc\nd\n", to: "f.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try write("a\nB\nc\nD\n", to: "f.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let change = try XCTUnwrap(repository.changes.first)
        let diff = try await inspector.diff(for: change, in: repository)
        let section = try XCTUnwrap(diff.sections.first { $0.scope == .unstaged })
        let lines = try textLines(in: diff, scope: .unstaged)
        let hunkID = try XCTUnwrap(lines.first { $0.kind == .hunk }?.id)
        let chosen = Set(lines.filter { $0.text == "-b" || $0.text == "+B" }.map(\.id))
        let partial = try XCTUnwrap(section.partialHunk(id: hunkID, keeping: chosen, direction: .revert))

        let discarded = try await inspector.discard(partial, for: change, in: repository)
        XCTAssertEqual(try String(contentsOf: repositoryURL.appending(path: "f.txt"), encoding: .utf8), "a\nb\nc\nD\n")
        let remaining = try XCTUnwrap(discarded.changes.first)
        XCTAssertNil(remaining.staged)
        XCTAssertEqual(remaining.unstaged, .modified)
    }

    func testReadsHeadCommitMessageSubjectAndBody() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "feature.txt", in: repositoryURL)
        try runGit(["-C", repositoryURL.path, "add", "--all"])
        try runGit([
            "-C", repositoryURL.path, "commit", "--quiet",
            "-m", "Add feature", "-m", "First paragraph.\n\nSecond paragraph."
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let message = try await inspector.headCommitMessage(in: repository)

        XCTAssertEqual(message.subject, "Add feature")
        XCTAssertEqual(message.body, "First paragraph.\n\nSecond paragraph.")
    }

    func testReadsBranchDivergenceCounts() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "branch", "feature"])
        try write("current\n", to: "current.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Current work")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "feature"])
        try write("feature-1\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature one")
        try write("feature-2\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature two")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)

        let diverged = try await inspector.divergence(from: "feature", in: repository)
        XCTAssertEqual(diverged, .init(uniqueToCurrent: 1, uniqueToOther: 2))

        let identical = try await inspector.divergence(from: "main", in: repository)
        XCTAssertEqual(identical, .init(uniqueToCurrent: 0, uniqueToOther: 0))
    }

    func testFastForwardsBranchToCurrentWithoutCheckout() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature work")
        try write("dirty\n", to: "dirty.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let updated = try await inspector.fastForwardBranch("main", toCurrentIn: repository)

        let headID = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mainID = try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(mainID, headID)
        XCTAssertEqual(updated.head, .branch("feature"))
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "dirty.txt"), encoding: .utf8),
            "dirty\n"
        )
    }

    func testFastForwardBranchToCurrentRejectsDivergedBranch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature work")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])
        try write("main\n", to: "main.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main only")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "feature"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let mainBefore = try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"])

        do {
            _ = try await inspector.fastForwardBranch("main", toCurrentIn: repository)
            XCTFail("Expected the diverged fast-forward to fail")
        } catch let error as RepositoryBranchError {
            XCTAssertEqual(error, .fastForwardOutRequiresAncestor)
        }
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"]),
            mainBefore
        )
    }

    func testFastForwardBranchToCurrentRefusesWorktreeCheckedOutBranch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        let worktreeParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repositoryURL)
            try? FileManager.default.removeItem(at: worktreeParent)
        }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature work")
        let worktreeURL = worktreeParent.appending(path: "main-worktree")
        try runGit([
            "-C", repositoryURL.path,
            "worktree", "add", "--quiet", worktreeURL.path, "main"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let mainBefore = try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"])

        do {
            _ = try await inspector.fastForwardBranch("main", toCurrentIn: repository)
            XCTFail("Expected the checked-out branch fast-forward to fail")
        } catch let error as RepositoryBranchError {
            guard case .fastForwardOutFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"]),
            mainBefore
        )
    }

    func testFastForwardsBranchInsideItsWorktree() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        let worktreeParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repositoryURL)
            try? FileManager.default.removeItem(at: worktreeParent)
        }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("advanced\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature work")
        let worktreeURL = worktreeParent.appending(path: "main-worktree")
        try runGit([
            "-C", repositoryURL.path,
            "worktree", "add", "--quiet", worktreeURL.path, "main"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let updated = try await inspector.fastForwardBranch(
            "main",
            inWorktreeAt: worktreeURL,
            toCurrentIn: repository
        )

        let headID = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mainID = try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(mainID, headID)
        XCTAssertEqual(updated.head, .branch("feature"))
        XCTAssertEqual(
            try String(contentsOf: worktreeURL.appending(path: "shared.txt"), encoding: .utf8),
            "advanced\n"
        )
    }

    func testCreatesMergeCommitOnBranchWithoutCheckout() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature work")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])
        try write("main\n", to: "main.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main only")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "feature"])
        try write("dirty\n", to: "dirty.txt", in: repositoryURL)

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let mainBefore = try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let headID = try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let updated = try await inspector.createMergeCommit(on: "main", in: repository)

        XCTAssertEqual(updated.head, .branch("feature"))
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "main^1"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            mainBefore
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "main^2"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            headID
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "log", "-1", "--format=%s", "main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "Merge branch 'feature' into main"
        )
        XCTAssertEqual(
            try String(contentsOf: repositoryURL.appending(path: "dirty.txt"), encoding: .utf8),
            "dirty\n"
        )
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            headID
        )
    }

    func testMergePredictionReportsConflictedFiles() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature side")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])
        try write("main\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main side")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "feature"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)

        let prediction = try await inspector.mergePrediction(into: "main", in: repository)
        XCTAssertFalse(prediction.isClean)
        XCTAssertEqual(prediction.conflictedPaths, ["shared.txt"])

        let mainBefore = try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"])
        do {
            _ = try await inspector.createMergeCommit(on: "main", in: repository)
            XCTFail("Expected the conflicted merge to fail")
        } catch let error as RepositoryBranchError {
            XCTAssertEqual(error, .mergeOutConflicts(["shared.txt"]))
        }
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"]),
            mainBefore
        )
    }

    func testCreateMergeCommitRequiresDivergence() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature work")

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)

        do {
            _ = try await inspector.createMergeCommit(on: "main", in: repository)
            XCTFail("Expected the non-diverged merge to fail")
        } catch let error as RepositoryBranchError {
            XCTAssertEqual(error, .mergeCommitRequiresDivergence)
        }
    }

    func testCreateMergeCommitRefusesWorktreeCheckedOutBranch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        let worktreeParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repositoryURL)
            try? FileManager.default.removeItem(at: worktreeParent)
        }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature work")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])
        try write("main\n", to: "main.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main only")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "feature"])
        let worktreeURL = worktreeParent.appending(path: "main-worktree")
        try runGit([
            "-C", repositoryURL.path,
            "worktree", "add", "--quiet", worktreeURL.path, "main"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let mainBefore = try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"])

        do {
            _ = try await inspector.createMergeCommit(on: "main", in: repository)
            XCTFail("Expected the checked-out branch merge to fail")
        } catch let error as RepositoryBranchError {
            XCTAssertEqual(error, .mergeOutCheckedOut)
        }
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"]),
            mainBefore
        )
    }

    func testMergesCurrentBranchInsideTargetWorktree() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        let worktreeParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repositoryURL)
            try? FileManager.default.removeItem(at: worktreeParent)
        }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature work")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])
        try write("main\n", to: "main.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main only")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "feature"])
        let worktreeURL = worktreeParent.appending(path: "main-worktree")
        try runGit([
            "-C", repositoryURL.path,
            "worktree", "add", "--quiet", worktreeURL.path, "main"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let updated = try await inspector.mergeCurrentBranch(
            into: "main",
            inWorktreeAt: worktreeURL,
            in: repository
        )

        XCTAssertEqual(updated.head, .branch("feature"))
        // git은 기본 브랜치로 merge할 때 " into <branch>" 접미사를 생략한다.
        XCTAssertTrue(
            try gitOutput(["-C", worktreeURL.path, "log", "-1", "--format=%s"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("Merge branch 'feature'")
        )
        XCTAssertEqual(
            try String(contentsOf: worktreeURL.appending(path: "feature.txt"), encoding: .utf8),
            "feature\n"
        )
        XCTAssertEqual(
            try String(contentsOf: worktreeURL.appending(path: "main.txt"), encoding: .utf8),
            "main\n"
        )
    }

    func testWorktreeMergeConflictLeavesResolvableStateAndAborts() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        let worktreeParent = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repositoryURL)
            try? FileManager.default.removeItem(at: worktreeParent)
        }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature side")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])
        try write("main\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Main side")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "feature"])
        let worktreeURL = worktreeParent.appending(path: "main-worktree")
        try runGit([
            "-C", repositoryURL.path,
            "worktree", "add", "--quiet", worktreeURL.path, "main"
        ])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let mainBefore = try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"])

        do {
            _ = try await inspector.mergeCurrentBranch(
                into: "main",
                inWorktreeAt: worktreeURL,
                in: repository
            )
            XCTFail("Expected the conflicted worktree merge to fail")
        } catch let error as RepositoryBranchError {
            XCTAssertEqual(error, .mergeInWorktreeConflicted(worktreeURL))
        }
        XCTAssertEqual(
            try gitOutput(["-C", worktreeURL.path, "rev-parse", "--verify", "MERGE_HEAD"])
                .isEmpty,
            false
        )

        _ = try await inspector.abortMerge(inWorktreeAt: worktreeURL, in: repository)
        XCTAssertEqual(
            try gitOutput(["-C", repositoryURL.path, "rev-parse", "refs/heads/main"]),
            mainBefore
        )
        XCTAssertEqual(
            try String(contentsOf: worktreeURL.appending(path: "shared.txt"), encoding: .utf8),
            "main\n"
        )
    }

    func testAddsAndRemovesTemporaryWorktree() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        let baseDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repositoryURL)
            try? FileManager.default.removeItem(at: baseDirectory)
        }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "feature"])
        try write("feature\n", to: "feature.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Feature work")

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)

        let worktreeURL = try await inspector.addTemporaryWorktree(
            for: "main",
            in: repository,
            baseDirectory: baseDirectory
        )
        XCTAssertEqual(
            try gitOutput(["-C", worktreeURL.path, "branch", "--show-current"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "main"
        )

        try write("blocking\n", to: worktreeURL.appending(path: "blocking.txt").lastPathComponent, in: worktreeURL)
        do {
            _ = try await inspector.removeWorktree(at: worktreeURL, in: repository)
            XCTFail("Expected removal of a dirty worktree to fail")
        } catch let error as RepositoryBranchError {
            guard case .worktreeRemovalFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        try FileManager.default.removeItem(at: worktreeURL.appending(path: "blocking.txt"))
        _ = try await inspector.removeWorktree(at: worktreeURL, in: repository)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeURL.path))
    }

    func testDeletesRemoteBranchAndItsTrackingReference() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        let remoteURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repositoryURL)
            try? FileManager.default.removeItem(at: remoteURL)
        }

        try runGit(["init", "--quiet", "--bare", remoteURL.path])
        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "remote", "add", "origin", remoteURL.path])
        try runGit(["-C", repositoryURL.path, "branch", "topic"])
        try runGit(["-C", repositoryURL.path, "push", "--quiet", "origin", "topic"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        _ = try await inspector.deleteRemoteBranch(trackingRef: "origin/topic", in: repository)

        try runGit(
            ["-C", remoteURL.path, "show-ref", "--verify", "--quiet", "refs/heads/topic"],
            expectedStatus: 1
        )
        try runGit(
            ["-C", repositoryURL.path, "show-ref", "--verify", "--quiet", "refs/remotes/origin/topic"],
            expectedStatus: 1
        )
        let branches = try await inspector.localBranches(in: repository)
        XCTAssertTrue(branches.contains("topic"))
    }

    func testRemovesTrackingReferenceWithoutTouchingRemote() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        let remoteURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repositoryURL)
            try? FileManager.default.removeItem(at: remoteURL)
        }

        try runGit(["init", "--quiet", "--bare", remoteURL.path])
        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "remote", "add", "origin", remoteURL.path])
        try runGit(["-C", repositoryURL.path, "push", "--quiet", "origin", "main"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        _ = try await inspector.removeRemoteTrackingReference("origin/main", in: repository)

        try runGit(
            ["-C", repositoryURL.path, "show-ref", "--verify", "--quiet", "refs/remotes/origin/main"],
            expectedStatus: 1
        )
        try runGit(["-C", remoteURL.path, "show-ref", "--verify", "--quiet", "refs/heads/main"])
    }

    func testTrackingBranchReflectsConfiguredUpstream() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        let remoteURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repositoryURL)
            try? FileManager.default.removeItem(at: remoteURL)
        }

        try runGit(["init", "--quiet", "--bare", remoteURL.path])
        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "remote", "add", "origin", remoteURL.path])
        try runGit(["-C", repositoryURL.path, "push", "--quiet", "--set-upstream", "origin", "main"])
        try runGit(["-C", repositoryURL.path, "branch", "local-only"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)

        let tracked = try await inspector.trackingBranch(of: "main", in: repository)
        XCTAssertEqual(tracked, "origin/main")
        let untracked = try await inspector.trackingBranch(of: "local-only", in: repository)
        XCTAssertNil(untracked)
    }

    func testDeletesMergedBranchSafely() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "branch", "merged"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        _ = try await inspector.deleteBranch(named: "merged", in: repository)

        let branches = try await inspector.localBranches(in: repository)
        XCTAssertFalse(branches.contains("merged"))
        XCTAssertTrue(branches.contains("main"))
    }

    func testDeleteBranchRefusesUnmergedBranch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "-c", "unmerged"])
        try write("extra\n", to: "extra.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Unmerged work")
        try runGit(["-C", repositoryURL.path, "switch", "--quiet", "main"])

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)

        do {
            _ = try await inspector.deleteBranch(named: "unmerged", in: repository)
            XCTFail("Expected the unmerged branch deletion to fail")
        } catch let error as RepositoryBranchError {
            guard case .deletionFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let branches = try await inspector.localBranches(in: repository)
        XCTAssertTrue(branches.contains("unmerged"))
    }

    func testDeleteBranchRefusesCurrentBranch() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)

        do {
            _ = try await inspector.deleteBranch(named: "main", in: repository)
            XCTFail("Expected the current branch deletion to fail")
        } catch let error as RepositoryBranchError {
            XCTAssertEqual(error, .deletionUnavailable)
        }
        let branches = try await inspector.localBranches(in: repository)
        XCTAssertTrue(branches.contains("main"))
    }

    func testAuthorAvatarSourceParsesOnlyGitHubNoreplyEmails() {
        XCTAssertEqual(
            AuthorAvatarSource.url(for: "12345+octocat@users.noreply.github.com")?.absoluteString,
            "https://avatars.githubusercontent.com/u/12345?s=64&v=4"
        )
        XCTAssertEqual(
            AuthorAvatarSource.url(for: "Octo-Cat@users.noreply.GitHub.com")?.absoluteString,
            "https://github.com/octo-cat.png?size=64"
        )
        XCTAssertNil(AuthorAvatarSource.url(for: "someone@example.com"))
        XCTAssertNil(AuthorAvatarSource.url(for: "abc+octocat@users.noreply.github.com"))
        XCTAssertNil(AuthorAvatarSource.url(for: "bad/../name@users.noreply.github.com"))
        XCTAssertNil(AuthorAvatarSource.url(for: "@users.noreply.github.com"))
    }

    @MainActor
    func testGitHubAvatarLookupParsesSearchResponse() {
        let found = Data("""
        {"total_count":1,"items":[{"login":"octocat","avatar_url":"https://avatars.githubusercontent.com/u/583231?v=4"}]}
        """.utf8)
        XCTAssertEqual(
            GitHubAvatarLookup.avatarURL(fromSearchResponse: found)?.absoluteString,
            "https://avatars.githubusercontent.com/u/583231?v=4&s=64"
        )

        let empty = Data("{\"total_count\":0,\"items\":[]}".utf8)
        XCTAssertNil(GitHubAvatarLookup.avatarURL(fromSearchResponse: empty))

        XCTAssertNil(GitHubAvatarLookup.avatarURL(fromSearchResponse: Data("not json".utf8)))
    }

    func testCommitSignatureStatusMapping() {
        XCTAssertEqual(
            RepositoryCommitSignature.make(status: "G", keyID: "ABCD", signer: "Eugene"),
            .good(keyID: "ABCD", signer: "Eugene")
        )
        XCTAssertEqual(
            RepositoryCommitSignature.make(status: "U", keyID: "ABCD", signer: ""),
            .unverifiedTrust(keyID: "ABCD", signer: "")
        )
        for status in ["B", "X", "Y", "R"] {
            XCTAssertEqual(
                RepositoryCommitSignature.make(status: status, keyID: "", signer: ""),
                .invalid
            )
        }
        XCTAssertEqual(RepositoryCommitSignature.make(status: "E", keyID: "", signer: ""), .cannotCheck)
        XCTAssertEqual(RepositoryCommitSignature.make(status: "N", keyID: "", signer: ""), .none)
    }

    func testCommitSignatureForUnsignedCommitIsNone() async throws {
        let repositoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try initializeRepository(at: repositoryURL)
        try write("base\n", to: "shared.txt", in: repositoryURL)
        try commitAll(in: repositoryURL, message: "Initial")

        let inspector = RepositoryInspector()
        let repository = try await inspector.inspect(at: repositoryURL)
        let history = try await inspector.history(in: repository)
        let commit = try XCTUnwrap(history.commits.first)

        let signature = try await inspector.commitSignature(for: commit, in: repository)
        XCTAssertEqual(signature, .none)
    }

    func testGPGKeyParserReadsSecretKeysAndMatchesConfiguredValues() {
        let output = """
        sec:u:4096:1:ABCDEF1234567890:1600000000:::u:::scESC:::+:::23::0:
        fpr:::::::::00112233445566778899ABCDEF1234567890AABB:
        uid:u::::1600000000::HASH::Eugene Epilo9er <epilo9er@gmail.com>::::::::::0:
        ssb:u:4096:1:1122334455667788:1600000000::::::e:::+:::23:
        sec:u:255:22:FEDCBA0987654321:1700000000:::u:::scESC:::+:::ed25519::0:
        uid:u::::1700000000::HASH2::Second Key <second@example.com>::::::::::0:
        """

        let keys = GPGKeyParser.keys(fromColonOutput: output)
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys.first?.id, "ABCDEF1234567890")
        XCTAssertEqual(keys.first?.userID, "Eugene Epilo9er <epilo9er@gmail.com>")
        XCTAssertEqual(keys.first?.shortID, "34567890")

        XCTAssertEqual(GPGKeyParser.matchedKeyID("34567890", in: keys), "ABCDEF1234567890")
        XCTAssertEqual(
            GPGKeyParser.matchedKeyID("00112233445566778899abcdef1234567890", in: keys),
            "ABCDEF1234567890"
        )
        XCTAssertNil(GPGKeyParser.matchedKeyID("DEADBEEF", in: keys))
        XCTAssertNil(GPGKeyParser.matchedKeyID("", in: keys))
    }

    func testAuthorIdentityInitialsAndStableColorIndex() {
        XCTAssertEqual(AuthorIdentity.initials(for: "Eugene Epilo9er"), "EE")
        XCTAssertEqual(AuthorIdentity.initials(for: "홍길동"), "홍")
        XCTAssertEqual(AuthorIdentity.initials(for: ""), "?")

        let index = AuthorIdentity.colorIndex(for: "epilo9er@gmail.com", paletteCount: 8)
        XCTAssertTrue((0..<8).contains(index))
        XCTAssertEqual(
            AuthorIdentity.colorIndex(for: "EPILO9ER@GMAIL.COM", paletteCount: 8),
            index
        )
        XCTAssertEqual(AuthorIdentity.colorIndex(for: "someone@example.com", paletteCount: 0), 0)
    }

    func testInstallsCommandLineToolIntoWritableDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let installed = try CommandLineToolInstaller.install(into: [directory])

        XCTAssertEqual(installed.lastPathComponent, "gallae")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installed.path))
        let content = try String(contentsOf: installed, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("#!/bin/sh"))
        XCTAssertTrue(content.contains("usage: gallae [path]"))
        XCTAssertEqual(CommandLineToolInstaller.installedLocation(in: [directory]), installed)
    }

    func testCommandLineToolInstallFailsWithoutWritableDirectory() throws {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "GallaeTests-missing-\(UUID().uuidString)", directoryHint: .isDirectory)

        XCTAssertThrowsError(try CommandLineToolInstaller.install(into: [missing])) { error in
            XCTAssertEqual(
                error as? CommandLineToolError,
                .noWritableLocation([missing])
            )
        }
        XCTAssertNil(CommandLineToolInstaller.installedLocation(in: [missing]))
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
        try runGit(["-C", url.path, "config", "commit.gpgSign", "false"])
        try runGit(["-C", url.path, "config", "commit.signOff", "false"])
        try runGit(["-C", url.path, "config", "tag.gpgSign", "false"])
        try runGit(["-C", url.path, "config", "tag.signOff", "false"])
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
