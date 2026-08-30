import AppKit
import Observation
import SwiftUI

private enum RepositoryChangeViewMode: Int {
    case hierarchy
    case status
}

private enum RepositoryWorkspaceSection: Int {
    case changes
    case history
}

struct RepositoryWorkspaceView: View {
    @Bindable var model: AppModel
    @Environment(\.gallaeTheme) private var theme
    @State private var selectedChangeNodeID: RepositoryChangeHierarchyNode.ID?
    @State private var expandedStatusGroups = Set(RepositoryChangeStatusGroup.ID.allCases)
    @State private var commitSubject = ""
    @State private var commitBody = ""
    @State private var isAmending = false
    @SceneStorage("repositoryChangeViewMode") private var changeViewMode = RepositoryChangeViewMode.status
    @SceneStorage("repositoryWorkspaceSection") private var workspaceSection = RepositoryWorkspaceSection.changes

    var body: some View {
        VStack(spacing: 0) {
            repositoryHeader
            Divider()

            if let repository = model.repository {
                switch workspaceSection {
                case .changes:
                    changesContent(repository)
                case .history:
                    RepositoryHistoryView(model: model)
                }
            }
        }
        .task(id: model.diffRequest) {
            await model.loadSelectedDiff()
        }
        .onChange(of: model.repository?.rootURL) {
            commitSubject = ""
            commitBody = ""
            isAmending = false
        }
    }

