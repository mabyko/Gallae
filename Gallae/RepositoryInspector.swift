import Foundation

struct RepositoryInspector: Sendable {
    static let maximumDisplayedDiffBytes = 2 * 1_024 * 1_024
    static let maximumExpandedDiffBytes = 16 * 1_024 * 1_024
    static let maximumHistoryCommits = 100

    private static let gitURL = CommandRunner.gitURL

    /// Git's patch output is what Gallae parses, and for the working tree it is fed straight back to
    /// `git apply`. A user's diff configuration can change that text enough to break both, so every patch is
    /// produced with the format pinned. Settings that define what a file's content *is* — `core.autocrlf`,
    /// `.gitattributes` — are deliberately left alone. See `docs/git-configuration.md`.
    static let pinnedDiffConfiguration = [
        // Escapes non-ASCII paths as octal, which only ever reaches the reader as noise.
        "-c", "core.quotepath=false",
        // Writes a blank context line with no leading space, which stops the parser counting it.
        "-c", "diff.suppressBlankEmpty=false"
    ]

    /// `--src-prefix`/`--dst-prefix` rather than `--default-prefix`: they override `diff.noprefix`,
    /// `diff.mnemonicPrefix`, `diff.srcPrefix` and `diff.dstPrefix` just the same, and predate Git 2.45.
    /// Zero context (`diff.context = 0`) makes `git apply` reject the patch, so the width is pinned too.
    static let pinnedDiffOptions = [
        "--no-color", "--no-ext-diff", "--no-textconv",
        "--src-prefix=a/", "--dst-prefix=b/",
        "--diff-algorithm=histogram", "--unified=3"
    ]

    func inspect(at selectedURL: URL) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let repository = try await Task.detached(priority: .userInitiated) {
            try Self.inspectSynchronously(at: selectedURL)
        }.value
        try Task.checkCancellation()
        return repository
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

    func trackingBranch(
        of branch: String,
        in repository: RepositorySummary
    ) async throws -> String? {
        try Task.checkCancellation()
        let trackingRef = try await Task.detached(priority: .userInitiated) {
            try Self.trackingBranchSynchronously(of: branch, in: repository)
        }.value
        try Task.checkCancellation()
        return trackingRef
    }

