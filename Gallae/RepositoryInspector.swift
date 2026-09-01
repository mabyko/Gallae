import Foundation

struct RepositorySummary: Equatable, Sendable {
    enum Head: Equatable, Sendable {
        case branch(String)
        case detached(String)
    }

    struct Upstream: Equatable, Sendable {
        let name: String
        let ahead: Int?
        let behind: Int?
    }

    struct Operation: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case merge
            case rebase
        }

        let kind: Kind
        let unresolvedConflictCount: Int

        var canContinue: Bool { unresolvedConflictCount == 0 }
    }

    struct Change: Equatable, Identifiable, Sendable {
        enum State: Equatable, Sendable {
            case modified
            case typeChanged
            case added
            case deleted
            case renamed
            case copied
            case untracked
        }

        let path: String
        let originalPath: String?
        let staged: State?
        let unstaged: State?
        let isConflicted: Bool

        var id: String { path }

        var canDiscardUnstagedChanges: Bool {
            guard !isConflicted else { return false }
            return switch unstaged {
            case .modified, .typeChanged, .deleted: true
            default: false
            }
        }
    }

    let rootURL: URL
    let head: Head
    let isUnborn: Bool
    let upstream: Upstream?
    let changes: [Change]
    let operation: Operation?

    var name: String {
        rootURL.lastPathComponent
    }
}

struct RepositoryRemote: Equatable, Identifiable, Sendable {
    let name: String
    let fetchURL: String
    let pushURL: String

    var id: String { name }
}

struct RepositoryActivity: Equatable, Sendable {
    struct Commit: Equatable, Identifiable, Sendable {
        let id: String
        let subject: String
        let committedAt: Date
    }

    let commitCount: Int
    let recentCommits: [Commit]
}

struct RepositoryCommitMessage: Equatable, Sendable {
    let subject: String
    let body: String
}

struct RepositoryBranchDivergence: Equatable, Sendable {
    let uniqueToCurrent: Int
    let uniqueToOther: Int
}

struct RepositoryMergePrediction: Equatable, Sendable {
    let isClean: Bool
    let conflictedPaths: [String]
    let treeID: String
}

struct RepositoryHistory: Equatable, Sendable {
    struct GraphEdge: Equatable, Sendable {
        let fromLane: Int
        let toLane: Int
    }

    struct GraphRow: Equatable, Sendable {
        let commitLane: Int
        let topLaneCount: Int
        let bottomLaneCount: Int
        let hasIncomingEdge: Bool
        let continuationEdges: [GraphEdge]
        let parentEdges: [GraphEdge]
    }

    struct Reference: Equatable, Hashable, Identifiable, Sendable {
        enum Kind: String, Equatable, Hashable, Sendable {
            case branch
            case remoteBranch
            case tag
        }

        let name: String
        let kind: Kind

        var id: String { "\(kind.rawValue):\(name)" }
    }

    struct Commit: Equatable, Identifiable, Sendable {
        let id: String
        let parentIDs: [String]
        let authorName: String
        let authorEmail: String
        let committedAt: Date
        let subject: String
        let body: String
        let references: [Reference]

        func matches(search query: String) -> Bool {
            let terms = query.split { $0.isWhitespace }
            guard !terms.isEmpty else { return true }

            let fields = [subject, body, authorName, authorEmail, id] + references.map(\.name)
            return terms.allSatisfy { term in
                fields.contains { $0.localizedCaseInsensitiveContains(String(term)) }
            }
        }
    }

    let commits: [Commit]
    let headCommitID: String?
    let graphRows: [String: GraphRow]
    let graphLaneCount: Int

    init(commits: [Commit], headCommitID: String? = nil) {
        self.commits = commits
        self.headCommitID = headCommitID ?? commits.first?.id
        let layout = Self.makeGraphLayout(for: commits)
        graphRows = layout.rows
        graphLaneCount = layout.laneCount
    }

    private static func makeGraphLayout(
        for commits: [Commit]
    ) -> (rows: [String: GraphRow], laneCount: Int) {
        var lanes: [String] = []
        var rows: [String: GraphRow] = [:]
        var maximumLaneCount = 0

        for commit in commits {
            let hasIncomingEdge = lanes.contains(commit.id)
            if !hasIncomingEdge { lanes.append(commit.id) }
            guard let commitLane = lanes.firstIndex(of: commit.id) else { continue }

            let topLanes = lanes
            var bottomLanes = lanes
            bottomLanes.remove(at: commitLane)
            var insertionIndex = min(commitLane, bottomLanes.count)

            for (parentIndex, parentID) in commit.parentIDs.enumerated() {
                if let existingIndex = bottomLanes.firstIndex(of: parentID) {
                    if parentIndex == 0 { insertionIndex = existingIndex + 1 }
                    continue
                }
                bottomLanes.insert(parentID, at: min(insertionIndex, bottomLanes.count))
                insertionIndex += 1
            }

            let continuationEdges: [GraphEdge] = topLanes.enumerated().compactMap { lane, commitID in
                guard lane != commitLane,
                      let bottomLane = bottomLanes.firstIndex(of: commitID)
                else { return nil }
                return GraphEdge(fromLane: lane, toLane: bottomLane)
            }
            let parentEdges = commit.parentIDs.compactMap { parentID in
                bottomLanes.firstIndex(of: parentID).map {
                    GraphEdge(fromLane: commitLane, toLane: $0)
                }
            }

            rows[commit.id] = .init(
                commitLane: commitLane,
                topLaneCount: topLanes.count,
                bottomLaneCount: bottomLanes.count,
                hasIncomingEdge: hasIncomingEdge,
                continuationEdges: continuationEdges,
                parentEdges: parentEdges
            )
            maximumLaneCount = max(
                maximumLaneCount,
                max(topLanes.count, bottomLanes.count)
            )
            lanes = bottomLanes
        }

        return (rows, maximumLaneCount)
    }
}

struct RepositoryInteractiveRebasePlan: Equatable, Sendable {
    enum Action: String, CaseIterable, Equatable, Hashable, Sendable {
        case pick
        case reword
        case squash
        case fixup
        case drop
    }

    enum ValidationError: Equatable, Sendable {
        case noCommits
        case actionNeedsPreviousCommit(stepID: String)
    }

    struct Step: Equatable, Identifiable, Sendable {
        let id: String
        let subject: String
        var action: Action = .pick
    }

    var steps: [Step]

    var validationError: ValidationError? {
        var hasPreviousCommit = false
        for step in steps {
            switch step.action {
            case .drop:
                continue
            case .squash, .fixup:
                guard hasPreviousCommit else {
                    return .actionNeedsPreviousCommit(stepID: step.id)
                }
            case .pick, .reword:
                hasPreviousCommit = true
            }
        }
        return hasPreviousCommit ? nil : .noCommits
    }
}

struct RepositoryCommitPatch: Equatable, Sendable {
    let commitID: String
    let fileID: String
    let content: RepositoryDiff.Section.Content
}

struct RepositoryStash: Equatable, Identifiable, Sendable {
    let id: String
    let reference: String
    let subject: String
    let createdAt: Date
}

struct RepositoryReflogEntry: Equatable, Identifiable, Sendable {
    let selector: String
    let commitID: String
    let actorName: String
    let actorEmail: String
    let occurredAt: Date
    let action: String

    var id: String { selector }
}

struct RepositoryCommitFile: Equatable, Identifiable, Sendable {
    let path: String
    let originalPath: String?
    let state: RepositorySummary.Change.State

    var id: String { path }

    var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    var parentPath: String {
        guard let separator = path.lastIndex(of: "/") else { return "" }
        return String(path[..<separator])
    }
}

struct RepositoryDiff: Equatable, Sendable {
    enum Scope: Equatable, Hashable, Sendable {
        case staged
        case unstaged
        case untracked
        case base
        case ours
        case theirs
    }

    struct Section: Equatable, Identifiable, Sendable {
        enum Content: Equatable, Sendable {
            case text([Line])
            case binary
            case unsupportedEncoding
            case tooLarge(byteLimit: Int)
            case missing
            case unavailable(String)
        }

        let scope: Scope
        let content: Content

        var id: Scope { scope }

        var hunks: [Hunk] {
            guard case .text(let lines) = content else { return [] }
            let starts = lines.indices.filter { lines[$0].kind == .hunk }
            guard let first = starts.first else { return [] }
            let metadata = lines[..<first].map(\.text)

            return starts.enumerated().map { offset, start in
                let end = offset + 1 < starts.count ? starts[offset + 1] : lines.endIndex
                let patch = (metadata + lines[start..<end].map(\.text)).joined(separator: "\n") + "\n"
                return Hunk(
                    id: lines[start].id,
                    scope: scope,
                    patch: Data(patch.utf8)
                )
            }
        }
    }

    struct Line: Equatable, Identifiable, Sendable {
        enum Kind: Equatable, Sendable {
            case metadata
            case hunk
            case context
            case addition
            case deletion
        }

        let id: Int
        let kind: Kind
        let oldLineNumber: Int?
        let newLineNumber: Int?
        let text: String
    }

    struct Hunk: Equatable, Identifiable, Sendable {
        let id: Int
        let scope: Scope
        fileprivate let patch: Data
    }

    let path: String
    let originalPath: String?
    let sections: [Section]
}

enum RepositoryConflictSide: Hashable, Sendable {
    case ours
    case theirs

    fileprivate var stage: Int {
        switch self {
        case .ours: 2
        case .theirs: 3
        }
    }

    fileprivate var checkoutArgument: String {
        switch self {
        case .ours: "--ours"
        case .theirs: "--theirs"
        }
    }
}

struct RepositoryInspector: Sendable {
    static let maximumDisplayedDiffBytes = 2 * 1_024 * 1_024
    static let maximumExpandedDiffBytes = 16 * 1_024 * 1_024
    static let maximumHistoryCommits = 100

