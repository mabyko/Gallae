import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

private enum RepositoryChangeViewMode: Int {
    case hierarchy
    case status
}

struct RepositoryWorkspaceView: View {
    @Bindable var model: AppModel
    @Environment(\.gallaeTheme) private var theme
    @Environment(\.windowWidth) private var windowWidth
    @State private var selectedChangeIDs = Set<RepositorySummary.Change.ID>()
    @State private var selectAllEventMonitor: Any?
    @State private var expandedStatusGroups = Set(RepositoryChangeStatusGroup.ID.allCases)
    @State private var commitSubject = ""
    @State private var commitBody = ""
    @State private var isAmending = false
    /// The commit fields open by themselves when something is staged; this opens them by hand before that.
    @State private var isComposerExpanded = false
    @State private var amendPrefill: RepositoryCommitMessage?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isNavigatorAutoCollapsed = false
    @State private var isCreatingBranch = false
    @State private var worktreeCreation: WorktreeCreationRequest?
    /// The Navigator's scope axis; the screen axis is `workspaceSection`. Choosing a scope shows History.
    private var scope: RepositoryHistoryScope? {
        get { model.historySelection }
        nonmutating set { model.historySelection = newValue }
    }
    @AppStorage(GallaeAppearanceSettings.narrowNavigatorKey) private var narrowNavigatorStyle = GallaeAppearanceSettings.NarrowNavigator.floatingPanel
    /// The floating Navigator over the detail column in narrow windows.
    @State private var isNavigatorPanelPresented = false
    @State private var navigatorWidthTask: Task<Void, Never>?
    /// Bumped once a drag past the sidebar maximum settles; the clamp view then moves the divider back.
    @State private var navigatorClampGeneration = 0
    /// The narrowest detail column worth sharing the window with the Navigator: list plus diff at their minimums.
    /// A guide for folding only; the detail itself has no minimum (see `ResizableHSplit`).
    private static let detailComfortableWidth: CGFloat = 320 + 400
    static let navigatorDefaultWidth: CGFloat = 220
    static let navigatorMaximumWidth: CGFloat = 320
    /// The sidebar width the user last dragged to; the fold threshold follows it.
    @AppStorage("navigatorWidth") private var navigatorWidth = Double(navigatorDefaultWidth)
    /// Read once per launch, before the first layout, so the sidebar's ideal equals the width AppKit restores.
    private static let launchNavigatorWidth: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: "navigatorWidth")
        return stored >= 180 ? min(CGFloat(stored), navigatorMaximumWidth) : navigatorDefaultWidth
    }()
    /// Navigator width plus the comfortable detail width and the divider; narrower windows fold the Navigator.
    private var navigatorFoldWidth: CGFloat {
        CGFloat(navigatorWidth) + Self.detailComfortableWidth + 8
    }
    @State private var isConfirmingOperationAbort = false
    @FocusState private var isChangeListFocused: Bool
    @SceneStorage("repositoryChangeViewMode") private var changeViewMode = RepositoryChangeViewMode.status
    @SceneStorage("repositoryWorkspaceSection") private var workspaceSection = RepositoryWorkspaceSection.changes

    private var workspaceLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            navigatorColumn
        } detail: {
            VStack(spacing: 0) {
                repositoryHeader
                Divider()

                if let repository = model.repository {
                    switch workspaceSection {
                    case .changes:
                        changesContent(repository)
                    case .history:
                        RepositoryHistoryView(model: model, scope: $model.historyScope)
                    case .stashes:
                        RepositoryStashesView(model: model)
                    case .reflog:
                        RepositoryReflogView(model: model)
                    }
                }
            }
            // No minimum or ideal width here on purpose: `NavigationSplitView` counts the sidebar into the detail
            // minimum twice, growing the window or leaving a gap on the right (see `ResizableHSplit`).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if isNavigatorPanelPresented {
                    navigatorPanel
                }
            }
        }
        .onChange(of: windowWidth, initial: true) { _, width in
            foldNavigatorIfNeeded(windowWidth: width)
        }
        .onChange(of: isWindowNarrow) { _, isNarrow in
            if !isNarrow { isNavigatorPanelPresented = false }
        }
        .onChange(of: narrowNavigatorStyle) { _, _ in
            isNavigatorPanelPresented = false
        }
        .task(id: model.diffRequest) {
            await model.loadSelectedDiff()
        }
        .task(id: model.repositoryRevision) {
            await model.loadNavigator()
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            // One capsule, two controls: a divider between the sidebar toggle and Library keeps them from
            // reading as one button.
            // Two one-control groups in an HStack: a single ControlGroup either drifts to the trailing end
            // (default style) or spaces its controls too widely (navigation style); this keeps the leading
            // placement, the tight divider, and each button's own accessibility name.
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 0) {
                    ControlGroup {
                        navigatorToolbarItem
                    }

                    ToolbarDivider(inset: 0)

                    ControlGroup {
                    Button {
                        model.showLibrary()
                    } label: {
                        Label("Library", systemImage: "chevron.backward")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Return to the Repository Library in this window (⇧⌘L)")
                    .accessibilityLabel("Library")
                    .accessibilityHint("Return to the Repository Library in this window")
                    .disabled(model.isLoading)
                    }
                }
            }
        }
    }

    var body: some View {
        workspaceLayout
        .onChange(of: model.repository?.rootURL, initial: true) {
            commitSubject = ""
            commitBody = ""
            isAmending = false
            amendPrefill = nil
            isConfirmingOperationAbort = false
            selectedChangeIDs = model.selectedChangeID.map { [$0] } ?? []
            // AppModel resets the scope for an ordinary open and retains it for Worktree navigation.
            if let conflict = model.repository?.changes.first(where: \.isConflicted) {
                show(.changes)
                model.selectedChangeID = conflict.id
            } else if model.repository?.changes.isEmpty == true, workspaceSection == .changes {
                workspaceSection = .history
            }
        }
        .onChange(of: workspaceSection) { _, _ in
            isNavigatorPanelPresented = false
        }
        .onChange(of: scope, initial: true) { _, scope in
            isNavigatorPanelPresented = false
        }
        .onChange(of: model.repository?.changes) { previous, changes in
            if previous?.contains(where: \.isConflicted) != true,
               let conflict = changes?.first(where: \.isConflicted) {
                show(.changes)
                model.selectedChangeID = conflict.id
            }
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
        .focusedSceneValue(
            \.workspaceSection,
            Binding(
                get: { workspaceSection },
                set: { if let section = $0 { show(section) } }
            )
        )
        .focusedSceneValue(\.navigatorToggle, navigatorToggleCommand)
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
            HStack(alignment: .center, spacing: 14) {
                if let repository = model.repository {
                    Menu {
                        branchMenuItems(for: repository)
                    } label: {
                        Label(isWindowNarrow ? repository.head.label : "Working on: \(repository.head.label)", systemImage: repository.head.systemImage)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.callout.weight(.medium))
                    .help("Working on: \(repository.head.label). Switch, create, or integrate local branches")
                    .accessibilityLabel("HEAD, \(repository.head.label). Branch actions")
                    .disabled(model.isLoading || model.isSyncing)

                    if isWindowNarrow, narrowNavigatorStyle == .locationMenu {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, -6)
                            .accessibilityHidden(true)
                        let location = RepositoryNavigatorLocation(screen: workspaceSection, scope: scope)
                        Menu {
                            navigatorMenuItems(includeBranches: false)
                        } label: {
                            Label(location.title, systemImage: location.systemImage)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .font(.callout.weight(.medium))
                        .help("Where you are. Choose a destination, remote, or tag")
                        .accessibilityLabel("Location, \(location.title). Go to")
                    }

                    if let upstream = repository.upstream {
                        Label(
                            upstreamDisplayLabel(upstream, head: repository.head),
                            systemImage: "arrow.up.arrow.down"
                        )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help("Tracks \(upstream.label)")
                            .accessibilityLabel("Tracking branch, \(upstream.label)")
                    }
                    if !repository.changes.isEmpty {
                        Button {
                            show(.changes)
                        } label: {
                            Label(workingTreeSummary(repository), systemImage: "pencil.line")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help("Show Changes")
                        .accessibilityLabel("Working tree, \(workingTreeSummary(repository)). Show Changes")
                    }
                    if repository.isUnborn {
                        Label("No commits yet", systemImage: "circle.dashed")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if model.isRepositoryStale {
                        Label("Refresh failed · showing earlier data", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                            .font(.callout)
                            .foregroundStyle(theme.colors.statusConflict)
                    }
                    if model.isCurrentWorkspaceTemporaryWorktree {
                        Label("Temporary Worktree", systemImage: "folder.badge.gearshape")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .help("Gallae created this Worktree for a merge and offers to remove it when the merge finishes")
                    }

                    Spacer(minLength: 0)

                    if let fetched = model.lastFetchDate {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(lastFetchText(fetched, now: context.date))
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("Last fetch \(fetched.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .sheet(isPresented: $isCreatingBranch) {
                CreateBranchSheet(model: model)
            }
            .sheet(item: $worktreeCreation) { request in
                CreateWorktreeSheet(model: model, existingBranch: request.branch)
            }

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
    private func branchMenuItems(for repository: RepositorySummary) -> some View {
        let currentBranch: String? = if case .branch(let branch) = repository.head { branch } else { nil }
        RepositoryFolderMenu(folderURL: repository.rootURL) {
            model.present($0, title: "Couldn’t Open Folder")
        }
        Divider()
        if case .loaded(let branches) = model.localBranchesState {
            let otherBranches = branches.filter { $0 != currentBranch }
            if !otherBranches.isEmpty {
                Section("Switch To") {
                    ForEach(otherBranches, id: \.self) { branch in
                        if let worktreeURL = model.localBranchWorktreeURLs[branch] {
                            Button(branch, systemImage: "folder") {
                                Task { _ = await model.openWorktree(at: worktreeURL) }
                            }
                        } else {
                            Button(branch, systemImage: "arrow.triangle.branch") {
                                Task { _ = await model.switchBranch(to: branch) }
                            }
                        }
                    }
                }
            }
        }

        if case .loaded(let branches) = model.localBranchesState, !branches.isEmpty {
            Menu("Show History", systemImage: "clock") {
                ForEach(branches, id: \.self) { branch in
                    scopeMenuItem(.branch(branch))
                }
            }
        }

        Button("New Worktree…", systemImage: "folder.badge.plus") {
            worktreeCreation = .init()
        }
        .disabled(model.isLoading || model.isSyncing)

        Button("New Branch…", systemImage: "plus") {
            isCreatingBranch = true
        }
        .disabled(model.isLoading || model.isSyncing)

        Divider()

        Button("Integrate…", systemImage: "arrow.triangle.merge") {
            model.showIntegrateBranch()
        }
        .disabled(!model.canIntegrateBranch || model.isLoading || model.isSyncing)
    }

    private var navigatorColumn: some View {
        RepositoryNavigatorView(model: model, screen: $workspaceSection, scope: $model.historySelection)
            .navigationSplitViewColumnWidth(min: 180, ideal: Self.launchNavigatorWidth, max: Self.navigatorMaximumWidth)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                guard columnVisibility != .detailOnly, width >= 180 else { return }
                // Settled width only: AppKit ignores the declared maximum for mouse drags and for its own
                // restored frames, so after the drag rests the divider is moved back to the maximum.
                navigatorWidthTask?.cancel()
                navigatorWidthTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    navigatorWidth = Double(min(width, Self.navigatorMaximumWidth))
                    if width > Self.navigatorMaximumWidth { navigatorClampGeneration += 1 }
                }
            }
            .background(SidebarWidthClamp(maximum: Self.navigatorMaximumWidth, generation: navigatorClampGeneration))
            .toolbar(removing: .sidebarToggle)
    }

    // MARK: - Narrow window Navigator

    /// Only the window width folds the Navigator, never a divider drag: flipping the column mid-drag leaves
    /// AppKit's split view and our state disagreeing. A sidebar dragged too wide just squeezes the detail.
    private func foldNavigatorIfNeeded(windowWidth width: CGFloat) {
        guard width > 0 else { return }
        if width < navigatorFoldWidth, columnVisibility != .detailOnly {
            isNavigatorAutoCollapsed = true
            columnVisibility = .detailOnly
        } else if isNavigatorAutoCollapsed, width >= navigatorFoldWidth {
            isNavigatorAutoCollapsed = false
            columnVisibility = .all
        }
    }

    /// Below the fold width the sidebar column never opens, so the window never grows; the setting decides the way in.
    private var isWindowNarrow: Bool {
        windowWidth > 0 && windowWidth < navigatorFoldWidth
    }

    /// What the toolbar button and the View menu item do right now.
    private var navigatorToggleCommand: NavigatorToggleCommand {
        guard isWindowNarrow else {
            let isFolded = columnVisibility == .detailOnly
            return .init(title: isFolded ? "Show Navigator" : "Hide Navigator", isEnabled: true) {
                isNavigatorAutoCollapsed = false
                columnVisibility = isFolded ? .all : .detailOnly
            }
        }
        switch narrowNavigatorStyle {
        case .floatingPanel:
            return .init(title: isNavigatorPanelPresented ? "Hide Navigator" : "Show Navigator", isEnabled: true) {
                isNavigatorPanelPresented.toggle()
            }
        case .toolbarMenu, .locationMenu:
            return .init(title: "Show Navigator", isEnabled: false) {}
        }
    }

    private var navigatorToggleHelp: String {
        guard isWindowNarrow else { return "Show or hide the Navigator (⌃⌘S)" }
        return switch narrowNavigatorStyle {
        case .floatingPanel: "Show the Navigator over the content (⌃⌘S)"
        case .toolbarMenu: "Choose a destination, branch, remote, or tag"
        case .locationMenu: "Widen the window past \(Int(navigatorFoldWidth)) points to show the Navigator, or use the location menu in the context bar"
        }
    }

    @ViewBuilder
    private var navigatorToolbarItem: some View {
        if isWindowNarrow, narrowNavigatorStyle == .toolbarMenu {
            Menu {
                navigatorMenuItems(includeBranches: true)
            } label: {
                Label("Navigator", systemImage: "sidebar.leading")
            }
            .help(navigatorToggleHelp)
            .accessibilityLabel("Navigator Menu")
        } else {
            let command = navigatorToggleCommand
            Button(action: command.perform) {
                Label("Navigator", systemImage: "sidebar.leading")
            }
            .disabled(!command.isEnabled)
            .help(navigatorToggleHelp)
            .accessibilityLabel(command.title)
        }
    }

    /// The Navigator floating over the detail column; tap outside or Escape dismisses, choosing an item closes it.
    private var navigatorPanel: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { isNavigatorPanelPresented = false }
                .accessibilityHidden(true)

            RepositoryNavigatorView(model: model, screen: $workspaceSection, scope: $model.historySelection, isFloating: true)
                .frame(width: 220)
                .background(
                    theme.materials.translucentChrome
                        ? AnyShapeStyle(.regularMaterial)
                        : AnyShapeStyle(theme.colors.opaqueChrome)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                .padding(8)

            // ponytail: an invisible button is the simplest way to give the panel an Escape key.
            Button("Hide Navigator") { isNavigatorPanelPresented = false }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    /// Destinations, remotes, and tags as menu items with the current one checked; branches only for the toolbar
    /// menu, because the context bar's branch menu already owns them.
    @ViewBuilder
    private func navigatorMenuItems(includeBranches: Bool) -> some View {
        Section("Workspace") {
            destinationMenuItem(.changes, count: model.repository?.changes.count ?? 0)
            destinationMenuItem(.history, count: 0)
        }
        Section("Recovery") {
            destinationMenuItem(.stashes, count: stashCount)
            destinationMenuItem(.reflog, count: 0)
        }
        if includeBranches, case .loaded(let branches) = model.localBranchesState, !branches.isEmpty {
            Section {
                Menu("Branches", systemImage: "arrow.triangle.branch") {
                    ForEach(branches, id: \.self) { branch in
                        scopeMenuItem(.branch(branch))
                    }
                }
            }
        }
        if case .loaded(let remotes) = model.remotesState, !remotes.isEmpty {
            Section("Remotes") {
                ForEach(remotes) { remote in
                    scopeMenuItem(.remote(remote.name))
                }
            }
        }
        if case .loaded(let tags) = model.tagsState, !tags.isEmpty {
            Section("Tags") {
                ForEach(tags, id: \.self) { tag in
                    scopeMenuItem(.tag(tag))
                }
            }
        }
    }

    private func destinationMenuItem(_ section: RepositoryWorkspaceSection, count: Int) -> some View {
        Toggle(isOn: Binding(get: { workspaceSection == section }, set: { if $0 { show(section) } })) {
            Label(count > 0 ? "\(section.title) (\(count))" : section.title, systemImage: section.systemImage)
        }
    }

    /// Switching screens clears the Navigator selection, not the History filter.
    private func show(_ section: RepositoryWorkspaceSection) {
        workspaceSection = section
        scope = nil
    }

    /// Checked while this reference is selected in History.
    private func scopeMenuItem(_ target: RepositoryHistoryScope) -> some View {
        Toggle(
            isOn: Binding(
                get: { scope == target && workspaceSection == .history },
                set: { if $0 { scope = target; workspaceSection = .history } }
            )
        ) {
            Label(target.name, systemImage: target.systemImage)
        }
    }

    private var stashCount: Int {
        if case .loaded(let stashes) = model.stashesState { stashes.count } else { 0 }
    }

    /// A clean working tree empties the file list, not the screen: the header, the commit bar and the diff
    /// pane stay where they were so the window does not change shape between one state and the next.
    private func changesContent(_ repository: RepositorySummary) -> some View {
            ResizableHSplit(
                leadingMinimum: theme.metrics.changeListMinimumWidth,
                leadingIdeal: theme.metrics.changeListIdealWidth,
                trailingMinimum: 400,
                storageKey: "changes"
            ) {
                changeList(repository)
            } trailing: {
                if repository.changes.isEmpty {
                    ContentUnavailableView {
                        Label("No Changes to Review", systemImage: "checkmark.circle")
                    } description: {
                        Text("New edits will appear here. You can review earlier commits in History.")
                    } actions: {
                        Button("Show History") { show(.history) }
                    }
                } else {
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
                        openMergeTool: { Task { await model.openSelectedConflictInMergeTool() } },
                        activeMergeTool: model.activeMergeTool,
                        updateHunk: { hunk in
                            Task { await model.updateSelectedHunk(hunk) }
                        },
                        discardHunk: { hunk in
                            Task { await model.discardSelectedHunk(hunk) }
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
            .listHeaderInset()

            Divider()

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
                switch changeViewMode {
                case .hierarchy:
                    changeHierarchyList(repository)
                case .status:
                    changeStatusList(repository)
                }
            }

            Divider()
            if repository.changes.contains(where: { $0.staged != nil }) || isComposerExpanded {
                commitComposer(repository)
            } else {
                collapsedCommitBar(repository)
            }
        }
    }

    /// One line while nothing is staged: the commit fields would only take room from the list.
    private func collapsedCommitBar(_ repository: RepositorySummary) -> some View {
        HStack {
            Button {
                isComposerExpanded = true
            } label: {
                Label("Commit …", systemImage: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open the commit message fields. Staging a change opens them too")
            .accessibilityLabel("Commit, nothing staged. Open message fields")

            Spacer()

            stageAllButton(repository)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func stageAllButton(_ repository: RepositorySummary) -> some View {
        Button("Stage All") {
            Task { await model.stageAllChanges() }
        }
        .controlSize(.small)
        .disabled(model.isLoading || !repository.changes.contains { $0.unstaged != nil && !$0.isConflicted })
        .help("Stage every unstaged change, untracked files included")
        .accessibilityHint("Stage every unstaged change, untracked files included")
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

                stageAllButton(repository)

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
                            isComposerExpanded = false
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
                    .listRowInsets(.init(top: theme.metrics.rowVerticalPadding, leading: 12, bottom: theme.metrics.rowVerticalPadding, trailing: 12))
            }
        }
        .listStyle(.plain)
                .legacyScrollerAware()
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
                                .listRowInsets(.init(top: theme.metrics.rowVerticalPadding, leading: 12, bottom: theme.metrics.rowVerticalPadding, trailing: 12))
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
                .legacyScrollerAware()
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
            .gallaeSelectionBackground(isSelected: selectedChangeIDs.contains(change.id), isFocused: isChangeListFocused)
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
    private func workingTreeSummary(_ repository: RepositorySummary) -> String {
        let total = repository.changes.count
        let staged = repository.changes.filter { $0.staged != nil }.count
        let changes = total == 1 ? "1 change" : "\(total) changes"
        return staged > 0 ? "\(changes) · \(staged) staged" : changes
    }

    private func lastFetchText(_ fetched: Date, now: Date) -> String {
        let age = now.timeIntervalSince(fetched)
        let when = age < 60 ? "just now" : fetched.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return "Last fetch \(when)" + (model.automaticFetchEnabled ? " · Auto" : "")
    }

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
                        Text(badge.state?.shortLabel ?? "!")
                            .font(.caption2.monospaced().weight(.medium))
                            .foregroundStyle(statusColor(for: badge.state))
                            .lineLimit(1)
                            .frame(width: 22)
                            .padding(.vertical, 1)
                            .fixedSize()
                            .background(theme.colors.badgeBackground, in: .capsule)
                            .help(badge.label)
                            .accessibilityLabel(badge.label)
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


extension RepositorySummary.Change.State {
    var shortLabel: String {
        switch self {
        case .modified: "M"
        case .typeChanged: "T"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .untracked: "?"
        }
    }

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
