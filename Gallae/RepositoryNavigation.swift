import Foundation

enum RepositoryWorkspaceSection: Int, CaseIterable {
    case changes
    case history
    case stashes
    case reflog

    var title: String {
        switch self {
        case .changes: "Changes"
        case .history: "History"
        case .stashes: "Stashes"
        case .reflog: "Reflog"
        }
    }

    var systemImage: String {
        switch self {
        case .changes: "list.bullet"
        case .history: "clock"
        case .stashes: "archivebox"
        case .reflog: "arrow.uturn.backward"
        }
    }
}

/// A reference used either for Navigator selection or an explicit History filter.
/// The screen (Changes, History, Stashes, Reflog) is the other axis and lives in `RepositoryWorkspaceSection`.
enum RepositoryHistoryScope: Hashable {
    case branch(String)
    case remote(String)
    /// Remote-tracking name such as `origin/main`.
    case remoteBranch(String)
    case tag(String)

    var name: String {
        switch self {
        case .branch(let name), .remote(let name), .remoteBranch(let name), .tag(let name): name
        }
    }

    var kind: String {
        switch self {
        case .branch: "Local branch"
        case .remote: "Remote"
        case .remoteBranch: "Remote branch"
        case .tag: "Tag"
        }
    }

    var systemImage: String {
        switch self {
        case .branch, .remoteBranch: "arrow.triangle.branch"
        case .remote: "network"
        case .tag: "tag"
        }
    }

    /// Fully qualified so a tag and a branch sharing a name never resolve to each other; a remote reads every
    /// branch it tracks.
    var historyReference: String {
        switch self {
        case .branch(let name): "refs/heads/\(name)"
        case .tag(let name): "refs/tags/\(name)"
        case .remoteBranch(let name): "refs/remotes/\(name)"
        case .remote(let name): "--remotes=\(name)/"
        }
    }

    /// The remote this scope belongs to, if any.
    var remoteName: String? {
        switch self {
        case .remote(let name): name
        case .remoteBranch(let name): name.split(separator: "/", maxSplits: 1).first.map(String.init)
        case .branch, .tag: nil
        }
    }
}

/// The context bar's location label when the Navigator is folded: the screen, and for History its scope.
struct RepositoryNavigatorLocation {
    var screen: RepositoryWorkspaceSection
    var scope: RepositoryHistoryScope?

    var title: String {
        if screen == .history, let scope { "\(scope.name) · \(scope.kind)" } else { screen.title }
    }

    var systemImage: String {
        if screen == .history, let scope { scope.systemImage } else { screen.systemImage }
    }
}

enum RepositoryBranchIntegrationAction: Sendable {
    case fastForward
    case mergeCommit
    case rebase
}
