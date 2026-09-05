import Foundation

extension RepositoryInspector {
    func activity(in repository: RepositorySummary) async throws -> RepositoryActivity {
        try Task.checkCancellation()
        let activity = try await Task.detached(priority: .userInitiated) {
            try Self.activitySynchronously(in: repository)
        }.value
        try Task.checkCancellation()
        return activity
    }

    /// `reference` narrows the log to one fully qualified ref (`refs/heads/main`, `refs/tags/v1`); nil reads every ref.
    func history(
        in repository: RepositorySummary,
        reference: String? = nil,
        focusReference: String? = nil,
        limit: Int = maximumHistoryCommits
    ) async throws -> RepositoryHistory {
        try Task.checkCancellation()
        let history = try await Task.detached(priority: .userInitiated) {
            try Self.historySynchronously(in: repository, reference: reference, focusReference: focusReference, limit: limit)
        }.value
        try Task.checkCancellation()
        return history
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

    func commitSignature(
        for commit: RepositoryHistory.Commit,
        in repository: RepositorySummary
    ) async throws -> RepositoryCommitSignature {
        try Task.checkCancellation()
        let signature = try await Task.detached(priority: .userInitiated) {
            try Self.commitSignatureSynchronously(for: commit, in: repository)
        }.value
        try Task.checkCancellation()
        return signature
    }

    /// Tag names, newest tag first.
    func tags(in repository: RepositorySummary) async throws -> [String] {
        try Task.checkCancellation()
        let tags = try await Task.detached(priority: .userInitiated) {
            try Self.referenceNamesSynchronously(
                in: repository,
                pattern: "refs/tags",
                dropping: "refs/tags/",
                sort: "-creatordate"
            )
        }.value
        try Task.checkCancellation()
        return tags
    }

    /// Remote-tracking branch names of one remote, such as `origin/main`; the remote's `HEAD` alias is skipped.
    func remoteBranches(of remote: String, in repository: RepositorySummary) async throws -> [String] {
        try Task.checkCancellation()
        let branches = try await Task.detached(priority: .userInitiated) {
            try Self.referenceNamesSynchronously(
                in: repository,
                pattern: "refs/remotes/\(remote)/",
                dropping: "refs/remotes/",
                sort: "refname"
            )
            .filter { $0 != "\(remote)/HEAD" }
        }.value
        try Task.checkCancellation()
        return branches
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
        in repository: RepositorySummary,
        reference: String?,
        focusReference: String?,
        limit: Int
    ) throws -> RepositoryHistory {
        guard !repository.isUnborn else { return .init(commits: []) }

        let revisions: [String]
        if let reference {
            revisions = [reference, "--"]
        } else {
            // Detached Worktree commits have no branch ref, but still belong in the shared History.
            // Keep unrelated refs (such as refs/stash) out of this branch-and-tag graph.
            let detachedHeads = try worktreesSynchronously(in: repository)
                .filter { !$0.isBare && $0.branch == nil && $0.headID.contains(where: { $0 != "0" }) }
                .map(\.headID)
            revisions = ["--branches", "--remotes", "--tags", "HEAD"] + detachedHeads + ["--"]
        }
        var count = max(1, limit)
        var focusedCommitID: String?
        if let focusReference {
            let resolved = try runGit([
                "-C", repository.rootURL.path, "rev-parse", "--verify", "--end-of-options", "\(focusReference)^{commit}"
            ])
            guard resolved.status == 0 else { throw RepositoryHistoryError.unreadable(resolved.standardError) }
            let resolvedID = text(from: resolved.standardOutput).trimmingCharacters(in: .whitespacesAndNewlines)
            focusedCommitID = resolvedID
            // Locate an older tip without reading every commit's message. Preserve the same graph ordering.
            let ids = try runGit(["-C", repository.rootURL.path, "rev-list", "--topo-order"] + revisions)
            guard ids.status == 0 else { throw RepositoryHistoryError.unreadable(ids.standardError) }
            if let index = text(from: ids.standardOutput).split(separator: "\n").firstIndex(where: { $0 == resolvedID }) {
                count = max(count, index + 1)
            }
        }
        let result = try runGit([
            "-C", repository.rootURL.path,
            "log", "-\(count + 1)", "--topo-order", "-z", "--no-show-signature",
            "--format=%H%x00%P%x00%an%x00%ae%x00%ct%x00%s%x00%b"
        ] + revisions)
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
        return .init(
            commits: Array(commits.prefix(count)), headCommitID: referenceSnapshot.headCommitID,
            focusedCommitID: focusedCommitID, hasMoreCommits: commits.count > count
        )
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

    private static func commitSignatureSynchronously(
        for commit: RepositoryHistory.Commit,
        in repository: RepositorySummary
    ) throws -> RepositoryCommitSignature {
        let result = try runGit([
            "-C", repository.rootURL.path,
            "log", "-1", "--format=%G?%x00%GK%x00%GS", commit.id, "--"
        ])
        guard result.status == 0 else {
            throw RepositoryHistoryError.unreadable(result.standardError)
        }

        let fields = result.standardOutput
            .split(separator: 0, omittingEmptySubsequences: false)
            .map {
                String(decoding: $0, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        guard fields.count >= 3 else {
            return .none
        }
        return RepositoryCommitSignature.make(
            status: fields[0],
            keyID: fields[1],
            signer: fields[2]
        )
    }

    /// Reads full ref names under `pattern` and drops `prefix`; `refname:short` would rename a tag that
    /// shares its name with a branch to `tags/<name>` and a remote's `HEAD` alias to the bare remote name.
    private static func referenceNamesSynchronously(
        in repository: RepositorySummary,
        pattern: String,
        dropping prefix: String,
        sort: String
    ) throws -> [String] {
        let result = try runGit([
            "-C", repository.rootURL.path,
            "for-each-ref", "--format=%(refname)", "--sort=\(sort)", pattern
        ])
        guard result.status == 0 else {
            throw RepositoryReferenceError.unreadable(result.standardError)
        }
        return text(from: result.standardOutput)
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
            }
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
}
