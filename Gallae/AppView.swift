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
                    model: model,
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
                            Text("Pull")
                        } icon: {
                            syncIcon("arrow.down.to.line", running: model.remoteOperation == .pull)
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    .disabled(!model.canPullRepository || model.isLoading || model.isSyncing)
                    .accessibilityLabel("Pull")
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
                            ? "Publish the current branch to its remote and start tracking it"
                            : "Push the current branch to its configured destination"
                    )
                    .accessibilityHint(
                        model.repository?.upstream == nil
                            ? "Publish the current local branch to its only remote and start tracking it without force"
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
                        model.reconnectLibraryFolder(replacedID, to: url)
                    } else {
                        model.addLibraryFolder(at: url)
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
            model.errorTitle ?? "Couldn’t Complete the Request",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
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
                    .font(.callout)
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
                    .font(.callout)
            }
        } else if let result = model.remoteOperationResult {
            capsule {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.colors.statusAdded)
                    .accessibilityHidden(true)
                Text(result)
                    .font(.callout)
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

enum RepositoryBranchIntegrationAction: Sendable {
    case fastForward
    case mergeCommit
    case rebase
}

private struct RepositoryIntegrateBranchSheet: View {
    private enum Direction: Hashable {
        case into
        case from
    }

    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    let repositoryRootURL: URL
    @State private var direction: Direction = .into
    @State private var selectedBranch: String?
    @State private var divergence: RepositoryBranchDivergence?
    @State private var mergePrediction: RepositoryMergePrediction?
    @State private var conflictedWorktreeURL: URL?

    init(model: AppModel, repositoryRootURL: URL, initialBranch: String? = nil) {
        self.model = model
        self.repositoryRootURL = repositoryRootURL
        _selectedBranch = State(initialValue: initialBranch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Integrate Local Branch", systemImage: "arrow.triangle.merge")
                    .font(.title2.bold())
                Text(
                    direction == .into
                        ? "Bring the selected branch into \(currentBranch), or rebase \(currentBranch) onto it."
                        : "Fast-forward the selected branch to \(currentBranch) without switching."
                )
                .foregroundStyle(.secondary)
            }

            Picker("Direction", selection: $direction) {
                Text("Update \(currentBranch)").tag(Direction.into)
                Text("Update another branch").tag(Direction.from)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Integration Direction")
            .accessibilityHint(
                "Choose whether the selected branch updates \(currentBranch), or \(currentBranch) updates the selected branch"
            )

            branchContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let divergenceDescription {
                Label(divergenceDescription, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            directionCaption

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                if direction == .into {
                    Button("Rebase Current Branch") {
                        integrateBranch(.rebase)
                    }
                    .disabled(
                        selectedBranch == nil || !hasCleanRepository || !hasCommitsToIntegrate
                            || model.isLoading
                    )
                    .accessibilityHint(
                        "Replay the current branch commits onto the selected local branch"
                    )

                    Button("Create Merge Commit") {
                        integrateBranch(.mergeCommit)
                    }
                    .disabled(
                        selectedBranch == nil || !hasCleanRepository || !hasCommitsToIntegrate
                            || model.isLoading
                    )
                    .accessibilityHint(
                        "Create a merge commit from the selected divergent local branch"
                    )

                    Button("Fast-Forward") {
                        integrateBranch(.fastForward)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedBranch == nil || !canFastForward || model.isLoading)
                    .accessibilityHint(
                        "Fast-forward the current branch to the selected local branch"
                    )
                } else if isDivergedSelection {
                    if selectedWorktreeURL == nil, mergePrediction?.isClean == false {
                        Button("Merge in Temporary Worktree…") {
                            mergeInTemporaryWorktree()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedBranch == nil || model.isLoading)
                        .accessibilityHint(
                            "Create a temporary Worktree for the selected branch, merge there, and resolve the conflicts in Gallae"
                        )
                    } else {
                        Button("Create Merge Commit on \(selectedBranch ?? "Branch")") {
                            mergeIntoSelectedBranch()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            selectedBranch == nil || !canCreateMergeCommitOut || model.isLoading
                        )
                        .accessibilityHint(
                            "Create a merge commit on the selected branch without switching to it"
                        )
                    }
                } else {
                    Button("Fast-Forward \(selectedBranch ?? "Branch") to \(currentBranch)") {
                        fastForwardSelectedBranch()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedBranch == nil || !canFastForwardOut || model.isLoading)
                    .accessibilityHint(
                        "Move the selected branch forward to the current branch without switching"
                    )
                }
            }
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 360, idealHeight: 440)
        .task(id: repositoryRootURL) {
            await model.loadLocalBranches()
        }
        .task(id: selectedBranch) {
            divergence = nil
            guard let branch = selectedBranch else { return }
            let result = await model.branchDivergence(from: branch)
            guard !Task.isCancelled, branch == selectedBranch else { return }
            divergence = result
        }
        .task(id: predictionBranch) {
            mergePrediction = nil
            guard let branch = predictionBranch else { return }
            let result = await model.mergePrediction(into: branch)
            guard !Task.isCancelled, branch == predictionBranch else { return }
            mergePrediction = result
        }
        .onChange(of: model.localBranchesState, initial: true) { _, _ in
            reconcileSelection()
        }
        .confirmationDialog(
            "Merge Conflicted in Worktree",
            isPresented: Binding(
                get: { conflictedWorktreeURL != nil },
                set: { if !$0 { conflictedWorktreeURL = nil } }
            ),
            titleVisibility: .visible,
            presenting: conflictedWorktreeURL
        ) { worktreeURL in
            Button("Open Worktree") {
                Task {
                    if await model.openRepository(at: worktreeURL) {
                        dismiss()
                    }
                }
            }
            Button("Abort Merge", role: .destructive) {
                Task { await model.abortMergeInWorktree(at: worktreeURL) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { worktreeURL in
            Text(
                "The merge stopped with conflicts in \(worktreeURL.path). Open the Worktree to resolve the conflicts and Continue, or abort to restore its earlier state."
            )
        }
        .interactiveDismissDisabled(model.isLoading)
    }

    private var predictionBranch: String? {
        guard direction == .from, isDivergedSelection else { return nil }
        return selectedBranch
    }

    private var isDivergedSelection: Bool {
        divergence.map { $0.uniqueToCurrent > 0 && $0.uniqueToOther > 0 } == true
    }

    private var selectedWorktreeURL: URL? {
        guard let selectedBranch else { return nil }
        return model.localBranchWorktreeURLs[selectedBranch]
    }

    private var canCreateMergeCommitOut: Bool {
        if selectedWorktreeURL != nil {
            // Worktree 경로는 충돌해도 열어서 해결할 수 있으므로 예측과 무관하게 실행한다.
            return true
        }
        return mergePrediction?.isClean == true
    }

    private func mergeIntoSelectedBranch() {
        guard let selectedBranch else { return }
        Task {
            switch await model.mergeCurrentBranchIntoBranch(selectedBranch) {
            case .completed:
                dismiss()
            case .conflictedInWorktree(let worktreeURL):
                conflictedWorktreeURL = worktreeURL
            case .failed:
                break
            }
        }
    }

    private func mergeInTemporaryWorktree() {
        guard let selectedBranch else { return }
        Task {
            if await model.mergeInTemporaryWorktree(selectedBranch) {
                dismiss()
            }
        }
    }

    private var divergenceDescription: String? {
        guard let selectedBranch, let divergence else { return nil }
        let ours = divergence.uniqueToCurrent
        let theirs = divergence.uniqueToOther
        switch direction {
        case .into:
            switch (ours, theirs) {
            case (0, 0):
                return "\(currentBranch) and \(selectedBranch) point at the same commit."
            case (_, 0):
                return "\(currentBranch) already contains every commit of \(selectedBranch). Switch to Update another branch to fast-forward \(selectedBranch) here."
            case (0, _):
                return "\(selectedBranch) is \(theirs) commit\(theirs == 1 ? "" : "s") ahead. Fast-Forward applies them to \(currentBranch)."
            default:
                return "Diverged · \(currentBranch) has \(ours) and \(selectedBranch) has \(theirs) unique commit\(theirs == 1 ? "" : "s"). Fast-Forward isn’t possible."
            }
        case .from:
            switch (ours, theirs) {
            case (0, 0):
                return "\(currentBranch) and \(selectedBranch) point at the same commit — nothing to fast-forward."
            case (_, 0):
                return "\(selectedBranch) is \(ours) commit\(ours == 1 ? "" : "s") behind. Fast-Forward updates it to \(currentBranch) without switching."
            case (0, _):
                return "\(selectedBranch) is ahead of \(currentBranch) — there is nothing to bring into it."
            default:
                guard let mergePrediction else {
                    return "Diverged · checking whether a merge commit would conflict…"
                }
                if mergePrediction.isClean {
                    return "Diverged · a merge commit can bring \(currentBranch) into \(selectedBranch) without conflicts."
                }
                let paths = mergePrediction.conflictedPaths
                let shown = paths.prefix(3).joined(separator: ", ")
                return "Merging would conflict in \(paths.count) file\(paths.count == 1 ? "" : "s"): \(shown)\(paths.count > 3 ? ", …" : "")"
            }
        }
    }

    @ViewBuilder
    private var directionCaption: some View {
        if direction == .into {
            if hasCleanRepository {
                Label(
                    "Rebase rewrites commits unique to \(currentBranch); Gallae won’t force-push them.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "Commit or stash the current changes before creating a merge commit or rebasing.",
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else if let worktreeURL = selectedWorktreeURL {
            Label(
                isDivergedSelection
                    ? "The merge runs in the Worktree at \(worktreeURL.path). Conflicts can be resolved there in Gallae."
                    : "Fast-Forward runs in the Worktree at \(worktreeURL.path) and updates its files.",
                systemImage: "folder"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .help(worktreeURL.path)
        } else if isDivergedSelection {
            Label(
                mergePrediction?.isClean == false
                    ? "A temporary Worktree checks out \(selectedBranch ?? "the branch") so the conflicts can be resolved in Gallae."
                    : "The merge commit is created without a checkout, so merge hooks don’t run. Only the selected branch reference moves.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        } else {
            Label(
                "Only the selected branch reference moves. No working files change, and uncommitted changes here are fine.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var canFastForward: Bool {
        divergence.map { $0.uniqueToCurrent == 0 && $0.uniqueToOther > 0 } ?? true
    }

    private var canFastForwardOut: Bool {
        divergence.map { $0.uniqueToCurrent > 0 && $0.uniqueToOther == 0 } ?? true
    }

    private var hasCommitsToIntegrate: Bool {
        divergence.map { $0.uniqueToOther > 0 } ?? true
    }

    private func fastForwardSelectedBranch() {
        guard let selectedBranch else { return }
        Task {
            if await model.fastForwardBranchToCurrent(selectedBranch) {
                dismiss()
            }
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
        case .loaded where availableBranches.isEmpty:
            ContentUnavailableView(
                "No Other Local Branches",
                systemImage: "arrow.triangle.merge",
                description: Text("Create or Fetch another branch before integrating.")
            )
        case .loaded:
            List(availableBranches, id: \.self, selection: $selectedBranch) { branch in
                HStack {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let worktreeURL = model.localBranchWorktreeURLs[branch] {
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
            }
            .listStyle(.plain)
            .accessibilityLabel("Local Branches Available to Integrate")
        }
    }

    private var currentBranch: String {
        guard case .branch(let branch) = model.repository?.head else {
            return "the current branch"
        }
        return branch
    }

    private var availableBranches: [String] {
        guard case .loaded(let branches) = model.localBranchesState else { return [] }
        return branches.filter { $0 != currentBranch }
    }

    private var hasCleanRepository: Bool {
        model.repository?.changes.isEmpty == true
    }

    private func reconcileSelection() {
        guard selectedBranch.map(availableBranches.contains) != true else { return }
        selectedBranch = availableBranches.first
    }

    private func integrateBranch(_ action: RepositoryBranchIntegrationAction) {
        guard let selectedBranch else { return }
        Task {
            if await model.integrateBranch(
                selectedBranch,
                action: action,
                in: repositoryRootURL
            ) {
                dismiss()
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
                        .font(.title2.bold())
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
                .font(.caption)
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
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    let model: AppModel
    let repositoryRootURL: URL
    var publishAfterAdding = true
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var remoteName = "origin"
    @State private var repositoryURL = ""

    private var canSubmit: Bool {
        !remoteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Add Remote", systemImage: "network")
                    .font(.title2.bold())
                Text(publishAfterAdding
                     ? "Connect \(repositoryRootURL.lastPathComponent) to a remote, then publish the current branch."
                     : "Save a remote URL for \(repositoryRootURL.lastPathComponent). This does not fetch or push.")
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Name")
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
                        dismiss()
                        model.addRemoteAndPublish(named: name, url: url, in: repositoryRootURL)
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
                .disabled(!canSubmit || isSubmitting || model.isLoading || model.isSyncing)
                .accessibilityHint(publishAfterAdding ? "Add this remote and publish the current branch without force" : "Save this remote without fetching or pushing")
            }
        }
        .disabled(isSubmitting)
        .interactiveDismissDisabled(isSubmitting)
        .alert("Couldn’t Add Remote", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .padding(24)
        .frame(width: 520)
        .onAppear {
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
                    .font(.title2.bold())
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
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let unavailableReason {
                    Text(unavailableReason)
                        .font(.caption)
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
            case .fetch(let pruning):
                pruning ? "Choose Fetch & Prune Remote" : "Choose Fetch Remote"
            case .publish: "Choose Publish Remote"
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
            case .publish: "Publish"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    let model: AppModel
    let repositoryRootURL: URL
    let remotes: [String]
    let purpose: Purpose
    @State private var selectedRemote: String

    init(
        model: AppModel,
        repositoryRootURL: URL,
        remotes: [String],
        purpose: Purpose
    ) {
        self.model = model
        self.repositoryRootURL = repositoryRootURL
        self.remotes = remotes
        self.purpose = purpose
        _selectedRemote = State(initialValue: remotes.first ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label(purpose.title, systemImage: purpose.systemImage)
                    .font(.title2.bold())
                Text(description)
                    .foregroundStyle(.secondary)
            }

            Picker("Remote", selection: $selectedRemote) {
                ForEach(remotes, id: \.self) { remote in
                    Text(remote).tag(remote)
                }
            }
            .pickerStyle(.menu)
            .accessibilityHint(pickerAccessibilityHint)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(purpose.buttonTitle) {
                    dismiss()
                    switch purpose {
                    case .fetch(let pruning):
                        model.fetch(
                            from: selectedRemote,
                            pruning: pruning,
                            in: repositoryRootURL
                        )
                    case .publish:
                        model.publish(to: selectedRemote, in: repositoryRootURL)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedRemote.isEmpty)
                .accessibilityHint(actionAccessibilityHint)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var description: String {
        switch purpose {
        case .fetch(let pruning):
            pruning
                ? "Fetch changes and remove stale local tracking references for \(repositoryRootURL.lastPathComponent) from the selected Remote."
                : "Fetch changes for \(repositoryRootURL.lastPathComponent) from the selected Remote without changing local files."
        case .publish:
            "Publish \(repositoryRootURL.lastPathComponent)’s current branch and start tracking it on the selected Remote."
        }
    }

    private var pickerAccessibilityHint: String {
        switch purpose {
        case .fetch(let pruning):
            pruning
                ? "Choose which configured Git Remote to fetch and prune"
                : "Choose which configured Git Remote to fetch from"
        case .publish: "Choose which configured Git Remote receives the current branch"
        }
    }

    private var actionAccessibilityHint: String {
        switch purpose {
        case .fetch(let pruning):
            pruning
                ? "Fetch and prune only the selected Remote without changing local branches or working files"
                : "Fetch only the selected Remote without changing the current branch or working tree"
        case .publish: "Publish without force and start tracking the selected Remote branch"
        }
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
            Label("New Tag", systemImage: "tag").font(.title2.bold())
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
