import Foundation

struct RepositoryWorktree: Identifiable, Equatable, Sendable {
    let url: URL
    let headID: String
    let branch: String?
    let isPrimary: Bool
    let isBare: Bool
    let lockedReason: String?
    let prunableReason: String?
    let isAvailable: Bool
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var headLabel: String { branch ?? "Detached HEAD · \(headID.prefix(8))" }

    func removalRestriction(currentURL: URL) -> String? {
        if isPrimary || isBare { return "The primary working tree cannot be removed." }
        if sameFileLocation(url.resolvingSymlinksInPath(), currentURL.resolvingSymlinksInPath()) {
            return "Open another working tree before removing this one."
        }
        if let lockedReason { return lockedReason.isEmpty ? "This Worktree is locked." : "Locked: \(lockedReason)" }
        if !isAvailable || prunableReason != nil { return "This Worktree folder is unavailable. Its registration has been kept." }
        return nil
    }

    static func branchURLs(in worktrees: [Self]) -> [String: URL] {
        var result: [String: URL] = [:]
        for worktree in worktrees where !worktree.isBare && worktree.prunableReason == nil {
            if let branch = worktree.branch { result[branch] = worktree.url }
        }
        return result
    }
}

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
            case cherryPick
        }

        struct Identity: Equatable, Sendable {
            let kind: Kind
            let markerURL: URL
            let fileNumber: UInt64
            let creationDate: Date
        }

        let identity: Identity
        let unresolvedConflictCount: Int

        var kind: Kind { identity.kind }
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

/// A preview pins both branch tips and the folder that will receive the update.
struct RepositoryBranchIntegrationPreview: Equatable, Sendable {
    let rootURL: URL
    let source: String
    let target: String
    let sourceCommitID: String
    let targetCommitID: String
    let divergence: RepositoryBranchDivergence
    let targetWorktree: RepositorySummary?

    var isDiverged: Bool { divergence.uniqueToCurrent > 0 && divergence.uniqueToOther > 0 }

    func unavailableReason(for action: RepositoryBranchIntegrationAction) -> String? {
        if targetWorktree?.operation != nil { return "Finish the operation in the target Worktree first." }
        if divergence.uniqueToOther == 0 { return "The target already contains all commits from the source." }
        if action == .fastForward {
            return divergence.uniqueToCurrent > 0 ? "These branches have diverged. Choose Merge Commit or Rebase." : nil
        }
        if targetWorktree?.changes.isEmpty == false { return "Commit or stash changes in the target Worktree first." }
        if !isDiverged { return "No merge or replay is needed. Choose Fast-Forward." }
        return nil
    }
}

struct RepositoryMergePrediction: Equatable, Sendable {
    let isClean: Bool
    let conflictedPaths: [String]
    let treeID: String
}

enum RepositoryCommitSignature: Equatable, Sendable {
    case none
    case good(keyID: String, signer: String)
    case unverifiedTrust(keyID: String, signer: String)
    case invalid
    case cannotCheck

    static func make(status: String, keyID: String, signer: String) -> RepositoryCommitSignature {
        switch status {
        case "G": .good(keyID: keyID, signer: signer)
        case "U": .unverifiedTrust(keyID: keyID, signer: signer)
        case "B", "X", "Y", "R": .invalid
        case "E": .cannotCheck
        default: .none
        }
    }
}

struct RepositoryPushPreview: Equatable, Sendable {
    struct Commit: Equatable, Identifiable, Sendable {
        let id: String
        let subject: String
    }

    let rootURL: URL
    let source: String
    let commitID: String
    let remote: String
    let branch: String
    let pushURL: String
    let destinationCommitID: String?
    let ahead: Int
    let behind: Int
    let commits: [Commit]

    var destination: String { "\(remote)/\(branch)" }
    var canPush: Bool { ahead > 0 && behind == 0 }
}

struct RepositoryHistory: Equatable, Sendable {
    struct GraphEdge: Equatable, Sendable {
        let fromLane: Int
        let toLane: Int
        let colorIndex: Int
        var isHeadPath: Bool = false
    }

