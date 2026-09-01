import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

private enum RepositoryChangeViewMode: Int {
    case hierarchy
    case status
}

enum RepositoryWorkspaceSection: Int, CaseIterable {
    case changes
    case history
    case stashes
    case reflog

    var title: String {
        switch self {
        case .changes: "Changes"
        case .history: "History"
        case .stashes: "Stashes"
        case .reflog: "Reflog"
        }
    }
}

struct RepositoryWorkspaceView: View {
    @Bindable var model: AppModel
    @Environment(\.gallaeTheme) private var theme
    @State private var selectedChangeIDs = Set<RepositorySummary.Change.ID>()
    @State private var selectAllEventMonitor: Any?
    @State private var expandedStatusGroups = Set(RepositoryChangeStatusGroup.ID.allCases)
    @State private var commitSubject = ""
    @State private var commitBody = ""
    @State private var isAmending = false
    @State private var amendPrefill: RepositoryCommitMessage?
    @State private var isBranchPickerPresented = false
    @State private var isConfirmingOperationAbort = false
    @FocusState private var isChangeListFocused: Bool
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
                case .stashes:
                    RepositoryStashesView(model: model)
                case .reflog:
                    RepositoryReflogView(model: model)
                }
            }
        }
        .task(id: model.diffRequest) {
            await model.loadSelectedDiff()
        }
        .onChange(of: model.repository?.rootURL, initial: true) {
            commitSubject = ""
            commitBody = ""
            isAmending = false
            amendPrefill = nil
            isConfirmingOperationAbort = false
            selectedChangeIDs = model.selectedChangeID.map { [$0] } ?? []
            if model.repository?.changes.isEmpty == true, workspaceSection == .changes {
                workspaceSection = .history
            }
        }
        .onChange(of: model.repository?.changes) { _, changes in
            let availableIDs = Set((changes ?? []).map(\.id))
            selectedChangeIDs.formIntersection(availableIDs)
            if
                selectedChangeIDs.isEmpty,
                let selectedChangeID = model.selectedChangeID,
                availableIDs.contains(selectedChangeID)
            {
                selectedChangeIDs.insert(selectedChangeID)
            }
        }
        .onChange(of: model.selectedChangeID) { _, selectedChangeID in
            guard let selectedChangeID else {
                selectedChangeIDs.removeAll()
                return
            }
            if !selectedChangeIDs.contains(selectedChangeID) {
                selectedChangeIDs = [selectedChangeID]
            }
        }
        .onChange(of: selectedChangeIDs) { previousSelection, selection in
            let addedIDs = selection.subtracting(previousSelection)
            let focusedID: RepositorySummary.Change.ID?
            if addedIDs.count == 1 {
                focusedID = addedIDs.first
            } else if let selectedChangeID = model.selectedChangeID,
                      selection.contains(selectedChangeID) {
                focusedID = selectedChangeID
            } else {
                focusedID = model.repository?.changes.first {
                    selection.contains($0.id)
                }?.id
            }
            if model.selectedChangeID != focusedID {
                model.selectedChangeID = focusedID
            }
        }
        .focusedSceneValue(\.workspaceSection, $workspaceSection)
        .onAppear(perform: startSelectAllEventMonitor)
        .onDisappear(perform: stopSelectAllEventMonitor)
        .confirmationDialog(
            "Remove Temporary Worktree?",
            isPresented: Binding(
                get: { model.pendingTemporaryWorktreeRemovalURL != nil },
                set: { if !$0 { model.pendingTemporaryWorktreeRemovalURL = nil } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingTemporaryWorktreeRemovalURL
        ) { worktreeURL in
            Button("Remove Temporary Worktree", role: .destructive) {
                Task { await model.removeTemporaryWorktree(at: worktreeURL) }
            }
            Button("Keep Worktree", role: .cancel) {}
        } message: { worktreeURL in
            Text(
                "The merge is finished. Removing deletes the folder at \(worktreeURL.path); the branch and its commits stay. Gallae won’t remove it while changes remain inside."
            )
        }
        .confirmationDialog(
            "Abort Repository Operation?",
            isPresented: $isConfirmingOperationAbort,
            titleVisibility: .visible,
            presenting: model.repository?.operation
        ) { operation in
            Button("Abort \(operation.kind.name)", role: .destructive) {
                Task { await model.abortRepositoryOperation() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { operation in
            Text(
                "Git will stop the \(operation.kind.name.lowercased()) and try to restore its earlier state. "
                    + "Changes made while resolving conflicts may be discarded."
            )
        }
    }

    private var repositoryHeader: some View {
        VStack(spacing: 0) {
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
                        ForEach(RepositoryWorkspaceSection.allCases, id: \.self) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Switch between working tree changes, commit history, Stashes, and Reflog")
                    .accessibilityLabel("Repository View")

                    VStack(alignment: .trailing, spacing: 5) {
                        Button {
                            isBranchPickerPresented = true
                        } label: {
                            HStack(spacing: 6) {
                                Label(repository.head.label, systemImage: repository.head.systemImage)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .accessibilityHidden(true)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .font(.callout.weight(.medium))
                        .help("Choose a local branch")
                        .accessibilityLabel("HEAD, \(repository.head.label). Choose Local Branch")
                        .disabled(model.isLoading)
                        .popover(isPresented: $isBranchPickerPresented) {
                            RepositoryBranchPicker(
                                model: model,
                                isPresented: $isBranchPickerPresented
                            )
                        }
                        if let upstream = repository.upstream {
                            Label(
                                upstreamDisplayLabel(upstream, head: repository.head),
                                systemImage: "arrow.up.arrow.down"
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help("Tracks \(upstream.label)")
                                .accessibilityLabel("Tracking branch, \(upstream.label)")
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
                        if model.isCurrentWorkspaceTemporaryWorktree {
                            Label("Temporary Worktree", systemImage: "folder.badge.gearshape")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Gallae created this Worktree for a merge and offers to remove it when the merge finishes")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if let operation = model.repository?.operation {
                Divider()
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Label(operation.kind.label, systemImage: "arrow.triangle.merge")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(
                                operation.canContinue
                                    ? theme.colors.statusAdded
                                    : theme.colors.statusConflict
                            )
                        Text(operation.conflictLabel)
                        Text(operation.actionLabel)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(operation.kind.label). \(operation.conflictLabel). \(operation.actionLabel)"
                    )
                    Spacer()
                    Button("Continue") {
                        Task { await model.continueRepositoryOperation() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!operation.canContinue || model.isLoading)
                    .help("Continue the \(operation.kind.name) after resolving all conflicts")
                    .accessibilityHint("Finish the \(operation.kind.name) using Git")

                    Button("Abort…", role: .destructive) {
                        isConfirmingOperationAbort = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isLoading)
                    .help("Stop the \(operation.kind.name) and try to restore its earlier state")
                    .accessibilityHint("Opens a confirmation before stopping the \(operation.kind.name)")
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(theme.colors.badgeBackground)
            }
        }
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
                    canResolveConflict: model.canResolveSelectedConflict,
                    canStageHunks: model.canStageSelectedHunks,
                    canUnstageHunks: model.canUnstageSelectedHunks,
                    isBusy: model.isLoading,
                    stage: { Task { await model.stageSelectedChange() } },
                    unstage: { Task { await model.unstageSelectedChange() } },
                    discard: { id in Task { await model.discardChange(id: id) } },
                    resolveConflict: { side in
                        Task { await model.resolveSelectedConflict(using: side) }
                    },
                    markConflictResolved: {
                        Task { await model.markSelectedConflictResolved() }
                    },
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
        .onChange(of: isAmending) { _, isOn in
            if isOn {
                guard commitSubject.isEmpty, commitBody.isEmpty else { return }
                Task {
                    guard
                        let message = await model.headCommitMessage(),
                        isAmending, commitSubject.isEmpty, commitBody.isEmpty
                    else { return }
                    commitSubject = message.subject
                    commitBody = message.body
                    amendPrefill = message
                }
            } else if let amendPrefill {
                self.amendPrefill = nil
                if commitSubject == amendPrefill.subject, commitBody == amendPrefill.body {
                    commitSubject = ""
                    commitBody = ""
                }
            }
        }
    }

    private func changeHierarchyList(_ repository: RepositorySummary) -> some View {
        List(selection: $selectedChangeIDs) {
            OutlineGroup(
                RepositoryChangeHierarchyNode.make(repository.changes),
                children: \.children
            ) { node in
                changeHierarchyRow(node)
                    .listRowInsets(.init(top: 7, leading: 12, bottom: 7, trailing: 12))
            }
        }
        .listStyle(.plain)
        .focused($isChangeListFocused)
        .accessibilityLabel("Changes by folder, \(repository.changes.count) files")
    }

    private func changeStatusList(_ repository: RepositorySummary) -> some View {
        List(selection: $selectedChangeIDs) {
            ForEach(RepositoryChangeStatusGroup.make(repository.changes)) { group in
                Section {
                    if expandedStatusGroups.contains(group.id) {
                        ForEach(group.changes) { change in
                            changeRow(change, showsParentPath: true)
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
        .focused($isChangeListFocused)
        .accessibilityLabel("Changes by status, \(repository.changes.count) files")
    }

    private func startSelectAllEventMonitor() {
        guard selectAllEventMonitor == nil else { return }
        selectAllEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard
                !(event.window is NSPanel),
                modifiers == .command,
                event.keyCode == UInt16(kVK_ANSI_A),
                workspaceSection == .changes,
                changeViewMode == .status,
                isChangeListFocused,
                let repository = model.repository,
                let selectedChangeID = model.selectedChangeID
            else { return event }

            let groupIDs = RepositoryChangeStatusGroup.selectAllIDs(
                containing: selectedChangeID,
                in: repository.changes
            )
            guard !groupIDs.isEmpty else { return event }
            selectedChangeIDs = groupIDs
            return nil
        }
    }

    private func stopSelectAllEventMonitor() {
        guard let selectAllEventMonitor else { return }
        NSEvent.removeMonitor(selectAllEventMonitor)
        self.selectAllEventMonitor = nil
    }

    private func toggleStatusGroup(_ id: RepositoryChangeStatusGroup.ID) {
        if expandedStatusGroups.contains(id) {
            expandedStatusGroups.remove(id)
        } else {
            expandedStatusGroups.insert(id)
        }
    }

    @ViewBuilder
    private func changeHierarchyRow(_ node: RepositoryChangeHierarchyNode) -> some View {
        if let change = node.change {
            changeRow(change)
        } else {
            RepositoryChangeFolderRow(node: node)
        }
    }

    private func changeRow(
        _ change: RepositorySummary.Change,
        showsParentPath: Bool = false
    ) -> some View {
        RepositoryChangeRow(change: change, showsParentPath: showsParentPath)
            .contextMenu {
                let changeIDs = contextChangeIDs(for: change.id)
                Button(changeIDs.count > 1 ? "Stage Selected" : "Stage") {
                    Task { await model.stageChanges(ids: changeIDs) }
                }
                .disabled(model.isLoading || !model.canStageChanges(ids: changeIDs))

                Button(changeIDs.count > 1 ? "Unstage Selected" : "Unstage") {
                    Task { await model.unstageChanges(ids: changeIDs) }
                }
                .disabled(model.isLoading || !model.canUnstageChanges(ids: changeIDs))
            }
            .tag(change.id)
    }

    private func contextChangeIDs(
        for changeID: RepositorySummary.Change.ID
    ) -> Set<RepositorySummary.Change.ID> {
        selectedChangeIDs.contains(changeID) ? selectedChangeIDs : [changeID]
    }

    private func selectedFileURL(in repository: RepositorySummary) -> URL? {
        guard let selectedChangeID = model.selectedChangeID else { return nil }
        return repository.rootURL.appending(path: selectedChangeID)
    }

    // remote branch 이름이 현재 branch와 같으면 remote 이름만 남겨 긴 이름의 중복 잘림을 줄인다.
    private func upstreamDisplayLabel(
        _ upstream: RepositorySummary.Upstream,
        head: RepositorySummary.Head
    ) -> String {
        guard
            case .branch(let branch) = head,
            upstream.name.hasSuffix("/\(branch)"),
            upstream.name.count > branch.count + 1
        else {
            return upstream.label
        }
        let remote = String(upstream.name.dropLast(branch.count + 1))
        guard let ahead = upstream.ahead, let behind = upstream.behind else { return remote }
        return "\(remote) · ↑\(ahead) ↓\(behind)"
    }
}

private struct RepositoryBranchPicker: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var selectedBranch: String?
    @State private var newBranchName = ""
    @State private var isCreatingBranch = false
    @State private var pendingWorktreeRemoval: WorktreeRemovalRequest?
    @State private var pendingBranchDeletion: String?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isNewBranchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search Local Branches", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .accessibilityLabel("Search Local Branches")
                .padding(12)

            Divider()

            branchContent

            Divider()

            branchActions
        }
        .frame(width: 340, height: 360)
        .task(id: model.repositoryRevision) {
            await model.loadLocalBranches()
            isSearchFocused = true
        }
        .onChange(of: model.localBranchesState, initial: true) { _, _ in
            reconcileSelection()
        }
        .onChange(of: searchText) {
            reconcileSelection()
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
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(
                "This removes the Worktree folder at \(request.worktreeURL.path). The \(request.branch) branch and its commits stay. Git keeps the Worktree if changes or an operation remain inside."
            )
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
    }

    @ViewBuilder
    private var branchActions: some View {
        if isCreatingBranch {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create from \(model.repository?.head.label ?? "current HEAD")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("New Branch Name", text: $newBranchName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNewBranchFocused)
                        .accessibilityLabel("New Branch Name")

                    Button("Cancel") {
                        newBranchName = ""
                        isCreatingBranch = false
                        isSearchFocused = true
                    }

                    Button("Create") {
                        createBranch()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
                    .accessibilityHint("Creates and switches to the new local branch")
                }
            }
            .padding(12)
        } else {
            HStack {
                Button("New Branch…", systemImage: "plus") {
                    isCreatingBranch = true
                    Task {
                        await Task.yield()
                        isNewBranchFocused = true
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoading)
                .accessibilityHint("Creates a local branch from the current HEAD")

                Spacer()

                if case .loaded(let branches) = model.localBranchesState {
                    Text("\(branches.count) Local Branches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button(primaryActionTitle) {
                    performPrimaryAction()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canPerformPrimaryAction)
                .accessibilityHint(primaryActionHint)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var branchContent: some View {
        switch model.localBranchesState {
        case .notLoaded, .loading:
            ProgressView("Loading Branches…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Load Branches", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await model.loadLocalBranches() }
                }
            }
        case .loaded(let branches) where branches.isEmpty:
            ContentUnavailableView(
                "No Local Branches",
                systemImage: "arrow.triangle.branch",
                description: Text("This Repository has no local branches to switch to.")
            )
        case .loaded:
            if filteredBranches.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Branches", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different branch name.")
                } actions: {
                    Button("Clear Search") { searchText = "" }
                }
            } else {
                List(filteredBranches, id: \.self, selection: $selectedBranch) { branch in
                    HStack(spacing: 8) {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(1)
                        Spacer()
                        if branch == currentBranch {
                            Label("Current", systemImage: "checkmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let worktreeURL = model.localBranchWorktreeURLs[branch] {
                            Label(
                                worktreeURL.lastPathComponent == branch
                                    ? "Worktree"
                                    : worktreeURL.lastPathComponent,
                                systemImage: "folder"
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 140)
                                .layoutPriority(2)
                                .help(worktreeURL.path)
                        }
                    }
                    .tag(branch)
                    .contentShape(.rect)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(accessibilityValue(for: branch))
                }
                .listStyle(.plain)
                .contextMenu(forSelectionType: String.self) { branches in
                    if let branch = branches.first, branch != currentBranch {
                        if let worktreeURL = model.localBranchWorktreeURLs[branch] {
                            Button("Open Worktree", systemImage: "folder") {
                                performPrimaryAction(for: branch)
                            }
                            .disabled(model.isLoading)

                            Button(
                                "Remove Worktree…",
                                systemImage: "folder.badge.minus",
                                role: .destructive
                            ) {
                                pendingWorktreeRemoval = .init(
                                    branch: branch,
                                    worktreeURL: worktreeURL
                                )
                            }
                            .disabled(model.isLoading)
                        } else {
                            Button("Switch", systemImage: "arrow.triangle.branch") {
                                performPrimaryAction(for: branch)
                            }
                            .disabled(model.isLoading)

                            Button(
                                "Remove Branch…",
                                systemImage: "minus.circle",
                                role: .destructive
                            ) {
                                pendingBranchDeletion = branch
                            }
                            .disabled(model.isLoading)
                        }
                    }
                } primaryAction: { branches in
                    guard let branch = branches.first else { return }
                    performPrimaryAction(for: branch)
                }
                .accessibilityLabel("Local Branches")
            }
        }
    }

    private var filteredBranches: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return loadedBranches }
        return loadedBranches.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var loadedBranches: [String] {
        guard case .loaded(let branches) = model.localBranchesState else { return [] }
        return branches
    }

    private var currentBranch: String? {
        guard let repository = model.repository else { return nil }
        guard case .branch(let branch) = repository.head else { return nil }
        return branch
    }

    private var selectedWorktreeURL: URL? {
        guard let selectedBranch, selectedBranch != currentBranch else { return nil }
        return model.localBranchWorktreeURLs[selectedBranch]
    }

    private var primaryActionTitle: String {
        selectedWorktreeURL == nil ? "Switch" : "Open Worktree"
    }

    private var primaryActionHint: String {
        selectedWorktreeURL == nil
            ? "Switches to the selected local branch"
            : "Opens the selected branch’s existing Worktree folder"
    }

    private var canPerformPrimaryAction: Bool {
        guard let selectedBranch else { return false }
        return selectedBranch != currentBranch && !model.isLoading
    }

    private var canCreate: Bool {
        !newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isLoading
    }

    private func reconcileSelection() {
        if let selectedBranch, filteredBranches.contains(selectedBranch) {
            return
        }
        selectedBranch = currentBranch.flatMap { branch in
            filteredBranches.contains(branch) ? branch : nil
        } ?? filteredBranches.first
    }

    private func performPrimaryAction() {
        guard let selectedBranch else { return }
        performPrimaryAction(for: selectedBranch)
    }

    private func performPrimaryAction(for branch: String) {
        guard branch != currentBranch, !model.isLoading else { return }
        Task {
            let succeeded = if let worktreeURL = model.localBranchWorktreeURLs[branch] {
                await model.openRepository(at: worktreeURL)
            } else {
                await model.switchBranch(to: branch)
            }
            if succeeded {
                isPresented = false
            }
        }
    }

    private func accessibilityValue(for branch: String) -> String {
        if branch == currentBranch { return "Current branch" }
        guard let worktreeURL = model.localBranchWorktreeURLs[branch] else { return "" }
        return "Existing Worktree at \(worktreeURL.path)"
    }

    private func createBranch() {
        guard canCreate else { return }
        Task {
            if await model.createBranch(named: newBranchName) {
                isPresented = false
            }
        }
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

    static func selectAllIDs(
        containing selectedChangeID: RepositorySummary.Change.ID,
        in changes: [RepositorySummary.Change]
    ) -> Set<RepositorySummary.Change.ID> {
        guard let group = make(changes).first(where: {
            $0.changes.contains { $0.id == selectedChangeID }
        }) else { return [] }
        return Set(group.changes.map(\.id))
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

private struct WorktreeRemovalRequest {
    let branch: String
    let worktreeURL: URL
}

private struct RepositoryHistoryView: View {
    @Bindable var model: AppModel
    @Environment(\.gallaeTheme) private var theme
    @State private var searchText = ""
    @State private var pendingWorktreeRemoval: WorktreeRemovalRequest?
    @State private var pendingBranchDeletion: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                VStack(spacing: 7) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("History")
                                .font(.headline)
                            Text("Branches & Tags · latest 100")
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
                        TextField("Search message, author, SHA, or ref", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Search Commit History")
                            .onExitCommand { searchText = "" }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider()

                historyList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(
                minWidth: theme.metrics.changeListMinimumWidth,
                idealWidth: theme.metrics.changeListIdealWidth,
                maxHeight: .infinity
            )

            RepositoryCommitDetailView(model: model)
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .task(id: model.historyRequest) {
            await model.loadHistory()
            await model.loadLocalBranches()
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
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(
                "This removes the Worktree folder at \(request.worktreeURL.path). The \(request.branch) branch and its commits stay. Git keeps the Worktree if changes or an operation remain inside."
            )
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
                    List(commits, selection: $model.selectedHistoryCommitID) { commit in
                        RepositoryHistoryRow(
                            commit: commit,
                            isHEAD: commit.id == history.headCommitID,
                            graphRow: showsCommitGraph ? history.graphRows[commit.id] : nil,
                            graphLaneCount: history.graphLaneCount,
                            currentBranchName: currentBranchName,
                            canFastForwardBranchRefs: commit.id != history.headCommitID
                                && reachableCommitIDs.contains(commit.id),
                            canFastForwardCurrentHere: commit.id != history.headCommitID
                                && descendantCommitIDs.contains(commit.id),
                            worktreeURLs: model.localBranchWorktreeURLs,
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
                                Task { await model.openRepository(at: url) }
                            },
                            requestWorktreeRemoval: { branch, url in
                                pendingWorktreeRemoval = .init(branch: branch, worktreeURL: url)
                            },
                            requestBranchDeletion: { branch in
                                pendingBranchDeletion = branch
                            }
                        )
                        .tag(commit.id)
                        .listRowInsets(.init(top: 0, leading: 12, bottom: 0, trailing: 12))
                    }
                    .listStyle(.plain)
                    .accessibilityLabel("Commit History, \(commits.count) commits")

                    if history.commits.count == RepositoryInspector.maximumHistoryCommits {
                        Divider()
                        Text("Showing the latest \(history.commits.count) commits · older commits aren’t listed")
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

private struct RepositoryStashesView: View {
    @Bindable var model: AppModel
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stashes")
                            .font(.headline)
                        Text("Newest first · latest 100")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if case .loaded(let stashes) = model.stashesState {
                        Text(stashes.count, format: .number)
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(theme.colors.badgeBackground, in: .capsule)
                    }
                    Button("New Stash", systemImage: "plus") {
                        model.showCreateStash()
                    }
                    .disabled(model.repository?.changes.isEmpty != false || model.isLoading)
                    .accessibilityHint("Save the current Repository changes as a new Stash")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider()

                stashList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(
                minWidth: theme.metrics.changeListMinimumWidth,
                idealWidth: theme.metrics.changeListIdealWidth,
                maxHeight: .infinity
            )

            RepositoryStashDetailView(model: model)
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .task(id: model.stashesRequest) {
            await model.loadStashes()
        }
        .task(id: model.stashFilesRequest) {
            await model.loadSelectedStashFiles()
        }
        .task(id: model.stashPatchRequest) {
            await model.loadSelectedStashPatch()
        }
    }

    @ViewBuilder
    private var stashList: some View {
        switch model.stashesState {
        case .notLoaded, .loading:
            ProgressView("Loading Stashes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Load Stashes", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await model.loadStashes() }
                }
                .accessibilityLabel("Try Again")
            }
        case .loaded(let stashes) where stashes.isEmpty:
            ContentUnavailableView(
                "No Stashes",
                systemImage: "archivebox",
                description: Text("This Repository has no saved Stashes.")
            )
        case .loaded(let stashes):
            List(stashes, selection: $model.selectedStashID) { stash in
                RepositoryStashRow(stash: stash)
                    .tag(stash.id)
                    .listRowInsets(.init(top: 0, leading: 12, bottom: 0, trailing: 12))
            }
            .listStyle(.plain)
            .accessibilityLabel("Stashes, \(stashes.count) items")
        }
    }
}

private struct RepositoryReflogView: View {
    @Bindable var model: AppModel
    @Environment(\.gallaeTheme) private var theme
    @State private var recoveryEntry: RepositoryReflogEntry?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reflog")
                            .font(.headline)
                        Text("HEAD movements · latest 100")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if case .loaded(let entries) = model.reflogState {
                        Text(entries.count, format: .number)
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(theme.colors.badgeBackground, in: .capsule)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider()

                reflogList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(
                minWidth: theme.metrics.changeListMinimumWidth,
                idealWidth: theme.metrics.changeListIdealWidth,
                maxHeight: .infinity
            )

            RepositoryReflogDetailView(
                entry: model.selectedReflogEntry,
                onRecover: { recoveryEntry = $0 }
            )
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .task(id: model.reflogRequest) {
            await model.loadReflog()
        }
        .sheet(item: $recoveryEntry) { entry in
            RepositoryRecoveryBranchSheet(model: model, entry: entry)
        }
    }

    @ViewBuilder
    private var reflogList: some View {
        switch model.reflogState {
        case .notLoaded, .loading:
            ProgressView("Loading Reflog…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Load Reflog", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await model.loadReflog() }
                }
                .accessibilityLabel("Try Again")
            }
        case .loaded(let entries) where entries.isEmpty:
            ContentUnavailableView(
                "No Recovery Points",
                systemImage: "clock.arrow.circlepath",
                description: Text("This Repository has no HEAD Reflog entries.")
            )
        case .loaded(let entries):
            List(entries, selection: $model.selectedReflogEntryID) { entry in
                RepositoryReflogRow(entry: entry)
                    .tag(entry.id)
                    .listRowInsets(.init(top: 0, leading: 12, bottom: 0, trailing: 12))
            }
            .listStyle(.plain)
            .accessibilityLabel("Reflog, \(entries.count) recovery points")
        }
    }
}

private struct RepositoryReflogRow: View {
    let entry: RepositoryReflogEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.action)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text(entry.selector)
                        .font(.caption.monospaced())
                    Text("·")
                    Text(RelativeTimeLabel.string(for: entry.occurredAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.vertical, 7)

            Spacer(minLength: 8)

            Text(entry.commitID.prefix(8))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.selector), \(entry.action), \(entry.occurredAt.formatted(date: .abbreviated, time: .shortened)), revision \(entry.commitID.prefix(8))"
        )
    }
}

private struct RepositoryReflogDetailView: View {
    let entry: RepositoryReflogEntry?
    let onRecover: (RepositoryReflogEntry) -> Void

    var body: some View {
        if let entry {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(entry.selector, systemImage: "clock.arrow.circlepath")
                        .font(.title2.weight(.semibold))

                    Text(entry.action)
                        .font(.title3)
                        .textSelection(.enabled)

                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            Text("Commit")
                                .foregroundStyle(.secondary)
                            Text(entry.commitID)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                        GridRow {
                            Text("Recorded")
                                .foregroundStyle(.secondary)
                            Text(entry.occurredAt.formatted(date: .abbreviated, time: .standard))
                        }
                        GridRow {
                            Text("By")
                                .foregroundStyle(.secondary)
                            Text("\(entry.actorName) <\(entry.actorEmail)>")
                                .textSelection(.enabled)
                        }
                    }

                    Text("This records where HEAD pointed after the action. Git may expire older Reflog entries during maintenance.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button("Create Recovery Branch…", systemImage: "arrow.triangle.branch") {
                        onRecover(entry)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Creates and switches to a new local branch at this recovery point")
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            ContentUnavailableView(
                "Select a Recovery Point",
                systemImage: "clock.arrow.circlepath",
                description: Text("Choose a Reflog entry to inspect its action and commit.")
            )
        }
    }
}

private struct RepositoryRecoveryBranchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    let entry: RepositoryReflogEntry
    @State private var branchName = ""
    @FocusState private var isBranchNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Create Recovery Branch", systemImage: "arrow.triangle.branch")
                    .font(.title2.bold())
                Text("Create and switch to a new local branch at (entry.selector).")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Commit") {
                Text(entry.commitID)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            TextField("Branch Name", text: $branchName)
                .textFieldStyle(.roundedBorder)
                .focused($isBranchNameFocused)
                .onSubmit(createBranch)
                .accessibilityLabel("Recovery Branch Name")

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create & Switch") {
                    createBranch()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .accessibilityHint("Creates the recovery branch without changing existing branch references")
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { isBranchNameFocused = true }
        .interactiveDismissDisabled(model.isLoading)
    }

    private var canCreate: Bool {
        !branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isLoading
    }

    private func createBranch() {
        guard canCreate else { return }
        Task {
            if await model.createBranch(named: branchName, at: entry.commitID) {
                dismiss()
            }
        }
    }
}

private struct RepositoryStashRow: View {
    let stash: RepositoryStash

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(stash.subject)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text(stash.reference)
                        .font(.caption.monospaced())
                    Text("·")
                    Text(RelativeTimeLabel.string(for: stash.createdAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.vertical, 7)

            Spacer(minLength: 8)

            Text(stash.id.prefix(8))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(stash.reference), \(stash.subject), \(stash.createdAt.formatted(date: .abbreviated, time: .shortened)), revision \(stash.id.prefix(8))"
        )
    }
}

@MainActor
enum RelativeTimeLabel {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func string(for date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: .now)
    }
}

enum AuthorAvatarSource {
    // GitHub noreply 이메일에 든 공개 ID·사용자명만 사용한다.
    // 이메일 자체는 어떤 네트워크 요청에도 실리지 않는다.
    static func url(for email: String) -> URL? {
        let email = email.lowercased()
        let suffix = "@users.noreply.github.com"
        guard email.hasSuffix(suffix) else { return nil }
        let local = email.dropLast(suffix.count)

        if let plusIndex = local.firstIndex(of: "+") {
            let id = local[..<plusIndex]
            guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
            return URL(string: "https://avatars.githubusercontent.com/u/\(id)?s=64&v=4")
        }

        guard
            !local.isEmpty,
            local.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        else {
            return nil
        }
        return URL(string: "https://github.com/\(local).png?size=64")
    }
}

// commit 이메일로 GitHub 공개 계정을 조회한다. 이메일은 GitHub API에만 전송되고,
// 성공 결과는 이메일별로 저장해 반복 조회하지 않는다. 실패는 세션 안에서만 기억한다.
@MainActor
final class GitHubAvatarLookup {
    static let shared = GitHubAvatarLookup()
    private static let cacheKey = "gitHubAvatarURLsByEmail"

    private var cache: [String: URL]
    private var unresolvedEmails: Set<String> = []

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: String]
        cache = stored?.compactMapValues(URL.init(string:)) ?? [:]
    }

    func avatarURL(for email: String) async -> URL? {
        let key = email.lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        guard !unresolvedEmails.contains(key) else { return nil }

        guard var components = URLComponents(string: "https://api.github.com/search/users") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: "\(key) in:email"),
            URLQueryItem(name: "per_page", value: "1")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                unresolvedEmails.insert(key)
                return nil
            }
            guard let avatarURL = Self.avatarURL(fromSearchResponse: data) else {
                unresolvedEmails.insert(key)
                return nil
            }
            cache[key] = avatarURL
            UserDefaults.standard.set(
                cache.mapValues(\.absoluteString),
                forKey: Self.cacheKey
            )
            return avatarURL
        } catch {
            unresolvedEmails.insert(key)
            return nil
        }
    }

    static func avatarURL(fromSearchResponse data: Data) -> URL? {
        struct SearchResponse: Decodable {
            struct Item: Decodable {
                let avatarURL: String

                enum CodingKeys: String, CodingKey {
                    case avatarURL = "avatar_url"
                }
            }

            let items: [Item]
        }

        guard
            let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
            let item = response.items.first,
            let url = URL(string: item.avatarURL + "&s=64")
        else {
            return nil
        }
        return url
    }
}

