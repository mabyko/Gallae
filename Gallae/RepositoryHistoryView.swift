import AppKit
import SwiftUI

struct RepositoryHistoryView: View {
    @Bindable var model: AppModel
    /// The explicit History filter; Navigator selection only moves the graph focus.
    @Binding var scope: RepositoryHistoryScope?
    @AppStorage(GallaeAppearanceSettings.historyLayoutKey) private var historyLayout = GallaeAppearanceSettings.HistoryLayout.stacked
    @State private var isReviewExpanded = false
    @FocusState private var historyFocused: Bool
    @State private var editedRemote: RepositoryRemote?
    @Environment(\.gallaeTheme) private var theme
    @State private var searchText = ""
    @State private var isCreatingBranch = false
    @State private var pendingWorktreeRemoval: WorktreeRemovalRequest?
    @State private var pendingBranchDeletion: String?
    @State private var pendingRemoteBranchDeletion: String?
    @State private var pendingTrackingReferenceRemoval: String?

    var body: some View {
        RepositoryHistorySplit(layout: historyLayout, isReviewExpanded: isReviewExpanded) {
            VStack(spacing: 0) {
                VStack(spacing: 7) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            historyScopeMenu
                            Text(headerSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        headerTools
                        if case .loaded(let history) = model.historyState {
                            Text(history.commits.count, format: .number)
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(theme.colors.badgeBackground, in: .capsule)
                        }
                    }

                    if scope != nil {
                        HStack {
                            Label("Filtered history", systemImage: "line.3.horizontal.decrease")
                            Spacer()
                            Button("Clear Filter") { scope = nil }
                        }
                        .font(.caption)
                    }
                    if let message = model.historyNavigationMessage {
                        HStack {
                            Text(message).foregroundStyle(.secondary)
                            Button("Show in All History") { scope = nil }
                        }
                        .font(.caption)
                    }

                    if case .loaded(let history) = model.historyState, !history.commits.isEmpty {
                        TextField("Search message, author, SHA, or ref", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Search Commit History")
                            .onExitCommand { searchText = "" }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .listHeaderInset()

                Divider()

                historyList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } review: {
            VStack(spacing: 0) {
                if historyLayout == .stacked {
                    reviewControls
                    Divider()
                }
                RepositoryCommitDetailView(model: model, compactHeader: historyLayout == .stacked)
            }
        }
        .onChange(of: historyLayout) { isReviewExpanded = false }
        .onChange(of: model.repository?.rootURL) { isReviewExpanded = false }
        .onChange(of: model.historyNavigationRevision) { searchText = "" }
        .task(id: model.historyRequest) {
            await model.loadHistory()
        }
        .task(id: model.commitFilesRequest) {
            await model.loadSelectedCommitFiles()
        }
        .task(id: model.commitFilesRequest) {
            await model.loadSelectedCommitSignature()
        }
        .task(id: model.commitPatchRequest) {
            await model.loadSelectedCommitPatch()
        }
        .onChange(of: visibleHistoryCommitIDs, initial: true) { _, visibleIDs in
            guard case .loaded = model.historyState else { return }
            guard model.selectedHistoryCommitID.map(visibleIDs.contains) != true else { return }
            model.selectedHistoryCommitID = visibleIDs.first
        }
        .confirmationDialog(
            "Remove Worktree?",
            isPresented: Binding(
                get: { pendingWorktreeRemoval != nil },
                set: { if !$0 { pendingWorktreeRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingWorktreeRemoval
        ) { request in
            Button("Remove Worktree", role: .destructive) {
                Task { await model.removeWorktree(at: request.worktreeURL) }
            }
            Button("Remove Worktree and Branch", role: .destructive) {
                Task {
                    await model.removeWorktree(
                        at: request.worktreeURL,
                        deletingBranch: request.branch,
                        deletingRemoteTrackingRef: nil
                    )
                }
            }
            if let trackingRef = request.trackingRef {
                Button("Remove Worktree, Branch, and \(trackingRef)", role: .destructive) {
                    Task {
                        await model.removeWorktree(
                            at: request.worktreeURL,
                            deletingBranch: request.branch,
                            deletingRemoteTrackingRef: trackingRef
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(request.confirmationMessage)
        }
        .confirmationDialog(
            "Delete Branch?",
            isPresented: Binding(
                get: { pendingBranchDeletion != nil },
                set: { if !$0 { pendingBranchDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingBranchDeletion
        ) { branch in
            Button("Delete \(branch)", role: .destructive) {
                Task { await model.deleteBranch(branch) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { branch in
            Text(
                "This deletes the \(branch) branch reference with a safe delete. Branches not merged into the current branch are kept, and commits stay reachable from other references."
            )
        }
        .remoteBranchDialogs(
            model: model,
            deletion: $pendingRemoteBranchDeletion,
            trackingRemoval: $pendingTrackingReferenceRemoval
        )
        .sheet(isPresented: $isCreatingBranch) {
            switch model.historySelection {
            case .tag(let tag):
                CreateBranchSheet(model: model, startPoint: "refs/tags/\(tag)", startPointLabel: tag)
            case .remoteBranch(let name):
                CreateBranchSheet(model: model, startPoint: "refs/remotes/\(name)", startPointLabel: name)
            default:
                EmptyView()
            }
        }
        .sheet(item: $editedRemote) { remote in
            if let rootURL = model.repository?.rootURL {
                EditRemoteSheet(model: model, repositoryRootURL: rootURL, remote: remote)
            }
        }
    }

    private var historyScopeMenu: some View {
        Menu {
            Toggle("All Branches & Tags", isOn: Binding(
                get: { scope == nil },
                set: { if $0 { scope = nil } }
            ))
            if let scope, scope != .branch(scope.name) {
                Toggle("\(scope.kind) · \(scope.name)", isOn: .constant(true))
            }
            if let selected = model.historySelection, selected != scope {
                Button("Only \(selected.name)") { scope = selected }
                Divider()
            }
            if case .loaded(let branches) = model.localBranchesState, !branches.isEmpty {
                Section("Filter by Branch") {
                    ForEach(branches, id: \.self) { branch in
                        Toggle(branch, isOn: Binding(
                            get: { scope == .branch(branch) },
                            set: { if $0 { scope = .branch(branch) } }
                        ))
                    }
                }
            }
        } label: {
            Text(scope.map { "History · Filter: \($0.name)" } ?? "History · All Branches & Tags")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("History scope")
        .accessibilityValue(scope.map { "\($0.kind) · \($0.name)" } ?? "All Branches & Tags")
        .help("History · \(scope?.name ?? "All Branches & Tags"). Change which commits are shown; this does not switch branches.")
    }

    private var headerTitle: String {
        scope?.name ?? "History"
    }

    private var headerSubtitle: String {
        switch model.historySelection {
        case .branch(let name):
            if name == currentBranchName {
                "Local branch · HEAD"
            } else if let worktreeURL = model.localBranchWorktreeURLs[name] {
                "Local branch · Worktree at \(worktreeURL.path)"
            } else {
                "Local branch"
            }
        case .tag:
            "Tag"
        case .remote(let name):
            if case .loaded(let remotes) = model.remotesState, let remote = remotes.first(where: { $0.name == name }) {
                "Remote · \(remote.fetchURL)"
            } else {
                "Remote"
            }
        case .remoteBranch:
            "Remote branch"
        case nil:
            "All branches and tags · select a branch to jump to its tip"
        }
    }

    /// Switch, Open Worktree, and Integrate for a branch; New Branch… for a tag or remote branch; Fetch, Fetch &
    /// Prune, and Edit… for a remote. Removing a remote lives in its context menu and the Edit… sheet.
    @ViewBuilder
    private var headerTools: some View {
        let isBusy = model.isLoading || model.isSyncing
        switch model.historySelection {
        case .branch(let name) where name != currentBranchName:
            if let worktreeURL = model.localBranchWorktreeURLs[name] {
                Button("Open Worktree") {
                    Task { _ = await model.openWorktree(at: worktreeURL) }
                }
                .help("Open the Worktree at \(worktreeURL.path)")
                .disabled(isBusy)
            } else {
                Button("Switch") {
                    Task { _ = await model.switchBranch(to: name) }
                }
                .help("Switch the working tree to \(name)")
                .disabled(isBusy)
            }
            Button("Integrate…") {
                model.showIntegrateBranch(preselecting: name)
            }
            .help("Merge, rebase, or fast-forward between \(name) and the current branch")
            .disabled(!model.canIntegrateBranch || isBusy)
        case .tag(let name), .remoteBranch(let name):
            Button("New Branch…") {
                isCreatingBranch = true
            }
            .help("Create a local branch at \(name) and switch to it")
            .disabled(isBusy || model.repository == nil)
        case .remote(let name):
            Button("Fetch") {
                fetch(from: name, pruning: false)
            }
            .help("Fetch from \(name)")
            .disabled(isBusy)
            Button("Fetch & Prune") {
                fetch(from: name, pruning: true)
            }
            .help("Fetch from \(name) and remove tracking references it no longer publishes")
            .disabled(isBusy)
            Button("Edit…") {
                if case .loaded(let remotes) = model.remotesState {
                    editedRemote = remotes.first { $0.name == name }
                }
            }
            .help("Rename this Remote, change its URLs, test the connection, or remove it")
            .disabled(model.isLoading)
        case .branch, nil:
            EmptyView()
        }
    }

    private func fetch(from remote: String, pruning: Bool) {
        guard let rootURL = model.repository?.rootURL, !model.isLoading, !model.isSyncing else { return }
        model.fetch(from: remote, pruning: pruning, in: rootURL)
    }

    private var reviewControls: some View {
        HStack(spacing: 8) {
            Text(searchText.isEmpty ? headerTitle : "\(headerTitle) · Filtered")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(searchText.isEmpty ? headerTitle : "\(headerTitle) · Search: \(searchText)")
            if let selected = model.selectedHistoryCommitID,
               let index = visibleHistoryCommitIDs.firstIndex(of: selected) {
                Text("\(index + 1) of \(visibleHistoryCommitIDs.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            Button("Previous Commit", systemImage: "chevron.up") { moveReview(by: -1) }
                .labelStyle(.iconOnly)
                .disabled(adjacentCommit(-1) == nil)
                .help("Previous commit in this History view")
            Button("Next Commit", systemImage: "chevron.down") { moveReview(by: 1) }
                .labelStyle(.iconOnly)
                .disabled(adjacentCommit(1) == nil)
                .help("Next commit in this History view")
            Button(isReviewExpanded ? "Show History" : "Expand Review",
                   systemImage: isReviewExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                isReviewExpanded.toggle()
                if !isReviewExpanded { historyFocused = true }
            }
            .disabled(model.selectedHistoryCommitID == nil && !isReviewExpanded)
            .accessibilityHint("Keep the selected commit and file when changing review size")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func adjacentCommit(_ offset: Int) -> String? {
        RepositoryHistoryNavigation.adjacent(to: model.selectedHistoryCommitID, offset: offset, in: visibleHistoryCommitIDs)
    }

    private func moveReview(by offset: Int) {
        guard let id = adjacentCommit(offset) else { return }
        model.selectedHistoryCommitID = id
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
                    Text("Try a different message, author, SHA, or ref.")
                } actions: {
                    Button("Clear Search") { searchText = "" }
                }
            } else {
                let reachableCommitIDs = history.headReachableCommitIDs()
                let descendantCommitIDs = history.headDescendantCommitIDs()
                VStack(spacing: 0) {
                    ScrollViewReader { scrollProxy in
                        List(commits, selection: $model.selectedHistoryCommitID) { commit in
                            RepositoryHistoryRow(
                                commit: commit,
                                isHEAD: commit.id == history.headCommitID,
                                usesWideRow: historyLayout == .stacked,
                                graphRow: showsCommitGraph ? history.graphRows[commit.id] : nil,
                                graphLaneCount: history.graphLaneCount,
                                currentBranchName: currentBranchName,
                                canFastForwardBranchRefs: commit.id != history.headCommitID
                                    && reachableCommitIDs.contains(commit.id),
                                canFastForwardCurrentHere: commit.id != history.headCommitID
                                    && descendantCommitIDs.contains(commit.id),
                                worktreeURLs: model.localBranchWorktreeURLs,
                                canRemoveWorktree: { model.canRemoveWorktree(at: $0) },
                                fastForward: { branch in
                                    Task { await model.fastForwardBranchToCurrent(branch) }
                                },
                                fastForwardCurrent: { branch in
                                    Task {
                                        guard let rootURL = model.repository?.rootURL else { return }
                                        _ = await model.integrateBranch(
                                            branch,
                                            action: .fastForward,
                                            in: rootURL
                                        )
                                    }
                                },
                                switchToBranch: { branch in
                                    Task { await model.switchBranch(to: branch) }
                                },
                                openWorktree: { url in
                                    Task { await model.openWorktree(at: url) }
                                },
                                requestWorktreeRemoval: { branch, url in
                                    Task {
                                        let trackingRef = await model.trackingRemoteBranch(for: branch)
                                        pendingWorktreeRemoval = .init(
                                            branch: branch,
                                            worktreeURL: url,
                                            trackingRef: trackingRef
                                        )
                                    }
                                },
                                requestBranchDeletion: { branch in
                                    pendingBranchDeletion = branch
                                },
                                requestRemoteBranchDeletion: { trackingRef in
                                    pendingRemoteBranchDeletion = trackingRef
                                },
                                requestTrackingReferenceRemoval: { trackingRef in
                                    pendingTrackingReferenceRemoval = trackingRef
                                }
                            )
                            .tag(commit.id)
                            .gallaeSelectionBackground(isSelected: model.selectedHistoryCommitID == commit.id, isFocused: historyFocused)
                            .listRowInsets(.init(top: 0, leading: 12, bottom: 0, trailing: 12))
                        }
                        .listStyle(.plain)
                        .legacyScrollerAware()
                        .accessibilityLabel("Commit History, \(commits.count) commits")
                        .focused($historyFocused)
                        .onChange(of: historyLayout) {
                            if let id = model.selectedHistoryCommitID { scrollProxy.scrollTo(id) }
                        }
                        .onAppear {
                            if let id = model.selectedHistoryCommitID { scrollProxy.scrollTo(id) }
                        }
                        .onChange(of: model.historyScrollRevision) {
                            if let id = model.selectedHistoryCommitID { scrollProxy.scrollTo(id, anchor: .center) }
                        }
                        .onChange(of: model.selectedHistoryCommitID) {
                            if let id = model.selectedHistoryCommitID { scrollProxy.scrollTo(id) }
                        }
                    }

                    if history.hasMoreCommits {
                        Divider()
                        Button("Load Older Commits · \(history.commits.count) shown") { model.loadMoreHistory() }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private var showsCommitGraph: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentBranchName: String? {
        guard case .branch(let name) = model.repository?.head else { return nil }
        return name
    }
}

private extension RepositoryHistory {
    func headReachableCommitIDs() -> Set<String> {
        guard let headCommitID else { return [] }
        let commitsByID = Dictionary(uniqueKeysWithValues: commits.map { ($0.id, $0) })
        var visited: Set<String> = []
        var stack = [headCommitID]
        while let id = stack.popLast() {
            guard visited.insert(id).inserted, let commit = commitsByID[id] else { continue }
            stack.append(contentsOf: commit.parentIDs)
        }
        return visited
    }

    // HEAD를 ancestor로 갖는 commit들. 여기 닿은 branch로는 현재 branch를 fast-forward할 수 있다.
    func headDescendantCommitIDs() -> Set<String> {
        guard let headCommitID else { return [] }
        var childrenByID: [String: [String]] = [:]
        for commit in commits {
            for parentID in commit.parentIDs {
                childrenByID[parentID, default: []].append(commit.id)
            }
        }
        var visited: Set<String> = []
        var stack = [headCommitID]
        while let id = stack.popLast() {
            guard visited.insert(id).inserted else { continue }
            stack.append(contentsOf: childrenByID[id] ?? [])
        }
        return visited
    }
}

/// Confirmations for the two destructive remote-branch actions, shared by History rows and the remote screen.
private struct RepositoryHistoryRow: View {
    @Environment(\.gallaeTheme) private var theme
    let commit: RepositoryHistory.Commit
    let isHEAD: Bool
    var usesWideRow = false
    let graphRow: RepositoryHistory.GraphRow?
    let graphLaneCount: Int
    var currentBranchName: String? = nil
    var canFastForwardBranchRefs = false
    var canFastForwardCurrentHere = false
    var worktreeURLs: [String: URL] = [:]
    var canRemoveWorktree: (URL) -> Bool = { _ in false }
    var fastForward: (String) -> Void = { _ in }
    var fastForwardCurrent: (String) -> Void = { _ in }
    var switchToBranch: (String) -> Void = { _ in }
    var openWorktree: (URL) -> Void = { _ in }
    var requestWorktreeRemoval: (String, URL) -> Void = { _, _ in }
    var requestBranchDeletion: (String) -> Void = { _ in }
    var requestRemoteBranchDeletion: (String) -> Void = { _ in }
    var requestTrackingReferenceRemoval: (String) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(width: theme.metrics.historyGraphWidth)

            VStack(alignment: .leading, spacing: 3) {
                Text(commit.subject)
                    .font(.callout.weight(isHEAD ? .bold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(isHEAD ? "Current checkout (HEAD)\n\(commit.subject)" : commit.subject)

                if !usesWideRow {
                    HStack(spacing: 4) {
                        Text(commit.authorName)
                        Text("·")
                        Text(RelativeTimeLabel.string(for: commit.committedAt))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if !commit.references.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(commit.references.prefix(2)) { reference in
                            referenceChip(reference)
                        }
                        if commit.references.count > 2 {
                            Text("+\(commit.references.count - 2)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, theme.metrics.rowVerticalPadding)

            Spacer(minLength: 8)

            if usesWideRow {
                Text(commit.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
                Text(RelativeTimeLabel.string(for: commit.committedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 64, alignment: .trailing)
            }
            Text(commit.id.prefix(8))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .overlay(alignment: .leading) {
            RepositoryHistoryGraphView(
                row: graphRow,
                laneCount: max(graphLaneCount, 1)
            )
            .frame(width: theme.metrics.historyGraphWidth)
        }
        .contentShape(.rect)
        .contextMenu {
            branchMenuSections
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(isHEAD ? "HEAD, " : "")\(commit.subject), \(commit.authorName), \(commit.committedAt.formatted(date: .abbreviated, time: .shortened)), revision \(commit.id.prefix(8))\(topologyAccessibilityLabel)\(referenceAccessibilityLabel)"
        )
        .accessibilityActions {
            ForEach(localBranchReferences) { reference in
                if let worktreeURL = worktreeURLs[reference.name] {
                    Button("Open Worktree for \(reference.name)") {
                        openWorktree(worktreeURL)
                    }
                    if canRemoveWorktree(worktreeURL) {
                        Button("Remove Worktree for \(reference.name)") {
                            requestWorktreeRemoval(reference.name, worktreeURL)
                        }
                    }
                } else {
                    Button("Switch to \(reference.name)") {
                        switchToBranch(reference.name)
                    }
                    Button("Remove branch \(reference.name)") {
                        requestBranchDeletion(reference.name)
                    }
                }
                if let target = fastForwardTarget(for: reference) {
                    Button("Fast-Forward \(reference.name) to \(target)") {
                        fastForward(reference.name)
                    }
                }
                if let current = fastForwardCurrentTarget(for: reference) {
                    Button("Fast-Forward \(current) to \(reference.name)") {
                        fastForwardCurrent(reference.name)
                    }
                }
            }
            ForEach(remoteBranchReferences) { reference in
                Button("Delete \(reference.name) on Remote") {
                    requestRemoteBranchDeletion(reference.name)
                }
                Button("Remove tracking reference \(reference.name)") {
                    requestTrackingReferenceRemoval(reference.name)
                }
            }
        }
    }

    private func referenceChip(_ reference: RepositoryHistory.Reference) -> some View {
        let color: Color = switch reference.kind {
        case .branch: theme.colors.historyLocalBranch
        case .remoteBranch: theme.colors.historyRemoteBranch
        case .tag: theme.colors.historyTag
        }
        let highContrast = theme.materials.response == .increasedContrast
        return HStack(spacing: 0) {
            Image(systemName: reference.kind.systemImage)
                .frame(width: 20, height: 18)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(color.opacity(highContrast ? 0.6 : 0.35))
                        .frame(width: 1)
                        .padding(.vertical, 3)
                }
                .accessibilityHidden(true)
            Text(reference.name)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 5)
                .frame(minHeight: 18)
        }
        .font(.caption2.weight(isHEAD ? .bold : .regular))
        .foregroundStyle(color)
        .background(color.opacity(highContrast ? 0.22 : 0.12), in: .rect(cornerRadius: 4))
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(color.opacity(highContrast ? 1 : 0.7), lineWidth: 1)
        }
        .help("\(reference.kind.accessibilityName) · \(reference.name)")
    }

    @ViewBuilder
    private var branchMenuSections: some View {
        ForEach(remoteBranchReferences) { reference in
            Section(reference.name) {
                Button("Delete on Remote…", systemImage: "trash", role: .destructive) {
                    requestRemoteBranchDeletion(reference.name)
                }
                Button(
                    "Remove Tracking Reference…",
                    systemImage: "minus.circle",
                    role: .destructive
                ) {
                    requestTrackingReferenceRemoval(reference.name)
                }
            }
        }
        ForEach(localBranchReferences) { reference in
            Section(reference.name) {
                if let worktreeURL = worktreeURLs[reference.name] {
                    Button(
                        worktreeURL.lastPathComponent == reference.name
                            ? "Open Worktree"
                            : "Open Worktree (\(worktreeURL.lastPathComponent))",
                        systemImage: "folder"
                    ) {
                        openWorktree(worktreeURL)
                    }
                    if canRemoveWorktree(worktreeURL) {
                        Button("Remove Worktree…", systemImage: "folder.badge.minus", role: .destructive) {
                            requestWorktreeRemoval(reference.name, worktreeURL)
                        }
                    }
                } else {
                    Button("Switch", systemImage: "arrow.triangle.branch") {
                        switchToBranch(reference.name)
                    }
                    Button("Remove Branch…", systemImage: "minus.circle", role: .destructive) {
                        requestBranchDeletion(reference.name)
                    }
                }
                if let target = fastForwardTarget(for: reference) {
                    Button(
                        "Fast-Forward \(reference.name) to \(target)",
                        systemImage: "arrow.forward.to.line"
                    ) {
                        fastForward(reference.name)
                    }
                }
                if let current = fastForwardCurrentTarget(for: reference) {
                    Button(
                        "Fast-Forward \(current) to \(reference.name)",
                        systemImage: "arrow.down.to.line"
                    ) {
                        fastForwardCurrent(reference.name)
                    }
                }
            }
        }
    }

    private func fastForwardCurrentTarget(
        for reference: RepositoryHistory.Reference
    ) -> String? {
        guard
            canFastForwardCurrentHere,
            reference.kind == .branch,
            let currentBranchName,
            reference.name != currentBranchName
        else {
            return nil
        }
        return currentBranchName
    }

    private func fastForwardTarget(for reference: RepositoryHistory.Reference) -> String? {
        guard
            canFastForwardBranchRefs,
            reference.kind == .branch,
            let currentBranchName,
            reference.name != currentBranchName
        else {
            return nil
        }
        return currentBranchName
    }

    private var localBranchReferences: [RepositoryHistory.Reference] {
        commit.references.filter { $0.kind == .branch && $0.name != currentBranchName }
    }

    private var remoteBranchReferences: [RepositoryHistory.Reference] {
        commit.references.filter { $0.kind == .remoteBranch }
    }

    private var topologyAccessibilityLabel: String {
        switch commit.parentIDs.count {
        case 0: ", root commit"
        case 1: ""
        default: ", merge commit, \(commit.parentIDs.count) parents"
        }
    }

    private var referenceAccessibilityLabel: String {
        guard !commit.references.isEmpty else { return "" }
        return ", " + commit.references.map {
            "\($0.kind.accessibilityName) \($0.name)"
        }.joined(separator: ", ")
    }
}

private struct RepositoryHistoryGraphView: View {
    let row: RepositoryHistory.GraphRow?
    let laneCount: Int
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        let laneColors = theme.colors.historyGraphLanes
        Canvas { context, size in
            let middleY = size.height / 2
            let laneInset: CGFloat = 4
            let usableWidth = max(size.width - laneInset * 2, 0)
            let lineStyle = StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)

            func xPosition(for lane: Int) -> CGFloat {
                guard laneCount > 1 else { return size.width / 2 }
                return laneInset + CGFloat(lane) * usableWidth / CGFloat(laneCount - 1)
            }

            func laneColor(_ lane: Int) -> Color {
                laneColors[lane % laneColors.count]
            }

            guard let row else {
                let dot = CGRect(x: size.width / 2 - 3, y: middleY - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: dot), with: .color(.primary.opacity(0.75)))
                return
            }

            for edge in row.continuationEdges {
                var path = Path()
                path.move(to: .init(x: xPosition(for: edge.fromLane), y: 0))
                path.addLine(to: .init(x: xPosition(for: edge.toLane), y: size.height))
                context.stroke(
                    path,
                    with: .color(laneColor(edge.toLane).opacity(0.7)),
                    style: lineStyle
                )
            }

            let commitX = xPosition(for: row.commitLane)
            let commitColor = laneColor(row.commitLane)
            if row.hasIncomingEdge {
                var path = Path()
                path.move(to: .init(x: commitX, y: 0))
                path.addLine(to: .init(x: commitX, y: middleY))
                context.stroke(path, with: .color(commitColor), style: lineStyle)
            }

            for edge in row.parentEdges {
                var path = Path()
                path.move(to: .init(x: commitX, y: middleY))
                path.addLine(to: .init(x: xPosition(for: edge.toLane), y: size.height))
                context.stroke(path, with: .color(laneColor(edge.toLane)), style: lineStyle)
            }

            let dot = CGRect(x: commitX - 3, y: middleY - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: dot), with: .color(commitColor))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension RepositoryHistory.Reference.Kind {
    var systemImage: String {
        switch self {
        case .branch: "arrow.triangle.branch"
        case .remoteBranch: "network"
        case .tag: "tag"
        }
    }

    var accessibilityName: String {
        switch self {
        case .branch: "branch"
        case .remoteBranch: "remote branch"
        case .tag: "tag"
        }
    }
}

private struct RepositoryCommitDetailView: View {
    @Bindable var model: AppModel
    var compactHeader = false
    @State private var showsCommitDetails = false
    @Environment(\.gallaeTheme) private var theme
    @State private var mergeCommitPendingRevert: RepositoryHistory.Commit?
    @State private var commitPendingReset: RepositoryHistory.Commit?
    @State private var commitPendingRebasePlan: RepositoryHistory.Commit?
    @State private var showsFullMessage = false

    @ViewBuilder
    var body: some View {
        Group {
            if let commit = model.selectedHistoryCommit {
                VStack(spacing: 0) {
                    if compactHeader { compactCommitHeader(commit) }
                    else { commitHeader(commit) }
                    Divider()
                    RepositoryRevisionChangesView(
                        filesState: model.commitFilesState,
                        selectedFileID: $model.selectedHistoryFileID,
                        selectedFile: model.selectedHistoryFile,
                        patchState: model.commitPatchState,
                        retryFiles: { Task { await model.loadSelectedCommitFiles() } },
                        retryPatch: { Task { await model.loadSelectedCommitPatch() } },
                        loadExpandedPatch: {
                            Task {
                                await model.loadSelectedCommitPatch(
                                    maximumOutputBytes: RepositoryInspector.maximumExpandedDiffBytes
                                )
                            }
                        }
                    )
                }
            } else {
                ContentUnavailableView(
                    "Select a Commit",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Choose a commit to inspect its message and changes.")
                )
            }
        }
        .onChange(of: model.selectedHistoryCommitID) {
            showsFullMessage = false
            showsCommitDetails = false
        }
        .onChange(of: compactHeader) { showsCommitDetails = false }
        .sheet(item: $mergeCommitPendingRevert) { commit in
            RevertMergeCommitSheet(model: model, commit: commit)
        }
        .sheet(item: $commitPendingReset) { commit in
            ResetCurrentBranchSheet(model: model, commit: commit)
        }
        .sheet(item: $commitPendingRebasePlan) { commit in
            InteractiveRebasePlanSheet(model: model, commit: commit)
        }
    }

    private func compactCommitHeader(_ commit: RepositoryHistory.Commit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Text(commit.subject)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(commit.subject)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                Button("Details…", systemImage: "info.circle") { showsCommitDetails = true }
                    .controlSize(.small)
                    .help("Full message, signature, and commit actions")
                    .popover(isPresented: $showsCommitDetails) {
                        ScrollView { commitHeader(commit) }
                            .frame(width: 640, height: 320)
                    }
            }
            HStack(spacing: 12) {
                commitAuthor(commit)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(commit.id.prefix(8))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .help(commit.id)
                        .textSelection(.enabled)
                    commitSignature
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if !commit.body.isEmpty {
                Text(commit.body.split(whereSeparator: \.isWhitespace).joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func commitHeader(_ commit: RepositoryHistory.Commit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                commitAuthor(commit)

                Spacer(minLength: 12)

            HStack(spacing: 8) {
                let rebasePlanUnavailableReason = rebasePlanUnavailableReason
                Button("Rebase Plan…", systemImage: "list.number") {
                    commitPendingRebasePlan = commit
                }
                .disabled(model.isLoading || rebasePlanUnavailableReason != nil)
                .help(
                    rebasePlanUnavailableReason
                        ?? "Preview the default pick plan from this commit through HEAD"
                )
                .accessibilityLabel("Preview Interactive Rebase plan from \(commit.subject)")
                .accessibilityHint(
                    rebasePlanUnavailableReason
                        ?? "Shows a read-only plan without changing the Repository"
                )

                let revertUnavailableReason = historyWriteUnavailableReason
                Button("Revert", systemImage: "arrow.uturn.backward") {
                    if commit.parentIDs.count > 1 {
                        mergeCommitPendingRevert = commit
                    } else {
                        Task { await model.revertCommit(commit) }
                    }
                }
                .disabled(model.isLoading || revertUnavailableReason != nil)
                .help(
                    revertUnavailableReason
                        ?? "Create a new commit that reverses this commit on the current branch"
                )
                .accessibilityHint(
                    revertUnavailableReason
                        ?? "Creates a new commit and keeps the selected commit in History"
                )

                let resetUnavailableReason = resetUnavailableReason(for: commit)
                Button(role: .destructive) {
                    commitPendingReset = commit
                } label: {
                    Label("Reset…", systemImage: "arrow.counterclockwise")
                }
                .disabled(model.isLoading || resetUnavailableReason != nil)
                .help(
                    resetUnavailableReason
                        ?? "Move the current branch to this commit and keep working files"
                )
                .accessibilityLabel("Reset current branch to \(commit.subject)")
                .accessibilityHint(
                    resetUnavailableReason
                        ?? "Choose whether reset changes stay staged or unstaged"
                )
            }
            .fixedSize()
            // ponytail: regular-size buttons plus the author badge exceed the 400pt detail minimum by a few points.
            .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(commit.subject)
                    .font(.headline)
                    .textSelection(.enabled)

                if !commit.body.isEmpty {
                    if showsFullMessage {
                        ScrollView {
                            Text(commit.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Full commit message")
                    } else {
                        Text(commit.body)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                    }
                    Button(showsFullMessage ? "Show Less" : "Show Full Message") {
                        showsFullMessage.toggle()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .font(.caption)
                    .accessibilityValue(showsFullMessage ? "Expanded" : "Collapsed")
                }

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

                commitSignature
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func commitAuthor(_ commit: RepositoryHistory.Commit) -> some View {
        HStack(spacing: 9) {
            RepositoryAuthorBadge(name: commit.authorName, email: commit.authorEmail)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.authorName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(commit.authorEmail) · \(commit.committedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Author \(commit.authorName), \(commit.authorEmail), \(commit.committedAt.formatted(date: .abbreviated, time: .shortened))"
        )
        .help("Author \(commit.authorName), \(commit.authorEmail)")
    }

    @ViewBuilder
    private var commitSignature: some View {
        if let signatureBadge {
            Label(signatureBadge.text, systemImage: signatureBadge.systemImage)
                .font(.caption)
                .foregroundStyle(signatureBadge.color)
                .help("\(signatureBadge.text)\n\(signatureBadge.help)")
                .accessibilityLabel("Commit signature: \(signatureBadge.text)")
        }
    }

    private var signatureBadge: (text: String, systemImage: String, color: Color, help: String)? {
        guard let signature = model.selectedCommitSignature else { return nil }
        switch signature {
        case .none:
            return nil
        case .good(let keyID, let signer):
            return (
                "Signed · \(signer.isEmpty ? keyID : signer)",
                "checkmark.seal",
                theme.colors.statusAdded,
                "Good signature with key \(keyID)"
            )
        case .unverifiedTrust(let keyID, let signer):
            return (
                "Signed · \(signer.isEmpty ? keyID : signer) · trust not verified",
                "checkmark.seal",
                Color.secondary,
                "The signature is valid, but the key’s trust isn’t verified (key \(keyID))"
            )
        case .invalid:
            return (
                "Invalid signature",
                "xmark.seal",
                theme.colors.statusConflict,
                "The signature doesn’t verify, or its key is expired or revoked"
            )
        case .cannotCheck:
            return (
                "Signature can’t be verified",
                "seal",
                Color.secondary,
                "The signing key isn’t available to verify this signature"
            )
        }
    }

    private var rebasePlanUnavailableReason: String? {
        guard let repository = model.repository else {
            return "The Repository is no longer available."
        }
        guard case .branch = repository.head, !repository.isUnborn else {
            return "Switch to a local branch before previewing an Interactive Rebase plan."
        }
        guard repository.operation == nil else {
            return "Finish or abort the current Git operation before previewing a Rebase plan."
        }
        return nil
    }

    private var historyWriteUnavailableReason: String? {
        guard let repository = model.repository else {
            return "The Repository is no longer available."
        }
        guard repository.changes.isEmpty else {
            return "Commit or Stash the current changes before reverting a commit."
        }
        guard case .branch = repository.head, !repository.isUnborn else {
            return "Switch to a local branch before reverting a commit."
        }
        return nil
    }

    private func resetUnavailableReason(
        for commit: RepositoryHistory.Commit
    ) -> String? {
        if let historyWriteUnavailableReason {
            return historyWriteUnavailableReason
        }
        guard
            case .loaded(let history) = model.historyState,
            history.headCommitID != commit.id
        else {
            return "The selected commit is already the current branch’s HEAD."
        }
        return nil
    }

}

private struct InteractiveRebasePlanSheet: View {
    private enum Phase: Equatable {
        case loading
        case editing
        case reviewing
        case running
        case failed(String)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gallaeTheme) private var theme
    let model: AppModel
    let commit: RepositoryHistory.Commit
    @State private var phase = Phase.loading
    @State private var plan: RepositoryInteractiveRebasePlan?
    @State private var rewordMessages: [String: String] = [:]
    @State private var executionError: String?
    @State private var executionTask: Task<Void, Never>?
    @State private var isConfirmingExecution = false
    @FocusState private var focusedRewordStepID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Group {
                switch phase {
                case .loading:
                    ProgressView("Building Rebase Plan…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn’t Build Rebase Plan", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") {
                            Task { await load() }
                        }
                    }
                case .editing:
                    if let plan {
                        editor(plan)
                    }
                case .reviewing:
                    if let plan {
                        review(plan)
                    }
                case .running:
                    ProgressView("Running Interactive Rebase…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            HStack {
                Text(footerMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if phase == .reviewing {
                    Button("Back") {
                        executionError = nil
                        phase = .editing
                    }
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("Run Rebase…", role: .destructive) {
                        isConfirmingExecution = true
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(executionValidationMessage != nil)
                    .accessibilityHint(
                        executionValidationMessage
                            ?? "Confirm before rewriting the current local branch"
                    )
                } else if phase == .running {
                    Button("Cancel Rebase", role: .cancel) {
                        executionTask?.cancel()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Abort Interactive Rebase and restore the original branch")
                } else {
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                if phase == .editing {
                    Button("Review Plan") {
                        reviewPlan()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan?.validationError != nil)
                    .accessibilityHint(
                        validationMessage ?? "Enter Reword messages and review the edited plan"
                    )
                }
            }
        }
        .padding(24)
        .frame(width: 620, height: 520)
        .task(id: commit.id) {
            await load()
        }
        .confirmationDialog(
            "Run Interactive Rebase?",
            isPresented: $isConfirmingExecution
        ) {
            Button("Run Rebase", role: .destructive) {
                executePlan()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This rewrites commit IDs on the current local branch. Other refs and remotes are not moved, and Gallae will not force-push.")
        }
        .interactiveDismissDisabled(phase == .running)
        .onDisappear {
            executionTask?.cancel()
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(headerTitle, systemImage: "list.number")
                .font(.title2.bold())
            Text("Commits from \(commit.id.prefix(8)) through the current HEAD run from top to bottom.")
                .foregroundStyle(.secondary)
            Text(headerDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func editor(_ plan: RepositoryInteractiveRebasePlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 8) {
                        Text(index + 1, format: .number)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)

                        Picker("Action for \(step.subject)", selection: actionBinding(for: step)) {
                            ForEach(RepositoryInteractiveRebasePlan.Action.allCases, id: \.self) { action in
                                Text(action.title).tag(action)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 92)
                        .help(step.action.detail)
                        .accessibilityHint(step.action.detail)

                        Text(step.subject)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(step.id.prefix(8))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        Button("Move Up", systemImage: "chevron.up") {
                            move(stepID: step.id, offset: -1)
                        }
                        .labelStyle(.iconOnly)
                        .disabled(index == 0)
                        .help("Move \(step.subject) up")
                        .accessibilityLabel("Move \(step.subject) up")

                        Button("Move Down", systemImage: "chevron.down") {
                            move(stepID: step.id, offset: 1)
                        }
                        .labelStyle(.iconOnly)
                        .disabled(index == plan.steps.count - 1)
                        .help("Move \(step.subject) down")
                        .accessibilityLabel("Move \(step.subject) down")
                    }
                }
                .onMove(perform: move)
            }
            .listStyle(.inset)
                .legacyScrollerAware()

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(theme.colors.statusConflict)
                    .accessibilityLabel("Invalid Rebase plan: \(validationMessage)")
            }
        }
    }

    private func review(_ plan: RepositoryInteractiveRebasePlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            List(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(index + 1, format: .number)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)
                        Text(step.action.rawValue)
                            .font(.caption.monospaced().weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(theme.colors.badgeBackground, in: Capsule())
                        Text(step.subject)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(step.id.prefix(8))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(step.action.title) \(step.subject), commit \(step.id.prefix(8)), position \(index + 1)"
                    )

                    if step.action == .reword {
                        TextField(
                            "New commit message",
                            text: rewordMessageBinding(for: step),
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .focused($focusedRewordStepID, equals: step.id)
                        .accessibilityLabel("New commit message for \(step.subject)")
                    }
                }
            }
            .listStyle(.inset)
                .legacyScrollerAware()

            if let message = executionError ?? executionValidationMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(theme.colors.statusConflict)
                    .accessibilityLabel("Interactive Rebase unavailable: \(message)")
            }
        }
    }

    private var headerTitle: String {
        switch phase {
        case .editing:
            "Edit Interactive Rebase Plan"
        case .reviewing:
            "Review Interactive Rebase Plan"
        case .running:
            "Running Interactive Rebase"
        case .loading, .failed:
            "Interactive Rebase Plan"
        }
    }

    private var headerDetail: String {
        switch phase {
        case .editing:
            "Choose an action and drag rows or use the arrow buttons to reorder them. Merge commits are omitted."
        case .reviewing:
            "Enter each Reword message, then verify the final order and actions."
        case .running:
            "Git is applying the reviewed plan to the current local branch."
        case .loading, .failed:
            "Merge commits are omitted from the default linear plan."
        }
    }

    private var footerMessage: String {
        switch phase {
        case .reviewing:
            "Run only after checking the order, messages, and rewritten History."
        case .running:
            "Cancel aborts the Rebase and restores the original branch."
        case .loading, .editing, .failed:
            "HEAD, the index, and working files stay unchanged."
        }
    }

    private var executionValidationMessage: String? {
        guard model.repository?.changes.isEmpty == true else {
            return "Commit or Stash the current changes before running Interactive Rebase."
        }
        guard let plan else { return "The Rebase plan is no longer available." }
        for step in plan.steps where step.action == .reword {
            if rewordMessages[step.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                return "Enter a commit message for every Reword step."
            }
        }
        return nil
    }

    private var validationMessage: String? {
        guard let plan else { return nil }
        switch plan.validationError {
        case .none:
            return nil
        case .noCommits:
            return "Keep at least one commit instead of dropping every row."
        case .actionNeedsPreviousCommit(let stepID):
            let action = plan.steps.first { $0.id == stepID }?.action.title ?? "This action"
            return "\(action) needs an earlier commit that is not dropped."
        }
    }

    private func actionBinding(
        for step: RepositoryInteractiveRebasePlan.Step
    ) -> Binding<RepositoryInteractiveRebasePlan.Action> {
        Binding(
            get: {
                plan?.steps.first { $0.id == step.id }?.action ?? step.action
            },
            set: { action in
                guard var plan, let index = plan.steps.firstIndex(where: { $0.id == step.id }) else {
                    return
                }
                plan.steps[index].action = action
                self.plan = plan
            }
        )
    }

    private func rewordMessageBinding(
        for step: RepositoryInteractiveRebasePlan.Step
    ) -> Binding<String> {
        Binding(
            get: { rewordMessages[step.id] ?? step.subject },
            set: { rewordMessages[step.id] = $0 }
        )
    }

    private func reviewPlan() {
        guard let plan else { return }
        for step in plan.steps where step.action == .reword && rewordMessages[step.id] == nil {
            rewordMessages[step.id] = step.subject
        }
        executionError = nil
        phase = .reviewing
        focusedRewordStepID = plan.steps.first { $0.action == .reword }?.id
    }

    private func executePlan() {
        guard let plan, executionValidationMessage == nil else { return }
        executionError = nil
        phase = .running
        executionTask = Task {
            do {
                try await model.executeInteractiveRebase(
                    plan,
                    rewordMessages: rewordMessages,
                    startingAt: commit
                )
                executionTask = nil
                dismiss()
            } catch is CancellationError {
                executionTask = nil
                phase = .reviewing
            } catch {
                executionTask = nil
                executionError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                phase = .reviewing
            }
        }
    }

    private func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard var plan else { return }
        plan.steps.move(fromOffsets: offsets, toOffset: destination)
        self.plan = plan
    }

    private func move(stepID: String, offset: Int) {
        guard
            var plan,
            let index = plan.steps.firstIndex(where: { $0.id == stepID }),
            plan.steps.indices.contains(index + offset)
        else {
            return
        }
        plan.steps.swapAt(index, index + offset)
        self.plan = plan
    }

    @MainActor
    private func load() async {
        phase = .loading
        plan = nil
        rewordMessages = [:]
        executionError = nil
        do {
            let plan = try await model.interactiveRebasePlan(startingAt: commit)
            self.plan = plan
            phase = .editing
        } catch is CancellationError {
            return
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

private extension RepositoryInteractiveRebasePlan.Action {
    var title: String { rawValue.capitalized }

    var detail: String {
        switch self {
        case .pick:
            "Use this commit as it is."
        case .reword:
            "Use this commit and edit its message during Rebase."
        case .squash:
            "Combine this commit with the previous one and keep both messages."
        case .fixup:
            "Combine this commit with the previous one and discard this message."
        case .drop:
            "Remove this commit from the rewritten History."
        }
    }
}

private struct ResetCurrentBranchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: AppModel
    let commit: RepositoryHistory.Commit
    @State private var mode = RepositoryResetMode.mixed
    @State private var isConfirmingHardReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Reset Current Branch", systemImage: "arrow.counterclockwise")
                    .font(.title2.bold())
                Text("Move \(branchName) to \(commit.subject) (\(commit.id.prefix(8))).")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text("Later commits leave this local branch’s History. Remote branches are not changed.")

            VStack(alignment: .leading, spacing: 10) {
                Picker("Reset Mode", selection: $mode) {
                    Text("Keep files as unstaged changes (Mixed)")
                        .tag(RepositoryResetMode.mixed)
                    Text("Keep changes staged (Soft)")
                        .tag(RepositoryResetMode.soft)
                    Text("Discard later files and changes (Hard)")
                        .tag(RepositoryResetMode.hard)
                }
                .pickerStyle(.radioGroup)
                .accessibilityHint("Choose whether changes stay staged, unstaged, or are discarded")

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Reset Branch", role: .destructive) {
                    if mode == .hard {
                        isConfirmingHardReset = true
                    } else {
                        resetBranch()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isLoading)
                .accessibilityHint(modeDescription)
            }
        }
        .padding(24)
        .frame(width: 560)
        .confirmationDialog(
            "Discard Files and Hard Reset?",
            isPresented: $isConfirmingHardReset
        ) {
            Button("Hard Reset to \(commit.id.prefix(8))", role: .destructive) {
                resetBranch()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The branch, index, and working tree will match the selected commit. "
                    + "Later files and changes will be removed or replaced, and blocking untracked "
                    + "files or folders may be deleted. Gallae cannot undo this action."
            )
        }
    }

    private var branchName: String {
        if case .branch(let name) = model.repository?.head {
            name
        } else {
            "current branch"
        }
    }

    private var modeDescription: String {
        switch mode {
        case .mixed:
            "The index moves to the target commit while files stay on disk. Reverted changes become unstaged or untracked."
        case .soft:
            "The index and files stay unchanged. Reverted changes remain staged and ready to recommit."
        case .hard:
            "The index and working tree are replaced with the target commit. Later files and changes are discarded."
        }
    }

    private func resetBranch() {
        dismiss()
        Task { await model.resetCurrentBranch(to: commit, mode: mode) }
    }
}

private struct RevertMergeCommitSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: AppModel
    let commit: RepositoryHistory.Commit
    @State private var selectedMainlineParent: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Revert Merge Commit", systemImage: "arrow.uturn.backward")
                    .font(.title2.bold())
                Text(commit.subject)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Choose the parent to keep as the mainline. Git will reverse the merge’s changes relative to this parent.")

                Picker("Mainline Parent", selection: $selectedMainlineParent) {
                    ForEach(Array(commit.parentIDs.enumerated()), id: \.offset) { index, parentID in
                        Text(parentLabel(number: index + 1, id: parentID))
                            .tag(Optional(index + 1))
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityHint("Choose which parent side remains after reverting the merge")

                Text("The merge commit stays in History. Git records a new commit and treats the merged tree changes as unwanted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Revert Merge") {
                    guard let selectedMainlineParent else { return }
                    dismiss()
                    Task {
                        await model.revertCommit(
                            commit,
                            mainlineParent: selectedMainlineParent
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isLoading || selectedMainlineParent == nil)
                .accessibilityHint("Create a new commit that reverses this merge relative to the selected parent")
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func parentLabel(number: Int, id: String) -> String {
        guard
            case .loaded(let history) = model.historyState,
            let parent = history.commits.first(where: { $0.id == id })
        else {
            return "Parent \(number) · \(id.prefix(8))"
        }
        return "Parent \(number) · \(parent.subject) · \(id.prefix(8))"
    }
}