    func deleteRemoteBranch(
        trackingRef: String,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        let cancellation = GitProcessCancellation()
        return try await withTaskCancellationHandler {
            do {
                let updatedRepository = try await Task.detached(priority: .userInitiated) {
                    try Self.deleteRemoteBranchSynchronously(
                        trackingRef: trackingRef,
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

    func removeRemoteTrackingReference(
        _ trackingRef: String,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.removeRemoteTrackingReferenceSynchronously(trackingRef, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
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

    func addRemote(named name: String, url: String, in repository: RepositorySummary) async throws -> RepositorySummary {
        try Task.checkCancellation()
        return try await Task.detached(priority: .userInitiated) {
            try Self.addRemoteSynchronously(named: name, url: url, in: repository)
            return try Self.inspectSynchronously(at: repository.rootURL)
        }.value
    }

    func createTag(named name: String, at target: String, in repository: RepositorySummary) async throws -> RepositorySummary {
        try Task.checkCancellation()
        return try await Task.detached(priority: .userInitiated) {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.hasPrefix("-"), !target.isEmpty else {
                throw RepositoryTagCreationError.failed("Enter a tag name and target commit.")
            }
            let resolved = try Self.runGit(["-C", repository.rootURL.path, "rev-parse", "--verify", "--end-of-options", "\(target)^{commit}"])
            guard resolved.status == 0 else { throw RepositoryTagCreationError.failed(resolved.standardError) }
            // --no-sign explicitly creates a lightweight tag, including when tag.gpgSign is enabled.
            let result = try Self.runGit(["-C", repository.rootURL.path, "tag", "--no-sign", "--", name, Self.line(from: resolved.standardOutput)])
            guard result.status == 0 else { throw RepositoryTagCreationError.failed(result.standardError) }
            return try Self.inspectSynchronously(at: repository.rootURL)
        }.value
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

    func openMergeTool(
        for change: RepositorySummary.Change,
        in repository: RepositorySummary,
        tool: MergeTool,
        executableURL: URL? = nil
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        // Keep exported versions alive until the external editor has closed them.
        return try await Task.detached(priority: .userInitiated) {
            try Self.openMergeToolSynchronously(for: change, in: repository, tool: tool, executableURL: executableURL)
        }.value
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

    private static func openMergeToolSynchronously(
        for change: RepositorySummary.Change,
        in repository: RepositorySummary,
        tool: MergeTool,
        executableURL: URL?
    ) throws -> RepositorySummary {
        let current = try inspectSynchronously(at: repository.rootURL)
        guard current.changes.contains(where: { $0.path == change.path && $0.isConflicted }) else {
            throw RepositoryConflictResolutionError.unavailable
        }
        let merged = repository.rootURL.appending(path: change.path)
        let root = repository.rootURL.resolvingSymlinksInPath().path + "/"
        let attributes = try? FileManager.default.attributesOfItem(atPath: merged.path)
        guard merged.resolvingSymlinksInPath().path.hasPrefix(root),
              attributes?[.type] as? FileAttributeType == .typeRegular else {
            throw RepositoryConflictResolutionError.gitFailed("This conflict has no regular working file. Use Ours, Use Theirs, or resolve it in a terminal.")
        }
        let entries = try runGit(["-C", repository.rootURL.path, "ls-files", "--stage", "-z", "--", literalPathspec(change.path)])
        guard entries.status == 0 else { throw RepositoryConflictResolutionError.gitFailed(entries.standardError) }
        let records = entries.standardOutput.split(separator: 0)
        let objectIDs = conflictStageObjectIDs(from: entries.standardOutput)
        guard objectIDs[2] != nil, objectIDs[3] != nil,
              records.allSatisfy({ $0.starts(with: Data("100644 ".utf8)) || $0.starts(with: Data("100755 ".utf8)) }) else {
            throw RepositoryConflictResolutionError.gitFailed("External merging supports regular files present on both sides. Resolve deletions, symbolic links, and submodules with the file actions or in a terminal.")
        }

        if tool == .git {
            // Do not let Git guess a terminal tool in an app with no interactive stdin.
            var name = ""
            for key in ["merge.guitool", "merge.tool"] {
                let config = try runGit(["-C", repository.rootURL.path, "config", "--get", key])
                guard config.status == 0 || config.status == 1 else {
                    throw RepositoryConflictResolutionError.gitFailed(config.standardError)
                }
                name = line(from: config.standardOutput)
                if !name.isEmpty { break }
            }
            guard !name.isEmpty else {
                throw RepositoryConflictResolutionError.gitFailed("No Git merge tool is configured. Choose VS Code or Sublime Merge in Settings → General, or configure merge.guitool / merge.tool in Git.")
            }
            let result = try runGit([
                "-C", repository.rootURL.path, "mergetool", "--no-prompt", "--tool=\(name)", "--", literalPathspec(change.path)
            ], standardInput: Data())
            guard result.status == 0 else {
                throw RepositoryConflictResolutionError.gitFailed("The Git merge tool did not complete. If it requires terminal input, run it in a terminal.\n\n\(result.standardError)")
            }
        } else {
            guard let executableURL, executableURL.isFileURL,
                  FileManager.default.isExecutableFile(atPath: executableURL.path) else {
                throw RepositoryConflictResolutionError.gitFailed("\(tool.title) is not installed. Choose another Merge Tool in Settings → General.")
            }
            let temporary = FileManager.default.temporaryDirectory.appending(path: "Gallae-Merge-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: temporary) }
            var versions: [URL] = []
            for (stage, label) in [(1, "Base"), (2, "Ours"), (3, "Theirs")] {
                let directory = temporary.appending(path: label)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                let url = directory.appending(path: merged.lastPathComponent)
                var data = Data()
                if let objectID = objectIDs[stage] {
                    let result = try runGit(["-C", repository.rootURL.path, "cat-file", "--filters", "--path=\(change.path)", objectID])
                    guard result.status == 0 else { throw RepositoryConflictResolutionError.gitFailed(result.standardError) }
                    data = result.standardOutput
                }
                guard !data.contains(0), String(data: data, encoding: .utf8) != nil else {
                    throw RepositoryConflictResolutionError.gitFailed("This merge tool integration supports UTF-8 text files. Resolve this file using the file actions or in a terminal.")
                }
                try data.write(to: url)
                versions.append(url)
            }
            let result = try CommandRunner.run(
                tool.arguments(base: versions[0], ours: versions[1], theirs: versions[2], merged: merged),
                executableURL: executableURL, currentDirectoryURL: repository.rootURL, standardInput: Data()
            )
            guard result.status == 0 else {
                throw RepositoryConflictResolutionError.gitFailed("\(tool.title) closed without reporting success. Review the file before marking it resolved.\n\n\(result.standardError)")
            }
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
        guard let operation = currentRepository.operation,
              let confirmedOperation = repository.operation,
              operation.identity == confirmedOperation.identity else {
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

    static func localBranchesSynchronously(
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

    private static func trackingBranchSynchronously(
        of branch: String,
        in repository: RepositorySummary
    ) throws -> String? {
        let result = try runGit([
            "-C", repository.rootURL.path,
            "for-each-ref", "--format=%(upstream:short)", "refs/heads/\(branch)"
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.unreadable(result.standardError)
        }
        let trackingRef = line(from: result.standardOutput)
        return trackingRef.isEmpty ? nil : trackingRef
    }

    // remote 이름은 configured 목록과 가장 길게 일치하는 접두사로 해석해
    // 이름에 `/`가 든 branch도 정확히 나눈다.
    private static func resolveTrackingReference(
        _ trackingRef: String,
        in repository: RepositorySummary
    ) throws -> (remote: String, branch: String) {
        let remotesResult = try runGit([
            "-C", repository.rootURL.path,
            "remote"
        ])
        guard remotesResult.status == 0 else {
            throw RepositoryBranchError.unreadable(remotesResult.standardError)
        }
        let remotes = text(from: remotesResult.standardOutput)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard
            let remote = remotes
                .filter({ trackingRef.hasPrefix($0 + "/") })
                .max(by: { $0.count < $1.count })
        else {
            throw RepositoryBranchError.trackingReferenceUnavailable
        }
        let branch = String(trackingRef.dropFirst(remote.count + 1))
        guard !branch.isEmpty else {
            throw RepositoryBranchError.trackingReferenceUnavailable
        }
        return (remote, branch)
    }

    private static func deleteRemoteBranchSynchronously(
        trackingRef: String,
        in repository: RepositorySummary,
        cancellation: GitProcessCancellation
    ) throws -> RepositorySummary {
        let (remote, branch) = try resolveTrackingReference(trackingRef, in: repository)
        let result = try runGit([
            "-C", repository.rootURL.path,
            "push", "--quiet", remote, "--delete", branch
        ], cancellation: cancellation)
        if cancellation.isCancelled {
            throw CancellationError()
        }
        guard result.status == 0 else {
            throw RepositoryPushError.failed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func removeRemoteTrackingReferenceSynchronously(
        _ trackingRef: String,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        let result = try runGit([
            "-C", repository.rootURL.path,
            "branch", "--delete", "--remotes", "--", trackingRef
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.trackingReferenceRemovalFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
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
        guard currentRepository.operation == nil else {
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
            // A normal conflict is an unfinished merge, not a failed operation to roll back.
            if let conflicted = try? inspectSynchronously(at: repository.rootURL),
               conflicted.operation?.kind == .merge,
               conflicted.changes.contains(where: \.isConflicted) {
                return conflicted
            }
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

    private static func addRemoteSynchronously(
        named name: String,
        url: String,
        in repository: RepositorySummary,
        cancellation: GitProcessCancellation? = nil
    ) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("-"), !url.isEmpty else {
            throw RepositoryRemoteSetupError.invalidInput
        }

        let addResult = try runGit([
            "-C", repository.rootURL.path,
            "remote", "add", name, url
        ], cancellation: cancellation)
        if cancellation?.isCancelled == true {
            throw CancellationError()
        }
        guard addResult.status == 0 else {
            throw RepositoryRemoteSetupError.addFailed(addResult.standardError)
        }

    }

    private static func addRemoteAndPublishSynchronously(
        named name: String,
        url: String,
        in repository: RepositorySummary,
        cancellation: GitProcessCancellation
    ) throws -> RepositorySummary {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try addRemoteSynchronously(named: name, url: url, in: repository, cancellation: cancellation)

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

    static func inspectSynchronously(at selectedURL: URL) throws -> RepositorySummary {
        let rootURL = try workingTreeRoot(at: selectedURL)

        let statusResult = try runGit([
            "-C", rootURL.path,
            "status", "--porcelain=v2", "--branch", "--null", "--untracked-files=all", "--renames"
        ])
        guard statusResult.status == 0 else {
            throw RepositoryInspectionError.unreadableStatus(statusResult.standardError)
        }

        let operationIdentity = try operationIdentitySynchronously(in: rootURL)
        return try parseStatus(
            statusResult.standardOutput,
            rootURL: rootURL,
            operationIdentity: operationIdentity
        )
    }

    private static func operationIdentitySynchronously(
        in rootURL: URL
    ) throws -> RepositorySummary.Operation.Identity? {
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
        // Rebase's directory survives Continue; a new operation creates a new marker.
        // Conflict count and modification time change during normal resolution.
        let markerPath = paths.dropFirst().first(where: FileManager.default.fileExists(atPath:))
            ?? (FileManager.default.fileExists(atPath: paths[0]) ? paths[0] : nil)
        guard let markerPath else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: markerPath)
        guard let fileNumber = attributes[.systemFileNumber] as? NSNumber,
              let creationDate = attributes[.creationDate] as? Date else {
            throw RepositoryInspectionError.invalidGitOutput
        }
        return .init(
            kind: markerPath == paths[0] ? .merge : .rebase,
            markerURL: URL(fileURLWithPath: markerPath),
            fileNumber: fileNumber.uint64Value,
            creationDate: creationDate
        )
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

    private static func interactiveRebasePlanSynchronously(
        startingAt commit: RepositoryHistory.Commit,
        in repository: RepositorySummary
    ) throws -> RepositoryInteractiveRebasePlan {
        let currentRepository = try inspectSynchronously(at: repository.rootURL)
        guard
            case .branch(let branch) = currentRepository.head,
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

        return .init(
            rootURL: currentRepository.rootURL,
            branch: branch,
            headID: headID,
            startingCommitID: commit.id,
            steps: stride(from: 0, to: fields.count, by: 2).map { index in
                .init(
                    id: String(decoding: fields[index], as: UTF8.self),
                    subject: String(decoding: fields[index + 1], as: UTF8.self)
                )
            }
        )
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
            sameFileLocation(plan.rootURL, currentPlan.rootURL),
            plan.branch == currentPlan.branch,
            plan.headID == currentPlan.headID,
            plan.startingCommitID == currentPlan.startingCommitID,
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

        let originalHead = currentPlan.headID

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

    static func literalPathspec(_ path: String) -> String {
        ":(literal)\(path)"
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func runGit(
        _ arguments: [String],
        maximumOutputBytes: Int? = nil,
        standardInput: Data? = nil,
        cancellation: GitProcessCancellation? = nil,
        additionalEnvironment: [String: String] = [:]
    ) throws -> GitResult {
        try CommandRunner.run(arguments, executableURL: gitURL, maximumOutputBytes: maximumOutputBytes,
                       standardInput: standardInput, cancellation: cancellation, additionalEnvironment: additionalEnvironment)
    }

    private static func parseStatus(
        _ data: Data,
        rootURL: URL,
        operationIdentity: RepositorySummary.Operation.Identity?
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

        let operation = operationIdentity.map {
            RepositorySummary.Operation(
                identity: $0,
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

    static func state(from value: Character) throws -> RepositorySummary.Change.State? {
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

    static func text(from data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    static func line(from data: Data) -> String {
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