enum AuthorIdentity {
    static func initials(for name: String) -> String {
        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        let joined = letters.joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }

    // 실행마다 바뀌는 hashValue 대신 안정적인 해시로 같은 작성자에게 항상 같은 색을 준다.
    static func colorIndex(for identity: String, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        var hash: UInt64 = 5381
        for scalar in identity.lowercased().unicodeScalars {
            hash = (hash << 5) &+ hash &+ UInt64(scalar.value)
        }
        return Int(hash % UInt64(paletteCount))
    }
}

private struct RepositoryAuthorBadge: View {
    let name: String
    let email: String
    @AppStorage("loadsGitHubAvatars") private var loadsGitHubAvatars = true
    @State private var resolvedAvatarURL: URL?
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        Group {
            if let resolvedAvatarURL {
                AsyncImage(url: resolvedAvatarURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(.circle)
                    } else {
                        initialsBadge
                    }
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            } else {
                initialsBadge
            }
        }
        .task(id: "\(loadsGitHubAvatars)|\(email)") {
            guard loadsGitHubAvatars else {
                resolvedAvatarURL = nil
                return
            }
            if let directURL = AuthorAvatarSource.url(for: email) {
                resolvedAvatarURL = directURL
                return
            }
            resolvedAvatarURL = nil
            let lookedUp = await GitHubAvatarLookup.shared.avatarURL(for: email)
            guard !Task.isCancelled else { return }
            resolvedAvatarURL = lookedUp
        }
    }

    private var initialsBadge: some View {
        let palette = theme.colors.authorBadgeColors
        let color = palette[AuthorIdentity.colorIndex(
            for: email.isEmpty ? name : email,
            paletteCount: palette.count
        )]
        return Text(AuthorIdentity.initials(for: name))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color.gradient, in: .circle)
            .accessibilityHidden(true)
    }
}

