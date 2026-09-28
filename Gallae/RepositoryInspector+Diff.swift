import Foundation
import Darwin

struct RepositoryDiscardRecovery: Sendable, Identifiable {
    static let maximumFileBytes = 16 * 1024 * 1024
    static let scopeDescription = "Recovery is kept only for the latest discard of an existing regular file up to 16 MiB in this app session, outside an active Git operation. Restore requires a verified result and no later edits. Deleted files, symbolic links, and larger files cannot be restored."

    struct FileState: Equatable, Sendable {
        let contents: Data
        let permissions: UInt16
        let fileNumber: UInt64
        let modifiedAt: Date
    }

    let id = UUID()
    let rootURL: URL
    let path: String
    let head: RepositorySummary.Head
    let headID: Data?
    let indexEntry: Data
    let original: FileState
    let discarded: FileState?
}

enum RepositoryDiscardRecoveryError: LocalizedError {
    case changed
    case unreadable

    var errorDescription: String? {
        switch self {
        case .changed:
            "The file, branch, or staged version changed after the discard. Nothing was restored; the recovery copy is still kept for this app session."
        case .unreadable:
            "Gallae couldn’t safely save or read the discard recovery copy. The file has not been replaced."
        }
    }
}

extension RepositoryInspector {
    func files(
        for commit: RepositoryHistory.Commit,
        in repository: RepositorySummary
    ) async throws -> [RepositoryCommitFile] {
        try await CommandRunner.read {
            try Self.commitFilesSynchronously(for: commit, in: repository)
        }
    }

    func files(
        for stash: RepositoryStash,
        in repository: RepositorySummary
    ) async throws -> [RepositoryCommitFile] {
        try await CommandRunner.read {
            try Self.stashFilesSynchronously(for: stash, in: repository)
        }
    }

    func patch(
        for file: RepositoryCommitFile,
        in commit: RepositoryHistory.Commit,
        repository: RepositorySummary,
        maximumOutputBytes: Int? = maximumDisplayedDiffBytes
    ) async throws -> RepositoryCommitPatch {
        try await CommandRunner.read {
            try Self.patchSynchronously(
                for: file,
                in: commit,
                repository: repository,
                maximumOutputBytes: maximumOutputBytes
            )
        }
    }

    func patch(
        for file: RepositoryCommitFile,
        in stash: RepositoryStash,
        repository: RepositorySummary,
        maximumOutputBytes: Int? = maximumDisplayedDiffBytes
    ) async throws -> RepositoryCommitPatch {
        try await CommandRunner.read {
            try Self.stashPatchSynchronously(
                for: file,
                in: stash,
                repository: repository,
                maximumOutputBytes: maximumOutputBytes
            )
        }
    }