    struct GraphRow: Equatable, Sendable {
        let commitLane: Int
        let commitColorIndex: Int
        let topLaneCount: Int
        let bottomLaneCount: Int
        let incomingEdges: [GraphEdge]
        let continuationEdges: [GraphEdge]
        let parentEdges: [GraphEdge]

        var isHeadPath: Bool = false

        var hasIncomingEdge: Bool { !incomingEdges.isEmpty }
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
    let headGraphRows: [String: GraphRow]
    let defaultBranchName: String
    let graphPreferenceKey: String
    let focusedCommitID: String?
    let hasMoreCommits: Bool

    init(commits: [Commit], headCommitID: String? = nil, focusedCommitID: String? = nil,
         hasMoreCommits: Bool = false, defaultBranchName: String = "HEAD",
         graphPreferenceKey: String = "historyGraphBasis", defaultBranchPath: Set<String> = [],
         headPath: Set<String>? = nil) {
        self.commits = commits
        self.headCommitID = headCommitID ?? commits.first?.id
        self.focusedCommitID = focusedCommitID
        self.hasMoreCommits = hasMoreCommits
        self.defaultBranchName = defaultBranchName
        self.graphPreferenceKey = graphPreferenceKey
        var resolvedHeadPath = headPath ?? []
        if headPath == nil {
            let parents = Dictionary(uniqueKeysWithValues: commits.map { ($0.id, $0.parentIDs) })
            var id = self.headCommitID
            while let current = id, resolvedHeadPath.insert(current).inserted {
                id = parents[current]?.first
            }
        }
        // Stop the work highlight where it joins the default branch; retain the full spine for layout.
        let highlightedPath = defaultBranchPath.contains(self.headCommitID ?? "")
            ? resolvedHeadPath : resolvedHeadPath.subtracting(defaultBranchPath)
        let layout = Self.makeGraphLayout(for: commits, anchorPath: defaultBranchPath, headPath: highlightedPath)
        headGraphRows = defaultBranchPath == resolvedHeadPath ? layout.rows
            : Self.makeGraphLayout(for: commits, anchorPath: resolvedHeadPath, headPath: highlightedPath).rows
        graphRows = layout.rows
        graphLaneCount = layout.laneCount
    }

