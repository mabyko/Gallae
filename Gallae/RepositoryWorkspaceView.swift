import Observation
import SwiftUI

struct RepositoryWorkspaceView: View {
    @Bindable var model: AppModel
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            repositoryHeader
            Divider()

            if model.repository?.changes.isEmpty == true {
                ContentUnavailableView(
                    "Working Tree Clean",
                    systemImage: "checkmark.circle",
                    description: Text("There are no staged, unstaged, or untracked files.")
                )
            } else if let repository = model.repository {
                HSplitView {
                    changeList(repository)
                        .frame(
                            minWidth: theme.metrics.changeListMinimumWidth,
                            idealWidth: theme.metrics.changeListIdealWidth
                        )

                    RepositoryDiffView(
                        state: model.diffState,
                        fileURL: selectedFileURL(in: repository),
                        retry: { Task { await model.loadSelectedDiff() } },
                        loadExpanded: {
                            Task {
                                await model.loadSelectedDiff(
                                    maximumOutputBytes: RepositoryInspector.maximumExpandedDiffBytes
                                )
                            }
                        }
                    )
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: model.diffRequest) {
            await model.loadSelectedDiff()
        }
    }

    private var repositoryHeader: some View {
        HStack(alignment: .top, spacing: 24) {
            if let repository = model.repository {
                VStack(alignment: .leading, spacing: 6) {
                    Text(repository.name)
                        .font(.largeTitle.weight(.semibold))
                    Text(repository.rootURL.path)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Label(repository.head.label, systemImage: repository.head.systemImage)
                    if let upstream = repository.upstream {
                        Label(upstream.label, systemImage: "arrow.up.arrow.down")
                            .foregroundStyle(.secondary)
                    }
                    if repository.isUnborn {
                        Label("No commits yet", systemImage: "circle.dashed")
                            .foregroundStyle(.secondary)
                    }
                    if model.isRepositoryStale {
                        Label("Refresh failed · showing earlier data", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                            .font(.caption)
                            .foregroundStyle(theme.colors.statusConflict)
                    }
                }
            }
        }
        .padding(24)
    }

    private func changeList(_ repository: RepositorySummary) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Changes")
                    .font(.headline)
                Spacer()
                Text(repository.changes.count, format: .number)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            List(repository.changes, selection: $model.selectedChangeID) { change in
                RepositoryChangeRow(change: change)
                    .tag(change.id)
            }
            .listStyle(.inset)
            .accessibilityLabel("Changes, \(repository.changes.count) files")
        }
    }

    private func selectedFileURL(in repository: RepositorySummary) -> URL? {
        guard let selectedChangeID = model.selectedChangeID else { return nil }
        return repository.rootURL.appending(path: selectedChangeID)
    }
}

