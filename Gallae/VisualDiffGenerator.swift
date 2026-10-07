import Foundation

/// The same comparison the reader is reviewing, including the app's refresh generation.
struct VisualDiffRequest: Equatable, Sendable {
    enum Comparison: Equatable, Sendable {
        case workingTree, staged
        case commit(RepositoryHistory.Commit)
        case stash(RepositoryStash)
    }
    let repository: RepositorySummary
    var comparison: Comparison
    let revision: Int
}

enum VisualDiffGenerator {
    struct File: Sendable {
        let path: String
        let originalPath: String?
        let state: RepositorySummary.Change.State
        let content: RepositoryDiff.Section.Content
    }

    enum GenerationError: LocalizedError {
        case empty, tooManyFiles
        var errorDescription: String? {
            switch self {
            case .empty: "There are no changed files in this comparison. Return to Diff to choose another comparison."
            case .tooManyFiles: "This comparison has more than 256 files. The local diagram supports up to 256 changed files."
            }
        }
    }

    static func generate(_ request: VisualDiffRequest) async throws -> VisualDiffDocument {
        let inspector = RepositoryInspector()
        let repository = request.repository
        var files: [File] = []
        let label: String
        let base: String
        let head: String
        switch request.comparison {
        case .workingTree, .staged:
            let staged = request.comparison == .staged
            label = staged ? "Staged Changes" : "Working Tree Changes"
            base = staged ? "HEAD" : "Index"
            head = staged ? "Index" : "Working tree"
            let changes = repository.changes.filter { !$0.isConflicted && (staged ? $0.staged != nil : $0.unstaged != nil) }
            guard changes.count <= 256 else { throw GenerationError.tooManyFiles }
            for change in changes {
                try Task.checkCancellation()
                let diff = try await inspector.diff(for: change, in: repository, maximumOutputBytes: 128 * 1024)
                let scope: RepositoryDiff.Scope = staged ? .staged : (change.unstaged == .untracked ? .untracked : .unstaged)
                guard let content = diff.sections.first(where: { $0.scope == scope })?.content else { continue }
                files.append(.init(path: change.path, originalPath: change.originalPath,
                                   state: (staged ? change.staged : change.unstaged)!, content: content))
            }
        case .commit(let commit):
            label = "Commit \(commit.id.prefix(8))"
            base = commit.parentIDs.first ?? "Empty tree"
            head = commit.id
            let changes = try await inspector.files(for: commit, in: repository)
            guard changes.count <= 256 else { throw GenerationError.tooManyFiles }
            for file in changes {
                try Task.checkCancellation()
                let patch = try await inspector.patch(for: file, in: commit, repository: repository, maximumOutputBytes: 128 * 1024)
                files.append(.init(path: file.path, originalPath: file.originalPath, state: file.state, content: patch.content))
            }
        case .stash(let stash):
            label = "Stash · \(stash.reference)"
            base = "\(stash.id)^1"
            head = stash.id
            let changes = try await inspector.files(for: stash, in: repository)
            guard changes.count <= 256 else { throw GenerationError.tooManyFiles }
            for file in changes {
                try Task.checkCancellation()
                let patch = try await inspector.patch(for: file, in: stash, repository: repository, maximumOutputBytes: 128 * 1024)
                files.append(.init(path: file.path, originalPath: file.originalPath, state: file.state, content: patch.content))
            }
        }
        guard !files.isEmpty else { throw GenerationError.empty }
        let collected = files
        return try await CommandRunner.read {
            let result = try RepositoryInspector.runGit(["-C", repository.rootURL.path, "rev-parse", "--verify", "HEAD"])
            let sha = result.status == 0 ? String(decoding: result.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : "0000000"
            return try makeDocument(files: collected, repositoryName: repository.name, title: label,
                                    base: base, head: head, fallbackSHA: sha)
        }
    }

    /// Edges describe references actually present in the patch, not inferred runtime/data-flow behavior.
    static func makeDocument(files: [File], repositoryName: String, title: String,
                             base: String, head: String, fallbackSHA: String) throws -> VisualDiffDocument {
        guard !files.isEmpty else { throw GenerationError.empty }
        guard files.count <= 256 else { throw GenerationError.tooManyFiles }
        let files = files.sorted { $0.path < $1.path }
        let directories = Array(Set(files.map { ($0.path as NSString).deletingLastPathComponent })).sorted()
        let visibleDirectories = Array(directories.prefix(directories.count > 16 ? 15 : 16))
        var lanes: [[String: Any]] = visibleDirectories.enumerated().map { index, directory in
            ["id": "lane\(index)", "label": label(directory.isEmpty ? "Repository root" : directory)]
        }
        if directories.count > 16 { lanes.append(["id": "other", "label": "Other folders"]) }
        var nodes: [[String: Any]] = []
        var before: [String] = [], after: [String] = []
        var additions = 0, deletions = 0, limitedFiles = 0
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            var added = 0, removed = 0
            var oldLines: [String] = [], newLines: [String] = []
            var badges: [String] = []
            switch file.content {
            case .text(let lines):
                for line in lines {
                    switch line.kind {
                    case .addition: added += 1; newLines.append(line.displayText)
                    case .deletion: removed += 1; oldLines.append(line.displayText)
                    case .context: oldLines.append(line.displayText); newLines.append(line.displayText)
                    default: break
                    }
                }
                badges = ["+\(added) −\(removed)"]
            case .binary: badges = ["Binary · file only"]; limitedFiles += 1
            case .tooLarge: badges = ["Large diff · file only"]; limitedFiles += 1
            case .unsupportedEncoding: badges = ["Non-UTF-8 · file only"]; limitedFiles += 1
            case .missing, .unavailable: badges = ["Metadata only"]; limitedFiles += 1
            }
            if let original = file.originalPath { badges.append(label("From \(original)")) }
            additions += added; deletions += removed
            before.append(oldLines.joined(separator: "\n")); after.append(newLines.joined(separator: "\n"))
            let directory = (file.path as NSString).deletingLastPathComponent
            let lane = visibleDirectories.firstIndex(of: directory).map { "lane\($0)" } ?? "other"
            let refs: [[String: String]] = isLinkable(file.path) ? [["path": file.path, "revision": file.state == .deleted ? "base" : "head"]] : []
            if refs.isEmpty { badges.append("Path cannot be linked") }
            nodes.append(["id": "file\(index)", "label": label((file.path as NSString).lastPathComponent),
                          "kind": kind(file.path), "delta": delta(file.state), "lane": lane,
                          "subtitle": label(directory.isEmpty ? "Repository root" : directory),
                          "files": refs, "badges": badges])
        }
        // Resolve only declarations unique among changed files. Ambiguous symbol names are omitted.
        var owners: [String: Set<Int>] = [:]
        let declaration = try NSRegularExpression(pattern: #"\b(?:class|struct|enum|protocol|interface|actor|type|func|function)\s+([A-Za-z_$][A-Za-z0-9_$]*)"#)
        for index in files.indices {
            let text = before[index] + "\n" + after[index]
            for match in declaration.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                owners[String(text[range]), default: []].insert(index)
            }
        }
        let unique = owners.compactMapValues { $0.count == 1 ? $0.first : nil }
        func references(_ text: String, from index: Int) -> Set<Int> {
            let tokens = text.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$")).inverted)
            return Set(tokens.compactMap { unique[$0] }.filter { $0 != index })
        }
        var edges: [[String: Any]] = []
        var referencesLimited = false
        for index in files.indices {
            try Task.checkCancellation()
            let old = references(before[index], from: index)
            let new = references(after[index], from: index)
            for target in old.union(new).sorted() {
                guard edges.count < 512 else { referencesLimited = true; break }
                let change = !old.contains(target) ? "added" : (!new.contains(target) ? "removed" : "unchanged")
                edges.append(["id": "ref\(index)-\(target)", "from": "file\(index)", "to": "file\(target)",
                              "kind": "dependency", "delta": change, "label": "references",
                              "emphasis": "normal", "animated": false, "files": []])
            }
        }
        let summary = "Generated locally from this comparison. Connections are symbol references found in diff context; they are not runtime or data-flow analysis."
        let graph: [String: Any] = [
            "schemaVersion": "0.2.0", "kind": "graph", "title": label(title), "summary": summary,
            "lenses": ["architecture"],
            "provenance": ["repo": ["owner": "local", "name": label(repositoryName), "host": "local"],
                           "base": ["sha": revisionSHA(base, fallback: fallbackSHA), "ref": label(base)],
                           "head": ["sha": revisionSHA(head, fallback: fallbackSHA), "ref": label(head)],
                           "generator": ["name": "Gallae local diff"]],
            "lanes": lanes, "nodes": nodes, "edges": edges, "flows": [], "views": [],
            "stats": ["filesChanged": files.count, "additions": additions, "deletions": deletions]
        ]
        let source = "\(files.count) files · \(shortRevision(base)) → \(shortRevision(head)) · References in diff"
            + (limitedFiles > 0 ? " · \(limitedFiles) files without text analysis" : "")
            + (referencesLimited ? " · Showing first 512 references" : "")
        return try VisualDiffDocument(data: JSONSerialization.data(withJSONObject: graph, options: [.sortedKeys]), generatedSource: source)
    }