private struct RepositoryHistoryRow: View {
    @Environment(\.gallaeTheme) private var theme
    let commit: RepositoryHistory.Commit
    let isHEAD: Bool
    let graphRow: RepositoryHistory.GraphRow?
    let graphLaneCount: Int
    var currentBranchName: String? = nil
    var canFastForwardBranchRefs = false
    var canFastForwardCurrentHere = false
    var worktreeURLs: [String: URL] = [:]
    var fastForward: (String) -> Void = { _ in }
    var fastForwardCurrent: (String) -> Void = { _ in }
    var switchToBranch: (String) -> Void = { _ in }
    var openWorktree: (URL) -> Void = { _ in }
    var requestWorktreeRemoval: (String, URL) -> Void = { _, _ in }
    var requestBranchDeletion: (String) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(width: theme.metrics.historyGraphWidth)

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
                    Text(RelativeTimeLabel.string(for: commit.committedAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if !commit.references.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(commit.references.prefix(2)) { reference in
                            Label(reference.name, systemImage: reference.kind.systemImage)
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: .capsule)
                        }
                        if commit.references.count > 2 {
                            Text("+\(commit.references.count - 2)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 7)

            Spacer(minLength: 8)

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
                    Button("Remove Worktree for \(reference.name)") {
                        requestWorktreeRemoval(reference.name, worktreeURL)
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
        }
    }

    @ViewBuilder
    private var branchMenuSections: some View {
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
                    Button("Remove Worktree…", systemImage: "folder.badge.minus", role: .destructive) {
                        requestWorktreeRemoval(reference.name, worktreeURL)
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
    @Environment(\.gallaeTheme) private var theme
    @State private var mergeCommitPendingRevert: RepositoryHistory.Commit?
    @State private var commitPendingReset: RepositoryHistory.Commit?
    @State private var commitPendingRebasePlan: RepositoryHistory.Commit?

    @ViewBuilder
    var body: some View {
        Group {
            if let commit = model.selectedHistoryCommit {
                VStack(spacing: 0) {
                    commitHeader(commit)
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

    private func commitHeader(_ commit: RepositoryHistory.Commit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
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
            }

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

                if let signatureBadge {
                    Label(signatureBadge.text, systemImage: signatureBadge.systemImage)
                        .font(.caption)
                        .foregroundStyle(signatureBadge.color)
                        .help(signatureBadge.help)
                        .accessibilityLabel("Commit signature: \(signatureBadge.text)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
                            .padding(.vertical, 3)
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

private struct RepositoryStashDetailView: View {
    @Bindable var model: AppModel
    @State private var applyingStashID: String?
    @State private var stashPendingDeletion: RepositoryStash?

    @ViewBuilder
    var body: some View {
        if let stash = model.selectedStash {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stash.subject)
                            .font(.headline)
                            .textSelection(.enabled)
                        Text("\(stash.reference) · \(stash.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Stash \(stash.id)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    if applyingStashID == stash.id {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Applying Stash")
                    }
                    Button(role: .destructive) {
                        stashPendingDeletion = stash
                    } label: {
                        Label("Delete…", systemImage: "trash")
                    }
                    .disabled(model.isLoading || applyingStashID != nil)
                    .help("Permanently delete this Stash")
                    .accessibilityHint("Show a confirmation before permanently deleting this Stash")

                    Button("Apply", systemImage: "arrow.down.doc") {
                        applyingStashID = stash.id
                        Task {
                            defer { applyingStashID = nil }
                            await model.applyStash(stash)
                        }
                    }
                    .disabled(model.isLoading || applyingStashID != nil)
                    .accessibilityHint("Restore this Stash’s saved changes without deleting it")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                RepositoryRevisionChangesView(
                    filesState: model.stashFilesState,
                    selectedFileID: $model.selectedStashFileID,
                    selectedFile: model.selectedStashFile,
                    patchState: model.stashPatchState,
                    retryFiles: { Task { await model.loadSelectedStashFiles() } },
                    retryPatch: { Task { await model.loadSelectedStashPatch() } },
                    loadExpandedPatch: {
                        Task {
                            await model.loadSelectedStashPatch(
                                maximumOutputBytes: RepositoryInspector.maximumExpandedDiffBytes
                            )
                        }
                    }
                )
            }
            .confirmationDialog(
                "Delete Stash?",
                isPresented: Binding(
                    get: { stashPendingDeletion != nil },
                    set: { if !$0 { stashPendingDeletion = nil } }
                ),
                presenting: stashPendingDeletion
            ) { stash in
                Button("Delete Stash", role: .destructive) {
                    Task { await model.dropStash(stash) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { stash in
                Text(
                    "This permanently deletes “\(stash.subject)” without applying it. It doesn’t change HEAD, the index, or working files. Gallae cannot undo this action."
                )
            }
        } else {
            ContentUnavailableView(
                "Select a Stash",
                systemImage: "archivebox",
                description: Text("Choose a Stash to inspect its saved changes.")
            )
        }
    }
}

private struct RepositoryRevisionChangesView: View {
    let filesState: RepositoryCommitFilesLoadState
    @Binding var selectedFileID: String?
    let selectedFile: RepositoryCommitFile?
    let patchState: RepositoryCommitPatchLoadState
    let retryFiles: () -> Void
    let retryPatch: () -> Void
    let loadExpandedPatch: () -> Void

    @ViewBuilder
    var body: some View {
        switch filesState {
        case .noSelection:
            ContentUnavailableView(
                "No Saved Changes",
                systemImage: "doc.text.magnifyingglass"
            )
        case .loading:
            ProgressView("Loading Changed Files…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Load Changed Files", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", action: retryFiles)
                .accessibilityLabel("Try Again")
            }
        case .loaded(let files) where files.isEmpty:
            ContentUnavailableView(
                "No Saved Changes",
                systemImage: "doc.text.magnifyingglass",
                description: Text("This revision does not change any files from its base.")
            )
        case .loaded(let files):
            revisionFiles(files)
        }
    }

    private func revisionFiles(_ files: [RepositoryCommitFile]) -> some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Changed Files")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(files.count, format: .number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                List(files, selection: $selectedFileID) { file in
                    RepositoryCommitFileRow(file: file)
                        .tag(file.id)
                        .listRowInsets(.init(top: 7, leading: 10, bottom: 7, trailing: 10))
                }
                .listStyle(.plain)
                .accessibilityLabel("Changed Files, \(files.count) files")
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

            VStack(spacing: 0) {
                if let file = selectedFile {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.fileName)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(file.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()
                }

                revisionPatchContent
            }
            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var revisionPatchContent: some View {
        switch patchState {
        case .noSelection:
            ContentUnavailableView(
                "Select a Changed File",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose a file to inspect its patch.")
            )
        case .loading:
            ProgressView("Loading Changes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Load Changes", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", action: retryPatch)
                .accessibilityLabel("Try Again")
            }
        case .loaded(let patch):
            revisionPatch(patch.content)
        }
    }

    @ViewBuilder
    private func revisionPatch(_ content: RepositoryDiff.Section.Content) -> some View {
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
            .accessibilityLabel("Selected saved changes")
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
                title: "Changes Too Large",
                message: "The patch exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(byteLimit), countStyle: .file)) preview limit.",
                fileURL: nil,
                primaryAction: byteLimit < RepositoryInspector.maximumExpandedDiffBytes
                    ? (
                        "Load Larger Preview",
                        loadExpandedPatch
                    )
                    : nil
            )
        case .missing:
            RepositoryDiffNotice(
                title: "Version Missing",
                message: "This saved version is not present in the Git index.",
                fileURL: nil
            )
        case .unavailable(let message):
            RepositoryDiffNotice(
                title: "No Saved Changes",
                message: message,
                fileURL: nil
            )
        }
    }
}

private struct RepositoryCommitFileRow: View {
    let file: RepositoryCommitFile
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(statusColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.fileName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !file.parentPath.isEmpty {
                    Text(file.parentPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let originalPath = file.originalPath {
                    Text("From \(originalPath)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            Text(file.state.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(theme.colors.badgeBackground, in: .capsule)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            ([file.path, file.state.label] + [file.originalPath.map { "From \($0)" }].compactMap(\.self))
                .joined(separator: ", ")
        )
    }

    private var statusColor: Color {
        switch file.state {
        case .modified: theme.colors.statusModified
        case .typeChanged, .renamed: theme.colors.statusRenamed
        case .added, .copied: theme.colors.statusAdded
        case .deleted: theme.colors.statusDeleted
        case .untracked: theme.colors.statusUntracked
        }
    }
}

private enum ConflictResolutionConfirmation {
    case side(RepositoryConflictSide)
    case workingTree
}

private struct RepositoryDiffView: View {
    let state: RepositoryDiffLoadState
    let fileURL: URL?
    let canStage: Bool
    let canUnstage: Bool
    let canDiscard: Bool
    let canResolveConflict: Bool
    let canStageHunks: Bool
    let canUnstageHunks: Bool
    let isBusy: Bool
    let stage: () -> Void
    let unstage: () -> Void
    let discard: (RepositorySummary.Change.ID) -> Void
    let resolveConflict: (RepositoryConflictSide) -> Void
    let markConflictResolved: () -> Void
    let updateHunk: (RepositoryDiff.Hunk) -> Void
    let retry: () -> Void
    let loadExpanded: () -> Void
    @State private var isConfirmingDiscard = false
    @State private var pendingConflictResolution: ConflictResolutionConfirmation?

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

                if canResolveConflict, diff.sections.allSatisfy(\.scope.isConflictVersion) {
                    Button("Mark Resolved…") {
                        pendingConflictResolution = .workingTree
                    }
                    .disabled(isBusy)
                    .help("Stage this file’s current working tree state as resolved")
                    .accessibilityHint("Shows a confirmation before staging the file as resolved")

                    Button("Use Ours…") {
                        pendingConflictResolution = .side(.ours)
                    }
                    .disabled(isBusy)
                    .help("Resolve this file using the Ours version")
                    .accessibilityHint("Shows a confirmation before replacing and staging this file")

                    Button("Use Theirs…") {
                        pendingConflictResolution = .side(.theirs)
                    }
                    .disabled(isBusy)
                    .help("Resolve this file using the Theirs version")
                    .accessibilityHint("Shows a confirmation before replacing and staging this file")
                }

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

            if diff.sections.allSatisfy(\.scope.isConflictVersion) {
                RepositoryConflictComparisonView(
                    sections: diff.sections,
                    loadExpanded: loadExpanded
                )
            } else {
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
        .alert(
            pendingConflictResolution.map { confirmation in
                switch confirmation {
                case .side(let side): "Use \(side.label) to Resolve?"
                case .workingTree: "Mark Conflict Resolved?"
                }
            } ?? "Resolve Conflict?",
            isPresented: Binding(
                get: { pendingConflictResolution != nil },
                set: { if !$0 { pendingConflictResolution = nil } }
            )
        ) {
            if let confirmation = pendingConflictResolution {
                switch confirmation {
                case .side(let side):
                    Button("Use \(side.label)", role: .destructive) {
                        pendingConflictResolution = nil
                        resolveConflict(side)
                    }
                case .workingTree:
                    Button("Mark Resolved") {
                        pendingConflictResolution = nil
                        markConflictResolved()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingConflictResolution = nil
            }
        } message: {
            if let confirmation = pendingConflictResolution {
                switch confirmation {
                case .side(let side):
                    Text(conflictResolutionMessage(for: side, in: diff))
                case .workingTree:
                    Text(
                        "This stages the file’s current state on disk, including deletion, as resolved. Gallae does not check for conflict markers and cannot undo this action."
                    )
                }
            }
        }
    }

    private func conflictResolutionMessage(
        for side: RepositoryConflictSide,
        in diff: RepositoryDiff
    ) -> String {
        let scope: RepositoryDiff.Scope = side == .ours ? .ours : .theirs
        if diff.sections.first(where: { $0.scope == scope })?.content == .missing {
            return "The \(side.label) version has no file. This deletes \(diff.fileName) and stages the deletion as resolved. Gallae cannot undo this action."
        }
        return "This replaces \(diff.fileName) with the \(side.label) version and stages it as resolved. Gallae cannot undo this action."
    }
}

private struct RepositoryConflictComparisonView: View {
    let sections: [RepositoryDiff.Section]
    let loadExpanded: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                RepositoryConflictVersionView(
                    section: section,
                    loadExpanded: loadExpanded
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if index < sections.count - 1 {
                    Divider()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Base, Ours, and Theirs conflict comparison")
    }
}

private struct RepositoryConflictVersionView: View {
    let section: RepositoryDiff.Section
    let loadExpanded: () -> Void
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Label(section.scope.label, systemImage: section.scope.systemImage)
                    .font(.caption.weight(.semibold))
                Text(section.scope.stageLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.badgeBackground)

            Divider()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section.content {
        case .text(let lines) where lines.isEmpty:
            ContentUnavailableView(
                "Empty File",
                systemImage: "doc",
                description: Text("This version contains no text.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .text(let lines):
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            RepositoryConflictLineView(line: line)
                        }
                    }
                    .frame(minWidth: proxy.size.width, alignment: .leading)
                    .textSelection(.enabled)
                }
                .defaultScrollAnchor(.topLeading, for: .alignment)
            }
        case .binary:
            RepositoryDiffNotice(
                title: "Binary File",
                message: "Gallae does not render this version as text.",
                fileURL: nil
            )
        case .unsupportedEncoding:
            RepositoryDiffNotice(
                title: "Unsupported Text Encoding",
                message: "This version is not valid UTF-8 and cannot be displayed safely.",
                fileURL: nil
            )
        case .tooLarge(let byteLimit):
            RepositoryDiffNotice(
                title: "Version Too Large",
                message: "This version exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(byteLimit), countStyle: .file)) preview limit.",
                fileURL: nil,
                primaryAction: byteLimit < RepositoryInspector.maximumExpandedDiffBytes
                    ? ("Load Larger Preview", loadExpanded)
                    : nil
            )
        case .missing:
            RepositoryDiffNotice(
                title: "No \(section.scope.label) Version",
                message: section.scope.missingMessage,
                fileURL: nil
            )
        case .unavailable(let message):
            RepositoryDiffNotice(
                title: "Version Unavailable",
                message: message,
                fileURL: nil
            )
        }
    }
}

private struct RepositoryConflictLineView: View {
    let line: RepositoryDiff.Line
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: theme.metrics.diffLineNumberWidth, alignment: .trailing)
                .padding(.trailing, 8)
                .foregroundStyle(theme.colors.diffMetadataText)
            Text(line.text.isEmpty ? " " : line.text)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.callout.monospaced())
        .foregroundStyle(theme.colors.diffText)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            line.newLineNumber.map { "Line \($0): \(line.text)" } ?? line.text
        )
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
            case .missing:
                RepositoryDiffNotice(
                    title: "Version Missing",
                    message: "This version is not present in the Git index.",
                    fileURL: nil
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

private extension RepositorySummary.Operation.Kind {
    var name: String {
        switch self {
        case .merge: "Merge"
        case .rebase: "Rebase"
        }
    }

    var label: String {
        "\(name) in Progress"
    }
}

private extension RepositorySummary.Operation {
    var conflictLabel: String {
        unresolvedConflictCount == 0
            ? "No unresolved conflicts"
            : "\(unresolvedConflictCount) unresolved conflict\(unresolvedConflictCount == 1 ? "" : "s")"
    }

    var actionLabel: String {
        canContinue
            ? "Ready to Continue"
            : "Resolve conflicts to Continue"
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
        case .base: "Base"
        case .ours: "Ours"
        case .theirs: "Theirs"
        }
    }

    var systemImage: String {
        switch self {
        case .staged: "tray.and.arrow.down"
        case .unstaged: "pencil.line"
        case .untracked: "questionmark.diamond"
        case .base: "1.circle"
        case .ours: "2.circle"
        case .theirs: "3.circle"
        }
    }

    var isConflictVersion: Bool {
        switch self {
        case .base, .ours, .theirs: true
        case .staged, .unstaged, .untracked: false
        }
    }

    var stageLabel: String {
        switch self {
        case .base: "Git index stage 1"
        case .ours: "Git index stage 2"
        case .theirs: "Git index stage 3"
        case .staged, .unstaged, .untracked: ""
        }
    }

    var missingMessage: String {
        switch self {
        case .base: "The file has no common ancestor version."
        case .ours: "The file does not exist in Ours."
        case .theirs: "The file does not exist in Theirs."
        case .staged, .unstaged, .untracked: "This version is not present."
        }
    }
}

private extension RepositoryConflictSide {
    var label: String {
        switch self {
        case .ours: "Ours"
        case .theirs: "Theirs"
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