    private static func makeGraphLayout(
        for commits: [Commit], anchorPath: Set<String>, headPath: Set<String>
    ) -> (rows: [String: GraphRow], laneCount: Int) {
        let hasAnchor = !anchorPath.isEmpty
        var lanes: [(target: String, color: Int, isHeadPath: Bool)?] = hasAnchor ? [nil] : []
        var nextColorIndex = hasAnchor ? 1 : 0
        var rows: [String: GraphRow] = [:]
        var maximumLaneCount = 0

        for commit in commits {
            if hasAnchor && lanes.isEmpty { lanes.append(nil) }
            let incomingLanes = lanes.indices.filter { lanes[$0]?.target == commit.id }
            let commitLane = anchorPath.contains(commit.id) ? 0 : (incomingLanes.first
                ?? lanes.indices.first(where: { (!hasAnchor || $0 > 0) && lanes[$0] == nil })
                ?? lanes.count)
            if commitLane == lanes.count { lanes.append(nil) }
            let commitColor = lanes[commitLane]?.color ?? (hasAnchor && commitLane == 0 ? 0 : nextColorIndex)
            if lanes[commitLane] == nil && !(hasAnchor && commitLane == 0) { nextColorIndex += 1 }
            let topLaneCount = lanes.count

            let incomingEdges = incomingLanes.map {
                GraphEdge(fromLane: $0, toLane: commitLane, colorIndex: lanes[$0]!.color, isHeadPath: lanes[$0]!.isHeadPath)
            }
            let continuationEdges = lanes.indices.compactMap { lane -> GraphEdge? in
                guard let path = lanes[lane], path.target != commit.id else { return nil }
                return GraphEdge(fromLane: lane, toLane: lane, colorIndex: path.color, isHeadPath: path.isHeadPath)
            }
            for lane in incomingLanes { lanes[lane] = nil }

            var parentEdges: [GraphEdge] = []
            for (index, parentID) in commit.parentIDs.enumerated() {
                // Keep the first-parent spine in its lane. Paths waiting for the same
                // ancestor join at that ancestor's node, rather than shifting every rail.
                let parentLane: Int
                if index == 0 {
                    parentLane = commitLane
                } else {
                    parentLane = lanes.firstIndex(where: { $0?.target == parentID })
                        ?? lanes.indices.first(where: { $0 > commitLane && lanes[$0] == nil })
                        ?? lanes.indices.first(where: { (!hasAnchor || $0 > 0) && lanes[$0] == nil })
                        ?? lanes.count
                }
                if parentLane == lanes.count { lanes.append(nil) }
                if lanes[parentLane] == nil {
                    lanes[parentLane] = (parentID, index == 0 ? commitColor : nextColorIndex, false)
                    if index != 0 { nextColorIndex += 1 }
                }
                let isHeadPath = index == 0 && headPath.contains(commit.id)
                lanes[parentLane]!.isHeadPath = lanes[parentLane]!.isHeadPath || isHeadPath
                parentEdges.append(.init(
                    fromLane: commitLane, toLane: parentLane, colorIndex: lanes[parentLane]!.color,
                    isHeadPath: isHeadPath
                ))
            }
            // Interior empty lanes are reusable; removing them would bend unrelated paths.
            while !lanes.isEmpty && lanes[lanes.count - 1] == nil { lanes.removeLast() }

            rows[commit.id] = .init(
                commitLane: commitLane,
                commitColorIndex: commitColor,
                topLaneCount: topLaneCount,
                bottomLaneCount: lanes.count,
                incomingEdges: incomingEdges,
                continuationEdges: continuationEdges,
                parentEdges: parentEdges,
                isHeadPath: headPath.contains(commit.id)
            )
            maximumLaneCount = max(maximumLaneCount, topLaneCount, lanes.count)
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

    let rootURL: URL
    let branch: String
    let headID: String
    let startingCommitID: String
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
    let textPresentation: RepositoryDiffTextPresentation?

    init(commitID: String, fileID: String, content: RepositoryDiff.Section.Content) {
        self.commitID = commitID
        self.fileID = fileID
        self.content = content
        textPresentation = RepositoryDiffTextPresentation(content: content)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.commitID == rhs.commitID && lhs.fileID == rhs.fileID && lhs.content == rhs.content
    }
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

        /// Built once with the immutable diff, without materializing patch bytes for every button.
        struct HunkIndex: Equatable, Sendable {
            struct Entry: Equatable, Sendable {
                let range: Range<Int>
                let changedLineIDs: Set<Int>
            }
            let metadataEnd: Int
            let orderedIDs: [Int]
            let entries: [Int: Entry]

            init(content: Content) {
                guard case .text(let lines) = content else {
                    metadataEnd = 0; orderedIDs = []; entries = [:]
                    return
                }
                let starts = lines.indices.filter { lines[$0].kind == .hunk }
                metadataEnd = starts.first ?? 0
                orderedIDs = starts.map { lines[$0].id }
                var entries: [Int: Entry] = [:]
                for (offset, start) in starts.enumerated() {
                    let end = offset + 1 < starts.count ? starts[offset + 1] : lines.endIndex
                    let changed = Set(lines[(start + 1)..<end].compactMap {
                        $0.kind == .addition || $0.kind == .deletion ? $0.id : nil
                    })
                    entries[lines[start].id] = Entry(range: start..<end, changedLineIDs: changed)
                }
                self.entries = entries
            }
        }

        let hunkIndex: HunkIndex
        let textPresentation: RepositoryDiffTextPresentation?

        init(scope: Scope, content: Content) {
            self.scope = scope
            self.content = content
            hunkIndex = HunkIndex(content: content)
            textPresentation = RepositoryDiffTextPresentation(content: content)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.scope == rhs.scope && lhs.content == rhs.content
        }

        /// Construct only the patch the user actually acts on.
        func hunk(id: Int) -> Hunk? {
            guard case .text(let lines) = content, let entry = hunkIndex.entries[id] else { return nil }
            let metadata = lines[..<hunkIndex.metadataEnd].map(\.text)
            let patch = (metadata + lines[entry.range].map(\.text)).joined(separator: "\n") + "\n"
            return Hunk(id: id, scope: scope, patch: Data(patch.utf8))
        }

        var hunks: [Hunk] { hunkIndex.orderedIDs.compactMap { hunk(id: $0) } }
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

        /// The line as the reader should see it. `text` keeps Git's leading `+`, `-` or space because
        /// `Section.hunks` feeds it straight back to `git apply`; on screen the colour, the column and the
        /// change bar already say which side a line is on, and dropping the prefix lets context and changed
        /// lines start in the same column.
        var displayText: String {
            switch kind {
            case .context, .addition, .deletion: String(text.dropFirst())
            case .metadata, .hunk: text
            }
        }

        /// Where a hunk sits, for a reader who should not have to parse `@@ -1 +1,2 @@`. Reads the new side,
        /// which is what the working tree and the index look like now; a hunk that only removes lines has no
        /// new lines to point at, so it names the line the removal follows.
        var hunkLocation: String? {
            guard kind == .hunk else { return nil }
            let fields = text.split(separator: " ")
            guard fields.count >= 3, fields[2].hasPrefix("+") else { return nil }
            let numbers = fields[2].dropFirst().split(separator: ",")
            guard let start = Int(numbers[0]) else { return nil }
            let count = numbers.count > 1 ? (Int(numbers[1]) ?? 1) : 1
            switch count {
            case 0: return "After line \(start)"
            case 1: return "Line \(start)"
            default: return "Lines \(start)–\(start + count - 1)"
            }
        }

        /// The lines Git writes above the first hunk that the view around the diff already says itself —
        /// the file name and its blobs, and the mode a new or deleted file gets, which the file list shows
        /// as an Added or Deleted badge. `git apply` needs them, so they stay in the patch `hunks` builds.
        /// Header lines the view does not say — a chmod's `old mode`/`new mode`, a rename's old path — are
        /// kept.
        var isPatchHeader: Bool {
            guard kind == .metadata else { return false }
            return text.hasPrefix("diff --git ")
                || text.hasPrefix("index ")
                || text.hasPrefix("--- ")
                || text.hasPrefix("+++ ")
                || text.hasPrefix("new file mode ")
                || text.hasPrefix("deleted file mode ")
        }
    }

    struct Hunk: Equatable, Identifiable, Sendable {
        let id: Int
        let scope: Scope
        let patch: Data

        var patchText: String { String(decoding: patch, as: UTF8.self) }
    }

    let path: String
    let originalPath: String?
    let sections: [Section]
}

/// Immutable, font-independent row geometry owned by the loaded diff, including saved revisions.
/// Offsets share the original line storage instead of copying every Line into both layouts.
final class RepositoryDiffTextPresentation: Sendable {
    struct SplitRow: Identifiable, Sendable {
        let id: Int
        let fullIndex: Int?
        let oldIndex: Int?
        let newIndex: Int?
    }