    private static func label(_ text: String) -> String {
        let singleLine = text.components(separatedBy: .newlines).joined(separator: " ")
        return singleLine.utf16.count <= 120 ? singleLine : String(decoding: Array(singleLine.utf16.prefix(118)), as: UTF16.self) + "…"
    }
    private static func isLinkable(_ path: String) -> Bool {
        !path.isEmpty && path.utf16.count <= 1024 && !path.hasPrefix("/") && !path.contains("\\")
            && !path.split(separator: "/").contains("..")
            && path.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil
    }
    private static func revisionSHA(_ ref: String, fallback: String) -> String {
        ref.range(of: #"^[0-9a-f]{7,40}$"#, options: .regularExpression) != nil ? ref : fallback
    }
    private static func shortRevision(_ ref: String) -> String {
        ref.range(of: #"^[0-9a-f]{7,40}$"#, options: .regularExpression) != nil ? String(ref.prefix(8)) : ref
    }
    private static func delta(_ state: RepositorySummary.Change.State) -> String {
        switch state { case .added, .untracked: "added"; case .deleted: "removed"; default: "modified" }
    }
    private static func kind(_ path: String) -> String {
        let lower = path.lowercased()
        if lower.contains("test") || lower.contains("spec.") { return "test" }
        if ["json", "yaml", "yml", "toml", "xcconfig", "plist"].contains((lower as NSString).pathExtension) { return "config" }
        return "module"
    }
}