private struct RepositoryChangeRow: View {
    let change: RepositorySummary.Change
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: change.isConflicted ? "exclamationmark.triangle" : "doc.text")
                .foregroundStyle(change.isConflicted ? theme.colors.statusConflict : theme.colors.diffMetadataText)

            VStack(alignment: .leading, spacing: 3) {
                Text(change.path)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                if let originalPath = change.originalPath {
                    Text("From \(originalPath)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    ForEach(change.badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.colors.badgeBackground, in: .capsule)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RepositoryDiffView: View {
    let state: RepositoryDiffLoadState
    let fileURL: URL?
    let retry: () -> Void
    let loadExpanded: () -> Void

    var body: some View {
        switch state {
        case .noSelection:
            ContentUnavailableView(
                "Select a Changed File",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose a file to inspect its staged and working tree diff.")
            )
        case .loading:
            ProgressView("Loading Diff…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Load Diff", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", action: retry)
                    .accessibilityLabel("Try Again")
            }
        case .loaded(let diff):
            diffContent(diff)
        }
    }

    private func diffContent(_ diff: RepositoryDiff) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(diff.path)
                    .font(.headline.monospaced())
                    .textSelection(.enabled)
                if let originalPath = diff.originalPath {
                    Text("From \(originalPath)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(diff.sections) { section in
                        RepositoryDiffSectionView(
                            section: section,
                            fileURL: fileURL,
                            loadExpanded: loadExpanded
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct RepositoryDiffSectionView: View {
    let section: RepositoryDiff.Section
    let fileURL: URL?
    let loadExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(section.scope.label, systemImage: section.scope.systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)

            Divider()

            switch section.content {
            case .text(let lines):
                ForEach(lines) { line in
                    RepositoryDiffLineView(line: line)
                }
            case .binary:
                RepositoryDiffNotice(
                    title: "Binary File",
                    message: "Gallae does not render binary content as text.",
                    fileURL: fileURL
                )
            case .unsupportedEncoding:
                RepositoryDiffNotice(
                    title: "Unsupported Text Encoding",
                    message: "This diff is not valid UTF-8 and cannot be displayed safely.",
                    fileURL: fileURL
                )
            case .tooLarge(let byteLimit):
                RepositoryDiffNotice(
                    title: "Diff Too Large",
                    message: "The diff exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(byteLimit), countStyle: .file)) preview limit.",
                    fileURL: fileURL,
                    primaryAction: byteLimit < RepositoryInspector.maximumExpandedDiffBytes
                        ? ("Load Larger Preview", loadExpanded)
                        : nil
                )
            case .unavailable(let message):
                RepositoryDiffNotice(title: "Diff Unavailable", message: message, fileURL: fileURL)
            }
        }
    }
}

private struct RepositoryDiffLineView: View {
    let line: RepositoryDiff.Line
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: theme.metrics.diffLineNumberWidth, alignment: .trailing)
                .padding(.trailing, 6)
            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: theme.metrics.diffLineNumberWidth, alignment: .trailing)
                .padding(.trailing, 8)
            Text(line.text.isEmpty ? " " : line.text)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.callout.monospaced())
        .foregroundStyle(foregroundColor)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.accessibilityLabel)
    }

    private var foregroundColor: Color {
        switch line.kind {
        case .metadata: theme.colors.diffMetadataText
        case .hunk: theme.colors.diffHunkText
        case .context, .addition, .deletion: theme.colors.diffText
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .addition: theme.colors.diffAdditionBackground
        case .deletion: theme.colors.diffDeletionBackground
        case .hunk: theme.colors.diffHunkBackground
        case .metadata, .context: .clear
        }
    }
}

private struct RepositoryDiffNotice: View {
    let title: String
    let message: String
    let fileURL: URL?
    var primaryAction: (label: String, action: () -> Void)? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
            if let primaryAction {
                Button(primaryAction.label, action: primaryAction.action)
            }
            if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                Button("Open File") {
                    openURL(fileURL)
                }
            }
        }
        .padding(20)
    }
}

extension RepositorySummary.Head {
    var label: String {
        switch self {
        case .branch(let name): name
        case .detached(let commit): "Detached at \(commit.prefix(8))"
        }
    }

    var systemImage: String {
        switch self {
        case .branch: "arrow.triangle.branch"
        case .detached: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

extension RepositorySummary.Upstream {
    var label: String {
        guard let ahead, let behind else { return name }
        return "\(name) · ↑\(ahead) ↓\(behind)"
    }
}

private extension RepositorySummary.Change {
    var badges: [String] {
        if isConflicted {
            return ["Conflict"]
        }

        var result: [String] = []
        if let staged {
            result.append("Staged · \(staged.label)")
        }
        if let unstaged {
            result.append(unstaged == .untracked ? "Untracked" : "Working · \(unstaged.label)")
        }
        return result
    }
}

private extension RepositorySummary.Change.State {
    var label: String {
        switch self {
        case .modified: "Modified"
        case .typeChanged: "Type changed"
        case .added: "Added"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .copied: "Copied"
        case .untracked: "Untracked"
        }
    }
}

private extension RepositoryDiff.Scope {
    var label: String {
        switch self {
        case .staged: "Staged"
        case .unstaged: "Working Tree"
        case .untracked: "Untracked"
        case .conflict: "Conflict"
        }
    }

    var systemImage: String {
        switch self {
        case .staged: "tray.and.arrow.down"
        case .unstaged: "pencil.line"
        case .untracked: "questionmark.diamond"
        case .conflict: "exclamationmark.triangle"
        }
    }
}

private extension RepositoryDiff.Line {
    var accessibilityLabel: String {
        let location = [
            oldLineNumber.map { "old line \($0)" },
            newLineNumber.map { "new line \($0)" }
        ].compactMap { $0 }.joined(separator: ", ")

        let kindLabel: String
        switch kind {
        case .metadata: kindLabel = "Metadata"
        case .hunk: kindLabel = "Hunk"
        case .context: kindLabel = "Context"
        case .addition: kindLabel = "Added"
        case .deletion: kindLabel = "Deleted"
        }

        return location.isEmpty ? "\(kindLabel): \(text)" : "\(kindLabel), \(location): \(text)"
    }
}
