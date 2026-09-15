import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Vertical separator between buttons that share one toolbar capsule, matching the line macOS draws between a
/// menu button's action and its chevron. A plain `Divider` lies horizontal in the toolbar.
struct ToolbarDivider: View {
    /// Horizontal padding around the line. Each toolbar button already pads its label by about 10pt (the hover
    /// pill shows it), which is where the system draws a menu button's own divider. ControlGroup adds 12pt
    /// between controls, so -12 cancels that; an HStack with zero spacing needs nothing.
    var inset: CGFloat = -12

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, inset)
            .accessibilityHidden(true)
    }
}

struct AppView: View {
    private enum FolderSelection {
        case openOrAdd
        case repository(replacing: URL?)
        case libraryFolder(replacing: URL?)
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @AppStorage(GallaeAppearanceSettings.translucentChromeKey) private var translucentChrome = true
    @AppStorage(GallaeAppearanceSettings.compactRowsKey) private var compactRows = false
    @AppStorage(GallaeAppearanceSettings.accentColorKey) private var accentColor = "system"
    @AppStorage(GallaeAppearanceSettings.historyGraphColorKey) private var historyGraphColor = GallaeHistoryColor.blue
    @AppStorage(GallaeAppearanceSettings.historyLocalColorKey) private var historyLocalColor = GallaeHistoryColor.blue
    @AppStorage(GallaeAppearanceSettings.historyRemoteColorKey) private var historyRemoteColor = GallaeHistoryColor.teal
    @AppStorage(GallaeAppearanceSettings.historyTagColorKey) private var historyTagColor = GallaeHistoryColor.purple
    @State private var model = AppModel()
    @State private var folderSelection: FolderSelection?
    @State private var isFolderImporterPresented = false
    @State private var expandedLibraryHierarchyFolderIDs: Set<URL> = []
    @State private var showsDelayedLocalProgress = false
    @State private var windowWidth: CGFloat = 0