    struct VisibleLines: RandomAccessCollection, Sendable {
        let lines: [RepositoryDiff.Line]
        let offsets: [Int]
        var startIndex: Int { offsets.startIndex }
        var endIndex: Int { offsets.endIndex }
        subscript(position: Int) -> RepositoryDiff.Line { lines[offsets[position]] }
    }

    let lines: [RepositoryDiff.Line]
    let visibleIndices: [Int]
    let splitRows: [SplitRow]
    let largestLineNumber: Int
    let canSplit: Bool

    convenience init?(content: RepositoryDiff.Section.Content) {
        guard case .text(let lines) = content else { return nil }
        self.init(lines: lines)
    }

    var visibleLines: VisibleLines { .init(lines: lines, offsets: visibleIndices) }

    init(lines: [RepositoryDiff.Line], hidesPatchHeaders: Bool = true) {
        self.lines = lines
        var visible: [Int] = []
        var rows: [SplitRow] = []
        var deletions: [Int] = []
        var additions: [Int] = []
        var largest = 0
        var sawContext = false, sawAddition = false, sawDeletion = false
        visible.reserveCapacity(lines.count)

        func flushChanges() {
            for offset in 0..<max(deletions.count, additions.count) {
                let old = offset < deletions.count ? deletions[offset] : nil
                let new = offset < additions.count ? additions[offset] : nil
                rows.append(.init(id: lines[old ?? new!].id, fullIndex: nil, oldIndex: old, newIndex: new))
            }
            deletions.removeAll(keepingCapacity: true)
            additions.removeAll(keepingCapacity: true)
        }

        for index in lines.indices {
            let line = lines[index]
            guard !hidesPatchHeaders || !line.isPatchHeader else { continue }
            visible.append(index)
            largest = max(largest, line.oldLineNumber ?? 0, line.newLineNumber ?? 0)
            switch line.kind {
            case .deletion: sawDeletion = true; deletions.append(index)
            case .addition: sawAddition = true; additions.append(index)
            case .context:
                sawContext = true
                flushChanges()
                rows.append(.init(id: line.id, fullIndex: nil, oldIndex: index, newIndex: index))
            case .metadata, .hunk:
                flushChanges()
                rows.append(.init(id: line.id, fullIndex: index, oldIndex: nil, newIndex: nil))
            }
        }
        flushChanges()
        visibleIndices = visible
        splitRows = rows
        largestLineNumber = largest
        canSplit = !lines.isEmpty && (sawContext || sawAddition == sawDeletion)
    }
}

extension RepositoryDiff.Section.Content {
    /// Counts only changed content, never patch headers or unchanged context.
    var lineChangeCounts: (added: Int, removed: Int)? {
        guard case .text(let lines) = self else { return nil }
        return lines.reduce(into: (added: 0, removed: 0)) { counts, line in
            if line.kind == .addition { counts.added += 1 }
            if line.kind == .deletion { counts.removed += 1 }
        }
    }