    func diff(
        for change: RepositorySummary.Change,
        in repository: RepositorySummary,
        maximumOutputBytes: Int? = maximumDisplayedDiffBytes
    ) async throws -> RepositoryDiff {
        try await CommandRunner.read {
            try Self.diffSynchronously(
                for: change,
                in: repository,
                maximumOutputBytes: maximumOutputBytes
            )
        }
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

    func discard(
        _ change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        _ = try await discardWithRecovery(change, in: repository)
        return try await inspect(at: repository.rootURL)
    }

    /// Reverses one working tree hunk, or the partial hunk of chosen lines, on disk. The index is not touched.
    func discard(
        _ hunk: RepositoryDiff.Hunk,
        for change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        _ = try await discardWithRecovery(change, hunk: hunk, in: repository)
        return try await inspect(at: repository.rootURL)
    }

    func discardWithRecovery(
        _ change: RepositorySummary.Change,
        hunk: RepositoryDiff.Hunk? = nil,
        in repository: RepositorySummary
    ) async throws -> RepositoryDiscardRecovery? {
        try Task.checkCancellation()
        return try await Task.detached(priority: .userInitiated) {
            guard change.canDiscardUnstagedChanges else { throw RepositoryDiscardError.unavailable }
            let rootURL = repository.rootURL.resolvingSymlinksInPath()
            let current = try Self.inspectSynchronously(at: rootURL)
            guard current.rootURL.resolvingSymlinksInPath() == rootURL,
                  current.head == repository.head, current.isUnborn == repository.isUnborn else {
                throw RepositoryDiscardRecoveryError.changed
            }
            let indexEntry = try Self.discardRecoveryGit(["ls-files", "--stage", "--", Self.literalPathspec(change.path)], at: rootURL)
            let original = try Self.discardRecoveryFile(path: change.path, rootURL: rootURL)
            let indexIsRegular = indexEntry.starts(with: Data("100644 ".utf8))
                || indexEntry.starts(with: Data("100755 ".utf8))
            let blobSize = indexIsRegular
                ? Int(String(decoding: try Self.discardRecoveryGit(["cat-file", "-s", ":\(change.path)"], at: rootURL), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
                : nil
            let canRecover = original != nil && indexIsRegular && current.operation == nil
                && blobSize.map { $0 <= RepositoryDiscardRecovery.maximumFileBytes } == true
            let headID = canRecover && !current.isUnborn
                ? try Self.discardRecoveryGit(["rev-parse", "--verify", "HEAD"], at: rootURL) : nil
            let expectedContents: Data?
            if canRecover, let original {
                expectedContents = try Self.expectedDiscardContents(original: original, hunk: hunk, path: change.path, rootURL: rootURL)
            } else {
                expectedContents = nil
            }
            // Check the saved file again immediately before Git modifies it.
            if let original, canRecover {
                guard try Self.discardRecoveryContextMatches(rootURL: rootURL, path: change.path, head: current.head, headID: headID, indexEntry: indexEntry),
                      try Self.discardRecoveryFile(path: change.path, rootURL: rootURL) == original else {
                    throw RepositoryDiscardRecoveryError.changed
                }
            }
            if let hunk {
                try Self.discardHunkSynchronously(hunk, for: change, in: repository)
            } else {
                try Self.discardSynchronously(change, in: repository)
            }
            guard canRecover, let original else { return nil }
            // Keep the original even if a concurrent edit makes the post-discard state unreadable.
            let observed = try? Self.discardRecoveryFile(path: change.path, rootURL: rootURL)
            let contextMatches = (try? Self.discardRecoveryContextMatches(rootURL: rootURL, path: change.path, head: current.head, headID: headID, indexEntry: indexEntry)) == true
            // A watcher/filter may write after Git. Never approve those new bytes as the restore baseline.
            let discarded = contextMatches && expectedContents != nil && observed?.contents == expectedContents
                ? observed : nil
            return RepositoryDiscardRecovery(
                rootURL: rootURL, path: change.path, head: repository.head,
                headID: headID, indexEntry: indexEntry, original: original, discarded: discarded
            )
        }.value
    }

    func restoreDiscard(_ recovery: RepositoryDiscardRecovery, in repository: RepositorySummary) async throws {
        try Task.checkCancellation()
        try await Task.detached(priority: .userInitiated) {
            guard let discarded = recovery.discarded,
                  repository.rootURL.resolvingSymlinksInPath() == recovery.rootURL else {
                throw RepositoryDiscardRecoveryError.changed
            }
            guard try Self.discardRecoveryContextMatches(rootURL: recovery.rootURL, path: recovery.path, head: recovery.head, headID: recovery.headID, indexEntry: recovery.indexEntry),
                  try Self.discardRecoveryFile(path: recovery.path, rootURL: recovery.rootURL) == discarded else {
                throw RepositoryDiscardRecoveryError.changed
            }
            let fileURL = recovery.rootURL.appending(path: recovery.path)
            let temporaryURL = fileURL.deletingLastPathComponent().appending(path: ".gallae-restore-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            try recovery.original.contents.write(to: temporaryURL, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: recovery.original.permissions], ofItemAtPath: temporaryURL.path)
            guard try Self.discardRecoveryContextMatches(rootURL: recovery.rootURL, path: recovery.path, head: recovery.head, headID: recovery.headID, indexEntry: recovery.indexEntry),
                  try Self.discardRecoveryFile(path: recovery.path, rootURL: recovery.rootURL) == discarded else {
                throw RepositoryDiscardRecoveryError.changed
            }
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL, options: .usingNewMetadataOnly)
        }.value
    }

    private static func discardRecoveryGit(_ arguments: [String], at rootURL: URL) throws -> Data {
        let result = try runGit(["-C", rootURL.path] + arguments)
        guard result.status == 0 else { throw RepositoryDiscardRecoveryError.unreadable }
        return result.standardOutput
    }

    private static func discardRecoveryContextMatches(
        rootURL: URL, path: String, head: RepositorySummary.Head, headID: Data?, indexEntry: Data
    ) throws -> Bool {
        let current = try inspectSynchronously(at: rootURL)
        guard current.rootURL.resolvingSymlinksInPath() == rootURL,
              current.head == head, current.operation == nil, current.isUnborn == (headID == nil) else { return false }
        if let headID, try discardRecoveryGit(["rev-parse", "--verify", "HEAD"], at: rootURL) != headID { return false }
        return try discardRecoveryGit(["ls-files", "--stage", "--", literalPathspec(path)], at: rootURL) == indexEntry
    }

    private static func expectedDiscardContents(
        original: RepositoryDiscardRecovery.FileState, hunk: RepositoryDiff.Hunk?, path: String, rootURL: URL
    ) throws -> Data? {
        if let hunk {
            let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: "Gallae-Discard-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temporaryRoot) }
            let fileURL = temporaryRoot.appending(path: path)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try original.contents.write(to: fileURL, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: original.permissions], ofItemAtPath: fileURL.path)
            let result = try runGit(["-C", temporaryRoot.path, "apply", "--reverse"], standardInput: hunk.patch)
            // Repository-specific conversions may make the isolated prediction unavailable.
            // Keep the existing discard command usable, but do not enable restoration without a prediction.
            guard result.status == 0 else { return nil }
            return try discardRecoveryFile(path: path, rootURL: temporaryRoot)?.contents
        }
        // Git performs the same smudge/EOL conversion used by restore; raw index bytes are insufficient.
        let result = try runGit(["-C", rootURL.path, "cat-file", "--filters", ":\(path)"],
                                maximumOutputBytes: RepositoryDiscardRecovery.maximumFileBytes)
        guard result.status == 0 else { throw RepositoryDiscardRecoveryError.unreadable }
        return result.standardOutputExceededLimit ? nil : result.standardOutput
    }

    private static func discardRecoveryFile(path: String, rootURL: URL) throws -> RepositoryDiscardRecovery.FileState? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw RepositoryDiscardRecoveryError.unreadable
        }
        var url = rootURL
        for component in components.dropLast() {
            url.append(path: String(component))
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw RepositoryDiscardRecoveryError.unreadable
            }
        }
        url.append(path: String(components.last!))
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.intValue <= RepositoryDiscardRecovery.maximumFileBytes else { return nil }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw RepositoryDiscardRecoveryError.unreadable }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0,
              opened.st_mode & S_IFMT == S_IFREG,
              (attributes[.systemFileNumber] as? NSNumber)?.uint64Value == UInt64(opened.st_ino),
              (attributes[.systemNumber] as? NSNumber)?.int32Value == opened.st_dev else {
            throw RepositoryDiscardRecoveryError.changed
        }
        let contents = try file.read(upToCount: RepositoryDiscardRecovery.maximumFileBytes + 1) ?? Data()
        guard contents.count == size.intValue,
              let permissions = attributes[.posixPermissions] as? NSNumber,
              let fileNumber = attributes[.systemFileNumber] as? NSNumber,
              let modifiedAt = attributes[.modificationDate] as? Date else {
            throw RepositoryDiscardRecoveryError.unreadable
        }
        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        var finished = stat()
        guard after[.type] as? FileAttributeType == .typeRegular,
              fstat(descriptor, &finished) == 0,
              finished.st_size == opened.st_size, finished.st_mode == opened.st_mode,
              finished.st_mtimespec.tv_sec == opened.st_mtimespec.tv_sec,
              finished.st_mtimespec.tv_nsec == opened.st_mtimespec.tv_nsec,
              after[.systemFileNumber] as? NSNumber == fileNumber,
              after[.modificationDate] as? Date == modifiedAt,
              after[.size] as? NSNumber == size else {
            throw RepositoryDiscardRecoveryError.changed
        }
        return .init(contents: contents, permissions: permissions.uint16Value,
                     fileNumber: fileNumber.uint64Value, modifiedAt: modifiedAt)
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
        })).map(literalPathspec)
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
        })).map(literalPathspec)
        let command = repository.isUnborn
            ? ["rm", "--cached", "--force", "--ignore-unmatch", "--"]
            : ["restore", "--staged", "--"]
        let result = try runGit(["-C", repository.rootURL.path] + command + paths)
        guard result.status == 0 else {
            throw RepositoryIndexError.gitFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }

    private static func discardHunkSynchronously(
        _ hunk: RepositoryDiff.Hunk,
        for change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) throws {
        guard !change.isConflicted, change.unstaged == .modified, hunk.scope == .unstaged else {
            throw RepositoryDiscardError.unavailable
        }
        let result = try runGit(
            ["-C", repository.rootURL.path, "apply", "--reverse"],
            standardInput: hunk.patch
        )
        guard result.status == 0 else {
            throw RepositoryDiscardError.gitFailed(result.standardError)
        }
    }

    private static func discardSynchronously(
        _ change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) throws {
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
    }

    private static func updateIndexSynchronously(
        with hunk: RepositoryDiff.Hunk,
        for change: RepositorySummary.Change,
        in repository: RepositorySummary,
        reverse: Bool
    ) throws -> RepositorySummary {
        let expectedScope: RepositoryDiff.Scope = reverse ? .staged : .unstaged
        let expectedState = reverse ? change.staged : change.unstaged
        // An untracked file's diff is a new-file patch; applying part of it adds the file to the index with
        // only the chosen lines, and the rest stays as a working tree modification.
        let stagesUntracked = !reverse && hunk.scope == .untracked && change.unstaged == .untracked
        // The mirror of that: part of a newly added file can be taken back out of the index.
        // `partialMetadata` has already rewritten the patch so it no longer claims to create the file.
        let unstagesAdded = reverse && change.staged == .added && hunk.scope == .staged
        guard
            !change.isConflicted,
            stagesUntracked || unstagesAdded || (expectedState == .modified && hunk.scope == expectedScope)
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
        var arguments = ["-C", repository.rootURL.path]
            + pinnedDiffConfiguration
            + ["show", "--format="]
            + pinnedDiffOptions
            + [
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
        var arguments = ["-C", repository.rootURL.path]
            + pinnedDiffConfiguration
            + ["diff", "--patch"]
            + pinnedDiffOptions
            + [
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
            arguments = ["-C", rootURL.path]
                + pinnedDiffConfiguration
                + ["diff", "--no-index"]
                + pinnedDiffOptions
                + ["--", "/dev/null", change.path]
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

    static func conflictStageObjectIDs(from data: Data) -> [Int: String] {
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
        var arguments = ["-C", rootURL.path]
            + pinnedDiffConfiguration
            + ["diff"]
            + pinnedDiffOptions
            + ["--find-renames"]
        arguments.append(contentsOf: options)
        arguments.append("--")
        arguments.append(literalPathspec(change.path))
        if let originalPath = change.originalPath {
            arguments.append(literalPathspec(originalPath))
        }
        return arguments
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
}
