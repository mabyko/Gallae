import Foundation

extension RepositoryInspector {
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
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.discardSynchronously(change, in: repository)
        }.value
        try Task.checkCancellation()
        return updatedRepository
    }

    /// Reverses one working tree hunk, or the partial hunk of chosen lines, on disk. The index is not touched.
    func discard(
        _ hunk: RepositoryDiff.Hunk,
        for change: RepositorySummary.Change,
        in repository: RepositorySummary
    ) async throws -> RepositorySummary {
        try Task.checkCancellation()
        let updatedRepository = try await Task.detached(priority: .userInitiated) {
            try Self.discardHunkSynchronously(hunk, for: change, in: repository)
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
    ) throws -> RepositorySummary {
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