    /// A file with no opposite version at all: every line added, or every line removed, and no context
    /// between them. An ordinary edit that happens to only add lines is *not* one-sided — its context lines
    /// are what the two columns line up against, which is the whole point of reading it side by side.
    /// The History pane holds a bare `Content`, so this lives here and `Section` reads it.
    var isOneSided: Bool {
        guard case .text(let lines) = self else { return false }
        var sawAddition = false
        var sawDeletion = false
        for line in lines {
            switch line.kind {
            case .context: return false
            case .addition: sawAddition = true
            case .deletion: sawDeletion = true
            case .metadata, .hunk: break
            }
            if sawAddition, sawDeletion { return false }
        }
        return sawAddition != sawDeletion
    }
}

extension RepositoryDiff.Section {
    /// Additions and deletions — what a reader counts as changed. Context and headers are not changes.
    var changedLineCount: Int {
        guard let counts = content.lineChangeCounts else { return 0 }
        return counts.added + counts.removed
    }

    /// New or deleted content without context uses one column; ordinary edits keep their comparison.
    var isOneSided: Bool { content.isOneSided }

    /// The section's patch exactly as Git wrote it. `Line.text` keeps each line's original prefix, so joining
    /// them reproduces the bytes `git diff` produced.
    var patchText: String? {
        guard case .text(let lines) = content, !lines.isEmpty else { return nil }
        return lines.map(\.text).joined(separator: "\n") + "\n"
    }

    /// Which side a partial patch has to match. Staging applies against the index, which still equals the diff's
    /// old side, so an unchosen deletion stays as context and an unchosen addition drops out. Unstaging and
    /// discarding reverse a patch against the new side, so the opposite holds.
    enum PartialDirection: Sendable {
        case apply
        case revert
    }

