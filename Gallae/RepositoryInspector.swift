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
    }

    let rootURL: URL
    let head: Head
    let isUnborn: Bool
    let upstream: Upstream?
    let changes: [Change]

    var name: String {
        rootURL.lastPathComponent
    }
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

struct RepositoryDiff: Equatable, Sendable {
    enum Scope: Equatable, Hashable, Sendable {
        case staged
        case unstaged
        case untracked
        case conflict
    }

    struct Section: Equatable, Identifiable, Sendable {
        enum Content: Equatable, Sendable {
            case text([Line])
            case binary
            case unsupportedEncoding
            case tooLarge(byteLimit: Int)
            case unavailable(String)
        }

        let scope: Scope
        let content: Content

        var id: Scope { scope }
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

    let path: String
    let originalPath: String?
    let sections: [Section]
}

struct RepositoryInspector: Sendable {
    static let maximumDisplayedDiffBytes = 2 * 1_024 * 1_024
    static let maximumExpandedDiffBytes = 16 * 1_024 * 1_024

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

    private static func inspectSynchronously(at selectedURL: URL) throws -> RepositorySummary {
        let rootURL = try workingTreeRoot(at: selectedURL)

        let statusResult = try runGit([
            "-C", rootURL.path,
            "status", "--porcelain=v2", "--branch", "--null", "--untracked-files=all", "--renames"
        ])
        guard statusResult.status == 0 else {
            throw RepositoryInspectionError.unreadableStatus(statusResult.standardError)
        }

        return try parseStatus(statusResult.standardOutput, rootURL: rootURL)
    }

    static func workingTreeRoot(at selectedURL: URL) throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: gitURL.path) else {
            throw RepositoryInspectionError.gitUnavailable
        }

        let bareResult = try runGit(["-C", selectedURL.path, "rev-parse", "--is-bare-repository"])
        guard bareResult.status == 0 else {
            throw RepositoryInspectionError.notWorkingTree(bareResult.standardError)
        }

        switch text(from: bareResult.standardOutput).trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true":
            throw RepositoryInspectionError.bareRepository
        case "false":
            break
        default:
            throw RepositoryInspectionError.invalidGitOutput
        }

        let rootResult = try runGit(["-C", selectedURL.path, "rev-parse", "--show-toplevel"])
        guard rootResult.status == 0 else {
            throw RepositoryInspectionError.notWorkingTree(rootResult.standardError)
        }

        let rootPath = line(from: rootResult.standardOutput)
        guard !rootPath.isEmpty else {
            throw RepositoryInspectionError.invalidGitOutput
        }

        return URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
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

    private static func diffSynchronously(
        for change: RepositorySummary.Change,
        in repository: RepositorySummary,
        maximumOutputBytes: Int?
    ) throws -> RepositoryDiff {
        var sections: [RepositoryDiff.Section] = []

        if change.isConflicted {
            sections.append(try makeDiffSection(
                scope: .conflict,
                change: change,
                rootURL: repository.rootURL,
                maximumOutputBytes: maximumOutputBytes
            ))
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
        case .conflict:
            arguments = trackedDiffArguments(
                rootURL: rootURL,
                options: ["--cc"],
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

    private static func runGit(
        _ arguments: [String],
        maximumOutputBytes: Int? = nil
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
        defer {
            try? standardOutput.close()
            try? standardError.close()
        }

        process.executableURL = gitURL
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["LC_ALL"] = "C"
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw RepositoryInspectionError.gitUnavailable
        }

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

    private static func parseStatus(_ data: Data, rootURL: URL) throws -> RepositorySummary {
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

        return RepositorySummary(
            rootURL: rootURL,
            head: head,
            isUnborn: branchOID == "(initial)",
            upstream: upstream,
            changes: changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
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