    private var repositoryHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            if let repository = model.repository {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(repository.name)
                        .accessibilityLabel("Repository, \(repository.name)")
                    Text(repository.rootURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(repository.rootURL.path)
                        .accessibilityLabel("Repository path, \(repository.rootURL.path)")
                }

                Spacer()

                Picker("Workspace", selection: $workspaceSection) {
                    Text("Changes").tag(RepositoryWorkspaceSection.changes)
                    Text("History").tag(RepositoryWorkspaceSection.history)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Switch between working tree changes and commit history")
                .accessibilityLabel("Repository View")

                VStack(alignment: .trailing, spacing: 5) {
                    Label(repository.head.label, systemImage: repository.head.systemImage)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(repository.head.label)
                        .accessibilityLabel("HEAD, \(repository.head.label)")
                    if let upstream = repository.upstream {
                        Label(upstream.label, systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(upstream.label)
                            .accessibilityLabel("Upstream, \(upstream.label)")
                    }
                    if repository.isUnborn {
                        Label("No commits yet", systemImage: "circle.dashed")
                            .font(.caption)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func changesContent(_ repository: RepositorySummary) -> some View {
        if repository.changes.isEmpty {
            ContentUnavailableView {
                Label("Working Tree Clean", systemImage: "checkmark.circle")
            } description: {
                Text("There are no staged, unstaged, or untracked files.")
            } actions: {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([repository.rootURL])
                }
                .accessibilityHint("Open the Repository folder in Finder")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                changeList(repository)
                    .frame(
                        minWidth: theme.metrics.changeListMinimumWidth,
                        idealWidth: theme.metrics.changeListIdealWidth
                    )

                RepositoryDiffView(
                    state: model.diffState,
                    fileURL: selectedFileURL(in: repository),
                    canStage: model.canStageSelectedChange,
                    canUnstage: model.canUnstageSelectedChange,
                    canDiscard: model.canDiscardSelectedChange,
                    canStageHunks: model.canStageSelectedHunks,
                    canUnstageHunks: model.canUnstageSelectedHunks,
                    isBusy: model.isLoading,
                    stage: { Task { await model.stageSelectedChange() } },
                    unstage: { Task { await model.unstageSelectedChange() } },
                    discard: { id in Task { await model.discardChange(id: id) } },
                    updateHunk: { hunk in
                        Task { await model.updateSelectedHunk(hunk) }
                    },
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
                .layoutPriority(1)
            }
        }
    }

    private func changeList(_ repository: RepositorySummary) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Changes")
                        .font(.headline)
                    Text("Working tree")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(repository.changes.count, format: .number)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(theme.colors.badgeBackground, in: .capsule)
                Picker("Change View", selection: $changeViewMode) {
                    Text("Status").tag(RepositoryChangeViewMode.status)
                    Text("Folders").tag(RepositoryChangeViewMode.hierarchy)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .help("Switch between folder hierarchy and status groups")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            switch changeViewMode {
            case .hierarchy:
                changeHierarchyList(repository)
            case .status:
                changeStatusList(repository)
            }

            Divider()
            commitComposer(repository)
        }
    }

    private func commitComposer(_ repository: RepositorySummary) -> some View {
        VStack(spacing: 8) {
            TextField("Commit subject", text: $commitSubject)
                .textFieldStyle(.roundedBorder)
                .accessibilityHint("Describe the staged changes")

            TextField("Commit body (optional)", text: $commitBody, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)
                .accessibilityHint("Add optional details about the staged changes")

            Toggle("Amend last commit", isOn: $isAmending)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(repository.isUnborn || model.isLoading)
                .help("Replace the latest commit with the staged changes and entered message")
                .accessibilityHint("Rewrites the latest commit without including unstaged changes")

            HStack {
                Text("\(repository.changes.filter { $0.staged != nil }.count) staged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Button(isAmending ? "Amend" : "Commit") {
                    let subject = commitSubject
                    let body = commitBody
                    let amend = isAmending
                    Task {
                        if await model.commit(subject: subject, body: body, amend: amend) {
                            commitSubject = ""
                            commitBody = ""
                            isAmending = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(
                    !model.canCommit
                        || commitSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (isAmending && repository.isUnborn)
                        || model.isLoading
                )
                .help(isAmending ? "Replace the latest commit (⌘↩)" : "Commit staged changes (⌘↩)")
                .accessibilityHint(
                    isAmending
                        ? "Replace the latest commit using the staged changes"
                        : "Create a commit from the staged changes"
                )
            }
        }
        .padding(12)
    }

    private func changeHierarchyList(_ repository: RepositorySummary) -> some View {
        List(
            RepositoryChangeHierarchyNode.make(repository.changes),
            children: \.children,
            selection: changeHierarchySelection
        ) { node in
            changeHierarchyRow(node)
                .listRowInsets(.init(top: 7, leading: 12, bottom: 7, trailing: 12))
        }
        .listStyle(.plain)
        .accessibilityLabel("Changes by folder, \(repository.changes.count) files")
        .onChange(of: model.selectedChangeID, initial: true) { _, path in
            if let path {
                selectedChangeNodeID = .change(path)
            } else if case .some(.change) = selectedChangeNodeID {
                selectedChangeNodeID = nil
            }
        }
    }

    private func changeStatusList(_ repository: RepositorySummary) -> some View {
        List(selection: $model.selectedChangeID) {
            ForEach(RepositoryChangeStatusGroup.make(repository.changes)) { group in
                Section {
                    if expandedStatusGroups.contains(group.id) {
                        ForEach(group.changes) { change in
                            RepositoryChangeRow(change: change, showsParentPath: true)
                                .tag(change.id)
                                .listRowInsets(.init(top: 7, leading: 12, bottom: 7, trailing: 12))
                        }
                    }
                } header: {
                    Button {
                        toggleStatusGroup(group.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(
                                systemName: expandedStatusGroups.contains(group.id)
                                    ? "chevron.down"
                                    : "chevron.right"
                            )
                            .font(.caption2.weight(.semibold))
                            .frame(width: 10)
                            .accessibilityHidden(true)
                            Text(group.title)
                            Spacer()
                            Text(group.changes.count, format: .number)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .contentShape(.interaction, Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityValue(
                        expandedStatusGroups.contains(group.id) ? "Expanded" : "Collapsed"
                    )
                }
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Changes by status, \(repository.changes.count) files")
    }

    private func toggleStatusGroup(_ id: RepositoryChangeStatusGroup.ID) {
        if expandedStatusGroups.contains(id) {
            expandedStatusGroups.remove(id)
        } else {
            expandedStatusGroups.insert(id)
        }
    }

    private var changeHierarchySelection: Binding<RepositoryChangeHierarchyNode.ID?> {
        Binding(
            get: {
                model.selectedChangeID.map {
                    RepositoryChangeHierarchyNode.ID.change($0)
                } ?? selectedChangeNodeID
            },
            set: { id in
                selectedChangeNodeID = id
                if case .some(.change(let path)) = id {
                    model.selectedChangeID = path
                } else {
                    model.selectedChangeID = nil
                }
            }
        )
    }

    @ViewBuilder
    private func changeHierarchyRow(_ node: RepositoryChangeHierarchyNode) -> some View {
        if let change = node.change {
            RepositoryChangeRow(change: change)
        } else {
            RepositoryChangeFolderRow(node: node)
        }
    }

    private func selectedFileURL(in repository: RepositorySummary) -> URL? {
        guard let selectedChangeID = model.selectedChangeID else { return nil }
        return repository.rootURL.appending(path: selectedChangeID)
    }
}

private struct RepositoryChangeRow: View {
    let change: RepositorySummary.Change
    var showsParentPath = false
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: change.isConflicted ? "exclamationmark.triangle" : "doc.text")
                .foregroundStyle(iconColor)
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(change.fileName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(change.path)
                    Spacer(minLength: 6)
                    ForEach(change.badges) { badge in
                        Text(badge.label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(statusColor(for: badge.state))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.colors.badgeBackground, in: .capsule)
                    }
                }
                if showsParentPath, !change.parentPath.isEmpty {
                    Text(change.parentPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(change.path)
                }
                if let originalPath = change.originalPath {
                    Text("From \(originalPath)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        ([change.path] + change.badges.map(\.label) + [change.originalPath.map { "From \($0)" }].compactMap(\.self))
            .joined(separator: ", ")
    }

    private var iconColor: Color {
        if change.isConflicted {
            return theme.colors.statusConflict
        }
        guard let state = change.unstaged ?? change.staged else {
            return theme.colors.diffMetadataText
        }
        return statusColor(for: state)
    }

    private func statusColor(for state: RepositorySummary.Change.State?) -> Color {
        guard let state else { return theme.colors.statusConflict }
        return switch state {
        case .modified: theme.colors.statusModified
        case .typeChanged, .renamed: theme.colors.statusRenamed
        case .added, .copied: theme.colors.statusAdded
        case .deleted: theme.colors.statusDeleted
        case .untracked: theme.colors.statusUntracked
        }
    }
}

private struct RepositoryChangeFolderRow: View {
    let node: RepositoryChangeHierarchyNode

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(node.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Spacer()
            Text(node.changeCount, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityValue("\(node.path), folder, \(node.changeCount) changed files")
        .help(node.path)
    }
}

struct RepositoryChangeStatusGroup: Equatable, Identifiable, Sendable {
    enum ID: CaseIterable, Equatable, Hashable, Sendable {
        case conflicts
        case changes
        case untracked
    }

    let id: ID
    let changes: [RepositorySummary.Change]

    var title: String {
        switch id {
        case .conflicts: "Conflicts"
        case .changes: "Changes"
        case .untracked: "Untracked Files"
        }
    }

    static func make(_ changes: [RepositorySummary.Change]) -> [RepositoryChangeStatusGroup] {
        [
            .init(id: .conflicts, changes: changes.filter(\.isConflicted)),
            .init(id: .changes, changes: changes.filter {
                !$0.isConflicted && $0.unstaged != .untracked
            }),
            .init(id: .untracked, changes: changes.filter {
                !$0.isConflicted && $0.unstaged == .untracked
            })
        ]
        .filter { !$0.changes.isEmpty }
    }
}

struct RepositoryChangeHierarchyNode: Equatable, Identifiable, Sendable {
    enum ID: Equatable, Hashable, Sendable {
        case folder(String)
        case change(String)
    }

    let id: ID
    let name: String
    let path: String
    var children: [RepositoryChangeHierarchyNode]?
    let change: RepositorySummary.Change?
    private typealias Entry = (change: RepositorySummary.Change, components: [String])

    var changeCount: Int {
        change == nil
            ? children?.reduce(0) { $0 + $1.changeCount } ?? 0
            : 1
    }

    static func make(_ changes: [RepositorySummary.Change]) -> [RepositoryChangeHierarchyNode] {
        let entries: [Entry] = changes.compactMap { change in
            let components = change.path.split(separator: "/").map(String.init)
            return components.isEmpty ? nil : (change, components)
        }
        return make(entries, depth: 0)
    }

    private static func make(_ entries: [Entry], depth: Int) -> [RepositoryChangeHierarchyNode] {
        var nodes: [RepositoryChangeHierarchyNode] = []
        for (name, group) in Dictionary(grouping: entries, by: { $0.components[depth] }) {
            for entry in group where entry.components.count == depth + 1 {
                nodes.append(.init(
                    id: .change(entry.change.id),
                    name: name,
                    path: entry.change.path,
                    children: nil,
                    change: entry.change
                ))
            }

            let descendants = group.filter { $0.components.count > depth + 1 }
            if let first = descendants.first {
                let folderPath = first.components.prefix(depth + 1).joined(separator: "/")
                nodes.append(.init(
                    id: .folder(folderPath),
                    name: name,
                    path: folderPath,
                    children: make(descendants, depth: depth + 1),
                    change: nil
                ))
            }
        }
        return nodes.sorted {
            if ($0.children != nil) != ($1.children != nil) {
                return $0.children != nil
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

private struct RepositoryChangeBadge: Identifiable {
    let label: String
    let state: RepositorySummary.Change.State?

    var id: String { label }
}

private struct RepositoryHistoryView: View {
    @Bindable var model: AppModel
    @Environment(\.gallaeTheme) private var theme
    @State private var searchText = ""

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                VStack(spacing: 7) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("History")
                                .font(.headline)
                            Text("Current HEAD · latest 100")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if case .loaded(let history) = model.historyState {
                            Text(history.commits.count, format: .number)
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(theme.colors.badgeBackground, in: .capsule)
                        }
                    }

                    if case .loaded(let history) = model.historyState, !history.commits.isEmpty {
                        TextField("Search message, author, or SHA", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Search Commit History")
                            .onExitCommand { searchText = "" }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider()

                historyList
            }
            .frame(
                minWidth: theme.metrics.changeListMinimumWidth,
                idealWidth: theme.metrics.changeListIdealWidth
            )

            RepositoryCommitDetailView(model: model)
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .task(id: model.historyRequest) {
            await model.loadHistory()
        }
        .task(id: model.commitPatchRequest) {
            await model.loadSelectedCommitPatch()
        }
        .onChange(of: visibleHistoryCommitIDs, initial: true) { _, visibleIDs in
            guard case .loaded = model.historyState else { return }
            guard model.selectedHistoryCommitID.map(visibleIDs.contains) != true else { return }
            model.selectedHistoryCommitID = visibleIDs.first
        }
    }

    private var visibleHistoryCommitIDs: [String] {
        guard case .loaded(let history) = model.historyState else { return [] }
        return visibleCommits(in: history).map(\.id)
    }

    private func visibleCommits(in history: RepositoryHistory) -> [RepositoryHistory.Commit] {
        history.commits.filter { $0.matches(search: searchText) }
    }

    @ViewBuilder
    private var historyList: some View {
        switch model.historyState {
        case .notLoaded, .loading:
            ProgressView("Loading History…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Load History", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await model.loadHistory() }
                }
                .accessibilityLabel("Try Again")
            }
        case .loaded(let history) where history.commits.isEmpty:
            ContentUnavailableView(
                "No Commits Yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("Create the first commit to start this Repository’s history.")
            )
        case .loaded(let history):
            let commits = visibleCommits(in: history)
            if commits.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Commits", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different message, author, or SHA.")
                } actions: {
                    Button("Clear Search") { searchText = "" }
                }
            } else {
                List(commits, selection: $model.selectedHistoryCommitID) { commit in
                    RepositoryHistoryRow(
                        commit: commit,
                        isHEAD: commit.id == history.commits.first?.id
                    )
                    .tag(commit.id)
                    .listRowInsets(.init(top: 7, leading: 12, bottom: 7, trailing: 12))
                }
                .listStyle(.plain)
                .accessibilityLabel("Commit History, \(commits.count) commits")
            }
        }
    }
}

private struct RepositoryHistoryRow: View {
    let commit: RepositoryHistory.Commit
    let isHEAD: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(Color.accentColor)
                .opacity(isHEAD ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isHEAD {
                        Text("HEAD")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: .capsule)
                    }
                    Text(commit.subject)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 4) {
                    Text(commit.authorName)
                    Text("·")
                    Text(commit.committedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(commit.id.prefix(8))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(isHEAD ? "HEAD, " : "")\(commit.subject), \(commit.authorName), \(commit.committedAt.formatted(date: .abbreviated, time: .shortened)), revision \(commit.id.prefix(8))"
        )
    }
}

private struct RepositoryCommitDetailView: View {
    @Bindable var model: AppModel

    @ViewBuilder
    var body: some View {
        if let commit = model.selectedHistoryCommit {
            VStack(spacing: 0) {
                commitHeader(commit)
                Divider()
                patchContent
            }
        } else {
            ContentUnavailableView(
                "Select a Commit",
                systemImage: "clock.arrow.circlepath",
                description: Text("Choose a commit to inspect its message and changes.")
            )
        }
    }

    private func commitHeader(_ commit: RepositoryHistory.Commit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commit.subject)
                .font(.headline)
                .textSelection(.enabled)

            if !commit.body.isEmpty {
                Text(commit.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            Text("\(commit.authorName) <\(commit.authorEmail)> · \(commit.committedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Commit \(commit.id)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if !commit.parentIDs.isEmpty {
                Text("Parent \(commit.parentIDs.map { String($0.prefix(8)) }.joined(separator: ", "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var patchContent: some View {
        switch model.commitPatchState {
        case .noSelection:
            ContentUnavailableView(
                "No Commit Changes",
                systemImage: "doc.text.magnifyingglass"
            )
        case .loading:
            ProgressView("Loading Commit Changes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Load Commit Changes", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await model.loadSelectedCommitPatch() }
                }
                .accessibilityLabel("Try Again")
            }
        case .loaded(let patch):
            commitPatch(patch.content)
        }
    }

    @ViewBuilder
    private func commitPatch(_ content: RepositoryDiff.Section.Content) -> some View {
        switch content {
        case .text(let lines):
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            RepositoryDiffLineView(line: line)
                        }
                    }
                    .frame(minWidth: proxy.size.width, alignment: .leading)
                    .textSelection(.enabled)
                }
                .defaultScrollAnchor(.topLeading, for: .alignment)
            }
            .accessibilityLabel("Selected commit changes")
        case .binary:
            RepositoryDiffNotice(
                title: "Binary Changes",
                message: "Gallae does not render binary content as text.",
                fileURL: nil
            )
        case .unsupportedEncoding:
            RepositoryDiffNotice(
                title: "Unsupported Text Encoding",
                message: "This patch is not valid UTF-8 and cannot be displayed safely.",
                fileURL: nil
            )
        case .tooLarge(let byteLimit):
            RepositoryDiffNotice(
                title: "Commit Changes Too Large",
                message: "The patch exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(byteLimit), countStyle: .file)) preview limit.",
                fileURL: nil,
                primaryAction: byteLimit < RepositoryInspector.maximumExpandedDiffBytes
                    ? (
                        "Load Larger Preview",
                        {
                            Task {
                                await model.loadSelectedCommitPatch(
                                    maximumOutputBytes: RepositoryInspector.maximumExpandedDiffBytes
                                )
                            }
                        }
                    )
                    : nil
            )
        case .unavailable(let message):
            RepositoryDiffNotice(
                title: "No Commit Changes",
                message: message,
                fileURL: nil
            )
        }
    }
}

private struct RepositoryDiffView: View {
    let state: RepositoryDiffLoadState
    let fileURL: URL?
    let canStage: Bool
    let canUnstage: Bool
    let canDiscard: Bool
    let canStageHunks: Bool
    let canUnstageHunks: Bool
    let isBusy: Bool
    let stage: () -> Void
    let unstage: () -> Void
    let discard: (RepositorySummary.Change.ID) -> Void
    let updateHunk: (RepositoryDiff.Hunk) -> Void
    let retry: () -> Void
    let loadExpanded: () -> Void
    @State private var isConfirmingDiscard = false

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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(diff.fileName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(diff.path)
                    Text(diff.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if let originalPath = diff.originalPath {
                        Text("From \(originalPath)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if canDiscard {
                    Button("Discard…", role: .destructive) {
                        isConfirmingDiscard = true
                    }
                    .disabled(isBusy)
                    .help("Discard this file’s unstaged changes")
                    .accessibilityHint(
                        "Shows a confirmation before replacing the working tree file"
                    )
                }
                if canUnstage {
                    Button("Unstage", action: unstage)
                        .disabled(isBusy)
                        .help("Remove this file from the next commit without changing it on disk")
                        .accessibilityHint(
                            "Remove this file from the next commit without changing its working tree content"
                        )
                }
                if canStage {
                    Button("Stage", action: stage)
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)
                        .help("Add this file to the next commit")
                        .accessibilityHint("Add this file’s current changes to the next commit")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diff.sections) { section in
                            RepositoryDiffSectionView(
                                section: section,
                                fileURL: fileURL,
                                canStageHunks: canStageHunks,
                                canUnstageHunks: canUnstageHunks,
                                isBusy: isBusy,
                                updateHunk: updateHunk,
                                loadExpanded: loadExpanded
                            )
                        }
                    }
                    .frame(minWidth: proxy.size.width, alignment: .leading)
                    .textSelection(.enabled)
                }
                .defaultScrollAnchor(.topLeading, for: .alignment)
            }
        }
        .alert("Discard Unstaged Changes?", isPresented: $isConfirmingDiscard) {
            Button("Discard Changes", role: .destructive) {
                discard(diff.path)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This replaces the file on disk with its staged version, or its last committed version when nothing is staged. Gallae cannot undo this action."
            )
        }
    }
}

private struct RepositoryDiffSectionView: View {
    let section: RepositoryDiff.Section
    let fileURL: URL?
    let canStageHunks: Bool
    let canUnstageHunks: Bool
    let isBusy: Bool
    let updateHunk: (RepositoryDiff.Hunk) -> Void
    let loadExpanded: () -> Void
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(section.scope.label, systemImage: section.scope.systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.colors.badgeBackground)

            Divider()

            switch section.content {
            case .text(let lines):
                ForEach(lines) { line in
                    if let hunk = section.hunks.first(where: { $0.id == line.id }),
                       let actionLabel = hunkActionLabel {
                        HStack(spacing: 8) {
                            RepositoryDiffLineView(line: line, fillsWidth: false)
                            Button(actionLabel) {
                                updateHunk(hunk)
                            }
                            .controlSize(.small)
                            .disabled(isBusy)
                            .help("\(actionLabel) without changing the working tree file")
                            .accessibilityHint("Update only this hunk in the Git index")
                            Spacer(minLength: 8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.colors.diffHunkBackground)
                    } else {
                        RepositoryDiffLineView(line: line)
                    }
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

    private var hunkActionLabel: String? {
        switch section.scope {
        case .staged where canUnstageHunks: "Unstage Hunk"
        case .unstaged where canStageHunks: "Stage Hunk"
        default: nil
        }
    }
}

private struct RepositoryDiffLineView: View {
    let line: RepositoryDiff.Line
    var fillsWidth = true
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
        .frame(minWidth: 0, maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
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
                    NSWorkspace.shared.open(fileURL)
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
    var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    var parentPath: String {
        guard let separator = path.lastIndex(of: "/") else { return "" }
        return String(path[..<separator])
    }

    var badges: [RepositoryChangeBadge] {
        if isConflicted {
            return [.init(label: "Conflict", state: nil)]
        }

        var result: [RepositoryChangeBadge] = []
        if let staged {
            result.append(.init(label: "Staged · \(staged.label)", state: staged))
        }
        if let unstaged {
            result.append(.init(
                label: unstaged == .untracked ? "Untracked" : "Working · \(unstaged.label)",
                state: unstaged
            ))
        }
        return result
    }
}

private extension RepositoryDiff {
    var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
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
