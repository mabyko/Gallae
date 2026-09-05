import Foundation

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

    var gitArgument: String {
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

enum RepositoryReferenceError: LocalizedError, Equatable {
    case unreadable(String)

    var errorDescription: String? {
        "Git couldn’t read this Repository’s tags or remote branches."
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
    case trackingReferenceUnavailable
    case trackingReferenceRemovalFailed(String)

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
        case .trackingReferenceUnavailable:
            "The remote for this tracking reference is no longer configured. Reload the Repository and try again."
        case .trackingReferenceRemovalFailed(let message):
            message.isEmpty
                ? "Git couldn’t remove the tracking reference."
                : "Git couldn’t remove the tracking reference.\n\n\(message)"
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
        case .notWorkingTree(let reason):
            "The selected folder is not a Git working tree.\(Self.gitReason(reason))"
        case .bareRepository:
            "The selected folder is a bare Repository, which this version cannot open."
        case .unreadableHead(let reason):
            "The Repository exists, but its HEAD cannot be read.\(Self.gitReason(reason))"
        case .unreadableStatus(let reason):
            "The Repository exists, but its working tree status cannot be read.\(Self.gitReason(reason))"
        case .unreadableHistory(let reason):
            "The Repository exists, but its recent activity cannot be read.\(Self.gitReason(reason))"
        case .invalidGitOutput:
            "Git returned an unexpected Repository description."
        }
    }

    /// Git's own first line of stderr names the cause, and often the setting at fault — a malformed value in
    /// a gitconfig makes every command fail, and without this the reader is told only that reading failed.
    private static func gitReason(_ standardError: String) -> String {
        guard
            let line = standardError
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first?
                .trimmingCharacters(in: .whitespaces),
            !line.isEmpty
        else {
            return ""
        }
        return " Git said: \(line)"
    }
}

enum RepositoryTagCreationError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message.isEmpty ? "Git couldn’t create this tag." : message
        }
    }
}