    private static let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    func inspect(at selectedURL: URL) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let repository = try await Task.detached(priority: .userInitiated) {
            try Self.inspectSynchronously(at: selectedURL)
        }.value
        try Task.checkCancellation()
        return repository
    }

    func activity(in repository: RepositorySummary) async throws -> RepositoryActivity {
        try Task.checkCancellation()
        let activity = try await Task.detached(priority: .userInitiated) {
            try Self.activitySynchronously(in: repository)
        }.value
        try Task.checkCancellation()
        return activity
    }

    func history(in repository: RepositorySummary) async throws -> RepositoryHistory {
        try Task.checkCancellation()
        let history = try await Task.detached(priority: .userInitiated) {
            try Self.historySynchronously(in: repository)
        }.value
        try Task.checkCancellation()
        return history
    }

    func interactiveRebasePlan(
        startingAt commit: RepositoryHistory.Commit,
        in repository: RepositorySummary
    ) async throws -> RepositoryInteractiveRebasePlan {
        try Task.checkCancellation()
        let plan = try await Task.detached(priority: .userInitiated) {
            try Self.interactiveRebasePlanSynchronously(startingAt: commit, in: repository)
        }.value
        try Task.checkCancellation()
        return plan
    }

    func executeInteractiveRebase(
        _ plan: RepositoryInteractiveRebasePlan,
        rewordMessages: [String: String],
        startingAt commit: RepositoryHistory.Commit,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        let cancellation = GitProcessCancellation()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try Self.executeInteractiveRebaseSynchronously(
                    plan,
                    rewordMessages: rewordMessages,
                    startingAt: commit,
                    in: repository,
                    cancellation: cancellation
                )
            }.value
        } onCancel: {
            cancellation.cancel()
        }
    }

    func revertCommit(
        _ commit: RepositoryHistory.Commit,
        mainlineParent: Int? = nil,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.revertCommitSynchronously(
                commit,
                mainlineParent: mainlineParent,
                in: repository
            )
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func resetCurrentBranch(
        to commit: RepositoryHistory.Commit,
        mode: RepositoryResetMode,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.resetCurrentBranchSynchronously(
                to: commit,
                mode: mode,
                in: repository
            )
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func stashes(in repository: RepositorySummary) async throws -> [RepositoryStash] {
        try Task.checkCancellation()
        let stashes = try await Task.detached(priority: .userInitiated) {
            try Self.stashesSynchronously(in: repository)
        }.value
        try Task.checkCancellation()
        return stashes
    }

    func reflog(in repository: RepositorySummary) async throws -> [RepositoryReflogEntry] {
        try Task.checkCancellation()
        let entries = try await Task.detached(priority: .userInitiated) {
            try Self.reflogSynchronously(in: repository)
        }.value
        try Task.checkCancellation()
        return entries
    }

    func createStash(
        message: String,
        includeUntracked: Bool,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        let cancellation = GitProcessCancellation()
        return try await withTaskCancellationHandler {
            do {
                let updatedRepository = try await Task.detached(priority: .userInitiated) {
                    try Self.createStashSynchronously(
                        message: message,
                        includeUntracked: includeUntracked,
                        in: repository,
                        cancellation: cancellation
                    )
                }.value
                try Task.checkCancellation()
                return updatedRepository
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func applyStash(
        _ stash: RepositoryStash,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        let cancellation = GitProcessCancellation()
        return try await withTaskCancellationHandler {
            do {
                let updatedRepository = try await Task.detached(priority: .userInitiated) {
                    try Self.applyStashSynchronously(
                        stash,
                        in: repository,
                        cancellation: cancellation
                    )
                }.value
                try Task.checkCancellation()
                return updatedRepository
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func dropStash(
        _ stash: RepositoryStash,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.dropStashSynchronously(stash, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func headCommitMessage(
        in repository: RepositorySummary
    ) async throws -> RepositoryCommitMessage {
        try Task.checkCancellation()
        let message = try await Task.detached(priority: .userInitiated) {
            try Self.headCommitMessageSynchronously(in: repository)
        }.value
        try Task.checkCancellation()
        return message
    }

    func divergence(
        from branch: String,
        in repository: RepositorySummary
    ) async throws -> RepositoryBranchDivergence {
        try Task.checkCancellation()
        let divergence = try await Task.detached(priority: .userInitiated) {
            try Self.divergenceSynchronously(from: branch, in: repository)
        }.value
        try Task.checkCancellation()
        return divergence
    }

    func localBranches(in repository: RepositorySummary) async throws -> [String] {
        try Task.checkCancellation()
        let branches = try await Task.detached(priority: .userInitiated) {
            try Self.localBranchesSynchronously(in: repository)
        }.value
        try Task.checkCancellation()
        return branches
    }

    func localBranchWorktrees(in repository: RepositorySummary) async throws -> [String: URL] {
        try Task.checkCancellation()
        let worktrees = try await Task.detached(priority: .userInitiated) {
            try Self.localBranchWorktreesSynchronously(in: repository)
        }.value
        try Task.checkCancellation()
        return worktrees
    }

    func remotes(in repository: RepositorySummary) async throws -> [RepositoryRemote] {
        try Task.checkCancellation()
        let remotes = try await Task.detached(priority: .userInitiated) {
            try Self.remotesSynchronously(in: repository)
        }.value
        try Task.checkCancellation()
        return remotes
    }

    func testRemoteConnection(
        named name: String,
        in repository: RepositorySummary
    ) async throws {
        let cancellation = GitProcessCancellation()
        try await withTaskCancellationHandler {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try Self.testRemoteConnectionSynchronously(
                        named: name,
                        in: repository,
                        cancellation: cancellation
                    )
                }.value
                try Task.checkCancellation()
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func updateRemote(
        named name: String,
        renamingTo newName: String,
        fetchURL: String,
        pushURL: String,
        in repository: RepositorySummary
    ) async throws -> [RepositoryRemote] {
        try Task.checkCancellation()
        let remotes = try await Task.detached(priority: .userInitiated) {
            try Self.updateRemoteSynchronously(
                named: name,
                renamingTo: newName,
                fetchURL: fetchURL,
                pushURL: pushURL,
                in: repository
            )
        }.value
        try Task.checkCancellation()
        return remotes
    }

    func removeRemote(
        named name: String,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.removeRemoteSynchronously(named: name, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func switchBranch(
        to branch: String,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.switchBranchSynchronously(to: branch, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func createBranch(
        named branch: String,
        at startPoint: String? = nil,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.createBranchSynchronously(
                named: branch,
                at: startPoint,
                in: repository
            )
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func mergeBranch(
        _ branch: String,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.mergeBranchSynchronously(branch, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func fastForwardBranch(
        _ branch: String,
        toCurrentIn repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.fastForwardBranchSynchronously(branch, toCurrentIn: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func fastForwardBranch(
        _ branch: String,
        inWorktreeAt worktreeURL: URL,
        toCurrentIn repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.fastForwardBranchSynchronously(
                branch,
                inWorktreeAt: worktreeURL,
                toCurrentIn: repository
            )
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func mergePrediction(
        into branch: String,
        in repository: RepositorySummary
    ) async throws -> RepositoryMergePrediction {
        try Task.checkCancellation()
        let prediction = try await Task.detached(priority: .userInitiated) {
            try Self.mergePredictionSynchronously(into: branch, in: repository)
        }.value
        try Task.checkCancellation()
        return prediction
    }

    func createMergeCommit(
        on branch: String,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.createMergeCommitSynchronously(on: branch, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func mergeCurrentBranch(
        into branch: String,
        inWorktreeAt worktreeURL: URL,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.mergeCurrentBranchSynchronously(
                into: branch,
                inWorktreeAt: worktreeURL,
                in: repository
            )
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func abortMerge(
        inWorktreeAt worktreeURL: URL,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.abortMergeSynchronously(inWorktreeAt: worktreeURL, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func addTemporaryWorktree(
        for branch: String,
        in repository: RepositorySummary,
        baseDirectory: URL? = nil
    ) async throws -> URL {
        try Task.checkCancellation()
        let worktreeURL = try await Task.detached(priority: .userInitiated) {
            try Self.addTemporaryWorktreeSynchronously(
                for: branch,
                in: repository,
                baseDirectory: baseDirectory
            )
        }.value
        try Task.checkCancellation()
        return worktreeURL
    }

    func deleteBranch(
        named branch: String,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.deleteBranchSynchronously(named: branch, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func removeWorktree(
        at worktreeURL: URL,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.removeWorktreeSynchronously(at: worktreeURL, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func mergeBranchCreatingCommit(
        _ branch: String,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.mergeBranchCreatingCommitSynchronously(branch, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func rebaseCurrentBranch(
        onto branch: String,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.rebaseCurrentBranchSynchronously(onto: branch, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func fetch(
        from remote: String? = nil,
        pruning: Bool = false,
        usingConfiguredDefaultRemote: Bool = false,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        let cancellation = GitProcessCancellation()
        return try await withTaskCancellationHandler {
            do {
                let updatedRepository = try await Task.detached(priority: .userInitiated) {
                    try Self.fetchSynchronously(
                        from: remote,
                        pruning: pruning,
                        usingConfiguredDefaultRemote: usingConfiguredDefaultRemote,
                        in: repository,
                        cancellation: cancellation
                    )
                }.value
                try Task.checkCancellation()
                return updatedRepository
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func pull(in repository: RepositorySummary) async throws -> RepositorySummary {
        let cancellation = GitProcessCancellation()
        return try await withTaskCancellationHandler {
            do {
                let updatedRepository = try await Task.detached(priority: .userInitiated) {
                    try Self.pullSynchronously(in: repository, cancellation: cancellation)
                }.value
                try Task.checkCancellation()
                return updatedRepository
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func push(in repository: RepositorySummary) async throws -> RepositorySummary {
        let cancellation = GitProcessCancellation()
        return try await withTaskCancellationHandler {
            do {
                let updatedRepository = try await Task.detached(priority: .userInitiated) {
                    try Self.pushSynchronously(in: repository, cancellation: cancellation)
                }.value
                try Task.checkCancellation()
                return updatedRepository
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func addRemoteAndPublish(
        named name: String,
        url: String,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        let cancellation = GitProcessCancellation()
        return try await withTaskCancellationHandler {
            do {
                let updatedRepository = try await Task.detached(priority: .userInitiated) {
                    try Self.addRemoteAndPublishSynchronously(
                        named: name,
                        url: url,
                        in: repository,
                        cancellation: cancellation
                    )
                }.value
                try Task.checkCancellation()
                return updatedRepository
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func publish(
        to remote: String,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        let cancellation = GitProcessCancellation()
        return try await withTaskCancellationHandler {
            do {
                let updatedRepository = try await Task.detached(priority: .userInitiated) {
                    try Self.publishSynchronously(
                        to: remote,
                        in: repository,
                        cancellation: cancellation
                    )
                }.value
                try Task.checkCancellation()
                return updatedRepository
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func files(
        for commit: RepositoryHistory.Commit,
        in repository: RepositorySummary
    ) async throws -> [RepositoryCommitFile] {
        try Task.checkCancellation()
        let files = try await Task.detached(priority: .userInitiated) {
            try Self.commitFilesSynchronously(for: commit, in: repository)
        }.value
        try Task.checkCancellation()
        return files
    }

    func files(
        for stash: RepositoryStash,
        in repository: RepositorySummary
    ) async throws -> [RepositoryCommitFile] {
        try Task.checkCancellation()
        let files = try await Task.detached(priority: .userInitiated) {
            try Self.stashFilesSynchronously(for: stash, in: repository)
        }.value
        try Task.checkCancellation()
        return files
    }

    func patch(
        for file: RepositoryCommitFile,
        in commit: RepositoryHistory.Commit,
        repository: RepositorySummary,
        maximumOutputBytes: Int? = maximumDisplayedDiffBytes
    ) async throws -> RepositoryCommitPatch {
        try Task.checkCancellation()
        let patch = try await Task.detached(priority: .userInitiated) {
            try Self.patchSynchronously(
                for: file,
                in: commit,
                repository: repository,
                maximumOutputBytes: maximumOutputBytes
            )
        }.value
        try Task.checkCancellation()
        return patch
    }

    func patch(
        for file: RepositoryCommitFile,
        in stash: RepositoryStash,
        repository: RepositorySummary,
        maximumOutputBytes: Int? = maximumDisplayedDiffBytes
    ) async throws -> RepositoryCommitPatch {
        try Task.checkCancellation()
        let patch = try await Task.detached(priority: .userInitiated) {
            try Self.stashPatchSynchronously(
                for: file,
                in: stash,
                repository: repository,
                maximumOutputBytes: maximumOutputBytes
            )
        }.value
        try Task.checkCancellation()
        return patch
    }

    func diff(
        for change: RepositorySummary.Change,
        in repository: RepositorySummary,
        maximumOutputBytes: Int? = maximumDisplayedDiffBytes
    ) async throws -> RepositoryDiff {
        try Task.checkCancellation()
        let diff = try await Task.detached(priority: .userInitiated) {
            try Self.diffSynchronously(
                for: change,
                in: repository,
                maximumOutputBytes: maximumOutputBytes
            )
        }.value
        try Task.checkCancellation()
        return diff
    }

    func stage(
        _ change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try await stage([change], in: repository)
    }

    func stage(
        _ changes: [RepositorySummary.Change],
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.stageSynchronously(changes, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func unstage(
        _ change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try await unstage([change], in: repository)
    }

    func unstage(
        _ changes: [RepositorySummary.Change],
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.unstageSynchronously(changes, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func discard(
        _ change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.discardSynchronously(change, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func resolveConflict(
        _ change: RepositorySummary.Change,
        using side: RepositoryConflictSide,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.resolveConflictSynchronously(change, using: side, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func markConflictResolved(
        _ change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.markConflictResolvedSynchronously(change, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func continueOperation(in repository: RepositorySummary) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.updateOperationSynchronously(in: repository, aborting: false)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func abortOperation(in repository: RepositorySummary) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.updateOperationSynchronously(in: repository, aborting: true)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func stage(
        _ hunk: RepositoryDiff.Hunk,
        for change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.updateIndexSynchronously(
                with: hunk,
                for: change,
                in: repository,
                reverse: false
            )
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func unstage(
        _ hunk: RepositoryDiff.Hunk,
        for change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.updateIndexSynchronously(
                with: hunk,
                for: change,
                in: repository,
                reverse: true
            )
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    func commit(
        subject: String,
        body: String,
        amend: Bool = false,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.commitSynchronously(subject: subject, body: body, amend: amend, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    private static func stageSynchronously(
        _ changes: [RepositorySummary.Change],
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        guard
            !changes.isEmpty,
            changes.allSatisfy({ !$0.isConflicted && $0.unstaged != nil })
        else {
            throw RepositoryIndexError.unavailable
        }
        let paths = Array(Set(changes.flatMap { change in
            [change.originalPath, change.path].compactMap(\.self)
        }))
        let result = try runGit([
            "-C", repository.rootURL.path,
            "add", "--all", "--"
        ] + paths)
        guard result.status == 0 else {
            throw RepositoryIndexError.gitFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func unstageSynchronously(
        _ changes: [RepositorySummary.Change],
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        guard
            !changes.isEmpty,
            changes.allSatisfy({ !$0.isConflicted && $0.staged != nil })
        else {
            throw RepositoryIndexError.unavailable
        }
        let paths = Array(Set(changes.flatMap { change in
            [change.originalPath, change.path].compactMap(\.self)
        }))
        let command = repository.isUnborn
            ? ["rm", "--cached", "--force", "--ignore-unmatch", "--"]
            : ["restore", "--staged", "--"]
        let result = try runGit(["-C", repository.rootURL.path] + command + paths)
        guard result.status == 0 else {
            throw RepositoryIndexError.gitFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func discardSynchronously(
        _ change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        guard change.canDiscardUnstagedChanges else {
            throw RepositoryDiscardError.unavailable
        }
        let result = try runGit([
            "-C", repository.rootURL.path,
            "restore", "--worktree", "--", literalPathspec(change.path)
        ])
        guard result.status == 0 else {
            throw RepositoryDiscardError.gitFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func resolveConflictSynchronously(
        _ change: RepositorySummary.Change,
        using side: RepositoryConflictSide,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        guard change.isConflicted else {
            throw RepositoryConflictResolutionError.unavailable
        }

        let pathspec = literalPathspec(change.path)
        let entries = try runGit([
            "-C", repository.rootURL.path,
            "ls-files", "--stage", "-z", "--", pathspec
        ])
        guard entries.status == 0 else {
            throw RepositoryConflictResolutionError.gitFailed(entries.standardError)
        }
        let objectIDs = conflictStageObjectIDs(from: entries.standardOutput)
        guard !objectIDs.isEmpty else {
            throw RepositoryConflictResolutionError.unavailable
        }

        let result: GitResult
        if objectIDs[side.stage] == nil {
            result = try runGit([
                "-C", repository.rootURL.path,
                "rm", "--force", "--", pathspec
            ])
        } else {
            let checkout = try runGit([
                "-C", repository.rootURL.path,
                "checkout", side.checkoutArgument, "--", pathspec
            ])
            guard checkout.status == 0 else {
                throw RepositoryConflictResolutionError.gitFailed(checkout.standardError)
            }
            result = try runGit([
                "-C", repository.rootURL.path,
                "add", "--", pathspec
            ])
        }
        guard result.status == 0 else {
            throw RepositoryConflictResolutionError.gitFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func markConflictResolvedSynchronously(
        _ change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        guard change.isConflicted else {
            throw RepositoryConflictResolutionError.unavailable
        }

        let pathspec = literalPathspec(change.path)
        let entries = try runGit([
            "-C", repository.rootURL.path,
            "ls-files", "--stage", "-z", "--", pathspec
        ])
        guard entries.status == 0 else {
            throw RepositoryConflictResolutionError.gitFailed(entries.standardError)
        }
        guard !conflictStageObjectIDs(from: entries.standardOutput).isEmpty else {
            throw RepositoryConflictResolutionError.unavailable
        }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "add", "--all", "--", pathspec
        ])
        guard result.status == 0 else {
            throw RepositoryConflictResolutionError.gitFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func updateOperationSynchronously(
        in repository: RepositorySummary,
        aborting: Bool
    ) throws -> RepositorySummary {
        let currentRepository = try inspectSynchronously(at: repository.rootURL)
        guard let operation = currentRepository.operation else {
            throw RepositoryOperationError.unavailable
        }
        guard aborting || operation.canContinue else {
            throw RepositoryOperationError.unresolvedConflicts
        }
        let command = switch operation.kind {
        case .merge: "merge"
        case .rebase: "rebase"
        }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "-c", "core.editor=true",
            command, aborting ? "--abort" : "--continue"
        ])
        guard result.status == 0 else {
            throw aborting
                ? RepositoryOperationError.abortFailed(result.standardError)
                : RepositoryOperationError.continueFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func updateIndexSynchronously(
        with hunk: RepositoryDiff.Hunk,
        for change: RepositorySummary.Change,
        in repository: RepositorySummary,
        reverse: Bool
    ) throws -> RepositorySummary {
        let expectedScope: RepositoryDiff.Scope = reverse ? .staged : .unstaged
        let expectedState = reverse ? change.staged : change.unstaged
        guard
            !change.isConflicted,
            expectedState == .modified,
            hunk.scope == expectedScope
        else {
            throw RepositoryIndexError.unavailable
        }

        var arguments = ["-C", repository.rootURL.path, "apply", "--cached"]
        if reverse {
            arguments.append("--reverse")
        }
        let result = try runGit(arguments, standardInput: hunk.patch)
        guard result.status == 0 else {
            throw RepositoryIndexError.gitFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func commitSynchronously(
        subject: String,
        body: String,
        amend: Bool,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !subject.isEmpty,
            repository.changes.contains(where: { $0.staged != nil }),
            !repository.changes.contains(where: \.isConflicted),
            !amend || !repository.isUnborn
        else {
            throw RepositoryCommitError.unavailable
        }
        var arguments = [
            "-C", repository.rootURL.path,
            "commit", "--quiet"
        ]
        if amend {
            arguments.append("--amend")
        }
        arguments += ["--message", subject]
        if !body.isEmpty {
            arguments += ["--message", body]
        }
        let result = try runGit(arguments)
        guard result.status == 0 else {
            throw RepositoryCommitError.gitFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func revertCommitSynchronously(
        _ commit: RepositoryHistory.Commit,
        mainlineParent: Int?,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let currentRepository = try inspectSynchronously(at: repository.rootURL)
        guard currentRepository.changes.isEmpty else {
            throw RepositoryRevertError.dirtyRepository
        }
        guard case .branch = currentRepository.head, !currentRepository.isUnborn else {
            throw RepositoryRevertError.detachedHead
        }
        let mainlineArguments: [String]
        if commit.parentIDs.count > 1 {
            guard let mainlineParent else {
                throw RepositoryRevertError.mainlineRequired
            }
            guard (1...commit.parentIDs.count).contains(mainlineParent) else {
                throw RepositoryRevertError.invalidMainline
            }
            mainlineArguments = ["--mainline", String(mainlineParent)]
        } else {
            guard mainlineParent == nil else {
                throw RepositoryRevertError.invalidMainline
            }
            mainlineArguments = []
        }

        let ancestry = try runGit([
            "-C", repository.rootURL.path,
            "merge-base", "--is-ancestor", commit.id, "HEAD"
        ])
        guard ancestry.status == 0 else {
            if ancestry.status == 1 {
                throw RepositoryRevertError.notOnCurrentBranch
            }
            throw RepositoryRevertError.gitFailed(ancestry.standardError)
        }
        let originalHead = try runGit([
            "-C", repository.rootURL.path,
            "rev-parse", "--verify", "HEAD"
        ])
        guard originalHead.status == 0 else {
            throw RepositoryRevertError.gitFailed(originalHead.standardError)
        }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "revert", "--no-edit",
        ] + mainlineArguments + [commit.id])
        guard result.status == 0 else {
            _ = try runGit([
                "-C", repository.rootURL.path,
                "revert", "--abort"
            ])
            let restoredRepository = try? inspectSynchronously(at: repository.rootURL)
            let restoredHead = try? runGit([
                "-C", repository.rootURL.path,
                "rev-parse", "--verify", "HEAD"
            ])
            guard
                restoredRepository?.changes.isEmpty == true,
                restoredHead?.status == 0,
                restoredHead?.standardOutput == originalHead.standardOutput
            else {
                throw RepositoryRevertError.recoveryFailed(result.standardError)
            }
            throw RepositoryRevertError.gitFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func resetCurrentBranchSynchronously(
        to commit: RepositoryHistory.Commit,
        mode: RepositoryResetMode,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let currentRepository = try inspectSynchronously(at: repository.rootURL)
        guard currentRepository.changes.isEmpty else {
            throw RepositoryResetError.dirtyRepository
        }
        guard case .branch = currentRepository.head, !currentRepository.isUnborn else {
            throw RepositoryResetError.detachedHead
        }

        let originalHead = try runGit([
            "-C", repository.rootURL.path,
            "rev-parse", "--verify", "HEAD"
        ])
        guard originalHead.status == 0 else {
            throw RepositoryResetError.gitFailed(originalHead.standardError)
        }
        guard line(from: originalHead.standardOutput) != commit.id else {
            throw RepositoryResetError.alreadyAtCommit
        }

        let ancestry = try runGit([
            "-C", repository.rootURL.path,
            "merge-base", "--is-ancestor", commit.id, "HEAD"
        ])
        guard ancestry.status == 0 else {
            if ancestry.status == 1 {
                throw RepositoryResetError.notOnCurrentBranch
            }
            throw RepositoryResetError.gitFailed(ancestry.standardError)
        }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "reset", mode.gitArgument, commit.id
        ])
        guard result.status == 0 else {
            _ = try? runGit([
                "-C", repository.rootURL.path,
                "reset", mode.gitArgument, line(from: originalHead.standardOutput)
            ])
            let restoredRepository = try? inspectSynchronously(at: repository.rootURL)
            let restoredHead = try? runGit([
                "-C", repository.rootURL.path,
                "rev-parse", "--verify", "HEAD"
            ])
            guard
                restoredRepository?.changes.isEmpty == true,
                restoredHead?.status == 0,
                restoredHead?.standardOutput == originalHead.standardOutput
            else {
                throw RepositoryResetError.recoveryFailed(result.standardError)
            }
            throw RepositoryResetError.gitFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func headCommitMessageSynchronously(
        in repository: RepositorySummary
    ) throws -> RepositoryCommitMessage {
        guard !repository.isUnborn else {
            return .init(subject: "", body: "")
        }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "log", "-1", "--no-show-signature", "--format=%B", "HEAD", "--"
        ])
        guard result.status == 0 else {
            throw RepositoryInspectionError.unreadableHistory(result.standardError)
        }

        let message = text(from: result.standardOutput)
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
        let subject = lines.first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = lines.dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(subject: subject, body: body)
    }

    private static func divergenceSynchronously(
        from branch: String,
        in repository: RepositorySummary
    ) throws -> RepositoryBranchDivergence {
        let result = try runGit([
            "-C", repository.rootURL.path,
            "rev-list", "--left-right", "--count",
            "HEAD...refs/heads/\(branch)", "--"
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.unreadable(result.standardError)
        }

        let counts = line(from: result.standardOutput)
            .split { $0 == "\t" || $0 == " " }
        guard
            counts.count == 2,
            let uniqueToCurrent = Int(counts[0]),
            let uniqueToOther = Int(counts[1])
        else {
            throw RepositoryInspectionError.invalidGitOutput
        }
        return .init(uniqueToCurrent: uniqueToCurrent, uniqueToOther: uniqueToOther)
    }

    private static func localBranchesSynchronously(
        in repository: RepositorySummary
    ) throws -> [String] {
        let result = try runGit([
            "-C", repository.rootURL.path,
            "for-each-ref", "--format=%(refname:short)", "refs/heads"
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.unreadable(result.standardError)
        }

        var branches = text(from: result.standardOutput)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        if case .branch(let currentBranch) = repository.head,
           !branches.contains(currentBranch) {
            branches.append(currentBranch)
        }
        return branches.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private static func localBranchWorktreesSynchronously(
        in repository: RepositorySummary
    ) throws -> [String: URL] {
        let result = try runGit([
            "-C", repository.rootURL.path,
            "worktree", "list", "--porcelain", "-z"
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.unreadable(result.standardError)
        }

        var worktrees: [String: URL] = [:]
        var worktreeURL: URL?
        var branch: String?
        var isBare = false
        var isPrunable = false

        func recordWorktree() {
            guard let worktreeURL, let branch, !isBare, !isPrunable else { return }
            worktrees[branch] = worktreeURL
        }

        for data in result.standardOutput.split(separator: 0) {
            let field = String(decoding: data, as: UTF8.self)
            if field.hasPrefix("worktree ") {
                recordWorktree()
                worktreeURL = URL(
                    filePath: String(field.dropFirst("worktree ".count)),
                    directoryHint: .isDirectory
                ).standardizedFileURL
                branch = nil
                isBare = false
                isPrunable = false
            } else if field.hasPrefix("branch refs/heads/") {
                branch = String(field.dropFirst("branch refs/heads/".count))
            } else if field == "bare" {
                isBare = true
            } else if field.hasPrefix("prunable") {
                isPrunable = true
            }
        }
        recordWorktree()
        return worktrees
    }

    private static func remotesSynchronously(
        in repository: RepositorySummary
    ) throws -> [RepositoryRemote] {
        let namesResult = try runGit([
            "-C", repository.rootURL.path,
            "remote"
        ])
        guard namesResult.status == 0 else {
            throw RepositoryRemoteError.unreadable(namesResult.standardError)
        }

        let names = text(from: namesResult.standardOutput)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        return try names.map { name in
            let fetchResult = try runGit([
                "-C", repository.rootURL.path,
                "remote", "get-url", name
            ])
            let pushResult = try runGit([
                "-C", repository.rootURL.path,
                "remote", "get-url", "--push", name
            ])
            guard fetchResult.status == 0, pushResult.status == 0 else {
                throw RepositoryRemoteError.unreadable(
                    fetchResult.status == 0
                        ? pushResult.standardError
                        : fetchResult.standardError
                )
            }
            return RepositoryRemote(
                name: name,
                fetchURL: line(from: fetchResult.standardOutput),
                pushURL: line(from: pushResult.standardOutput)
            )
        }
    }

    private static func testRemoteConnectionSynchronously(
        named name: String,
        in repository: RepositorySummary,
        cancellation: GitProcessCancellation
    ) throws {
        guard try remotesSynchronously(in: repository).contains(where: { $0.name == name }) else {
            throw RepositoryRemoteError.unavailable
        }
        let result = try runGit([
            "-C", repository.rootURL.path,
            "ls-remote", "--quiet", name, "HEAD"
        ], cancellation: cancellation)
        if cancellation.isCancelled {
            throw CancellationError()
        }
        guard result.status == 0 else {
            throw RepositoryRemoteError.connectionFailed(result.standardError)
        }
    }

    private static func updateRemoteSynchronously(
        named name: String,
        renamingTo newName: String,
        fetchURL: String,
        pushURL: String,
        in repository: RepositorySummary
    ) throws -> [RepositoryRemote] {
        let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fetchURL = fetchURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let pushURL = pushURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !newName.isEmpty, !fetchURL.isEmpty, !pushURL.isEmpty else {
            throw RepositoryRemoteError.invalidInput
        }
        guard let currentRemote = try remotesSynchronously(in: repository)
            .first(where: { $0.name == name })
        else {
            throw RepositoryRemoteError.unavailable
        }

        if newName != name {
            let renameResult = try runGit([
                "-C", repository.rootURL.path,
                "remote", "rename", name, newName
            ])
            guard renameResult.status == 0 else {
                throw RepositoryRemoteError.updateFailed(renameResult.standardError)
            }
        }

        let fetchResult = try runGit([
            "-C", repository.rootURL.path,
            "remote", "set-url", newName, fetchURL
        ])
        guard fetchResult.status == 0 else {
            if newName != name {
                _ = try? runGit([
                    "-C", repository.rootURL.path,
                    "remote", "rename", newName, name
                ])
            }
            throw RepositoryRemoteError.updateFailed(fetchResult.standardError)
        }

        let pushResult = try runGit([
            "-C", repository.rootURL.path,
            "remote", "set-url", "--push", newName, pushURL
        ])
        guard pushResult.status == 0 else {
            _ = try? runGit([
                "-C", repository.rootURL.path,
                "remote", "set-url", newName, currentRemote.fetchURL
            ])
            if newName != name {
                _ = try? runGit([
                    "-C", repository.rootURL.path,
                    "remote", "rename", newName, name
                ])
            }
            throw RepositoryRemoteError.updateFailed(pushResult.standardError)
        }

        return try remotesSynchronously(in: repository)
    }

    private static func removeRemoteSynchronously(
        named name: String,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        guard try remotesSynchronously(in: repository).contains(where: { $0.name == name }) else {
            throw RepositoryRemoteError.unavailable
        }
        let result = try runGit([
            "-C", repository.rootURL.path,
            "remote", "remove", name
        ])
        guard result.status == 0 else {
            throw RepositoryRemoteError.removeFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func switchBranchSynchronously(
        to branch: String,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let branches = try localBranchesSynchronously(in: repository)
        guard branches.contains(branch) else {
            throw RepositoryBranchError.unavailable
        }
        if case .branch(branch) = repository.head {
            return repository
        }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "switch", "--quiet", "--", branch
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.switchFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func createBranchSynchronously(
        named branch: String,
        at startPoint: String?,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        guard !branch.isEmpty else {
            throw RepositoryBranchError.creationFailed("Enter a branch name.")
        }

        var arguments = [
            "-C", repository.rootURL.path,
            "switch", "--quiet", "--create=\(branch)"
        ]
        if let startPoint { arguments.append(startPoint) }
        let result = try runGit(arguments)
        guard result.status == 0 else {
            throw RepositoryBranchError.creationFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func mergeBranchSynchronously(
        _ branch: String,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let branches = try localBranchesSynchronously(in: repository)
        guard branches.contains(branch) else {
            throw RepositoryBranchError.unavailable
        }
        guard
            case .branch(let currentBranch) = repository.head,
            !repository.isUnborn,
            currentBranch != branch
        else {
            throw RepositoryBranchError.mergeUnavailable
        }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "merge", "--quiet", "--ff-only", "--", branch
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.mergeFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func fastForwardBranchSynchronously(
        _ branch: String,
        toCurrentIn repository: RepositorySummary
    ) throws -> RepositorySummary {
        let currentBranch = try fastForwardOutCurrentBranch(of: branch, in: repository)

        let head = try runGit([
            "-C", repository.rootURL.path,
            "rev-parse", "--verify", "HEAD"
        ])
        guard head.status == 0 else {
            throw RepositoryBranchError.fastForwardOutFailed(head.standardError)
        }
        let headID = line(from: head.standardOutput)

        // 목적지를 refs/heads/로 완전 수식하면 fetch가 기존 ref를 삭제 후 갱신하려다
        // 실패할 수 있어, 비수식 branch 이름으로 fast-forward 갱신만 요청한다.
        let fetch = try runGit([
            "-C", repository.rootURL.path,
            "fetch", ".", "\(currentBranch):\(branch)"
        ])
        guard fetch.status == 0 else {
            throw RepositoryBranchError.fastForwardOutFailed(fetch.standardError)
        }

        // fetch는 non-fast-forward 거부를 종료 코드 0으로 보고하므로 결과 ref를 직접 확인한다.
        let updated = try runGit([
            "-C", repository.rootURL.path,
            "rev-parse", "--verify", "refs/heads/\(branch)"
        ])
        guard updated.status == 0, line(from: updated.standardOutput) == headID else {
            throw RepositoryBranchError.fastForwardOutFailed(fetch.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func fastForwardBranchSynchronously(
        _ branch: String,
        inWorktreeAt worktreeURL: URL,
        toCurrentIn repository: RepositorySummary
    ) throws -> RepositorySummary {
        let currentBranch = try fastForwardOutCurrentBranch(of: branch, in: repository)

        let worktrees = try localBranchWorktreesSynchronously(in: repository)
        guard worktrees[branch].map({ sameFileLocation($0, worktreeURL) }) == true else {
            throw RepositoryBranchError.fastForwardOutUnavailable
        }

        let result = try runGit([
            "-C", worktreeURL.path,
            "merge", "--quiet", "--ff-only", "--", currentBranch
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.fastForwardOutFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func mergePredictionSynchronously(
        into branch: String,
        in repository: RepositorySummary
    ) throws -> RepositoryMergePrediction {
        guard case .branch(let currentBranch) = repository.head else {
            throw RepositoryBranchError.mergeOutUnavailable
        }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "merge-tree", "--write-tree", "-z", "--name-only",
            branch, currentBranch
        ])
        guard result.status == 0 || result.status == 1 else {
            throw RepositoryBranchError.mergeOutFailed(result.standardError)
        }

        let fields = result.standardOutput
            .split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        guard let treeID = fields.first, !treeID.isEmpty else {
            throw RepositoryInspectionError.invalidGitOutput
        }
        var conflictedPaths: [String] = []
        for field in fields.dropFirst() {
            guard !field.isEmpty else { break }
            conflictedPaths.append(field)
        }
        return .init(
            isClean: result.status == 0,
            conflictedPaths: conflictedPaths,
            treeID: treeID
        )
    }

    private static func createMergeCommitSynchronously(
        on branch: String,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let currentRepository = try inspectSynchronously(at: repository.rootURL)
        let branches = try localBranchesSynchronously(in: currentRepository)
        guard branches.contains(branch) else {
            throw RepositoryBranchError.unavailable
        }
        guard
            case .branch(let currentBranch) = currentRepository.head,
            !currentRepository.isUnborn,
            currentBranch != branch
        else {
            throw RepositoryBranchError.mergeOutUnavailable
        }

        // ref 이동은 Git의 Worktree 체크아웃 보호를 우회하므로 직접 재확인한다.
        let worktrees = try localBranchWorktreesSynchronously(in: currentRepository)
        guard worktrees[branch] == nil else {
            throw RepositoryBranchError.mergeOutCheckedOut
        }

        for revisions in [["HEAD", branch], [branch, "HEAD"]] {
            let ancestry = try runGit([
                "-C", repository.rootURL.path,
                "merge-base", "--is-ancestor"
            ] + revisions)
            if ancestry.status == 0 {
                throw RepositoryBranchError.mergeCommitRequiresDivergence
            }
            guard ancestry.status == 1 else {
                throw RepositoryBranchError.mergeOutFailed(ancestry.standardError)
            }
        }

        let targetHead = try runGit([
            "-C", repository.rootURL.path,
            "rev-parse", "--verify", "refs/heads/\(branch)"
        ])
        guard targetHead.status == 0 else {
            throw RepositoryBranchError.mergeOutFailed(targetHead.standardError)
        }
        let targetID = line(from: targetHead.standardOutput)

        let currentHead = try runGit([
            "-C", repository.rootURL.path,
            "rev-parse", "--verify", "HEAD"
        ])
        guard currentHead.status == 0 else {
            throw RepositoryBranchError.mergeOutFailed(currentHead.standardError)
        }
        let currentID = line(from: currentHead.standardOutput)

        let prediction = try mergePredictionSynchronously(into: branch, in: currentRepository)
        guard prediction.isClean else {
            throw RepositoryBranchError.mergeOutConflicts(prediction.conflictedPaths)
        }

        // commit-tree는 commit.gpgsign을 스스로 읽지 않을 수 있어 설정을 확인해 서명을 명시한다.
        let signingConfig = try runGit([
            "-C", repository.rootURL.path,
            "config", "--type=bool", "--default=false", "commit.gpgsign"
        ])
        let shouldSign = signingConfig.status == 0
            && line(from: signingConfig.standardOutput) == "true"

        var commitArguments = [
            "-C", repository.rootURL.path,
            "commit-tree", prediction.treeID,
            "-p", targetID, "-p", currentID,
            "-m", "Merge branch '\(currentBranch)' into \(branch)"
        ]
        if shouldSign {
            commitArguments.append("-S")
        }
        let commit = try runGit(commitArguments)
        guard commit.status == 0 else {
            throw RepositoryBranchError.mergeOutFailed(commit.standardError)
        }
        let mergeCommitID = line(from: commit.standardOutput)

        let update = try runGit([
            "-C", repository.rootURL.path,
            "update-ref",
            "-m", "merge \(currentBranch): merge commit created without checkout",
            "refs/heads/\(branch)", mergeCommitID, targetID
        ])
        guard update.status == 0 else {
            throw RepositoryBranchError.mergeOutFailed(update.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func mergeCurrentBranchSynchronously(
        into branch: String,
        inWorktreeAt worktreeURL: URL,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let currentRepository = try inspectSynchronously(at: repository.rootURL)
        guard
            case .branch(let currentBranch) = currentRepository.head,
            !currentRepository.isUnborn,
            currentBranch != branch
        else {
            throw RepositoryBranchError.mergeOutUnavailable
        }

        let worktrees = try localBranchWorktreesSynchronously(in: currentRepository)
        guard worktrees[branch].map({ sameFileLocation($0, worktreeURL) }) == true else {
            throw RepositoryBranchError.mergeOutUnavailable
        }

        let result = try runGit([
            "-C", worktreeURL.path,
            "merge", "--quiet", "--no-ff", "--no-edit", "--", currentBranch
        ])
        if result.status != 0 {
            let mergeHead = try runGit([
                "-C", worktreeURL.path,
                "rev-parse", "--quiet", "--verify", "MERGE_HEAD"
            ])
            if mergeHead.status == 0 {
                throw RepositoryBranchError.mergeInWorktreeConflicted(worktreeURL)
            }
            throw RepositoryBranchError.mergeOutFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func abortMergeSynchronously(
        inWorktreeAt worktreeURL: URL,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let result = try runGit([
            "-C", worktreeURL.path,
            "merge", "--abort"
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.mergeOutFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func addTemporaryWorktreeSynchronously(
        for branch: String,
        in repository: RepositorySummary,
        baseDirectory: URL?
    ) throws -> URL {
        let baseURL = baseDirectory
            ?? URL.applicationSupportDirectory
                .appending(path: "Gallae/Temporary Worktrees", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let safeBranch = branch.replacingOccurrences(of: "/", with: "-")
        let worktreeURL = baseURL.appending(
            path: "\(repository.name)-\(safeBranch)-\(UUID().uuidString.prefix(8))",
            directoryHint: .isDirectory
        )

        let result = try runGit([
            "-C", repository.rootURL.path,
            "worktree", "add", "--quiet", worktreeURL.path, branch
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.worktreeCreationFailed(result.standardError)
        }
        return worktreeURL
    }

    private static func deleteBranchSynchronously(
        named branch: String,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let currentRepository = try inspectSynchronously(at: repository.rootURL)
        if case .branch(branch) = currentRepository.head {
            throw RepositoryBranchError.deletionUnavailable
        }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "branch", "--delete", "--", branch
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.deletionFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func removeWorktreeSynchronously(
        at worktreeURL: URL,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let result = try runGit([
            "-C", repository.rootURL.path,
            "worktree", "remove", worktreeURL.path
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.worktreeRemovalFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func fastForwardOutCurrentBranch(
        of branch: String,
        in repository: RepositorySummary
    ) throws -> String {
        let currentRepository = try inspectSynchronously(at: repository.rootURL)
        let branches = try localBranchesSynchronously(in: currentRepository)
        guard branches.contains(branch) else {
            throw RepositoryBranchError.unavailable
        }
        guard
            case .branch(let currentBranch) = currentRepository.head,
            !currentRepository.isUnborn,
            currentBranch != branch
        else {
            throw RepositoryBranchError.fastForwardOutUnavailable
        }

        let ancestry = try runGit([
            "-C", repository.rootURL.path,
            "merge-base", "--is-ancestor", branch, "HEAD"
        ])
        if ancestry.status == 1 {
            throw RepositoryBranchError.fastForwardOutRequiresAncestor
        }
        guard ancestry.status == 0 else {
            throw RepositoryBranchError.fastForwardOutFailed(ancestry.standardError)
        }
        return currentBranch
    }

    private static func mergeBranchCreatingCommitSynchronously(
        _ branch: String,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let currentRepository = try inspectSynchronously(at: repository.rootURL)
        let branches = try localBranchesSynchronously(in: currentRepository)
        guard branches.contains(branch) else {
            throw RepositoryBranchError.unavailable
        }
        guard
            case .branch(let currentBranch) = currentRepository.head,
            !currentRepository.isUnborn,
            currentBranch != branch
        else {
            throw RepositoryBranchError.mergeUnavailable
        }
        guard currentRepository.changes.isEmpty else {
            throw RepositoryBranchError.mergeCommitRequiresCleanRepository
        }

        for revisions in [["HEAD", branch], [branch, "HEAD"]] {
            let ancestry = try runGit([
                "-C", repository.rootURL.path,
                "merge-base", "--is-ancestor",
            ] + revisions)
            if ancestry.status == 0 {
                throw RepositoryBranchError.mergeCommitRequiresDivergence
            }
            guard ancestry.status == 1 else {
                throw RepositoryBranchError.mergeCommitFailed(ancestry.standardError)
            }
        }

        let originalHead = try runGit([
            "-C", repository.rootURL.path,
            "rev-parse", "--verify", "HEAD"
        ])
        guard originalHead.status == 0 else {
            throw RepositoryBranchError.mergeCommitFailed(originalHead.standardError)
        }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "merge", "--quiet", "--no-ff", "--no-edit", "--", branch
        ])
        guard result.status == 0 else {
            let abort = try? runGit([
                "-C", repository.rootURL.path,
                "merge", "--abort"
            ])
            if abort?.status != 0 {
                _ = try? runGit([
                    "-C", repository.rootURL.path,
                    "reset", "--merge", line(from: originalHead.standardOutput)
                ])
            }
            let restoredRepository = try? inspectSynchronously(at: repository.rootURL)
            let restoredHead = try? runGit([
                "-C", repository.rootURL.path,
                "rev-parse", "--verify", "HEAD"
            ])
            guard
                restoredRepository?.changes.isEmpty == true,
                restoredHead?.status == 0,
                restoredHead?.standardOutput == originalHead.standardOutput
            else {
                throw RepositoryBranchError.mergeCommitRecoveryFailed(result.standardError)
            }
            throw RepositoryBranchError.mergeCommitFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func rebaseCurrentBranchSynchronously(
        onto branch: String,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let currentRepository = try inspectSynchronously(at: repository.rootURL)
        let branches = try localBranchesSynchronously(in: currentRepository)
        guard branches.contains(branch) else {
            throw RepositoryBranchError.unavailable
        }
        guard
            case .branch(let currentBranch) = currentRepository.head,
            !currentRepository.isUnborn,
            currentBranch != branch
        else {
            throw RepositoryBranchError.rebaseUnavailable
        }
        guard currentRepository.changes.isEmpty else {
            throw RepositoryBranchError.rebaseRequiresCleanRepository
        }

        let originalHead = try runGit([
            "-C", repository.rootURL.path,
            "rev-parse", "--verify", "HEAD"
        ])
        guard originalHead.status == 0 else {
            throw RepositoryBranchError.rebaseFailed(originalHead.standardError)
        }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "rebase", "--quiet", "--no-update-refs", branch
        ])
        guard result.status == 0 else {
            _ = try? runGit([
                "-C", repository.rootURL.path,
                "rebase", "--abort"
            ])
            let restoredRepository = try? inspectSynchronously(at: repository.rootURL)
            let restoredHead = try? runGit([
                "-C", repository.rootURL.path,
                "rev-parse", "--verify", "HEAD"
            ])
            guard
                restoredRepository?.head == .branch(currentBranch),
                restoredRepository?.changes.isEmpty == true,
                restoredHead?.status == 0,
                restoredHead?.standardOutput == originalHead.standardOutput
            else {
                throw RepositoryBranchError.rebaseRecoveryFailed(result.standardError)
            }
            throw RepositoryBranchError.rebaseFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func fetchSynchronously(
        from selectedRemote: String?,
        pruning: Bool,
        usingConfiguredDefaultRemote: Bool,
        in repository: RepositorySummary,
        cancellation: GitProcessCancellation
    ) throws -> RepositorySummary {
        let remotesResult = try runGit([
            "-C", repository.rootURL.path,
            "remote"
        ])
        guard remotesResult.status == 0 else {
            throw RepositoryFetchError.failed(remotesResult.standardError)
        }
        let remotes = text(from: remotesResult.standardOutput)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .sorted()
        guard !remotes.isEmpty else {
            throw RepositoryFetchError.noRemote
        }
        var arguments = ["-C", repository.rootURL.path]
            + (pruning ? ["fetch", "--quiet", "--prune"] : ["fetch", "--quiet"])
        if !usingConfiguredDefaultRemote {
            let remote: String
            if let selectedRemote {
                guard remotes.contains(selectedRemote) else {
                    throw RepositoryFetchError.failed("The selected remote is no longer configured.")
                }
                remote = selectedRemote
            } else {
                guard remotes.count == 1, let onlyRemote = remotes.first else {
                    throw RepositoryFetchError.remoteSelectionRequired(remotes)
                }
                remote = onlyRemote
            }
            arguments += ["--", remote]
        }

        let result = try runGit(
            arguments,
            cancellation: cancellation
        )
        if cancellation.isCancelled {
            throw CancellationError()
        }
        guard result.status == 0 else {
            throw RepositoryFetchError.failed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func pullSynchronously(
        in repository: RepositorySummary,
        cancellation: GitProcessCancellation
    ) throws -> RepositorySummary {
        guard repository.upstream != nil else {
            throw RepositoryPullError.noUpstream
        }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "pull", "--quiet", "--ff-only"
        ], cancellation: cancellation)
        if cancellation.isCancelled {
            throw CancellationError()
        }
        guard result.status == 0 else {
            throw RepositoryPullError.failed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func pushSynchronously(
        in repository: RepositorySummary,
        cancellation: GitProcessCancellation
    ) throws -> RepositorySummary {
        if repository.upstream != nil {
            let result = try runGit([
                "-C", repository.rootURL.path,
                "push", "--quiet"
            ], cancellation: cancellation)
            if cancellation.isCancelled {
                throw CancellationError()
            }
            guard result.status == 0 else {
                throw RepositoryPushError.failed(result.standardError)
            }
            return try inspectSynchronously(at: repository.rootURL)
        }

        let remotesResult = try runGit([
            "-C", repository.rootURL.path,
            "remote"
        ], cancellation: cancellation)
        if cancellation.isCancelled {
            throw CancellationError()
        }
        guard remotesResult.status == 0 else {
            throw RepositoryPushError.failed(remotesResult.standardError)
        }
        let remotes = text(from: remotesResult.standardOutput)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .sorted()
        guard !remotes.isEmpty else {
            throw RepositoryPushError.noRemote
        }
        guard remotes.count == 1, let remote = remotes.first else {
            throw RepositoryPushError.remoteSelectionRequired(remotes)
        }
        return try publishSynchronously(
            to: remote,
            in: repository,
            cancellation: cancellation
        )
    }

    private static func addRemoteAndPublishSynchronously(
        named name: String,
        url: String,
        in repository: RepositorySummary,
        cancellation: GitProcessCancellation
    ) throws -> RepositorySummary {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("-"), !url.isEmpty else {
            throw RepositoryRemoteSetupError.invalidInput
        }

        let addResult = try runGit([
            "-C", repository.rootURL.path,
            "remote", "add", name, url
        ], cancellation: cancellation)
        if cancellation.isCancelled {
            throw CancellationError()
        }
        guard addResult.status == 0 else {
            throw RepositoryRemoteSetupError.addFailed(addResult.standardError)
        }

        do {
            return try publishSynchronously(
                to: name,
                in: repository,
                cancellation: cancellation
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RepositoryRemoteSetupError.publishFailed(
                remote: name,
                message: error.localizedDescription
            )
        }
    }

    private static func publishSynchronously(
        to remote: String,
        in repository: RepositorySummary,
        cancellation: GitProcessCancellation
    ) throws -> RepositorySummary {
        guard case .branch(let branch) = repository.head, !repository.isUnborn else {
            throw RepositoryPushError.publishUnavailable
        }
        let reference = "refs/heads/\(branch)"
        let result = try runGit([
            "-C", repository.rootURL.path,
            "push", "--quiet", "--set-upstream", "--",
            remote, "\(reference):\(reference)"
        ], cancellation: cancellation)
        if cancellation.isCancelled {
            throw CancellationError()
        }
        guard result.status == 0 else {
            throw RepositoryPushError.failed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func inspectSynchronously(at selectedURL: URL) throws -> RepositorySummary {
        let rootURL = try workingTreeRoot(at: selectedURL)

        let statusResult = try runGit([
            "-C", rootURL.path,
            "status", "--porcelain=v2", "--branch", "--null", "--untracked-files=all", "--renames"
        ])
        guard statusResult.status == 0 else {
            throw RepositoryInspectionError.unreadableStatus(statusResult.standardError)
        }

        let operationKind = try operationKindSynchronously(in: rootURL)
        return try parseStatus(
            statusResult.standardOutput,
            rootURL: rootURL,
            operationKind: operationKind
        )
    }

    private static func operationKindSynchronously(
        in rootURL: URL
    ) throws -> RepositorySummary.Operation.Kind? {
        let result = try runGit([
            "-C", rootURL.path,
            "rev-parse", "--path-format=absolute",
            "--git-path", "MERGE_HEAD",
            "--git-path", "rebase-merge",
            "--git-path", "rebase-apply"
        ])
        let paths = text(from: result.standardOutput)
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
        guard result.status == 0, paths.count == 3 else {
            throw RepositoryInspectionError.invalidGitOutput
        }
        if paths.dropFirst().contains(where: FileManager.default.fileExists(atPath:)) {
            return .rebase
        }
        return FileManager.default.fileExists(atPath: paths[0]) ? .merge : nil
    }

    static func workingTreeRoot(at selectedURL: URL) throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: gitURL.path) else {
            throw RepositoryInspectionError.gitUnavailable
        }

        let rootResult = try runGit([
            "-C", selectedURL.path,
            "rev-parse", "--is-bare-repository", "--show-toplevel"
        ])
        let lines = text(from: rootResult.standardOutput)
            .split(whereSeparator: \Character.isNewline)

        switch lines.first {
        case "true":
            throw RepositoryInspectionError.bareRepository
        case "false":
            break
        default:
            guard rootResult.status == 0 else {
                throw RepositoryInspectionError.notWorkingTree(rootResult.standardError)
            }
            throw RepositoryInspectionError.invalidGitOutput
        }
        guard rootResult.status == 0 else {
            throw RepositoryInspectionError.notWorkingTree(rootResult.standardError)
        }
        guard lines.count == 2 else {
            throw RepositoryInspectionError.invalidGitOutput
        }

        return URL(fileURLWithPath: String(lines[1]), isDirectory: true).standardizedFileURL
    }

    private static func activitySynchronously(
        in repository: RepositorySummary
    ) throws -> RepositoryActivity {
        guard !repository.isUnborn else {
            return .init(commitCount: 0, recentCommits: [])
        }

        let countResult = try runGit([
            "-C", repository.rootURL.path,
            "rev-list", "--count", "HEAD"
        ])
        guard
            countResult.status == 0,
            let commitCount = Int(line(from: countResult.standardOutput))
        else {
            throw RepositoryInspectionError.unreadableHistory(countResult.standardError)
        }

        let logResult = try runGit([
            "-C", repository.rootURL.path,
            "log", "-3", "-z", "--format=%H%x00%ct%x00%s"
        ])
        guard logResult.status == 0 else {
            throw RepositoryInspectionError.unreadableHistory(logResult.standardError)
        }

        var fields = logResult.standardOutput.split(
            separator: 0,
            omittingEmptySubsequences: false
        )
        if fields.last?.isEmpty == true {
            fields.removeLast()
        }
        guard fields.count.isMultiple(of: 3) else {
            throw RepositoryInspectionError.invalidGitOutput
        }

        var recentCommits: [RepositoryActivity.Commit] = []
        recentCommits.reserveCapacity(fields.count / 3)
        for index in stride(from: 0, to: fields.count, by: 3) {
            let id = String(decoding: fields[index], as: UTF8.self)
            guard let timestamp = TimeInterval(String(decoding: fields[index + 1], as: UTF8.self)) else {
                throw RepositoryInspectionError.invalidGitOutput
            }
            recentCommits.append(.init(
                id: id,
                subject: String(decoding: fields[index + 2], as: UTF8.self),
                committedAt: Date(timeIntervalSince1970: timestamp)
            ))
        }

        return .init(commitCount: commitCount, recentCommits: recentCommits)
    }

    private static func historySynchronously(
        in repository: RepositorySummary
    ) throws -> RepositoryHistory {
        guard !repository.isUnborn else { return .init(commits: []) }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "log", "-\(maximumHistoryCommits)", "--topo-order", "-z", "--no-show-signature",
            "--format=%H%x00%P%x00%an%x00%ae%x00%ct%x00%s%x00%b",
            "--branches", "--remotes", "--tags", "HEAD", "--"
        ])
        guard result.status == 0 else {
            throw RepositoryHistoryError.unreadable(result.standardError)
        }

        let referencesResult = try runGit([
            "-C", repository.rootURL.path,
            "show-ref", "--head", "--dereference"
        ])
        guard referencesResult.status == 0
                || (referencesResult.status == 1 && referencesResult.standardOutput.isEmpty)
        else {
            throw RepositoryHistoryError.unreadable(referencesResult.standardError)
        }
        let referenceSnapshot = historyReferences(referencesResult.standardOutput)

        var fields = result.standardOutput.split(
            separator: 0,
            omittingEmptySubsequences: false
        )
        if fields.last?.isEmpty == true {
            fields.removeLast()
        }
        guard fields.count.isMultiple(of: 7) else {
            throw RepositoryHistoryError.invalidOutput
        }

        var commits: [RepositoryHistory.Commit] = []
        commits.reserveCapacity(fields.count / 7)
        for index in stride(from: 0, to: fields.count, by: 7) {
            guard let timestamp = TimeInterval(String(decoding: fields[index + 4], as: UTF8.self)) else {
                throw RepositoryHistoryError.invalidOutput
            }
            commits.append(.init(
                id: String(decoding: fields[index], as: UTF8.self),
                parentIDs: String(decoding: fields[index + 1], as: UTF8.self)
                    .split(separator: " ")
                    .map(String.init),
                authorName: String(decoding: fields[index + 2], as: UTF8.self),
                authorEmail: String(decoding: fields[index + 3], as: UTF8.self),
                committedAt: Date(timeIntervalSince1970: timestamp),
                subject: String(decoding: fields[index + 5], as: UTF8.self),
                body: String(decoding: fields[index + 6], as: UTF8.self)
                    .trimmingCharacters(in: .newlines),
                references: referenceSnapshot.references[
                    String(decoding: fields[index], as: UTF8.self)
                ] ?? []
            ))
        }
        return .init(commits: commits, headCommitID: referenceSnapshot.headCommitID)
    }

    private static func interactiveRebasePlanSynchronously(
        startingAt commit: RepositoryHistory.Commit,
        in repository: RepositorySummary
    ) throws -> RepositoryInteractiveRebasePlan {
        let currentRepository = try inspectSynchronously(at: repository.rootURL)
        guard
            case .branch = currentRepository.head,
            !currentRepository.isUnborn,
            currentRepository.operation == nil
        else {
            throw RepositoryInteractiveRebasePlanError.unavailable
        }

        let headResult = try runGit([
            "-C", repository.rootURL.path,
            "rev-parse", "--verify", "HEAD"
        ])
        guard headResult.status == 0 else {
            throw RepositoryInteractiveRebasePlanError.unreadable(headResult.standardError)
        }
        let headID = line(from: headResult.standardOutput)

        let ancestryResult = try runGit([
            "-C", repository.rootURL.path,
            "merge-base", "--is-ancestor", commit.id, headID
        ])
        guard ancestryResult.status == 0 else {
            if ancestryResult.status == 1 {
                throw RepositoryInteractiveRebasePlanError.notOnCurrentBranch
            }
            throw RepositoryInteractiveRebasePlanError.unreadable(ancestryResult.standardError)
        }

        let revision = commit.parentIDs.first.map { "\($0)..\(headID)" } ?? headID
        let result = try runGit([
            "-C", repository.rootURL.path,
            "log", "--reverse", "--topo-order", "-z", "--no-show-signature", "--no-merges",
            "--format=%H%x00%s", revision, "--"
        ])
        guard result.status == 0 else {
            throw RepositoryInteractiveRebasePlanError.unreadable(result.standardError)
        }

        var fields = result.standardOutput.split(
            separator: 0,
            omittingEmptySubsequences: false
        )
        if fields.last?.isEmpty == true { fields.removeLast() }
        guard fields.count.isMultiple(of: 2) else {
            throw RepositoryInteractiveRebasePlanError.invalidOutput
        }

        return .init(steps: stride(from: 0, to: fields.count, by: 2).map { index in
            .init(
                id: String(decoding: fields[index], as: UTF8.self),
                subject: String(decoding: fields[index + 1], as: UTF8.self)
            )
        })
    }

    private static func executeInteractiveRebaseSynchronously(
        _ plan: RepositoryInteractiveRebasePlan,
        rewordMessages: [String: String],
        startingAt commit: RepositoryHistory.Commit,
        in repository: RepositorySummary,
        cancellation: GitProcessCancellation
    ) throws -> RepositorySummary {
        let currentRepository = try inspectSynchronously(at: repository.rootURL)
        guard
            case .branch(let currentBranch) = currentRepository.head,
            !currentRepository.isUnborn,
            currentRepository.operation == nil
        else {
            throw RepositoryInteractiveRebasePlanError.unavailable
        }
        guard currentRepository.changes.isEmpty else {
            throw RepositoryInteractiveRebasePlanError.requiresCleanRepository
        }
        guard plan.validationError == nil else {
            throw RepositoryInteractiveRebasePlanError.invalidPlan
        }

        let currentPlan = try interactiveRebasePlanSynchronously(
            startingAt: commit,
            in: currentRepository
        )
        guard
            plan.steps.count == currentPlan.steps.count,
            Set(plan.steps.map(\.id)) == Set(currentPlan.steps.map(\.id))
        else {
            throw RepositoryInteractiveRebasePlanError.invalidPlan
        }
        for step in plan.steps where step.action == .reword {
            guard
                let message = rewordMessages[step.id],
                !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw RepositoryInteractiveRebasePlanError.missingRewordMessage(stepID: step.id)
            }
        }

        let originalHeadResult = try runGit([
            "-C", repository.rootURL.path,
            "rev-parse", "--verify", "HEAD"
        ])
        guard originalHeadResult.status == 0 else {
            throw RepositoryInteractiveRebasePlanError.executionFailed(
                originalHeadResult.standardError
            )
        }
        let originalHead = line(from: originalHeadResult.standardOutput)

        let parentResult = try runGit([
            "-C", repository.rootURL.path,
            "rev-list", "--parents", "-n", "1", commit.id
        ])
        let parentFields = text(from: parentResult.standardOutput).split(whereSeparator: \.isWhitespace)
        guard parentResult.status == 0, parentFields.first.map(String.init) == commit.id else {
            throw RepositoryInteractiveRebasePlanError.executionFailed(parentResult.standardError)
        }

        let todo = plan.steps.flatMap { step -> [String] in
            if step.action == .reword, let message = rewordMessages[step.id] {
                let encodedMessage = Data(message.utf8).base64EncodedString()
                return [
                    "pick \(step.id)",
                    "exec /usr/bin/printf '%s' '\(encodedMessage)' | /usr/bin/base64 -D | /usr/bin/git commit --amend --file=-",
                ]
            }
            return ["\(step.action.rawValue) \(step.id)"]
        }.joined(separator: "\n") + "\n"

        let todoDirectory = FileManager.default.temporaryDirectory
            .appending(path: "Gallae-Rebase-\(UUID().uuidString)", directoryHint: .isDirectory)
        let todoURL = todoDirectory.appending(path: "todo")
        try FileManager.default.createDirectory(at: todoDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: todoDirectory) }
        try Data(todo.utf8).write(to: todoURL)

        var arguments = [
            "-C", repository.rootURL.path,
            "-c", "core.editor=true",
            "rebase", "--interactive", "--no-update-refs",
        ]
        if parentFields.count == 1 {
            arguments.append("--root")
        } else {
            arguments.append(String(parentFields[1]))
        }

        let result = try runGit(
            arguments,
            cancellation: cancellation,
            additionalEnvironment: [
                "GIT_SEQUENCE_EDITOR": "/bin/cp \(shellQuoted(todoURL.path))"
            ]
        )
        if cancellation.isCancelled, result.status != 0 {
            _ = try? runGit([
                "-C", repository.rootURL.path,
                "rebase", "--abort"
            ])
            let restoredRepository = try? inspectSynchronously(at: repository.rootURL)
            let restoredHead = try? runGit([
                "-C", repository.rootURL.path,
                "rev-parse", "--verify", "HEAD"
            ])
            guard
                restoredRepository?.head == .branch(currentBranch),
                restoredRepository?.changes.isEmpty == true,
                restoredHead?.status == 0,
                line(from: restoredHead?.standardOutput ?? Data()) == originalHead
            else {
                throw RepositoryInteractiveRebasePlanError.recoveryFailed(result.standardError)
            }
            throw CancellationError()
        }

        let updatedRepository = try inspectSynchronously(at: repository.rootURL)
        if result.status == 0 || updatedRepository.operation?.kind == .rebase {
            return updatedRepository
        }
        throw RepositoryInteractiveRebasePlanError.executionFailed(result.standardError)
    }

    private static func stashesSynchronously(
        in repository: RepositorySummary
    ) throws -> [RepositoryStash] {
        let result = try runGit([
            "-C", repository.rootURL.path,
            "stash", "list", "-100", "-z",
            "--format=%gd%x00%H%x00%ct%x00%s"
        ])
        guard result.status == 0 else {
            throw RepositoryStashError.unreadable(result.standardError)
        }

        var fields = result.standardOutput.split(
            separator: 0,
            omittingEmptySubsequences: false
        )
        if fields.last?.isEmpty == true { fields.removeLast() }
        guard fields.count.isMultiple(of: 4) else {
            throw RepositoryStashError.invalidOutput
        }

        return try stride(from: 0, to: fields.count, by: 4).map { index in
            guard let timestamp = TimeInterval(String(decoding: fields[index + 2], as: UTF8.self)) else {
                throw RepositoryStashError.invalidOutput
            }
            return RepositoryStash(
                id: String(decoding: fields[index + 1], as: UTF8.self),
                reference: String(decoding: fields[index], as: UTF8.self),
                subject: String(decoding: fields[index + 3], as: UTF8.self),
                createdAt: Date(timeIntervalSince1970: timestamp)
            )
        }
    }

    private static func reflogSynchronously(
        in repository: RepositorySummary
    ) throws -> [RepositoryReflogEntry] {
        guard !repository.isUnborn else { return [] }

        let result = try runGit([
            "-C", repository.rootURL.path,
            "reflog", "show", "HEAD", "-100", "-z", "--date=unix",
            "--format=%H%x00%gD%x00%gn%x00%ge%x00%gs",
        ])
        guard result.status == 0 else {
            throw RepositoryReflogError.unreadable(result.standardError)
        }

        var fields = result.standardOutput.split(
            separator: 0,
            omittingEmptySubsequences: false
        )
        if fields.last?.isEmpty == true { fields.removeLast() }
        guard fields.count.isMultiple(of: 5) else {
            throw RepositoryReflogError.invalidOutput
        }

        return try stride(from: 0, to: fields.count, by: 5).map { index in
            let rawSelector = String(decoding: fields[index + 1], as: UTF8.self)
            guard
                rawSelector.hasPrefix("HEAD@{"),
                rawSelector.hasSuffix("}"),
                let timestamp = TimeInterval(rawSelector.dropFirst(6).dropLast())
            else {
                throw RepositoryReflogError.invalidOutput
            }
            return RepositoryReflogEntry(
                selector: "HEAD@{\(index / 5)}",
                commitID: String(decoding: fields[index], as: UTF8.self),
                actorName: String(decoding: fields[index + 2], as: UTF8.self),
                actorEmail: String(decoding: fields[index + 3], as: UTF8.self),
                occurredAt: Date(timeIntervalSince1970: timestamp),
                action: String(decoding: fields[index + 4], as: UTF8.self)
            )
        }
    }

    private static func createStashSynchronously(
        message: String,
        includeUntracked: Bool,
        in repository: RepositorySummary,
        cancellation: GitProcessCancellation
    ) throws -> RepositorySummary {
        var arguments = [
            "-C", repository.rootURL.path,
            "stash", "push", "--quiet"
        ]
        if includeUntracked {
            arguments.append("--include-untracked")
        }
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            arguments += ["--message", message]
        }
        arguments.append("--")

        let result = try runGit(arguments, cancellation: cancellation)
        if cancellation.isCancelled {
            throw CancellationError()
        }
        guard result.status == 0 else {
            throw RepositoryStashError.creationFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func applyStashSynchronously(
        _ stash: RepositoryStash,
        in repository: RepositorySummary,
        cancellation: GitProcessCancellation
    ) throws -> RepositorySummary {
        let result = try runGit([
            "-C", repository.rootURL.path,
            "stash", "apply", "--quiet", "--index", stash.id
        ], cancellation: cancellation)
        if cancellation.isCancelled {
            throw CancellationError()
        }
        guard result.status == 0 else {
            throw RepositoryStashError.applyFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func dropStashSynchronously(
        _ stash: RepositoryStash,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        guard let currentStash = try stashesSynchronously(in: repository)
            .first(where: { $0.id == stash.id })
        else {
            throw RepositoryStashError.deletionUnavailable
        }
        let result = try runGit([
            "-C", repository.rootURL.path,
            "stash", "drop", "--quiet", currentStash.reference
        ])
        guard result.status == 0 else {
            throw RepositoryStashError.deletionFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func historyReferences(
        _ data: Data
    ) -> (
        references: [String: [RepositoryHistory.Reference]],
        headCommitID: String?
    ) {
        var references: [String: [RepositoryHistory.Reference]] = [:]
        var headCommitID: String?

        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 1)
            guard fields.count == 2 else { continue }

            let objectID = String(fields[0])
            var refName = String(fields[1])
            let kind: RepositoryHistory.Reference.Kind

            if refName == "HEAD" {
                headCommitID = objectID
                continue
            } else if refName.hasPrefix("refs/heads/") {
                refName.removeFirst("refs/heads/".count)
                kind = .branch
            } else if refName.hasPrefix("refs/remotes/"), !refName.hasSuffix("/HEAD") {
                refName.removeFirst("refs/remotes/".count)
                kind = .remoteBranch
            } else if refName.hasPrefix("refs/tags/") {
                refName.removeFirst("refs/tags/".count)
                if refName.hasSuffix("^{}") { refName.removeLast(3) }
                kind = .tag
            } else {
                continue
            }

            references[objectID, default: []].append(.init(name: refName, kind: kind))
        }

        let sortedReferences = references.mapValues { values in
            values.sorted {
                if $0.kind.rawValue != $1.kind.rawValue {
                    return $0.kind.rawValue < $1.kind.rawValue
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
        return (sortedReferences, headCommitID)
    }

    private static func commitFilesSynchronously(
        for commit: RepositoryHistory.Commit,
        in repository: RepositorySummary
    ) throws -> [RepositoryCommitFile] {
        var arguments = [
            "-C", repository.rootURL.path,
            "diff-tree", "--no-commit-id", "--name-status", "-z", "-r", "-M"
        ]
        if let parentID = commit.parentIDs.first {
            arguments.append(contentsOf: [parentID, commit.id])
        } else {
            arguments.append(contentsOf: ["--root", commit.id])
        }
        arguments.append("--")

        let result = try runGit(arguments)
        guard result.status == 0 else {
            throw RepositoryHistoryError.unreadable(result.standardError)
        }
        guard let files = revisionFiles(from: result.standardOutput) else {
            throw RepositoryHistoryError.invalidOutput
        }
        return files
    }

    private static func stashFilesSynchronously(
        for stash: RepositoryStash,
        in repository: RepositorySummary
    ) throws -> [RepositoryCommitFile] {
        let result = try runGit([
            "-C", repository.rootURL.path,
            "stash", "show", "--include-untracked", "--name-status", "-z",
            "--find-renames", stash.id, "--"
        ])
        guard result.status == 0 else {
            throw RepositoryStashError.unreadable(result.standardError)
        }
        guard let files = revisionFiles(from: result.standardOutput) else {
            throw RepositoryStashError.invalidOutput
        }
        return files
    }

    private static func revisionFiles(from data: Data) -> [RepositoryCommitFile]? {
        var fields = data.split(separator: 0, omittingEmptySubsequences: false)
        if fields.last?.isEmpty == true { fields.removeLast() }

        var files: [RepositoryCommitFile] = []
        var index = 0
        while index < fields.count {
            guard
                let status = String(data: fields[index], encoding: .utf8)?.first,
                let state = try? state(from: status)
            else {
                return nil
            }
            index += 1

            let originalPath: String?
            let path: String
            if state == .renamed || state == .copied {
                guard index + 1 < fields.count else { return nil }
                originalPath = String(decoding: fields[index], as: UTF8.self)
                path = String(decoding: fields[index + 1], as: UTF8.self)
                index += 2
            } else {
                guard index < fields.count else { return nil }
                originalPath = nil
                path = String(decoding: fields[index], as: UTF8.self)
                index += 1
            }
            files.append(.init(path: path, originalPath: originalPath, state: state))
        }

        return files.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private static func patchSynchronously(
        for file: RepositoryCommitFile,
        in commit: RepositoryHistory.Commit,
        repository: RepositorySummary,
        maximumOutputBytes: Int?
    ) throws -> RepositoryCommitPatch {
        var arguments = [
            "-C", repository.rootURL.path,
            "show", "--format=", "--no-color", "--no-ext-diff", "--no-textconv",
            "--find-renames", "--first-parent", "--patch", commit.id, "--",
            literalPathspec(file.path)
        ]
        if let originalPath = file.originalPath {
            arguments.append(literalPathspec(originalPath))
        }
        let result = try runGit(arguments, maximumOutputBytes: maximumOutputBytes)
        guard result.status == 0 else {
            throw RepositoryHistoryError.unreadablePatch(result.standardError)
        }

        return revisionPatch(
            result,
            revisionID: commit.id,
            fileID: file.id,
            maximumOutputBytes: maximumOutputBytes,
            unavailableMessage: "This commit has no patch to display."
        )
    }

    private static func stashPatchSynchronously(
        for file: RepositoryCommitFile,
        in stash: RepositoryStash,
        repository: RepositorySummary,
        maximumOutputBytes: Int?
    ) throws -> RepositoryCommitPatch {
        let baseRevision = "\(stash.id)^1"
        var arguments = [
            "-C", repository.rootURL.path,
            "diff", "--patch", "--no-color", "--no-ext-diff", "--no-textconv",
            "--find-renames", baseRevision, stash.id, "--",
            literalPathspec(file.path)
        ]
        if let originalPath = file.originalPath {
            arguments.append(literalPathspec(originalPath))
        }
        var result = try runGit(arguments, maximumOutputBytes: maximumOutputBytes)
        guard result.status == 0 else {
            throw RepositoryStashError.unreadablePatch(result.standardError)
        }

        if result.standardOutput.isEmpty, !result.standardOutputExceededLimit {
            let untrackedRevision = "\(stash.id)^3"
            let verifyResult = try runGit([
                "-C", repository.rootURL.path,
                "rev-parse", "--verify", "--quiet", untrackedRevision
            ])
            if verifyResult.status == 0 {
                arguments[arguments.firstIndex(of: stash.id)!] = untrackedRevision
                result = try runGit(arguments, maximumOutputBytes: maximumOutputBytes)
                guard result.status == 0 else {
                    throw RepositoryStashError.unreadablePatch(result.standardError)
                }
            }
        }

        return revisionPatch(
            result,
            revisionID: stash.id,
            fileID: file.id,
            maximumOutputBytes: maximumOutputBytes,
            unavailableMessage: "This Stash has no patch to display."
        )
    }

    private static func revisionPatch(
        _ result: GitResult,
        revisionID: String,
        fileID: String,
        maximumOutputBytes: Int?,
        unavailableMessage: String
    ) -> RepositoryCommitPatch {

        if result.standardOutputExceededLimit {
            return .init(
                commitID: revisionID,
                fileID: fileID,
                content: .tooLarge(byteLimit: maximumOutputBytes ?? maximumDisplayedDiffBytes)
            )
        }
        let lossyText = String(decoding: result.standardOutput, as: UTF8.self)
        if lossyText.split(separator: "\n").contains(where: {
            $0.hasPrefix("Binary files ") && $0.hasSuffix(" differ")
        }) {
            return .init(commitID: revisionID, fileID: fileID, content: .binary)
        }
        guard let text = String(data: result.standardOutput, encoding: .utf8) else {
            return .init(commitID: revisionID, fileID: fileID, content: .unsupportedEncoding)
        }
        let lines = parseDiffLines(text)
        return .init(
            commitID: revisionID,
            fileID: fileID,
            content: lines.isEmpty
                ? .unavailable(unavailableMessage)
                : .text(lines)
        )
    }

    private static func diffSynchronously(
        for change: RepositorySummary.Change,
        in repository: RepositorySummary,
        maximumOutputBytes: Int?
    ) throws -> RepositoryDiff {
        var sections: [RepositoryDiff.Section] = []

        if change.isConflicted {
            sections = try makeConflictSections(
                for: change,
                rootURL: repository.rootURL,
                maximumOutputBytes: maximumOutputBytes
            )
        } else {
            if change.staged != nil {
                sections.append(try makeDiffSection(
                    scope: .staged,
                    change: change,
                    rootURL: repository.rootURL,
                    maximumOutputBytes: maximumOutputBytes
                ))
            }
            if change.unstaged != nil {
                let scope: RepositoryDiff.Scope = change.unstaged == .untracked ? .untracked : .unstaged
                sections.append(try makeDiffSection(
                    scope: scope,
                    change: change,
                    rootURL: repository.rootURL,
                    maximumOutputBytes: maximumOutputBytes
                ))
            }
        }

        guard !sections.isEmpty else {
            throw RepositoryDiffError.unavailable
        }

        return RepositoryDiff(
            path: change.path,
            originalPath: change.originalPath,
            sections: sections
        )
    }

    private static func makeDiffSection(
        scope: RepositoryDiff.Scope,
        change: RepositorySummary.Change,
        rootURL: URL,
        maximumOutputBytes: Int?
    ) throws -> RepositoryDiff.Section {
        let arguments: [String]
        let acceptedStatuses: Set<Int32>

        switch scope {
        case .staged:
            arguments = trackedDiffArguments(
                rootURL: rootURL,
                options: ["--cached"],
                change: change
            )
            acceptedStatuses = [0]
        case .unstaged:
            arguments = trackedDiffArguments(
                rootURL: rootURL,
                options: [],
                change: change
            )
            acceptedStatuses = [0]
        case .untracked:
            arguments = [
                "-C", rootURL.path,
                "diff", "--no-index", "--no-ext-diff", "--no-textconv",
                "--", "/dev/null", change.path
            ]
            acceptedStatuses = [0, 1]
        case .base, .ours, .theirs:
            throw RepositoryDiffError.unavailable
        }

        let result = try runGit(arguments, maximumOutputBytes: maximumOutputBytes)
        guard acceptedStatuses.contains(result.status) else {
            throw RepositoryDiffError.gitFailed(result.standardError)
        }

        if result.standardOutputExceededLimit {
            return .init(
                scope: scope,
                content: .tooLarge(byteLimit: maximumOutputBytes ?? maximumDisplayedDiffBytes)
            )
        }

        let lossyText = String(decoding: result.standardOutput, as: UTF8.self)
        if lossyText.split(separator: "\n").contains(where: {
            $0.hasPrefix("Binary files ") && $0.hasSuffix(" differ")
        }) {
            return .init(scope: scope, content: .binary)
        }

        guard let text = String(data: result.standardOutput, encoding: .utf8) else {
            return .init(scope: scope, content: .unsupportedEncoding)
        }

        let lines = parseDiffLines(text)
        return .init(
            scope: scope,
            content: lines.isEmpty
                ? .unavailable("The file changed again before its diff could be read.")
                : .text(lines)
        )
    }

    private static func makeConflictSections(
        for change: RepositorySummary.Change,
        rootURL: URL,
        maximumOutputBytes: Int?
    ) throws -> [RepositoryDiff.Section] {
        let result = try runGit([
            "-C", rootURL.path,
            "ls-files", "--stage", "-z", "--", literalPathspec(change.path)
        ])
        guard result.status == 0 else {
            throw RepositoryDiffError.gitFailed(result.standardError)
        }

        let objectIDs = conflictStageObjectIDs(from: result.standardOutput)
        guard !objectIDs.isEmpty else {
            throw RepositoryDiffError.unavailable
        }

        return [
            try makeConflictSection(
                scope: .base,
                objectID: objectIDs[1],
                rootURL: rootURL,
                maximumOutputBytes: maximumOutputBytes
            ),
            try makeConflictSection(
                scope: .ours,
                objectID: objectIDs[2],
                rootURL: rootURL,
                maximumOutputBytes: maximumOutputBytes
            ),
            try makeConflictSection(
                scope: .theirs,
                objectID: objectIDs[3],
                rootURL: rootURL,
                maximumOutputBytes: maximumOutputBytes
            )
        ]
    }

    private static func makeConflictSection(
        scope: RepositoryDiff.Scope,
        objectID: String?,
        rootURL: URL,
        maximumOutputBytes: Int?
    ) throws -> RepositoryDiff.Section {
        guard let objectID else {
            return .init(scope: scope, content: .missing)
        }

        let result = try runGit(
            ["-C", rootURL.path, "cat-file", "blob", objectID],
            maximumOutputBytes: maximumOutputBytes
        )
        guard result.status == 0 else {
            throw RepositoryDiffError.gitFailed(result.standardError)
        }
        if result.standardOutputExceededLimit {
            return .init(
                scope: scope,
                content: .tooLarge(byteLimit: maximumOutputBytes ?? maximumDisplayedDiffBytes)
            )
        }
        if result.standardOutput.contains(0) {
            return .init(scope: scope, content: .binary)
        }
        guard let text = String(data: result.standardOutput, encoding: .utf8) else {
            return .init(scope: scope, content: .unsupportedEncoding)
        }
        return .init(scope: scope, content: .text(parseFileLines(text)))
    }

    private static func conflictStageObjectIDs(from data: Data) -> [Int: String] {
        data.split(separator: 0).reduce(into: [:]) { result, record in
            guard let tab = record.firstIndex(of: 9) else { return }
            let fields = record[..<tab].split(separator: 32)
            guard
                fields.count == 3,
                let stage = Int(String(decoding: fields[2], as: UTF8.self)),
                (1...3).contains(stage)
            else {
                return
            }
            result[stage] = String(decoding: fields[1], as: UTF8.self)
        }
    }

    private static func parseFileLines(_ text: String) -> [RepositoryDiff.Line] {
        guard !text.isEmpty else { return [] }
        var rawLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if text.hasSuffix("\n") {
            rawLines.removeLast()
        }
        return rawLines.enumerated().map { index, line in
            .init(
                id: index,
                kind: .context,
                oldLineNumber: nil,
                newLineNumber: index + 1,
                text: String(line)
            )
        }
    }

    private static func trackedDiffArguments(
        rootURL: URL,
        options: [String],
        change: RepositorySummary.Change
    ) -> [String] {
        var arguments = [
            "-C", rootURL.path,
            "diff", "--no-ext-diff", "--no-textconv", "--find-renames"
        ]
        arguments.append(contentsOf: options)
        arguments.append("--")
        arguments.append(literalPathspec(change.path))
        if let originalPath = change.originalPath {
            arguments.append(literalPathspec(originalPath))
        }
        return arguments
    }

    private static func literalPathspec(_ path: String) -> String {
        ":(literal)\(path)"
    }

    private static func parseDiffLines(_ text: String) -> [RepositoryDiff.Line] {
        var rawLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if rawLines.last?.isEmpty == true {
            rawLines.removeLast()
        }

        var oldLineNumber: Int?
        var newLineNumber: Int?
        var result: [RepositoryDiff.Line] = []
        result.reserveCapacity(rawLines.count)

        for (index, rawLine) in rawLines.enumerated() {
            let line = String(rawLine)
            var kind: RepositoryDiff.Line.Kind = .metadata
            var displayedOldLineNumber: Int?
            var displayedNewLineNumber: Int?

            if line.hasPrefix("diff --git ") {
                oldLineNumber = nil
                newLineNumber = nil
            } else if let starts = hunkStarts(in: rawLine) {
                kind = .hunk
                oldLineNumber = starts.old
                newLineNumber = starts.new
            } else if let currentOld = oldLineNumber, let currentNew = newLineNumber {
                switch rawLine.first {
                case " ":
                    kind = .context
                    displayedOldLineNumber = currentOld
                    displayedNewLineNumber = currentNew
                    oldLineNumber = currentOld + 1
                    newLineNumber = currentNew + 1
                case "-":
                    kind = .deletion
                    displayedOldLineNumber = currentOld
                    oldLineNumber = currentOld + 1
                case "+":
                    kind = .addition
                    displayedNewLineNumber = currentNew
                    newLineNumber = currentNew + 1
                default:
                    break
                }
            }

            result.append(.init(
                id: index,
                kind: kind,
                oldLineNumber: displayedOldLineNumber,
                newLineNumber: displayedNewLineNumber,
                text: line
            ))
        }

        return result
    }

    private static func hunkStarts(in line: Substring) -> (old: Int, new: Int)? {
        guard line.hasPrefix("@@ ") else { return nil }
        let fields = line.split(separator: " ")
        guard
            fields.count >= 3,
            let old = hunkStart(in: fields[1], prefix: "-"),
            let new = hunkStart(in: fields[2], prefix: "+")
        else {
            return nil
        }
        return (old, new)
    }

    private static func hunkStart(in field: Substring, prefix: Character) -> Int? {
        guard field.first == prefix else { return nil }
        guard let value = field.dropFirst().split(separator: ",", maxSplits: 1).first else {
            return nil
        }
        return Int(value)
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func runGit(
        _ arguments: [String],
        maximumOutputBytes: Int? = nil,
        standardInput: Data? = nil,
        cancellation: GitProcessCancellation? = nil,
        additionalEnvironment: [String: String] = [:]
    ) throws -> GitResult {
        let process = Process()
        let captureDirectory = FileManager.default.temporaryDirectory
            .appending(path: "Gallae-Git-\(UUID().uuidString)", directoryHint: .isDirectory)
        let standardOutputURL = captureDirectory.appending(path: "stdout")
        let standardErrorURL = captureDirectory.appending(path: "stderr")

        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: captureDirectory) }
        try Data().write(to: standardOutputURL)
        try Data().write(to: standardErrorURL)

        let standardOutput = try FileHandle(forWritingTo: standardOutputURL)
        let standardError = try FileHandle(forWritingTo: standardErrorURL)
        let standardInputHandle: FileHandle?
        if let standardInput {
            let standardInputURL = captureDirectory.appending(path: "stdin")
            try standardInput.write(to: standardInputURL)
            standardInputHandle = try FileHandle(forReadingFrom: standardInputURL)
        } else {
            standardInputHandle = nil
        }
        defer {
            try? standardOutput.close()
            try? standardError.close()
            try? standardInputHandle?.close()
        }

        process.executableURL = gitURL
        process.arguments = arguments
        process.standardInput = standardInputHandle
        process.standardOutput = standardOutput
        process.standardError = standardError

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_ALL"] = "C"
        environment.merge(additionalEnvironment) { _, value in value }
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw RepositoryInspectionError.gitUnavailable
        }

        cancellation?.register(process)
        defer { cancellation?.clear(process) }
        process.waitUntilExit()
        try standardOutput.close()
        try standardError.close()

        // ponytail: Git finishes writing to disk before the size cap is checked. Stream and
        // terminate the process only if large-diff latency becomes measurable.
        let outputSize = try standardOutputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let exceededLimit = maximumOutputBytes.map { outputSize > $0 } ?? false

        return GitResult(
            status: process.terminationStatus,
            standardOutput: exceededLimit ? Data() : try Data(contentsOf: standardOutputURL),
            standardOutputExceededLimit: exceededLimit,
            standardError: String(
                decoding: try Data(contentsOf: standardErrorURL),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func parseStatus(
        _ data: Data,
        rootURL: URL,
        operationKind: RepositorySummary.Operation.Kind?
    ) throws -> RepositorySummary {
        let records = data.split(separator: 0, omittingEmptySubsequences: true)
        var branchOID: String?
        var branchHead: String?
        var upstreamName: String?
        var ahead: Int?
        var behind: Int?
        var changes: [RepositorySummary.Change] = []
        var index = 0

        while index < records.count {
            let record = String(decoding: records[index], as: UTF8.self)

            if record.hasPrefix("# ") {
                if record.hasPrefix("# branch.oid ") {
                    branchOID = String(record.dropFirst("# branch.oid ".count))
                } else if record.hasPrefix("# branch.head ") {
                    branchHead = String(record.dropFirst("# branch.head ".count))
                } else if record.hasPrefix("# branch.upstream ") {
                    upstreamName = String(record.dropFirst("# branch.upstream ".count))
                } else if record.hasPrefix("# branch.ab ") {
                    let fields = record.dropFirst("# branch.ab ".count).split(separator: " ")
                    guard
                        fields.count == 2,
                        fields[0].first == "+",
                        fields[1].first == "-",
                        let parsedAhead = Int(fields[0].dropFirst()),
                        let parsedBehind = Int(fields[1].dropFirst())
                    else {
                        throw RepositoryInspectionError.invalidGitOutput
                    }
                    ahead = parsedAhead
                    behind = parsedBehind
                }
                index += 1
                continue
            }

            if record.hasPrefix("1 ") {
                let fields = record.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard fields.count == 9, !fields[8].isEmpty else {
                    throw RepositoryInspectionError.invalidGitOutput
                }
                let states = try states(from: fields[1])
                changes.append(.init(
                    path: String(fields[8]),
                    originalPath: nil,
                    staged: states.staged,
                    unstaged: states.unstaged,
                    isConflicted: false
                ))
                index += 1
                continue
            }

            if record.hasPrefix("2 ") {
                let fields = record.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard fields.count == 10, !fields[9].isEmpty, index + 1 < records.count else {
                    throw RepositoryInspectionError.invalidGitOutput
                }
                let states = try states(from: fields[1])
                changes.append(.init(
                    path: String(fields[9]),
                    originalPath: String(decoding: records[index + 1], as: UTF8.self),
                    staged: states.staged,
                    unstaged: states.unstaged,
                    isConflicted: false
                ))
                index += 2
                continue
            }

            if record.hasPrefix("u ") {
                let fields = record.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard fields.count == 11, !fields[10].isEmpty else {
                    throw RepositoryInspectionError.invalidGitOutput
                }
                changes.append(.init(
                    path: String(fields[10]),
                    originalPath: nil,
                    staged: nil,
                    unstaged: nil,
                    isConflicted: true
                ))
                index += 1
                continue
            }

            if record.hasPrefix("? ") {
                let fields = record.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                guard fields.count == 2, !fields[1].isEmpty else {
                    throw RepositoryInspectionError.invalidGitOutput
                }
                changes.append(.init(
                    path: String(fields[1]),
                    originalPath: nil,
                    staged: nil,
                    unstaged: .untracked,
                    isConflicted: false
                ))
                index += 1
                continue
            }

            throw RepositoryInspectionError.invalidGitOutput
        }

        guard let branchHead, !branchHead.isEmpty else {
            throw RepositoryInspectionError.unreadableHead("")
        }

        let head: RepositorySummary.Head
        if branchHead == "(detached)" {
            guard let branchOID, branchOID != "(initial)", !branchOID.isEmpty else {
                throw RepositoryInspectionError.unreadableHead("")
            }
            head = .detached(branchOID)
        } else {
            head = .branch(branchHead)
        }

        let upstream = upstreamName.map {
            RepositorySummary.Upstream(name: $0, ahead: ahead, behind: behind)
        }

        let operation = operationKind.map {
            RepositorySummary.Operation(
                kind: $0,
                unresolvedConflictCount: changes.count(where: \.isConflicted)
            )
        }
        return RepositorySummary(
            rootURL: rootURL,
            head: head,
            isUnborn: branchOID == "(initial)",
            upstream: upstream,
            changes: changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
            operation: operation
        )
    }

    private static func states(
        from value: Substring
    ) throws -> (staged: RepositorySummary.Change.State?, unstaged: RepositorySummary.Change.State?) {
        guard value.count == 2 else {
            throw RepositoryInspectionError.invalidGitOutput
        }
        let characters = Array(value)
        return (try state(from: characters[0]), try state(from: characters[1]))
    }

    private static func state(from value: Character) throws -> RepositorySummary.Change.State? {
        switch value {
        case ".": nil
        case "M": .modified
        case "T": .typeChanged
        case "A": .added
        case "D": .deleted
        case "R": .renamed
        case "C": .copied
        default: throw RepositoryInspectionError.invalidGitOutput
        }
    }

    private static func text(from data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    private static func line(from data: Data) -> String {
        var value = text(from: data)
        if value.last == "\n" {
            value.removeLast()
            if value.last == "\r" {
                value.removeLast()
            }
        }
        return value
    }
}

private struct GitResult: Sendable {
    let status: Int32
    let standardOutput: Data
    let standardOutputExceededLimit: Bool
    let standardError: String
}

private final class GitProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func register(_ process: Process) {
        let shouldTerminate = lock.withLock {
            guard !cancelled else { return true }
            self.process = process
            return false
        }
        if shouldTerminate, process.isRunning {
            process.terminate()
        }
    }

    func cancel() {
        let runningProcess = lock.withLock {
            cancelled = true
            return process
        }
        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }

    func clear(_ process: Process) {
        lock.withLock {
            if self.process === process {
                self.process = nil
            }
        }
    }
}

enum RepositoryHistoryError: LocalizedError, Equatable {
    case unreadable(String)
    case unreadablePatch(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "Git couldn’t read this Repository’s commit history."
        case .unreadablePatch:
            "Git couldn’t read the selected commit’s changes."
        case .invalidOutput:
            "Git returned an unexpected commit history."
        }
    }
}

enum RepositoryInteractiveRebasePlanError: LocalizedError, Equatable {
    case unavailable
    case notOnCurrentBranch
    case requiresCleanRepository
    case invalidPlan
    case missingRewordMessage(stepID: String)
    case unreadable(String)
    case executionFailed(String)
    case recoveryFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "A Rebase plan needs an attached branch with no Git operation in progress."
        case .notOnCurrentBranch:
            "The selected commit isn’t part of the current branch."
        case .requiresCleanRepository:
            "Commit or Stash the current changes before running an Interactive Rebase."
        case .invalidPlan:
            "The Interactive Rebase plan is no longer valid for the current branch."
        case .missingRewordMessage:
            "Enter a commit message for every Reword step."
        case .unreadable:
            "Git couldn’t build an Interactive Rebase plan."
        case .executionFailed:
            "Git couldn’t run the Interactive Rebase plan."
        case .recoveryFailed:
            "Git couldn’t fully restore the branch after cancelling Interactive Rebase."
        case .invalidOutput:
            "Git returned an unexpected Interactive Rebase plan."
        }
    }
}

enum RepositoryReflogError: LocalizedError, Equatable {
    case unreadable(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "Git couldn’t read this Repository’s Reflog."
        case .invalidOutput:
            "Git returned an unexpected Reflog."
        }
    }
}

enum RepositoryStashError: LocalizedError, Equatable {
    case unavailable
    case unreadable(String)
    case unreadablePatch(String)
    case creationFailed(String)
    case applyFailed(String)
    case deletionUnavailable
    case deletionFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The current Repository is no longer available for creating a Stash."
        case .unreadable:
            "Git couldn’t read this Repository’s Stashes."
        case .unreadablePatch:
            "Git couldn’t read the selected Stash’s changes."
        case .creationFailed(let message):
            message.isEmpty
                ? "Git couldn’t create a Stash from the current changes."
                : "Git couldn’t create a Stash from the current changes: \(message)"
        case .applyFailed(let message):
            message.isEmpty
                ? "Git couldn’t apply the selected Stash."
                : "Git couldn’t apply the selected Stash: \(message)"
        case .deletionUnavailable:
            "The selected Stash is no longer available. Reload the Stash list and try again."
        case .deletionFailed(let message):
            message.isEmpty
                ? "Git couldn’t delete the selected Stash."
                : "Git couldn’t delete the selected Stash: \(message)"
        case .invalidOutput:
            "Git returned an unexpected Stash list."
        }
    }
}

enum RepositoryDiffError: LocalizedError, Equatable {
    case unavailable
    case gitFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The selected file no longer has a readable diff. Refresh the Repository and try again."
        case .gitFailed:
            "Git couldn’t produce a diff for the selected file. Refresh the Repository and try again."
        }
    }
}

enum RepositoryIndexError: LocalizedError, Equatable {
    case unavailable
    case gitFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The selected file’s index state cannot be changed in its current state."
        case .gitFailed:
            "Git couldn’t update the selected file’s index state. Its working tree content was not discarded."
        }
    }
}

enum RepositoryConflictResolutionError: LocalizedError, Equatable {
    case unavailable
    case gitFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The selected file is no longer conflicted. Refresh the Repository and try again."
        case .gitFailed(let message):
            message.isEmpty
                ? "Git couldn’t resolve the selected conflict. Inspect the file before trying again."
                : "Git couldn’t resolve the selected conflict. Inspect the file before trying again.\n\n\(message)"
        }
    }
}

enum RepositoryOperationError: LocalizedError, Equatable {
    case unavailable
    case unresolvedConflicts
    case continueFailed(String)
    case abortFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The Merge or Rebase is no longer in progress. Refresh the Repository and try again."
        case .unresolvedConflicts:
            "Resolve every conflict before continuing the Merge or Rebase."
        case .continueFailed(let message):
            message.isEmpty
                ? "Git couldn’t continue the Merge or Rebase."
                : "Git couldn’t continue the Merge or Rebase.\n\n\(message)"
        case .abortFailed(let message):
            message.isEmpty
                ? "Git couldn’t abort the Merge or Rebase."
                : "Git couldn’t abort the Merge or Rebase.\n\n\(message)"
        }
    }
}

enum RepositoryCommitError: LocalizedError, Equatable {
    case unavailable
    case gitFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Enter a commit subject and Stage at least one change."
        case .gitFailed(let message):
            message.isEmpty
                ? "Git couldn’t create the commit."
                : "Git couldn’t create the commit.\n\n\(message)"
        }
    }
}

enum RepositoryRevertError: LocalizedError, Equatable {
    case dirtyRepository
    case detachedHead
    case mainlineRequired
    case invalidMainline
    case notOnCurrentBranch
    case gitFailed(String)
    case recoveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .dirtyRepository:
            "Commit or Stash the current changes before reverting a commit."
        case .detachedHead:
            "Switch to a local branch before reverting a commit."
        case .mainlineRequired:
            "Choose which merge parent to keep as the mainline before reverting this commit."
        case .invalidMainline:
            "The selected merge mainline is no longer valid. Choose a parent again."
        case .notOnCurrentBranch:
            "The selected commit isn’t part of the current branch."
        case .gitFailed(let message):
            message.isEmpty
                ? "Git couldn’t revert the selected commit. The Repository was restored to its previous state."
                : "Git couldn’t revert the selected commit. The Repository was restored to its previous state.\n\n\(message)"
        case .recoveryFailed(let message):
            message.isEmpty
                ? "Git couldn’t finish or fully abort the Revert. Inspect the current changes before continuing."
                : "Git couldn’t finish or fully abort the Revert. Inspect the current changes before continuing.\n\n\(message)"
        }
    }
}

enum RepositoryResetMode: Hashable, Sendable {
    case mixed
    case soft
    case hard

    fileprivate var gitArgument: String {
        switch self {
        case .mixed: "--mixed"
        case .soft: "--soft"
        case .hard: "--hard"
        }
    }
}

enum RepositoryResetError: LocalizedError, Equatable {
    case dirtyRepository
    case detachedHead
    case alreadyAtCommit
    case notOnCurrentBranch
    case gitFailed(String)
    case recoveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .dirtyRepository:
            "Commit or Stash the current changes before resetting the current branch."
        case .detachedHead:
            "Switch to a local branch before resetting it."
        case .alreadyAtCommit:
            "The selected commit is already the current branch’s HEAD."
        case .notOnCurrentBranch:
            "Choose an earlier commit from the current branch."
        case .gitFailed(let message):
            message.isEmpty
                ? "Git couldn’t reset the current branch. The branch and tracked state were restored."
                : "Git couldn’t reset the current branch. The branch and tracked state were restored.\n\n\(message)"
        case .recoveryFailed(let message):
            message.isEmpty
                ? "Git couldn’t reset or fully restore the current branch. Inspect the current changes before continuing."
                : "Git couldn’t reset or fully restore the current branch. Inspect the current changes before continuing.\n\n\(message)"
        }
    }
}

enum RepositoryDiscardError: LocalizedError, Equatable {
    case unavailable
    case gitFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Only unstaged changes to tracked files can be discarded."
        case .gitFailed:
            "Git couldn’t discard the selected file’s unstaged changes."
        }
    }
}

enum RepositoryBranchError: LocalizedError, Equatable {
    case unavailable
    case unreadable(String)
    case switchFailed(String)
    case creationFailed(String)
    case mergeUnavailable
    case mergeFailed(String)
    case mergeCommitRequiresCleanRepository
    case mergeCommitRequiresDivergence
    case mergeCommitFailed(String)
    case mergeCommitRecoveryFailed(String)
    case rebaseUnavailable
    case rebaseRequiresCleanRepository
    case rebaseFailed(String)
    case rebaseRecoveryFailed(String)
    case fastForwardOutUnavailable
    case fastForwardOutRequiresAncestor
    case fastForwardOutFailed(String)
    case mergeOutUnavailable
    case mergeOutCheckedOut
    case mergeOutConflicts([String])
    case mergeOutFailed(String)
    case mergeInWorktreeConflicted(URL)
    case worktreeCreationFailed(String)
    case worktreeRemovalFailed(String)
    case deletionUnavailable
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The selected local branch is no longer available. Reload the branch list and try again."
        case .unreadable:
            "Git couldn’t read this Repository’s local branches."
        case .switchFailed(let message):
            message.isEmpty
                ? "Git couldn’t switch to the selected branch."
                : "Git couldn’t switch to the selected branch.\n\n\(message)"
        case .creationFailed(let message):
            message.isEmpty
                ? "Git couldn’t create the new branch."
                : "Git couldn’t create the new branch.\n\n\(message)"
        case .mergeUnavailable:
            "Choose another local branch to merge into a current branch that has a commit."
        case .mergeFailed(let message):
            message.isEmpty
                ? "Git couldn’t fast-forward the current branch."
                : "Git couldn’t fast-forward the current branch.\n\n\(message)"
        case .mergeCommitRequiresCleanRepository:
            "Commit or stash the current changes before creating a merge commit."
        case .mergeCommitRequiresDivergence:
            "These branches haven’t diverged. Use Fast-Forward instead."
        case .mergeCommitFailed(let message):
            message.isEmpty
                ? "Git couldn’t create the merge commit. The merge was aborted."
                : "Git couldn’t create the merge commit. The merge was aborted.\n\n\(message)"
        case .mergeCommitRecoveryFailed(let message):
            message.isEmpty
                ? "Git couldn’t create or fully abort the merge. Inspect the current changes before continuing."
                : "Git couldn’t create or fully abort the merge. Inspect the current changes before continuing.\n\n\(message)"
        case .fastForwardOutUnavailable:
            "Choose another local branch to fast-forward from a current branch that has a commit."
        case .fastForwardOutRequiresAncestor:
            "The current branch doesn’t contain every commit of the selected branch, so it can’t be fast-forwarded without switching."
        case .fastForwardOutFailed(let message):
            message.isEmpty
                ? "Git couldn’t fast-forward the selected branch. No references were changed."
                : "Git couldn’t fast-forward the selected branch.\n\n\(message)"
        case .mergeOutUnavailable:
            "Choose another local branch to merge from a current branch that has a commit."
        case .mergeOutCheckedOut:
            "The selected branch is now checked out in a Worktree. Gallae merges in that Worktree instead — try again."
        case .mergeOutConflicts(let paths):
            "Merging would conflict in \(paths.count) file\(paths.count == 1 ? "" : "s"): \(paths.prefix(5).joined(separator: ", "))\(paths.count > 5 ? ", …" : ""). No references were changed."
        case .mergeOutFailed(let message):
            message.isEmpty
                ? "Git couldn’t create the merge commit. No references were changed."
                : "Git couldn’t create the merge commit. No references were changed.\n\n\(message)"
        case .mergeInWorktreeConflicted(let worktreeURL):
            "The merge stopped with conflicts in the Worktree at \(worktreeURL.path). Open it to resolve the conflicts, or abort the merge."
        case .worktreeCreationFailed(let message):
            message.isEmpty
                ? "Git couldn’t create the temporary Worktree."
                : "Git couldn’t create the temporary Worktree.\n\n\(message)"
        case .worktreeRemovalFailed(let message):
            message.isEmpty
                ? "Git couldn’t remove the Worktree. Changes may remain inside it."
                : "Git couldn’t remove the Worktree. Changes may remain inside it.\n\n\(message)"
        case .deletionUnavailable:
            "Switch to another branch before deleting the current branch."
        case .deletionFailed(let message):
            message.isEmpty
                ? "Git couldn’t delete the branch. Unmerged branches and branches checked out in a Worktree are kept."
                : "Git couldn’t delete the branch. Unmerged branches and branches checked out in a Worktree are kept.\n\n\(message)"
        case .rebaseUnavailable:
            "Choose another local branch to rebase a current branch that has a commit."
        case .rebaseRequiresCleanRepository:
            "Commit or stash the current changes before rebasing."
        case .rebaseFailed(let message):
            message.isEmpty
                ? "Git couldn’t rebase the current branch. The rebase was aborted."
                : "Git couldn’t rebase the current branch. The rebase was aborted.\n\n\(message)"
        case .rebaseRecoveryFailed(let message):
            message.isEmpty
                ? "Git couldn’t rebase or fully abort the operation. Inspect the current changes before continuing."
                : "Git couldn’t rebase or fully abort the operation. Inspect the current changes before continuing.\n\n\(message)"
        }
    }
}

enum RepositoryRemoteError: LocalizedError, Equatable {
    case unreadable(String)
    case invalidInput
    case unavailable
    case connectionFailed(String)
    case updateFailed(String)
    case removeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let message):
            message.isEmpty
                ? "Git couldn’t read this Repository’s remotes."
                : "Git couldn’t read this Repository’s remotes.\n\n\(message)"
        case .invalidInput:
            "Remote name, Fetch URL, and Push URL are required."
        case .unavailable:
            "The selected remote is no longer available. Reload Remotes and try again."
        case .connectionFailed(let message):
            message.isEmpty
                ? "Git couldn’t reach this Remote’s Fetch URL."
                : "Git couldn’t reach this Remote’s Fetch URL.\n\n\(message)"
        case .updateFailed(let message):
            message.isEmpty
                ? "Git couldn’t update this remote."
                : "Git couldn’t update this remote.\n\n\(message)"
        case .removeFailed(let message):
            message.isEmpty
                ? "Git couldn’t remove this remote."
                : "Git couldn’t remove this remote.\n\n\(message)"
        }
    }
}

enum RepositoryFetchError: LocalizedError, Equatable {
    case noRemote
    case remoteSelectionRequired([String])
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noRemote:
            "This Repository has no remote to fetch from."
        case .remoteSelectionRequired:
            "Choose which Git remote to fetch from."
        case .failed(let message):
            message.isEmpty
                ? "Git couldn’t fetch Remote changes."
                : "Git couldn’t fetch Remote changes.\n\n\(message)"
        }
    }
}

enum RepositoryPullError: LocalizedError, Equatable {
    case noUpstream
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noUpstream:
            "The current branch isn’t tracking a remote branch to pull from."
        case .failed(let message):
            message.isEmpty
                ? "Git couldn’t fast-forward the current branch from its tracking branch."
                : "Git couldn’t fast-forward the current branch from its tracking branch.\n\n\(message)"
        }
    }
}

enum RepositoryPushError: LocalizedError, Equatable {
    case noRemote
    case remoteSelectionRequired([String])
    case publishUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noRemote:
            "Add a Git remote before publishing the current branch."
        case .remoteSelectionRequired:
            "Choose which Git remote should receive the current branch."
        case .publishUnavailable:
            "Publishing requires a committed local branch."
        case .failed(let message):
            message.isEmpty
                ? "Git couldn’t push the current branch to its configured destination."
                : "Git couldn’t push the current branch to its configured destination.\n\n\(message)"
        }
    }
}

enum RepositoryRemoteSetupError: LocalizedError, Equatable {
    case invalidInput
    case addFailed(String)
    case publishFailed(remote: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            "Enter a remote name and Repository URL."
        case .addFailed(let message):
            message.isEmpty
                ? "Git couldn’t add this remote."
                : "Git couldn’t add this remote.\n\n\(message)"
        case .publishFailed(let remote, let message):
            "Remote “\(remote)” was added, but Publish didn’t finish.\n\n\(message)"
        }
    }
}

enum RepositoryInspectionError: LocalizedError, Equatable {
    case gitUnavailable
    case notWorkingTree(String)
    case bareRepository
    case unreadableHead(String)
    case unreadableStatus(String)
    case unreadableHistory(String)
    case invalidGitOutput

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            "System Git is unavailable. Install or repair the Xcode Command Line Tools, then try again."
        case .notWorkingTree:
            "The selected folder is not a Git working tree."
        case .bareRepository:
            "The selected folder is a bare Repository, which this version cannot open."
        case .unreadableHead:
            "The Repository exists, but its HEAD cannot be read."
        case .unreadableStatus:
            "The Repository exists, but its working tree status cannot be read."
        case .unreadableHistory:
            "The Repository exists, but its recent activity cannot be read."
        case .invalidGitOutput:
            "Git returned an unexpected Repository description."
        }
    }
}