    var body: some View {
        Group {
            if model.screen == .workspace, let repository = model.repository {
                RepositoryWorkspaceView(model: model)
                    .navigationTitle(repository.name)
                    .navigationSubtitle(workspaceSubtitle)
                    .navigationDocument(repository.rootURL)
            } else {
                RepositoryLibraryView(
                    model: model.library,
                    isOpeningRepository: model.isLoading,
                    openRepository: { await model.openLibraryRepository(at: $0) },
                    chooseFolder: { chooseFolder() },
                    chooseLibraryFolder: { chooseLibraryFolder() },
                    reconnectLibraryFolder: { url in chooseLibraryFolder(replacing: url) },
                    reconnectRepository: { url in chooseRepository(replacing: url) },
                    expandedHierarchyFolderIDs: $expandedLibraryHierarchyFolderIDs
                )
                .navigationTitle("Gallae for Git")
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            windowWidth = width
        }
        .environment(\.windowWidth, windowWidth)
        // The theme answers the system accessibility settings and the two appearance settings once, here.
        .environment(\.gallaeTheme, theme)
        .toolbarBackgroundVisibility(theme.materials.translucentChrome ? .automatic : .visible, for: .windowToolbar)
        .onAppear {
            GallaeAppearanceSettings.applyStoredAppearance()
        }
        .overlay(alignment: .bottomTrailing) {
            activityCapsule
        }
        .task(id: model.isLoading) {
            showsDelayedLocalProgress = false
            guard model.isLoading else { return }
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            showsDelayedLocalProgress = true
        }
        .toolbar {
            if model.screen == .library {
                ToolbarItemGroup {
                    Button("Choose Folder…", systemImage: "folder.badge.plus") {
                        chooseFolder()
                    }
                    .help("Open a Git Repository, or add the selected folder to the Library")
                    .accessibilityHint(
                        "Open a Git Repository, or add the selected folder to the Library"
                    )
                }
            } else {
                ToolbarItem {
                    Button("Merge / Rebase…", systemImage: "arrow.triangle.merge") {
                        model.showIntegrateBranch()
                    }
                    .labelStyle(.titleAndIcon)
                    .disabled(!model.canIntegrateBranch || model.isLoading || model.isSyncing)
                    .help(model.canIntegrateBranch
                          ? "Choose a local branch to merge, rebase, or fast-forward"
                          : "Merge / Rebase needs a local branch with at least one commit")
                }
                ToolbarItemGroup {
                    Menu {
                        Button("Fetch & Prune", systemImage: "scissors") {
                            model.fetchRepository(pruning: true)
                        }
                        .accessibilityHint(
                            "Fetch and remove stale local tracking references for the selected Remote"
                        )

                        Divider()

                        Toggle(
                            "Fetch Automatically",
                            isOn: Binding(
                                get: { model.automaticFetchEnabled },
                                set: { model.setAutomaticFetchEnabled($0) }
                            )
                        )
                        .accessibilityHint(
                            "Fetch Git’s configured default Remote every five minutes while this Workspace and Gallae are active"
                        )
                    } label: {
                        Label {
                            Text("Fetch")
                        } icon: {
                            syncIcon("arrow.down.circle", running: model.remoteOperation?.isFetch == true)
                        }
                        .labelStyle(.titleAndIcon)
                    } primaryAction: {
                        model.fetchRepository()
                    }
                    .disabled(model.repository == nil || model.isLoading || model.isSyncing)
                    .help("Fetch Remote changes (⌥⌘F) · the menu has Fetch & Prune and automatic Fetch")
                    .accessibilityHint(
                        "Fetch Remote changes, or open the menu to also prune stale tracking references"
                    )

                    // One-control groups in a zero-spacing HStack: each button keeps its own accessibility
                    // name, and only the buttons' own padding sits around the dividers, as in Fetch's menu.
                    HStack(spacing: 0) {
                    ControlGroup {
                    Button {
                        model.pullRepository()
                    } label: {
                        Label {
                            Text(model.pullTitle)
                        } icon: {
                            syncIcon("arrow.down.to.line", running: model.remoteOperation == .pull)
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    .disabled(!model.canPullRepository || model.isLoading || model.isSyncing)
                    .accessibilityLabel(model.pullTitle)
                    .help(
                        model.canPullRepository
                            ? "Fast-forward the current branch from its tracking branch"
                            : "Pull needs a local branch with a tracking branch"
                    )
                    .accessibilityHint(
                        "Fast-forward the current branch from its tracking branch without merging or rebasing"
                    )

                    }

                    ToolbarDivider(inset: 0)

                    ControlGroup {
                    Button {
                        model.pushRepository()
                    } label: {
                        Label {
                            Text(model.pushTitle)
                        } icon: {
                            syncIcon("arrow.up.to.line", running: model.remoteOperation?.isPush == true)
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    .disabled(!model.canPushRepository || model.isLoading || model.isSyncing)
                    .accessibilityLabel(model.pushTitle)
                    .help(
                        model.repository?.upstream == nil
                            ? "Review the remote and branch name before publishing"
                            : "Push the current branch to its configured destination"
                    )
                    .accessibilityHint(
                        model.repository?.upstream == nil
                            ? "Choose a remote and confirm the branch name before publishing without force"
                            : "Push the current branch to its configured destination without force"
                    )

                    }

                    ToolbarDivider(inset: 0)

                    ControlGroup {
                    Button("Refresh Repository", systemImage: "arrow.clockwise") {
                        Task { await model.refreshRepository() }
                    }
                    .disabled(model.repository == nil || model.isLoading)
                    .accessibilityLabel("Refresh Repository")
                    .help("Refresh · read the current Repository state again (⌘R)")
                    .accessibilityHint("Read the current Repository state again")
                    }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isFolderImporterPresented,
            allowedContentTypes: [.directory],
            allowsMultipleSelection: false
        ) { result in
            guard let folderSelection else { return }
            self.folderSelection = nil

            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                switch folderSelection {
                case .openOrAdd:
                    Task { await model.openOrAddFolder(at: url) }
                case .repository(let replacedID):
                    Task {
                        if let replacedID {
                            await model.reconnectRecentRepository(replacedID, to: url)
                        } else {
                            await model.openRepository(at: url)
                        }
                    }
                case .libraryFolder(let replacedID):
                    if let replacedID {
                        model.library.reconnectLibraryFolder(replacedID, to: url)
                    } else {
                        model.library.addLibraryFolder(at: url)
                    }
                }
            case .failure(let error):
                model.present(error)
            }
        }
        .sheet(
            item: Binding(
                get: { model.repositorySheetRequest },
                set: { model.repositorySheetRequest = $0 }
            )
        ) { request in
            switch request {
            case .addRemote(let repositoryRootURL, let publishAfterAdding):
                AddRemoteSheet(model: model, repositoryRootURL: repositoryRootURL, publishAfterAdding: publishAfterAdding)
            case .createTag(let repositoryRootURL):
                CreateTagSheet(model: model, repositoryRootURL: repositoryRootURL)
            case .createStash(let repositoryRootURL):
                CreateStashSheet(model: model, repositoryRootURL: repositoryRootURL)
            case .integrateBranch(let repositoryRootURL, let branch):
                RepositoryIntegrateBranchSheet(
                    model: model,
                    repositoryRootURL: repositoryRootURL,
                    initialBranch: branch
                )
            case .chooseFetchRemote(let repositoryRootURL, let remotes, let pruning):
                ChooseRemoteSheet(
                    model: model,
                    repositoryRootURL: repositoryRootURL,
                    remotes: remotes,
                    purpose: .fetch(pruning: pruning)
                )
            case .choosePublishRemote(let repositoryRootURL, let remotes):
                ChooseRemoteSheet(
                    model: model,
                    repositoryRootURL: repositoryRootURL,
                    remotes: remotes,
                    purpose: .publish
                )
            }
        }
        .alert(
            (model.errorMessage != nil ? model.errorTitle : nil) ?? "Couldn’t Complete the Request",
            isPresented: Binding(
                get: { model.errorMessage != nil || model.library.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil; model.library.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? model.library.errorMessage ?? "Unknown error")
        }
        .task {
            await model.restoreState()
        }
        .task(id: automaticFetchRootURL) {
            guard automaticFetchRootURL != nil else { return }
            await model.runAutomaticFetchLoop()
        }
        .onOpenURL { url in
            Task { await model.openRepository(at: url) }
        }
        .focusedSceneValue(\.appModel, model)
        .focusedSceneValue(\.openRepository) {
            chooseRepository()
        }
        // Not `scenePhase`: on macOS it stays `.active` while another app is frontmost, so a window coming
        // back to the front never fires it and the working tree stays as it was when the window opened.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard model.repository != nil else { return }
            Task { await model.refreshRepository() }
        }
    }

    private var theme: GallaeTheme {
        GallaeTheme.resolve(
            response: .resolve(
                reduceTransparency: reduceTransparency,
                increasedContrast: colorSchemeContrast == .increased,
                translucentChrome: translucentChrome
            ),
            compactRows: compactRows,
            graphColor: historyGraphColor, localBranchColor: historyLocalColor,
            remoteBranchColor: historyRemoteColor, tagColor: historyTagColor,
            accentColor: GallaeHistoryColor(rawValue: accentColor)
        )
    }

    private var workspaceSubtitle: String {
        if let operation = model.remoteOperation {
            return operation.progressTitle
        }
        if model.isLoading, showsDelayedLocalProgress {
            return model.isWritingRepository ? "Updating Repository…" : "Reading Repository…"
        }
        return ""
    }

    /// One corner capsule for every long operation: remote work with Cancel, slow local reads without,
    /// and the last remote result for a moment. It never covers the toolbar or the selection.
    @ViewBuilder
    private var activityCapsule: some View {
        if let operation = model.remoteOperation {
            capsule {
                ProgressView()
                    .controlSize(.small)
                Text(operation.progressTitle)
                    .gallaeFont(.callout)
                Button("Cancel") {
                    model.cancelRemoteOperation()
                }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(operation.cancelTitle)
                .accessibilityHint(operation.cancelAccessibilityHint)
            }
            .accessibilityLabel(operation.progressTitle)
        } else if model.isLoading, showsDelayedLocalProgress {
            capsule {
                ProgressView()
                    .controlSize(.small)
                Text(model.isWritingRepository ? "Updating Repository…" : "Reading Repository…")
                    .gallaeFont(.callout)
            }
        } else if let result = model.remoteOperationResult {
            capsule {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.colors.statusAdded)
                    .accessibilityHidden(true)
                Text(result)
                    .gallaeFont(.callout)
            }
            .accessibilityLabel(result)
        }
    }

    private func capsule<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8, content: content)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: .capsule)
            .padding(12)
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func syncIcon(_ systemImage: String, running: Bool) -> some View {
        if running {
            ProgressView()
                .controlSize(.small)
                .frame(width: 18)
        } else {
            Image(systemName: systemImage)
                .frame(width: 18)
        }
    }

    private func chooseFolder() {
        folderSelection = .openOrAdd
        isFolderImporterPresented = true
    }

    private func chooseRepository(replacing id: URL? = nil) {
        folderSelection = .repository(replacing: id)
        isFolderImporterPresented = true
    }

    private func chooseLibraryFolder(replacing id: URL? = nil) {
        folderSelection = .libraryFolder(replacing: id)
        isFolderImporterPresented = true
    }

    private var automaticFetchRootURL: URL? {
        guard
            model.automaticFetchEnabled,
            model.screen == .workspace,
            scenePhase == .active
        else {
            return nil
        }
        return model.repository?.rootURL
    }
}

private struct RepositoryIntegrateBranchSheet: View {
    private struct ComparisonRequest: Equatable, Hashable {
        let source: String
        let target: String
        let revision: Int
        let retry: Int
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gallaeTheme) private var theme
    @Bindable var model: AppModel
    let repositoryRootURL: URL
    @State private var target: String?
    @State private var source: String?
    @State private var action: RepositoryBranchIntegrationAction = .fastForward
    @State private var preview: RepositoryBranchIntegrationPreview?
    @State private var previewRequest: ComparisonRequest?
    @State private var comparisonError: String?
    @State private var retry = 0
    @State private var conflictedWorktree: RepositorySummary?
    @State private var isSubmitting = false

    init(model: AppModel, repositoryRootURL: URL, initialBranch: String? = nil) {
        self.model = model
        self.repositoryRootURL = repositoryRootURL
        if case .branch(let branch) = model.repository?.head { _target = State(initialValue: branch) }
        _source = State(initialValue: initialBranch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Merge / Rebase", systemImage: "arrow.triangle.merge")
                    .gallaeFont(.title2, weight: .bold)
                Text("Choose which branch to update and where its commits come from.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            branchContent

            if target != nil && source != nil {
                comparison
                if let preview = currentPreview, preview.divergence.uniqueToOther > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Method").gallaeFont(.body, weight: .semibold)
                        Picker("Method", selection: $action) {
                            Text("Fast-Forward").tag(RepositoryBranchIntegrationAction.fastForward)
                            Text("Merge Commit").tag(RepositoryBranchIntegrationAction.mergeCommit)
                            Text("Rebase").tag(RepositoryBranchIntegrationAction.rebase)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel("Update method")
                        Text(methodDescription)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let reason = preview.unavailableReason(for: action) {
                            Label(reason, systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if action == .rebase {
                            Label("Rebase rewrites commits on \(preview.target). Gallae won’t force-push them.",
                                  systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .gallaeFont(.callout)
                    .disabled(isSubmitting)
                }
            }

            Divider()
            HStack {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                    Text("Updating branch…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSubmitting)
                Button(actionTitle) { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(currentPreview?.unavailableReason(for: action) != nil
                              || currentPreview == nil || previewRequest != comparisonRequest
                              || model.isLoading || model.isSyncing || isSubmitting)
                    .accessibilityHint(methodDescription)
            }
        }
        .padding(24)
        .frame(width: 560)
        .task(id: repositoryRootURL) { await model.loadLocalBranches() }
        .task(id: comparisonRequest) { await compareBranches() }
        .onChange(of: model.localBranchesState, initial: true) { _, _ in reconcileSelection() }
        .onChange(of: model.repository?.rootURL) { _, root in
            if root != repositoryRootURL { dismiss() }
        }
        .confirmationDialog(
            "Merge Needs Conflict Resolution",
            isPresented: Binding(get: { conflictedWorktree != nil }, set: { if !$0 { conflictedWorktree = nil } }),
            titleVisibility: .visible,
            presenting: conflictedWorktree
        ) { worktree in
            Button("Open Worktree") {
                Task { if await model.openRepository(at: worktree.rootURL) { dismiss() } }
            }
            Button("Abort Merge", role: .destructive) {
                Task {
                    await model.abortMergeInWorktree(worktree)
                    retry += 1
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { worktree in
            Text("Resolve the conflicts in \(worktree.rootURL.path), or abort the merge to restore the target branch.")
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    @ViewBuilder
    private var branchContent: some View {
        switch model.localBranchesState {
        case .notLoaded, .loading:
            ProgressView("Loading Branches…").frame(maxWidth: .infinity)
        case .failed(let message):
            Text(message).foregroundStyle(.secondary)
            Button("Try Again") { Task { await model.loadLocalBranches() } }
        case .loaded(let branches) where branches.count < 2:
            Label("Create another local branch to merge or rebase.", systemImage: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
        case .loaded(let branches):
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    branchPicker("Update branch", selection: Binding(
                        get: { target },
                        set: { newTarget in
                            let oldTarget = target
                            target = newTarget
                            if source == newTarget { source = oldTarget }
                        }
                    ), branches: branches)
                    branchPicker("Using branch", selection: $source, branches: branches.filter { $0 != target })
                }
                Button {
                    (target, source) = (source, target)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Swap source and target branches")
                .help("Swap which branch receives the update")
                .disabled(target == nil || source == nil)
            }
            .padding(16)
            .background(theme.colors.badgeBackground, in: .rect(cornerRadius: 10))
            .disabled(isSubmitting)
        }
    }

    private func branchPicker(_ title: String, selection: Binding<String?>, branches: [String]) -> some View {
        HStack(spacing: 12) {
            Text(title).gallaeFont(.callout, weight: .semibold)
                .frame(width: 120, alignment: .leading)
            Picker(title, selection: selection) {
                if selection.wrappedValue == nil { Text("Choose a branch").tag(Optional<String>.none) }
                ForEach(branches, id: \.self) { branch in
                    Text(branchLabel(branch)).tag(Optional(branch))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(selection.wrappedValue ?? title)
        }
    }

    @ViewBuilder
    private var comparison: some View {
        if let message = comparisonError {
            Label(message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
            Button("Retry Comparison") { retry += 1 }
        } else if let preview = currentPreview {
            VStack(alignment: .leading, spacing: 6) {
                Label(comparisonTitle(preview), systemImage: preview.divergence.uniqueToOther == 0 ? "checkmark.circle" : "arrow.triangle.branch")
                    .gallaeFont(.body, weight: .semibold)
                Text(comparisonDescription(preview))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if preview.divergence.uniqueToOther > 0 {
                    Text(worktreeDescription(preview))
                        .gallaeFont(.caption1)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            ProgressView("Comparing branches…")
        }
    }

    private var currentPreview: RepositoryBranchIntegrationPreview? {
        guard let preview, preview.source == source, preview.target == target else { return nil }
        return preview
    }

    private var comparisonRequest: ComparisonRequest? {
        guard let source, let target, source != target else { return nil }
        return .init(source: source, target: target, revision: model.repositoryRevision, retry: retry)
    }

    private func compareBranches() async {
        comparisonError = nil
        guard let request = comparisonRequest else {
            preview = nil
            previewRequest = nil
            return
        }
        let isNewPair = previewRequest?.source != request.source || previewRequest?.target != request.target
        if isNewPair { preview = nil }
        do {
            let result = try await model.previewIntegration(from: request.source, into: request.target, in: repositoryRootURL)
            guard !Task.isCancelled, request == comparisonRequest else { return }
            if isNewPair { action = result.isDiverged ? .mergeCommit : .fastForward }
            preview = result
            previewRequest = request
        } catch {
            guard !Task.isCancelled, request == comparisonRequest else { return }
            comparisonError = error.localizedDescription
        }
    }

    private func comparisonTitle(_ preview: RepositoryBranchIntegrationPreview) -> String {
        if preview.divergence.uniqueToOther == 0 { return "Already up to date" }
        return preview.isDiverged ? "Both branches have new commits" : "Ready to fast-forward"
    }

    private func comparisonDescription(_ preview: RepositoryBranchIntegrationPreview) -> String {
        let ours = preview.divergence.uniqueToCurrent
        let theirs = preview.divergence.uniqueToOther
        if ours == 0 && theirs == 0 { return "\(preview.target) and \(preview.source) point at the same commit. No update is needed." }
        if theirs == 0 { return "\(preview.target) already contains every commit from \(preview.source). Swap the branches to update \(preview.source)." }
        if ours == 0 { return "Bring \(theirs) commit\(theirs == 1 ? "" : "s") from \(preview.source) into \(preview.target)." }
        return "\(preview.target) has \(ours) and \(preview.source) has \(theirs) unique commits. Choose how to combine them."
    }

    private func worktreeDescription(_ preview: RepositoryBranchIntegrationPreview) -> String {
        if let worktree = preview.targetWorktree {
            return sameFileLocation(worktree.rootURL, repositoryRootURL)
                ? "Updates files in the current working folder."
                : "Updates the target Worktree at \(worktree.rootURL.path). Your current working folder stays open."
        }
        return "Uses a temporary Worktree for \(preview.target), removed after success. Your current working folder stays open."
    }

    private var actionTitle: String {
        switch action {
        case .fastForward: "Fast-Forward"
        case .mergeCommit: "Create Merge Commit"
        case .rebase: "Rebase"
        }
    }

    private var methodDescription: String {
        let target = target ?? "the target branch"
        let source = source ?? "the source branch"
        switch action {
        case .fastForward: return "Move \(target) forward to \(source) without creating a commit."
        case .mergeCommit: return "Merge \(source) into \(target), preserving both histories with a merge commit."
        case .rebase: return "Replay commits unique to \(target) on top of \(source)."
        }
    }

    private func branchLabel(_ branch: String) -> String {
        if model.repository?.head == .branch(branch) { return "\(branch) · Current" }
        if model.localBranchWorktreeURLs[branch] != nil { return "\(branch) · Worktree" }
        return branch
    }

    private func reconcileSelection() {
        guard case .loaded(let branches) = model.localBranchesState else { return }
        if target.map(branches.contains) != true { target = branches.first }
        if source == target || source.map(branches.contains) != true { source = branches.first { $0 != target } }
    }

    private func submit() {
        guard let preview = currentPreview, previewRequest == comparisonRequest,
              preview.unavailableReason(for: action) == nil else { return }
        let chosenAction = action
        isSubmitting = true
        Task {
            let result = await model.integrateBranches(preview, action: chosenAction)
            isSubmitting = false
            switch result {
            case .completed: dismiss()
            case .conflictedInWorktree(let worktree):
                conflictedWorktree = worktree
                retry += 1
            case .failed: retry += 1
            }
        }
    }
}

struct EditRemoteSheet: View {
    private enum Field: Hashable {
        case name
        case fetchURL
        case pushURL
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    let model: AppModel
    let repositoryRootURL: URL
    let remote: RepositoryRemote
    @State private var remoteName: String
    @State private var fetchURL: String
    @State private var pushURL: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var connectionTestState: ConnectionTestState = .idle
    @State private var connectionTestTask: Task<Void, Never>?
    @State private var connectionTestErrorMessage: String?
    @State private var isConfirmingRemoval = false
    @State private var removalErrorMessage: String?

    private enum ConnectionTestState: Equatable {
        case idle
        case testing
        case reachable
    }

    init(model: AppModel, repositoryRootURL: URL, remote: RepositoryRemote) {
        self.model = model
        self.repositoryRootURL = repositoryRootURL
        self.remote = remote
        _remoteName = State(initialValue: remote.name)
        _fetchURL = State(initialValue: remote.fetchURL)
        _pushURL = State(initialValue: remote.pushURL)
    }

    private var trimmedRemoteName: String {
        remoteName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFetchURL: String {
        fetchURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPushURL: String {
        pushURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedRemoteName.isEmpty
            && !trimmedFetchURL.isEmpty
            && !trimmedPushURL.isEmpty
            && (
                trimmedRemoteName != remote.name
                    || trimmedFetchURL != remote.fetchURL
                    || trimmedPushURL != remote.pushURL
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Edit Remote", systemImage: "pencil")
                        .gallaeFont(.title2, weight: .bold)
                    Text(remote.name)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // The one destructive action sits apart from Save, top right, and asks first.
                Button("Remove…", role: .destructive) {
                    isConfirmingRemoval = true
                }
                .disabled(isSaving || model.isLoading)
                .accessibilityLabel("Remove \(remote.name) Remote")
                .help("Remove this Remote and its remote-tracking branches from the Repository")
            }

            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Name")
                    TextField("Remote name", text: $remoteName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)
                        .onSubmit { focusedField = .fetchURL }
                        .accessibilityHint("Name used for this Remote in Git")
                }
                GridRow {
                    Text("Fetch URL")
                    TextField("Fetch URL or path", text: $fetchURL)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .fetchURL)
                        .onSubmit { focusedField = .pushURL }
                        .accessibilityHint("Repository location used when fetching")
                }
                GridRow {
                    Text("Push URL")
                    TextField("Push URL or path", text: $pushURL)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .pushURL)
                        .accessibilityHint("Repository location used when pushing")
                }
            }

            Text("Fetch and Push URLs should point to the same Repository.")
                .gallaeFont(.caption1)
                .foregroundStyle(.secondary)

            HStack {
                switch connectionTestState {
                case .testing:
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Testing \(remote.name) Fetch Connection")
                    Text("Testing…")
                        .foregroundStyle(.secondary)
                    Button("Cancel Test") {
                        connectionTestTask?.cancel()
                    }
                case .reachable:
                    Button {
                        testConnection()
                    } label: {
                        Label("Reachable", systemImage: "checkmark.circle")
                    }
                    .disabled(model.isLoading)
                    .accessibilityLabel("Test \(remote.name) Fetch Connection")
                case .idle:
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(model.isLoading)
                    .accessibilityLabel("Test \(remote.name) Fetch Connection")
                    .help("Ask Git to read the saved Fetch URL without changing local Repository state")
                }

                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isSaving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || isSaving)
                .accessibilityHint("Save the Remote name and both URLs without contacting it")
            }
        }
        .padding(24)
        .frame(width: 560)
        .interactiveDismissDisabled(isSaving)
        .onAppear { focusedField = .name }
        .onDisappear { connectionTestTask?.cancel() }
        .confirmationDialog(
            "Remove Remote?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove “\(remote.name)”", role: .destructive) {
                Task { await removeRemote() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes “\(remote.name)” and its local remote-tracking branches from this Repository. It doesn’t delete the remote Repository, local branches, commits, or working files."
            )
        }
        .alert(
            "Couldn’t Remove Remote",
            isPresented: Binding(
                get: { removalErrorMessage != nil },
                set: { if !$0 { removalErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(removalErrorMessage ?? "Unknown error")
        }
        .alert(
            "Couldn’t Reach Remote",
            isPresented: Binding(
                get: { connectionTestErrorMessage != nil },
                set: { if !$0 { connectionTestErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(connectionTestErrorMessage ?? "Unknown error")
        }
        .alert(
            "Couldn’t Update Remote",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func removeRemote() async {
        do {
            try await model.removeRemote(named: remote.name, in: repositoryRootURL)
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            removalErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func testConnection() {
        guard connectionTestTask == nil else { return }
        connectionTestState = .testing
        connectionTestErrorMessage = nil
        connectionTestTask = Task {
            defer { connectionTestTask = nil }
            do {
                try await model.testRemoteConnection(named: remote.name, in: repositoryRootURL)
                try Task.checkCancellation()
                connectionTestState = .reachable
            } catch is CancellationError {
                connectionTestState = .idle
            } catch {
                connectionTestState = .idle
                connectionTestErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.updateRemote(
                named: remote.name,
                renamingTo: trimmedRemoteName,
                fetchURL: trimmedFetchURL,
                pushURL: trimmedPushURL,
                in: repositoryRootURL
            )
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

private struct AddRemoteSheet: View {
    private enum Field: Hashable {
        case url
        case branch
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gallaeTheme) private var theme
    @FocusState private var focusedField: Field?
    let model: AppModel
    let repositoryRootURL: URL
    var publishAfterAdding = true
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var remoteName = "origin"
    @State private var repositoryURL = ""
    @State private var remoteBranch = ""
    @State private var branchError: String?

    private var canSubmit: Bool {
        !remoteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!publishAfterAdding || !remoteBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label(publishAfterAdding ? "Publish Branch" : "Add Remote", systemImage: "network")
                    .gallaeFont(.title2, weight: .bold)
                Text(publishAfterAdding
                     ? "Add a remote to publish this branch from \(repositoryRootURL.lastPathComponent)."
                     : "Save a remote URL for \(repositoryRootURL.lastPathComponent). This does not fetch or push.")
                    .foregroundStyle(.secondary)
            }

            if publishAfterAdding, case .branch(let branch) = model.repository?.head {
                PublishSourceSummary(branch: branch)
            }

            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Remote Name")
                    TextField("Remote name", text: $remoteName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityHint("A short Git remote name, such as origin")
                }
                GridRow {
                    Text("Repository URL")
                    TextField("Remote URL or path", text: $repositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .url)
                        .accessibilityHint("HTTPS, SSH, or local Git Repository location")
                }
                if publishAfterAdding {
                    GridRow {
                        Text("Remote Branch")
                        TextField("Remote branch name", text: $remoteBranch)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Remote Branch")
                            .accessibilityHint(branchError ?? "Branch name on the remote; the local branch keeps its name")
                            .focused($focusedField, equals: .branch)
                    }
                    if let branchError {
                        GridRow {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            Label(branchError, systemImage: "exclamationmark.circle")
                                .gallaeFont(.caption1)
                                .foregroundStyle(theme.colors.statusConflict)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if publishAfterAdding, case .branch(let branch) = model.repository?.head {
                Divider()
                PublishDestinationSummary(remote: remoteName, branch: remoteBranch, localBranch: branch)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(publishAfterAdding ? "Add & Publish" : "Add Remote") {
                    let name = remoteName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let url = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if publishAfterAdding {
                        isSubmitting = true
                        Task {
                            defer { isSubmitting = false }
                            do {
                                let branch = try await model.validatePublishBranchName(remoteBranch)
                                model.addRemoteAndPublish(named: name, url: url, branch: branch, in: repositoryRootURL)
                                dismiss()
                            } catch {
                                branchError = error.localizedDescription
                                focusedField = .branch
                                NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
                                    .announcement: error.localizedDescription,
                                    .priority: NSAccessibilityPriorityLevel.high.rawValue
                                ])
                            }
                        }
                    } else {
                        isSubmitting = true
                        Task {
                            defer { isSubmitting = false }
                            do {
                                try await model.addRemote(named: name, url: url, in: repositoryRootURL)
                                dismiss()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || branchError != nil || isSubmitting || model.isLoading || model.isSyncing)
                .accessibilityHint(publishAfterAdding ? "Add this remote and publish the current branch without force" : "Save this remote without fetching or pushing")
            }
        }
        .disabled(isSubmitting)
        .interactiveDismissDisabled(isSubmitting)
        .alert("Couldn’t Add Remote", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .padding(24)
        .frame(width: 560)
        .onChange(of: remoteBranch) { branchError = nil }
        .onChange(of: isSubmitting) {
            if !isSubmitting, branchError != nil { focusedField = .branch }
        }
        .onChange(of: model.repository?.rootURL) { dismiss() }
        .onChange(of: model.repository?.head) { if publishAfterAdding { dismiss() } }
        .onAppear {
            if case .branch(let branch) = model.repository?.head { remoteBranch = branch }
            focusedField = .url
        }
    }
}

private struct CreateStashSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isMessageFocused: Bool
    let model: AppModel
    let repositoryRootURL: URL
    @State private var message = ""
    @State private var includeUntracked = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var repository: RepositorySummary? {
        guard model.repository?.rootURL.standardizedFileURL == repositoryRootURL.standardizedFileURL
        else { return nil }
        return model.repository
    }

    private var hasTrackedChanges: Bool {
        repository?.changes.contains {
            $0.staged != nil || ($0.unstaged != nil && $0.unstaged != .untracked)
        } == true
    }

    private var hasUntrackedChanges: Bool {
        repository?.changes.contains { $0.unstaged == .untracked } == true
    }

    private var unavailableReason: String? {
        guard let repository else {
            return "This Repository is no longer open."
        }
        if repository.isUnborn {
            return "Create the first commit before saving a Stash."
        }
        if repository.changes.contains(where: \.isConflicted) {
            return "Resolve conflicted files before saving a Stash."
        }
        if hasTrackedChanges || (includeUntracked && hasUntrackedChanges) {
            return nil
        }
        if hasUntrackedChanges {
            return "Turn on Include Untracked Files to save these changes."
        }
        return "There are no changes to save."
    }

    private var canCreate: Bool {
        unavailableReason == nil && !model.isLoading && !isCreating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Create Stash", systemImage: "archivebox")
                    .gallaeFont(.title2, weight: .bold)
                Text("Save the current changes in \(repositoryRootURL.lastPathComponent) and return tracked files to HEAD.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Message (optional)", text: $message)
                    .textFieldStyle(.roundedBorder)
                    .focused($isMessageFocused)
                    .accessibilityHint("Describe why these changes are being saved")

                Toggle("Include Untracked Files", isOn: $includeUntracked)
                    .accessibilityHint("Save untracked files too; ignored files remain in place")

                Text("Staged and unstaged tracked changes are always included. Ignored files are not included.")
                    .gallaeFont(.caption1)
                    .foregroundStyle(.secondary)

                if let unavailableReason {
                    Text(unavailableReason)
                        .gallaeFont(.caption1)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if isCreating {
                    ProgressView("Creating Stash…")
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isCreating)

                Button(isCreating ? "Creating…" : "Create Stash") {
                    Task { await createStash() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .accessibilityHint("Save the selected changes and refresh this Workspace")
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled(isCreating)
        .onAppear { isMessageFocused = true }
        .alert(
            "Couldn’t Create Stash",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func createStash() async {
        isCreating = true
        defer { isCreating = false }
        do {
            try await model.createStash(
                message: message,
                includeUntracked: includeUntracked,
                in: repositoryRootURL
            )
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

private struct ChooseRemoteSheet: View {
    enum Purpose {
        case fetch(pruning: Bool)
        case publish

        var title: String {
            switch self {
            case .fetch(let pruning): pruning ? "Choose Fetch & Prune Remote" : "Choose Fetch Remote"
            case .publish: "Publish Branch"
            }
        }

        var systemImage: String {
            switch self {
            case .fetch(let pruning): pruning ? "scissors" : "arrow.down.circle"
            case .publish: "arrow.up.to.line"
            }
        }

        var buttonTitle: String {
            switch self {
            case .fetch(let pruning): pruning ? "Fetch & Prune" : "Fetch"
            case .publish: "Publish Branch"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gallaeTheme) private var theme
    @FocusState private var isBranchFocused: Bool
    let model: AppModel
    let repositoryRootURL: URL
    let remotes: [String]
    let purpose: Purpose
    @State private var selectedRemote: String
    @State private var remoteBranch: String
    @State private var branchError: String?
    @State private var isValidating = false

    private var localBranch: String {
        if case .branch(let branch) = model.repository?.head { return branch }
        return ""
    }

    private var canSubmit: Bool {
        guard !selectedRemote.isEmpty else { return false }
        if case .publish = purpose {
            return !remoteBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var remoteURL: String? {
        guard case .loaded(let configuredRemotes) = model.remotesState else { return nil }
        return configuredRemotes.first { $0.name == selectedRemote }?.pushURL
    }

    init(model: AppModel, repositoryRootURL: URL, remotes: [String], purpose: Purpose) {
        self.model = model
        self.repositoryRootURL = repositoryRootURL
        self.remotes = remotes
        self.purpose = purpose
        let preferredRemote: String
        if case .publish = purpose, remotes.contains("origin") {
            preferredRemote = "origin"
        } else {
            preferredRemote = remotes.first ?? ""
        }
        _selectedRemote = State(initialValue: preferredRemote)
        if case .branch(let branch) = model.repository?.head {
            _remoteBranch = State(initialValue: branch)
        } else {
            _remoteBranch = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label(purpose.title, systemImage: purpose.systemImage)
                    .gallaeFont(.title2, weight: .bold)
                Text(description)
                    .foregroundStyle(.secondary)
            }

            if case .publish = purpose {
                PublishSourceSummary(branch: localBranch)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow(alignment: .top) {
                        Text("Remote").padding(.top, 3)
                        VStack(alignment: .leading, spacing: 6) {
                            if remotes.count == 1 {
                                Text(selectedRemote).gallaeFont(.body, weight: .medium)
                            } else {
                                remotePicker.labelsHidden()
                            }
                            if let remoteURL {
                                Text(remoteURL)
                                    .gallaeFont(.caption1)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .help(remoteURL)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow(alignment: .top) {
                        Text("Branch Name").padding(.top, 3)
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Remote branch name", text: $remoteBranch)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Remote Branch")
                                .accessibilityHint(branchError ?? "Name of the branch to publish on the selected remote")
                                .focused($isBranchFocused)
                            if let branchError {
                                Label(branchError, systemImage: "exclamationmark.circle")
                                    .gallaeFont(.caption1)
                                    .foregroundStyle(theme.colors.statusConflict)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(remoteBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? "Enter a name for the remote branch."
                                     : "Edit this name to publish under a different name.")
                                    .gallaeFont(.caption1)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Divider()
                PublishDestinationSummary(remote: selectedRemote, branch: remoteBranch, localBranch: localBranch)
            } else {
                remotePicker
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isValidating)
                Button(purpose.buttonTitle) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit || branchError != nil || model.isLoading || model.isSyncing || isValidating)
                    .accessibilityHint(actionAccessibilityHint)
            }
        }
        .padding(24)
        .frame(width: 560)
        .interactiveDismissDisabled(isValidating)
        .disabled(isValidating)
        .onAppear { if case .publish = purpose { isBranchFocused = true } }
        .onChange(of: remoteBranch) { branchError = nil }
        .onChange(of: isValidating) {
            if !isValidating, branchError != nil { isBranchFocused = true }
        }
        .onChange(of: model.repository?.rootURL) { dismiss() }
        .onChange(of: model.repository?.head) { if case .publish = purpose { dismiss() } }
    }

    private var remotePicker: some View {
        Picker("Remote", selection: $selectedRemote) {
            ForEach(remotes, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)
    }

    private var actionAccessibilityHint: String {
        switch purpose {
        case .fetch(let pruning):
            pruning
                ? "Fetch and prune only the selected Remote without changing local branches or working files"
                : "Fetch only the selected Remote without changing the current branch or working tree"
        case .publish: "Publish to the displayed destination and start tracking the remote branch"
        }
    }

    private func submit() {
        switch purpose {
        case .fetch(let pruning):
            model.fetch(from: selectedRemote, pruning: pruning, in: repositoryRootURL)
            dismiss()
        case .publish:
            isValidating = true
            Task {
                defer { isValidating = false }
                do {
                    let branch = try await model.validatePublishBranchName(remoteBranch)
                    model.publish(to: selectedRemote, branch: branch, in: repositoryRootURL)
                    dismiss()
                } catch {
                    branchError = error.localizedDescription
                    isBranchFocused = true
                    NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
                        .announcement: error.localizedDescription,
                        .priority: NSAccessibilityPriorityLevel.high.rawValue
                    ])
                }
            }
        }
    }

    private var description: String {
        switch purpose {
        case .fetch(let pruning):
            pruning
                ? "Fetch changes and remove stale local tracking references for \(repositoryRootURL.lastPathComponent) from the selected Remote."
                : "Fetch changes for \(repositoryRootURL.lastPathComponent) from the selected Remote without changing local files."
        case .publish:
            "Choose a destination for this branch in \(repositoryRootURL.lastPathComponent)."
        }
    }
}

private struct PublishSourceSummary: View {
    @Environment(\.gallaeTheme) private var theme
    let branch: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Local Branch").gallaeFont(.caption1).foregroundStyle(.secondary)
            Label(branch, systemImage: "arrow.triangle.branch")
                .gallaeFont(.body, weight: .medium)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.colors.badgeBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PublishDestinationSummary: View {
    let remote: String
    let branch: String
    let localBranch: String

    private var branchName: String { branch.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Publish to").gallaeFont(.caption1).foregroundStyle(.secondary)
            Text("\(remote.trimmingCharacters(in: .whitespacesAndNewlines))/\(branchName.isEmpty ? "…" : branchName)")
                .gallaeFont(.body, weight: .medium)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(branchName == localBranch
                 ? "Future pushes and pulls will use this branch."
                 : "Your local branch keeps its current name.")
                .gallaeFont(.caption1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CreateTagSheet: View {
    let model: AppModel
    let repositoryRootURL: URL
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name = ""
    @State private var target = "HEAD"
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("New Tag", systemImage: "tag").gallaeFont(.title2, weight: .bold)
            Text("Create a local lightweight tag at a commit. This does not switch branches or push the tag.")
                .foregroundStyle(.secondary)
            Form {
                TextField("Name", text: $name).focused($isNameFocused)
                TextField("Target Commit", text: $target)
                    .help("HEAD, a branch name, or a commit SHA")
            }
            .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create Tag") {
                    isCreating = true
                    Task {
                        defer { isCreating = false }
                        do {
                            try await model.createTag(named: name, at: target, in: repositoryRootURL)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || model.isLoading || model.isSyncing)
            }
        }
        .padding(24).frame(width: 440)
        .disabled(isCreating)
        .interactiveDismissDisabled(isCreating)
        .onAppear { isNameFocused = true }
        .alert("Couldn’t Create Tag", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }
}
