import Foundation

extension RepositoryInspector {
    func localBranchWorktrees(in repository: RepositorySummary) async throws -> [String: URL] {
        try Task.checkCancellation()
        let worktrees = try await Task.detached(priority: .userInitiated) {
            try Self.localBranchWorktreesSynchronously(in: repository)
        }.value
        try Task.checkCancellation()
        return worktrees
    }

    func worktrees(in repository: RepositorySummary) async throws -> [RepositoryWorktree] {
        try Task.checkCancellation()
        let result = try await Task.detached(priority: .userInitiated) {
            try Self.worktreesSynchronously(in: repository)
        }.value
        try Task.checkCancellation()
        return result
    }

    func createWorktree(
        at destination: URL, branch: String, creatingBranch: Bool,
        startPoint: String = "HEAD", in repository: RepositorySummary
    ) async throws -> URL {
        try Task.checkCancellation()
        // Once Git has created the folder, report success even if the presenting view is dismissed.
        return try await Task.detached(priority: .userInitiated) {
            guard destination.isFileURL, !FileManager.default.fileExists(atPath: destination.path) else {
                throw RepositoryBranchError.worktreeCreationFailed("Choose a new folder. Existing paths will not be overwritten.")
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw RepositoryBranchError.worktreeCreationFailed("Choose an existing parent folder.")
            }
            guard !branch.isEmpty, !branch.contains("\0"), !startPoint.contains("\0"), !branch.hasPrefix("-"), branch != "HEAD",
                  try Self.runGit(["check-ref-format", "--branch", branch]).status == 0 else {
                throw RepositoryBranchError.worktreeCreationFailed("Enter a valid local branch name.")
            }
            let branches = try Self.localBranchesSynchronously(in: repository)
            var arguments = ["-C", repository.rootURL.path, "worktree", "add", "--quiet"]
            let target: String
            if creatingBranch {
                guard !branches.contains(branch) else {
                    throw RepositoryBranchError.worktreeCreationFailed("A branch named \(branch) already exists.")
                }
                let revision = try Self.runGit(["-C", repository.rootURL.path, "rev-parse", "--verify", "--end-of-options", "\(startPoint)^{commit}"])
                guard revision.status == 0 else {
                    throw RepositoryBranchError.worktreeCreationFailed("Choose an existing commit as the starting point.")
                }
                target = String(decoding: revision.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                arguments += ["-b", branch]
            } else {
                guard branches.contains(branch) else { throw RepositoryBranchError.unavailable }
                guard try !Self.worktreesSynchronously(in: repository).contains(where: { $0.branch == branch }) else {
                    throw RepositoryBranchError.worktreeCreationFailed("This branch already has a Worktree. Open that folder instead.")
                }
                target = branch
            }
            arguments += ["--", destination.path, target]
            let result = try Self.runGit(arguments)
            guard result.status == 0 else { throw RepositoryBranchError.worktreeCreationFailed(result.standardError) }
            return destination.standardizedFileURL
        }.value
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

    static func localBranchWorktreesSynchronously(
        in repository: RepositorySummary
    ) throws -> [String: URL] {
        RepositoryWorktree.branchURLs(in: try worktreesSynchronously(in: repository))
    }

    static func worktreesSynchronously(in repository: RepositorySummary) throws -> [RepositoryWorktree] {
        let result = try runGit(["-C", repository.rootURL.path, "worktree", "list", "--porcelain", "-z"])
        guard result.status == 0 else { throw RepositoryBranchError.unreadable(result.standardError) }
        return parseWorktrees(result.standardOutput)
    }

    static func parseWorktrees(_ data: Data) -> [RepositoryWorktree] {
        var result: [RepositoryWorktree] = []
        var url: URL?
        var headID = ""
        var branch: String?
        var isBare = false
        var locked: String?
        var prunable: String?
        func record() {
            guard let url else { return }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            result.append(RepositoryWorktree(
                url: url, headID: headID, branch: branch, isPrimary: result.isEmpty,
                isBare: isBare, lockedReason: locked, prunableReason: prunable,
                isAvailable: exists && isDirectory.boolValue
            ))
        }
        for bytes in data.split(separator: 0) {
            let field = String(decoding: bytes, as: UTF8.self)
            if field.hasPrefix("worktree ") {
                record()
                url = URL(filePath: String(field.dropFirst(9)), directoryHint: .isDirectory).standardizedFileURL
                headID = ""
                branch = nil
                isBare = false
                locked = nil
                prunable = nil
            } else if field.hasPrefix("HEAD ") { headID = String(field.dropFirst(5)) }
            else if field.hasPrefix("branch refs/heads/") { branch = String(field.dropFirst(18)) }
            else if field == "bare" { isBare = true }
            else if field == "locked" { locked = "" }
            else if field.hasPrefix("locked ") { locked = String(field.dropFirst(7)) }
            else if field == "prunable" { prunable = "" }
            else if field.hasPrefix("prunable ") { prunable = String(field.dropFirst(9)) }
        }
        record()
        return result
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

    private static func removeWorktreeSynchronously(
        at worktreeURL: URL,
        in repository: RepositorySummary
    ) throws -> RepositorySummary {
        guard let worktree = try worktreesSynchronously(in: repository).first(where: {
            sameFileLocation($0.url.resolvingSymlinksInPath(), worktreeURL.resolvingSymlinksInPath())
        }) else { throw RepositoryBranchError.worktreeRemovalFailed("This Worktree is no longer registered.") }
        if let restriction = worktree.removalRestriction(currentURL: repository.rootURL) {
            throw RepositoryBranchError.worktreeRemovalFailed(restriction)
        }
        let result = try runGit([
            "-C", repository.rootURL.path,
            "worktree", "remove", worktree.url.path
        ])
        guard result.status == 0 else {
            throw RepositoryBranchError.worktreeRemovalFailed(result.standardError)
        }
        return try inspectSynchronously(at: repository.rootURL)
    }
}