    /// The hunk `hunkID` cut down to the chosen addition and deletion lines, or nil when none is chosen. Context
    /// lines stay, the header's counts are recomputed, and a `\ No newline at end of file` marker follows the
    /// line it annotates: kept with it, dropped with it.
    func partialHunk(
        id hunkID: Int,
        keeping chosenLineIDs: Set<Int>,
        direction: PartialDirection
    ) -> RepositoryDiff.Hunk? {
        guard
            case .text(let lines) = content,
            let entry = hunkIndex.entries[hunkID]
        else {
            return nil
        }
        let firstHunk = hunkIndex.metadataEnd
        let start = entry.range.lowerBound
        let end = entry.range.upperBound
        var body: [String] = []
        var oldCount = 0
        var newCount = 0
        var hasChange = false
        var keptPreviousLine = true

        for line in lines[(start + 1)..<end] {
            switch line.kind {
            case .context:
                body.append(line.text)
                oldCount += 1
                newCount += 1
                keptPreviousLine = true
            case .addition:
                if chosenLineIDs.contains(line.id) {
                    body.append(line.text)
                    newCount += 1
                    hasChange = true
                    keptPreviousLine = true
                } else if direction == .revert {
                    body.append(" " + line.text.dropFirst())
                    oldCount += 1
                    newCount += 1
                    keptPreviousLine = true
                } else {
                    keptPreviousLine = false
                }
            case .deletion:
                if chosenLineIDs.contains(line.id) {
                    body.append(line.text)
                    oldCount += 1
                    hasChange = true
                    keptPreviousLine = true
                } else if direction == .apply {
                    body.append(" " + line.text.dropFirst())
                    oldCount += 1
                    newCount += 1
                    keptPreviousLine = true
                } else {
                    keptPreviousLine = false
                }
            case .metadata:
                if keptPreviousLine { body.append(line.text) }
            case .hunk:
                break
            }
        }
        guard hasChange else { return nil }

        let metadata = Self.partialMetadata(
            lines[..<firstHunk].map(\.text),
            oldCount: oldCount,
            newCount: newCount
        )
        let header = Self.hunkHeader(lines[start].text, oldCount: oldCount, newCount: newCount)
        let patch = (metadata + [header] + body).joined(separator: "\n") + "\n"
        return .init(id: hunkID, scope: scope, patch: Data(patch.utf8))
    }

    /// `@@ -12,7 +12,6 @@ func foo()` with both counts replaced; the starts and the trailing text stay.
    /// A whole-file patch that keeps some of its lines is no longer a whole-file patch. Leaving
    /// `new file mode` and `--- /dev/null` in place makes Git refuse it — `new file … depends on old
    /// contents` — because the header claims the old side is empty while the body has context lines.
    /// A partial delete is the same the other way round.
    static func partialMetadata(_ metadata: [String], oldCount: Int, newCount: Int) -> [String] {
        let keepsOldSide = oldCount > 0 && metadata.contains { $0.hasPrefix("--- /dev/null") }
        let keepsNewSide = newCount > 0 && metadata.contains { $0.hasPrefix("+++ /dev/null") }
        guard keepsOldSide || keepsNewSide else { return metadata }

        // The surviving side names the file; borrow that path for the side that was /dev/null.
        let newPath = metadata.first { $0.hasPrefix("+++ ") && !$0.hasPrefix("+++ /dev/null") }
            .map { String($0.dropFirst(4)) }
        let oldPath = metadata.first { $0.hasPrefix("--- ") && !$0.hasPrefix("--- /dev/null") }
            .map { String($0.dropFirst(4)) }

        return metadata.compactMap { line in
            if keepsOldSide, line.hasPrefix("new file mode ") { return nil }
            if keepsNewSide, line.hasPrefix("deleted file mode ") { return nil }
            if keepsOldSide, line.hasPrefix("--- /dev/null"), let newPath {
                return "--- " + (newPath.hasPrefix("b/") ? "a/" + newPath.dropFirst(2) : newPath[...])
            }
            if keepsNewSide, line.hasPrefix("+++ /dev/null"), let oldPath {
                return "+++ " + (oldPath.hasPrefix("a/") ? "b/" + oldPath.dropFirst(2) : oldPath[...])
            }
            return line
        }
    }

    static func hunkHeader(_ header: String, oldCount: Int, newCount: Int) -> String {
        let fields = header.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
        guard fields.count >= 3, fields[0] == "@@" else { return header }
        func start(_ field: Substring) -> Substring { field.split(separator: ",", maxSplits: 1)[0] }
        let trailing = fields.count > 3 ? " " + fields[3] : " @@"
        return "@@ \(start(fields[1])),\(oldCount) \(start(fields[2])),\(newCount)" + trailing
    }
}

enum RepositoryConflictSide: Hashable, Sendable {
    case ours
    case theirs

    var stage: Int {
        switch self {
        case .ours: 2
        case .theirs: 3
        }
    }

    var checkoutArgument: String {
        switch self {
        case .ours: "--ours"
        case .theirs: "--theirs"
        }
    }
}
