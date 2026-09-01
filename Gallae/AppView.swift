import Observation
import SwiftUI
import UniformTypeIdentifiers

struct AppView: View {
    private enum FolderSelection {
        case openOrAdd
        case repository(replacing: URL?)
        case libraryFolder(replacing: URL?)
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()
    @State private var folderSelection: FolderSelection?
    @State private var isFolderImporterPresented = false
    @State private var expandedLibraryHierarchyFolderIDs: Set<URL> = []

    var body: some View {
        Group {
            if model.screen == .workspace, model.repository != nil {
                RepositoryWorkspaceView(model: model)
            } else {
                RepositoryLibraryView(
                    model: model,
                    chooseFolder: { chooseFolder() },
                    chooseLibraryFolder: { chooseLibraryFolder() },
                    reconnectLibraryFolder: { url in chooseLibraryFolder(replacing: url) },
                    reconnectRepository: { url in chooseRepository(replacing: url) },
                    expandedHierarchyFolderIDs: $expandedLibraryHierarchyFolderIDs
                )
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .overlay {
            if model.isLoading {
                VStack(spacing: 12) {
                    ProgressView(
                        model.remoteOperation?.progressTitle
                            ?? (model.isWritingRepository
                                ? "Updating Repository…"
                                : "Reading Repository…")
                    )
                    if let remoteOperation = model.remoteOperation {
                        Button(remoteOperation.cancelTitle) {
                            model.cancelRemoteOperation()
                        }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel(remoteOperation.cancelTitle)
                        .accessibilityHint(remoteOperation.cancelAccessibilityHint)
                    }
                }
                    .padding(20)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if model.screen == .library {
                    Button("Choose Folder…", systemImage: "folder.badge.plus") {
                        chooseFolder()
                    }
                    .accessibilityHint(
                        "Open a Git Repository, or add the selected folder to the Library"
                    )
                } else {
                    Button {
                        model.showLibrary()
                    } label: {
                        Label("Library", systemImage: "chevron.backward")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityHint("Return to the Repository Library in this window")
                    .disabled(model.isLoading)

                    Button("Remotes", systemImage: "network") {
                        model.showRemotes()
                    }
                    .disabled(model.repository == nil || model.isLoading)
                    .accessibilityHint("Show the configured Git remote names and URLs")

                    Button("Integrate", systemImage: "arrow.triangle.merge") {
                        model.showIntegrateBranch()
                    }
                    .disabled(!model.canIntegrateBranch || model.isLoading)
                    .accessibilityHint(
                        "Fast-forward, merge, or rebase with another local branch"
                    )

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
                        Label("Fetch", systemImage: "arrow.down.circle")
                    } primaryAction: {
                        model.fetchRepository()
                    }
                    .disabled(model.repository == nil || model.isLoading)
                    .accessibilityHint(
                        "Fetch Remote changes, or open the menu to also prune stale tracking references"
                    )

                    Button("Pull", systemImage: "arrow.down.to.line") {
                        model.pullRepository()
                    }
                    .disabled(model.repository == nil || model.isLoading)
                    .accessibilityHint(
                        "Fast-forward the current branch from its tracking branch without merging or rebasing"
                    )

                    Button(model.pushTitle, systemImage: "arrow.up.to.line") {
                        model.pushRepository()
                    }
                    .disabled(!model.canPushRepository || model.isLoading)
                    .accessibilityHint(
                        model.repository?.upstream == nil
                            ? "Publish the current local branch to its only remote and start tracking it without force"
                            : "Push the current branch to its configured destination without force"
                    )

                    Button("Refresh Repository", systemImage: "arrow.clockwise") {
                        Task { await model.refreshRepository() }
                    }
                    .keyboardShortcut("r")
                    .disabled(model.repository == nil || model.isLoading)
                    .accessibilityHint("Read the current Repository state again")
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
            case .remotes(let repositoryRootURL):
                RepositoryRemotesSheet(
                    model: model,
                    repositoryRootURL: repositoryRootURL
                )
            case .addRemote(let repositoryRootURL):
                AddRemoteSheet(model: model, repositoryRootURL: repositoryRootURL)
            case .createStash(let repositoryRootURL):
                CreateStashSheet(model: model, repositoryRootURL: repositoryRootURL)
            case .integrateBranch(let repositoryRootURL):
                RepositoryIntegrateBranchSheet(
                    model: model,
                    repositoryRootURL: repositoryRootURL
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
            "Couldn’t Complete the Request",
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
        .focusedSceneValue(\.openRepository) {
            chooseRepository()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, model.repository != nil else { return }
            Task { await model.refreshRepository() }
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
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    let repositoryRootURL: URL
    @State private var selectedBranch: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Integrate Local Branch", systemImage: "arrow.triangle.merge")
                    .font(.title2.bold())
                Text("Bring the selected branch into \(currentBranch), or rebase \(currentBranch) onto it.")
                    .foregroundStyle(.secondary)
            }

            branchContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rebase Current Branch") {
                    integrateBranch(.rebase)
                }
                .disabled(selectedBranch == nil || !hasCleanRepository || model.isLoading)
                .accessibilityHint(
                    "Replay the current branch commits onto the selected local branch"
                )

                Button("Create Merge Commit") {
                    integrateBranch(.mergeCommit)
                }
                .disabled(selectedBranch == nil || !hasCleanRepository || model.isLoading)
                .accessibilityHint(
                    "Create a merge commit from the selected divergent local branch"
                )

                Button("Fast-Forward") {
                    integrateBranch(.fastForward)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedBranch == nil || model.isLoading)
                .accessibilityHint("Fast-forward the current branch to the selected local branch")
            }
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 320, idealHeight: 400)
        .task(id: repositoryRootURL) {
            await model.loadLocalBranches()
        }
        .onChange(of: model.localBranchesState, initial: true) { _, _ in
            reconcileSelection()
        }
        .interactiveDismissDisabled(model.isLoading)
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
                    Spacer()
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

private struct RepositoryRemotesSheet: View {
    private enum ConnectionTestState: Equatable {
        case idle
        case testing(RepositoryRemote)
        case reachable(RepositoryRemote)
    }

    @Environment(\.dismiss) private var dismiss
    let model: AppModel
    let repositoryRootURL: URL
    @State private var editedRemote: RepositoryRemote?
    @State private var removalRemote: RepositoryRemote?
    @State private var removalErrorMessage: String?
    @State private var connectionTestState: ConnectionTestState = .idle
    @State private var connectionTestTask: Task<Void, Never>?
    @State private var connectionTestErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Remotes", systemImage: "network")
                    .font(.title2.bold())
                Text(repositoryRootURL.lastPathComponent)
                    .foregroundStyle(.secondary)
            }

            remoteContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                if isTestingConnection {
                    Button("Cancel Test") {
                        connectionTestTask?.cancel()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Stop the current Remote connection test")
                } else {
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 600, idealWidth: 640, minHeight: 320, idealHeight: 400)
        .task(id: repositoryRootURL) {
            await model.loadRemotes(in: repositoryRootURL)
        }
        .sheet(item: $editedRemote) { remote in
            EditRemoteSheet(
                model: model,
                repositoryRootURL: repositoryRootURL,
                remote: remote
            )
        }
        .confirmationDialog(
            "Remove Remote?",
            isPresented: Binding(
                get: { removalRemote != nil },
                set: { if !$0 { removalRemote = nil } }
            ),
            presenting: removalRemote
        ) { remote in
            Button("Remove “\(remote.name)”", role: .destructive) {
                Task { await remove(remote) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { remote in
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
        .interactiveDismissDisabled(model.isLoading)
        .onDisappear {
            connectionTestTask?.cancel()
        }
    }

    @ViewBuilder
    private var remoteContent: some View {
        switch model.remotesState {
        case .notLoaded, .loading:
            ProgressView("Reading Remotes…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Read Remotes", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await model.loadRemotes(in: repositoryRootURL) }
                }
            }
        case .loaded(let remotes) where remotes.isEmpty:
            ContentUnavailableView(
                "No Remotes",
                systemImage: "network.slash",
                description: Text("This Repository has no configured Git remotes.")
            )
        case .loaded(let remotes):
            List(remotes) { remote in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(remote.name)
                            .font(.headline)
                        Spacer()
                        if isTesting(remote) {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Testing \(remote.name) Fetch Connection")
                            Text("Testing…")
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                testConnection(remote)
                            } label: {
                                if isReachable(remote) {
                                    Label("Reachable", systemImage: "checkmark.circle")
                                } else {
                                    Text("Test Connection")
                                }
                            }
                            .disabled(model.isLoading || connectionTestTask != nil)
                            .accessibilityLabel("Test \(remote.name) Fetch Connection")
                            .accessibilityHint(
                                "Ask Git to read the configured Fetch URL without changing local Repository state"
                            )
                        }

                        Button("Edit…") {
                            editedRemote = remote
                        }
                        .disabled(model.isLoading)
                        .accessibilityLabel("Edit \(remote.name) Remote")
                        .accessibilityHint("Change this Remote’s Fetch and Push URLs")

                        Button("Remove…", role: .destructive) {
                            removalRemote = remote
                        }
                        .disabled(model.isLoading)
                        .accessibilityLabel("Remove \(remote.name) Remote")
                        .accessibilityHint(
                            "Remove this configured Remote after confirmation without deleting local files or the remote Repository"
                        )
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow {
                            Text("Fetch URL")
                                .foregroundStyle(.secondary)
                            Text(remote.fetchURL)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                        GridRow {
                            Text("Push URL")
                                .foregroundStyle(.secondary)
                            Text(remote.pushURL)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .listStyle(.inset)
            .accessibilityLabel("Configured Remotes, \(remotes.count)")
        }
    }

    private func remove(_ remote: RepositoryRemote) async {
        do {
            try await model.removeRemote(named: remote.name, in: repositoryRootURL)
        } catch is CancellationError {
            return
        } catch {
            removalErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private var isTestingConnection: Bool {
        if case .testing = connectionTestState {
            true
        } else {
            false
        }
    }

    private func isTesting(_ remote: RepositoryRemote) -> Bool {
        connectionTestState == .testing(remote)
    }

    private func isReachable(_ remote: RepositoryRemote) -> Bool {
        connectionTestState == .reachable(remote)
    }

    private func testConnection(_ remote: RepositoryRemote) {
        guard connectionTestTask == nil else { return }
        connectionTestState = .testing(remote)
        connectionTestErrorMessage = nil
        connectionTestTask = Task {
            defer { connectionTestTask = nil }
            do {
                try await model.testRemoteConnection(
                    named: remote.name,
                    in: repositoryRootURL
                )
                try Task.checkCancellation()
                connectionTestState = .reachable(remote)
            } catch is CancellationError {
                connectionTestState = .idle
            } catch {
                connectionTestState = .idle
                connectionTestErrorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}

private struct EditRemoteSheet: View {
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
            VStack(alignment: .leading, spacing: 6) {
                Label("Edit Remote", systemImage: "pencil")
                    .font(.title2.bold())
                Text(remote.name)
                    .foregroundStyle(.secondary)
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
                Text("Connect \(repositoryRootURL.lastPathComponent) to a remote, then publish the current branch.")
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

                Button("Add & Publish") {
                    let name = remoteName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let url = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                    model.addRemoteAndPublish(named: name, url: url, in: repositoryRootURL)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
                .accessibilityHint("Add this remote and publish the current branch without force")
            }
        }
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

enum AppScreen: Equatable, Sendable {
    case library
    case workspace
}

enum RepositoryRemoteOperation: Equatable, Sendable {
    case fetch(remote: String?, pruning: Bool)
    case automaticFetch
    case pull
    case publish
    case push
    case addRemoteAndPublish(name: String, url: String)
    case publishTo(remote: String)

    var progressTitle: String {
        switch self {
        case .fetch(let remote, let pruning):
            pruning
                ? remote.map { "Fetching & Pruning from \($0)…" } ?? "Reading Fetch & Prune Remotes…"
                : remote.map { "Fetching from \($0)…" } ?? "Reading Fetch Remotes…"
        case .automaticFetch: "Fetching Automatically…"
        case .pull: "Pulling Remote Changes…"
        case .publish: "Publishing Local Branch…"
        case .push: "Pushing Local Commits…"
        case .addRemoteAndPublish: "Adding Remote and Publishing…"
        case .publishTo(let remote): "Publishing to \(remote)…"
        }
    }

    var cancelTitle: String {
        switch self {
        case .fetch: "Cancel Fetch"
        case .automaticFetch: "Cancel Automatic Fetch"
        case .pull: "Cancel Pull"
        case .publish: "Cancel Publish"
        case .push: "Cancel Push"
        case .addRemoteAndPublish: "Cancel Publish"
        case .publishTo: "Cancel Publish"
        }
    }

    var cancelAccessibilityHint: String {
        switch self {
        case .fetch: "Stop the current Fetch and keep the Repository open"
        case .automaticFetch: "Stop this automatic Fetch and keep the Repository open"
        case .pull: "Stop the current Pull and keep the Repository open"
        case .publish: "Stop publishing the current branch and keep the Repository open"
        case .push: "Stop the current Push and keep the Repository open"
        case .addRemoteAndPublish:
            "Stop publishing the current branch and keep the Repository open"
        case .publishTo:
            "Stop publishing the current branch and keep the Repository open"
        }
    }
}

enum RepositorySheetRequest: Identifiable, Equatable, Sendable {
    case remotes(repositoryRootURL: URL)
    case addRemote(repositoryRootURL: URL)
    case createStash(repositoryRootURL: URL)
    case integrateBranch(repositoryRootURL: URL)
    case chooseFetchRemote(repositoryRootURL: URL, remotes: [String], pruning: Bool)
    case choosePublishRemote(repositoryRootURL: URL, remotes: [String])

    var id: String {
        switch self {
        case .remotes(let repositoryRootURL):
            "remotes:\(repositoryRootURL.path)"
        case .addRemote(let repositoryRootURL):
            "add:\(repositoryRootURL.path)"
        case .createStash(let repositoryRootURL):
            "create-stash:\(repositoryRootURL.path)"
        case .integrateBranch(let repositoryRootURL):
            "integrate-branch:\(repositoryRootURL.path)"
        case .chooseFetchRemote(let repositoryRootURL, _, let pruning):
            "choose-fetch:\(repositoryRootURL.path):\(pruning)"
        case .choosePublishRemote(let repositoryRootURL, _):
            "choose-publish:\(repositoryRootURL.path)"
        }
    }
}

enum RepositoryLibrarySource: Hashable, Sendable {
    case recent
    case folder(URL)
}

struct RepositoryDiffRequest: Equatable, Hashable, Sendable {
    let rootURL: URL
    let changeID: String
    let revision: Int
}

enum RepositoryDiffLoadState: Equatable, Sendable {
    case noSelection
    case loading
    case loaded(RepositoryDiff)
    case failed(String)
}

struct RepositoryHistoryRequest: Equatable, Hashable, Sendable {
    let rootURL: URL
    let revision: Int
}

struct RepositoryCommitPatchRequest: Equatable, Hashable, Sendable {
    let rootURL: URL
    let commitID: String
    let fileID: String
    let revision: Int
}

struct RepositoryCommitFilesRequest: Equatable, Hashable, Sendable {
    let rootURL: URL
    let commitID: String
    let revision: Int
}

enum RepositoryHistoryLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded(RepositoryHistory)
    case failed(String)
}

enum RepositoryStashesLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded([RepositoryStash])
    case failed(String)
}

enum RepositoryReflogLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded([RepositoryReflogEntry])
    case failed(String)
}

enum RepositoryLocalBranchesLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded([String])
    case failed(String)
}

enum RepositoryRemotesLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded([RepositoryRemote])
    case failed(String)
}

enum RepositoryCommitPatchLoadState: Equatable, Sendable {
    case noSelection
    case loading
    case loaded(RepositoryCommitPatch)
    case failed(String)
}

enum RepositoryCommitFilesLoadState: Equatable, Sendable {
    case noSelection
    case loading
    case loaded([RepositoryCommitFile])
    case failed(String)
}

@MainActor
@Observable
final class AppModel {
    var screen: AppScreen = .library
    var repository: RepositorySummary?
    var selectedChangeID: String?
    var diffState: RepositoryDiffLoadState = .noSelection
    var selectedHistoryCommitID: String?
    var historyState: RepositoryHistoryLoadState = .notLoaded
    var localBranchesState: RepositoryLocalBranchesLoadState = .notLoaded
    var remotesState: RepositoryRemotesLoadState = .notLoaded
    var selectedHistoryFileID: String?
    var commitFilesState: RepositoryCommitFilesLoadState = .noSelection
    var commitPatchState: RepositoryCommitPatchLoadState = .noSelection
    var selectedStashID: String?
    var stashesState: RepositoryStashesLoadState = .notLoaded
    var selectedReflogEntryID: String?
    var reflogState: RepositoryReflogLoadState = .notLoaded
    var selectedStashFileID: String?
    var stashFilesState: RepositoryCommitFilesLoadState = .noSelection
    var stashPatchState: RepositoryCommitPatchLoadState = .noSelection
    var isLoading = false
    var isWritingRepository = false
    var remoteOperation: RepositoryRemoteOperation?
    var automaticFetchEnabled: Bool
    var repositorySheetRequest: RepositorySheetRequest?
    var isRepositoryStale = false
    var errorMessage: String?
    var libraryFolders: [RepositoryLibraryFolder] = []
    var recentRepositories: [RepositoryLocation] = []
    var selectedLibrarySource: RepositoryLibrarySource? = .recent
    var selectedLibraryRepositoryID: URL?
    private(set) var repositoryRevision = 0
    private(set) var libraryRepositorySummaries: [URL: RepositorySummary] = [:]

    var pushTitle: String {
        repository?.upstream == nil ? "Publish" : "Push"
    }

    var canPushRepository: Bool {
        guard let repository, !repository.isUnborn else { return false }
        guard case .branch = repository.head else { return false }
        return true
    }

    var canIntegrateBranch: Bool {
        guard let repository, !repository.isUnborn else { return false }
        guard case .branch = repository.head else { return false }
        return true
    }
    private(set) var libraryRepositorySummaryErrors: [URL: String] = [:]
    private(set) var loadingLibraryRepositorySummaries: Set<URL> = []
    private(set) var libraryRepositoryActivities: [URL: RepositoryActivity] = [:]
    private(set) var libraryRepositoryActivityErrors: [URL: String] = [:]
    private(set) var loadingLibraryRepositoryActivities: Set<URL> = []

    @ObservationIgnored private let inspector = RepositoryInspector()
    @ObservationIgnored private let scanner = RepositoryScanner()
    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private var didAttemptRestore = false
    @ObservationIgnored private var inspectionGeneration = 0
    @ObservationIgnored private var diffGeneration = 0
    @ObservationIgnored private var historyGeneration = 0
    @ObservationIgnored private var commitFilesGeneration = 0
    @ObservationIgnored private var commitPatchGeneration = 0
    @ObservationIgnored private var stashesGeneration = 0
    @ObservationIgnored private var reflogGeneration = 0
    @ObservationIgnored private var stashFilesGeneration = 0
    @ObservationIgnored private var stashPatchGeneration = 0
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var remoteTask: Task<Void, Never>?
    @ObservationIgnored private var scanningFolderIDs: [URL] = []

    init(store: LibraryStore = LibraryStore()) {
        self.store = store
        automaticFetchEnabled = store.restoreAutomaticFetchEnabled()
    }

    var diffRequest: RepositoryDiffRequest? {
        guard
            let repository,
            let selectedChangeID,
            repository.changes.contains(where: { $0.id == selectedChangeID })
        else {
            return nil
        }
        return .init(
            rootURL: repository.rootURL,
            changeID: selectedChangeID,
            revision: repositoryRevision
        )
    }

    var selectedChange: RepositorySummary.Change? {
        guard let selectedChangeID else { return nil }
        return repository?.changes.first { $0.id == selectedChangeID }
    }

    var historyRequest: RepositoryHistoryRequest? {
        guard let repository else { return nil }
        return .init(rootURL: repository.rootURL, revision: repositoryRevision)
    }

    var selectedHistoryCommit: RepositoryHistory.Commit? {
        guard
            let selectedHistoryCommitID,
            case .loaded(let history) = historyState
        else {
            return nil
        }
        return history.commits.first { $0.id == selectedHistoryCommitID }
    }

    var commitFilesRequest: RepositoryCommitFilesRequest? {
        guard let repository, let selectedHistoryCommit else { return nil }
        return .init(
            rootURL: repository.rootURL,
            commitID: selectedHistoryCommit.id,
            revision: repositoryRevision
        )
    }

    var selectedHistoryFile: RepositoryCommitFile? {
        guard
            let selectedHistoryFileID,
            case .loaded(let files) = commitFilesState
        else {
            return nil
        }
        return files.first { $0.id == selectedHistoryFileID }
    }

    var commitPatchRequest: RepositoryCommitPatchRequest? {
        guard
            let repository,
            let selectedHistoryCommit,
            let selectedHistoryFile
        else {
            return nil
        }
        return .init(
            rootURL: repository.rootURL,
            commitID: selectedHistoryCommit.id,
            fileID: selectedHistoryFile.id,
            revision: repositoryRevision
        )
    }

    var stashesRequest: RepositoryHistoryRequest? {
        historyRequest
    }

    var reflogRequest: RepositoryHistoryRequest? {
        historyRequest
    }

    var selectedReflogEntry: RepositoryReflogEntry? {
        guard
            let selectedReflogEntryID,
            case .loaded(let entries) = reflogState
        else {
            return nil
        }
        return entries.first { $0.id == selectedReflogEntryID }
    }

    var selectedStash: RepositoryStash? {
        guard
            let selectedStashID,
            case .loaded(let stashes) = stashesState
        else {
            return nil
        }
        return stashes.first { $0.id == selectedStashID }
    }

    var stashFilesRequest: RepositoryCommitFilesRequest? {
        guard let repository, let selectedStash else { return nil }
        return .init(
            rootURL: repository.rootURL,
            commitID: selectedStash.id,
            revision: repositoryRevision
        )
    }

    var selectedStashFile: RepositoryCommitFile? {
        guard
            let selectedStashFileID,
            case .loaded(let files) = stashFilesState
        else {
            return nil
        }
        return files.first { $0.id == selectedStashFileID }
    }

    var stashPatchRequest: RepositoryCommitPatchRequest? {
        guard
            let repository,
            let selectedStash,
            let selectedStashFile
        else {
            return nil
        }
        return .init(
            rootURL: repository.rootURL,
            commitID: selectedStash.id,
            fileID: selectedStashFile.id,
            revision: repositoryRevision
        )
    }

    var canStageSelectedChange: Bool {
        selectedChange.map { !$0.isConflicted && $0.unstaged != nil } ?? false
    }

    var canUnstageSelectedChange: Bool {
        selectedChange.map { !$0.isConflicted && $0.staged != nil } ?? false
    }

    var canDiscardSelectedChange: Bool {
        selectedChange?.canDiscardUnstagedChanges == true
    }

    var canResolveSelectedConflict: Bool {
        selectedChange?.isConflicted == true
    }

    var canStageSelectedHunks: Bool {
        selectedChange.map { !$0.isConflicted && $0.unstaged == .modified } ?? false
    }

    var canUnstageSelectedHunks: Bool {
        selectedChange.map { !$0.isConflicted && $0.staged == .modified } ?? false
    }

    var canCommit: Bool {
        repository.map {
            $0.changes.contains(where: { $0.staged != nil })
                && !$0.changes.contains(where: \.isConflicted)
        } ?? false
    }

    var selectedLibraryFolder: RepositoryLibraryFolder? {
        guard case .folder(let id) = selectedLibrarySource else { return nil }
        return libraryFolders.first { sameFileLocation($0.id, id) }
    }

    var selectedLibraryFolderID: URL? {
        selectedLibraryFolder?.id
    }

    var displayedLibraryRepositories: [RepositoryLocation] {
        switch selectedLibrarySource {
        case .recent:
            recentRepositories
        case .folder:
            selectedLibraryFolder?.repositories ?? []
        case nil:
            []
        }
    }

    var selectedLibraryRepository: RepositoryLocation? {
        guard let selectedLibraryRepositoryID else { return nil }
        return displayedLibraryRepositories.first {
            sameFileLocation($0.id, selectedLibraryRepositoryID)
        }
    }

    var selectedRepositoryIsRecent: Bool {
        selectedLibrarySource == .recent
            && selectedLibraryRepositoryID.map { id in
                recentRepositories.contains { sameFileLocation($0.id, id) }
            } == true
    }

    func showLibrary() {
        screen = .library
    }

    func addLibraryFolder(at url: URL) {
        let folderURL = url.standardizedFileURL
        do {
            try store.addLibraryFolder(folderURL)
            if !libraryFolders.contains(where: { sameFileLocation($0.id, folderURL) }) {
                libraryFolders.append(.init(url: folderURL))
                sortLibraryFolders()
            }
            selectLibrarySource(.folder(folderURL))
            startLibraryScan(folderID: folderURL)
        } catch {
            present(error)
        }
    }

    func reconnectLibraryFolder(_ oldURL: URL, to newURL: URL) {
        let folderURL = newURL.standardizedFileURL
        do {
            try store.replaceLibraryFolder(oldURL, with: folderURL)
            if scanTask != nil {
                cancelLibraryScan()
            }
            let removedRepositories = libraryFolders
                .filter {
                    sameFileLocation($0.id, oldURL) || sameFileLocation($0.id, folderURL)
                }
                .flatMap(\.repositories)
            libraryFolders.removeAll {
                sameFileLocation($0.id, oldURL) || sameFileLocation($0.id, folderURL)
            }
            libraryFolders.append(.init(url: folderURL))
            sortLibraryFolders()
            discardUnusedCaches(for: removedRepositories)
            selectLibrarySource(.folder(folderURL))
            startLibraryScan(folderID: folderURL)
        } catch {
            present(error)
        }
    }

    func removeLibraryFolder(_ url: URL) {
        let wasSelected = selectedLibraryFolderID.map { sameFileLocation($0, url) } == true
        if scanningFolderIDs.contains(where: { sameFileLocation($0, url) }) {
            cancelLibraryScan()
        }
        let removedRepositories = libraryFolders
            .first(where: { sameFileLocation($0.id, url) })?
            .repositories ?? []
        store.removeLibraryFolder(url)
        libraryFolders.removeAll { sameFileLocation($0.id, url) }
        discardUnusedCaches(for: removedRepositories)

        if wasSelected {
            if !recentRepositories.isEmpty {
                selectLibrarySource(.recent)
            } else if let firstFolder = libraryFolders.first {
                selectLibrarySource(.folder(firstFolder.id))
            } else {
                selectLibrarySource(.recent)
            }
        }
    }

    func selectLibrarySource(_ source: RepositoryLibrarySource?) {
        selectedLibrarySource = source
        selectedLibraryRepositoryID = displayedLibraryRepositories.first?.id
    }

    func selectLibraryRepository(_ id: URL?) {
        selectedLibraryRepositoryID = id
    }

    func rescanSelectedLibraryFolder() {
        guard let selectedLibraryFolderID else { return }
        do {
            try store.addLibraryFolder(selectedLibraryFolderID)
            startLibraryScan(folderID: selectedLibraryFolderID)
        } catch {
            present(error)
        }
    }

    func cancelLibraryScan() {
        guard scanTask != nil else { return }
        scanGeneration += 1
        scanTask?.cancel()
        scanTask = nil
        for folderID in scanningFolderIDs {
            updateLibraryFolder(id: folderID) { folder in
                if case .scanning = folder.scanState {
                    folder.scanState = .cancelled
                }
            }
        }
        scanningFolderIDs = []
    }

    func loadLibraryRepositorySummary(at url: URL) async {
        guard
            libraryRepositorySummaries[url] == nil,
            libraryRepositorySummaryErrors[url] == nil,
            !loadingLibraryRepositorySummaries.contains(url)
        else {
            return
        }

        loadingLibraryRepositorySummaries.insert(url)
        defer { loadingLibraryRepositorySummaries.remove(url) }

        do {
            let summary = try await inspector.inspect(at: url)
            guard containsLibraryRepository(at: url) else { return }
            libraryRepositorySummaries[url] = summary
        } catch is CancellationError {
            return
        } catch {
            guard containsLibraryRepository(at: url) else { return }
            libraryRepositorySummaryErrors[url] = Self.message(for: error)
        }
    }

    func retryLibraryRepositorySummary(at url: URL) async {
        libraryRepositorySummaryErrors[url] = nil
        libraryRepositorySummaries[url] = nil
        libraryRepositoryActivityErrors[url] = nil
        libraryRepositoryActivities[url] = nil
        await loadLibraryRepositorySummary(at: url)
    }

    func loadLibraryRepositoryActivity(at url: URL) async {
        guard
            selectedLibraryRepositoryID.map({ sameFileLocation($0, url) }) == true,
            let summary = libraryRepositorySummaries[url],
            libraryRepositoryActivities[url] == nil,
            libraryRepositoryActivityErrors[url] == nil,
            !loadingLibraryRepositoryActivities.contains(url)
        else {
            return
        }

        loadingLibraryRepositoryActivities.insert(url)
        defer { loadingLibraryRepositoryActivities.remove(url) }

        do {
            let activity = try await inspector.activity(in: summary)
            guard selectedLibraryRepositoryID.map({ sameFileLocation($0, url) }) == true else {
                return
            }
            libraryRepositoryActivities[url] = activity
        } catch is CancellationError {
            return
        } catch {
            guard selectedLibraryRepositoryID.map({ sameFileLocation($0, url) }) == true else {
                return
            }
            libraryRepositoryActivityErrors[url] = Self.message(for: error)
        }
    }

    func retryLibraryRepositoryActivity(at url: URL) async {
        libraryRepositoryActivityErrors[url] = nil
        libraryRepositoryActivities[url] = nil
        await loadLibraryRepositoryActivity(at: url)
    }

    func openLibraryRepository(at url: URL) async {
        await openRepository(at: url)
    }

    func openSelectedLibraryRepository() async {
        guard let url = selectedLibraryRepository?.rootURL else { return }
        await openLibraryRepository(at: url)
    }

    func openRepository(at url: URL) async {
        _ = await inspect(
            url,
            rememberOnSuccess: true,
            markCurrentStaleOnFailure: false,
            showWorkspaceOnSuccess: true,
            presentFailure: true
        )
    }

    func openOrAddFolder(at url: URL) async {
        _ = await inspect(
            url,
            rememberOnSuccess: true,
            markCurrentStaleOnFailure: false,
            showWorkspaceOnSuccess: true,
            presentFailure: true,
            addLibraryFolderWhenNotWorkingTree: true
        )
    }

    func refreshRepository() async {
        guard !isLoading, let rootURL = repository?.rootURL else { return }
        _ = await inspect(
            rootURL,
            rememberOnSuccess: false,
            markCurrentStaleOnFailure: true,
            showWorkspaceOnSuccess: false,
            presentFailure: true
        )
    }

    func fetchRepository(pruning: Bool = false) {
        startRemoteOperation(.fetch(remote: nil, pruning: pruning))
    }

    func setAutomaticFetchEnabled(_ enabled: Bool) {
        automaticFetchEnabled = enabled
        store.setAutomaticFetchEnabled(enabled)
    }

    func runAutomaticFetchLoop(interval: Duration = .seconds(300)) async {
        while automaticFetchEnabled, screen == .workspace, repository != nil {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            guard automaticFetchEnabled, !Task.isCancelled else { return }
            if let task = startRemoteOperation(.automaticFetch) {
                await task.value
            }
        }
    }

    func fetch(from remote: String, pruning: Bool, in rootURL: URL) {
        guard repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true else { return }
        repositorySheetRequest = nil
        startRemoteOperation(.fetch(remote: remote, pruning: pruning))
    }

    func pullRepository() {
        startRemoteOperation(.pull)
    }

    func pushRepository() {
        startRemoteOperation(repository?.upstream == nil ? .publish : .push)
    }

    func showRemotes() {
        guard let repository else { return }
        remotesState = .notLoaded
        repositorySheetRequest = .remotes(repositoryRootURL: repository.rootURL)
    }

    func showIntegrateBranch() {
        guard canIntegrateBranch, let repository else { return }
        localBranchesState = .notLoaded
        repositorySheetRequest = .integrateBranch(repositoryRootURL: repository.rootURL)
    }

    func showCreateStash() {
        guard !isLoading, let repository else { return }
        repositorySheetRequest = .createStash(repositoryRootURL: repository.rootURL)
    }

    func loadRemotes(in rootURL: URL) async {
        guard
            let repository,
            sameFileLocation(repository.rootURL, rootURL)
        else {
            remotesState = .notLoaded
            return
        }
        let revision = repositoryRevision
        remotesState = .loading

        do {
            let remotes = try await inspector.remotes(in: repository)
            guard
                revision == repositoryRevision,
                self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true
            else {
                return
            }
            remotesState = .loaded(remotes)
        } catch is CancellationError {
            return
        } catch {
            guard
                revision == repositoryRevision,
                self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true
            else {
                return
            }
            remotesState = .failed(Self.message(for: error))
        }
    }

    func updateRemote(
        named name: String,
        renamingTo newName: String,
        fetchURL: String,
        pushURL: String,
        in rootURL: URL
    ) async throws {
        guard
            !isLoading,
            let repository,
            sameFileLocation(repository.rootURL, rootURL)
        else {
            throw RepositoryRemoteError.unavailable
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        let remotes = try await inspector.updateRemote(
            named: name,
            renamingTo: newName,
            fetchURL: fetchURL,
            pushURL: pushURL,
            in: repository
        )
        guard
            generation == inspectionGeneration,
            self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true
        else {
            throw CancellationError()
        }
        if name != newName,
           let updatedRepository = try? await inspector.inspect(at: repository.rootURL) {
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        }
        remotesState = .loaded(remotes)
    }

    func testRemoteConnection(named name: String, in rootURL: URL) async throws {
        guard
            !isLoading,
            let repository,
            sameFileLocation(repository.rootURL, rootURL)
        else {
            throw RepositoryRemoteError.unavailable
        }

        isLoading = true
        defer { isLoading = false }
        try await inspector.testRemoteConnection(named: name, in: repository)
    }

    func removeRemote(named name: String, in rootURL: URL) async throws {
        guard
            !isLoading,
            let repository,
            sameFileLocation(repository.rootURL, rootURL)
        else {
            throw RepositoryRemoteError.unavailable
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        let updatedRepository = try await inspector.removeRemote(named: name, in: repository)
        guard
            generation == inspectionGeneration,
            self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true
        else {
            throw CancellationError()
        }
        apply(updatedRepository, showWorkspaceOnSuccess: false)
        let cacheID = repositoryCacheID(for: updatedRepository.rootURL)
        libraryRepositoryActivities[cacheID] = nil
        libraryRepositoryActivityErrors[cacheID] = nil
        await loadRemotes(in: rootURL)
    }

    func addRemoteAndPublish(named name: String, url: String, in rootURL: URL) {
        guard repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true else { return }
        repositorySheetRequest = nil
        startRemoteOperation(.addRemoteAndPublish(name: name, url: url))
    }

    func publish(to remote: String, in rootURL: URL) {
        guard repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true else { return }
        repositorySheetRequest = nil
        startRemoteOperation(.publishTo(remote: remote))
    }

    func cancelRemoteOperation() {
        remoteTask?.cancel()
    }

    @discardableResult
    private func startRemoteOperation(
        _ operation: RepositoryRemoteOperation
    ) -> Task<Void, Never>? {
        guard remoteTask == nil, !isLoading, let repository else { return nil }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        remoteOperation = operation
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                remoteTask = nil
                if generation == inspectionGeneration {
                    isLoading = false
                    isWritingRepository = false
                    remoteOperation = nil
                }
            }

            do {
                let updatedRepository = switch operation {
                case .fetch(let remote, let pruning):
                    try await inspector.fetch(
                        from: remote,
                        pruning: pruning,
                        in: repository
                    )
                case .automaticFetch:
                    try await inspector.fetch(
                        usingConfiguredDefaultRemote: true,
                        in: repository
                    )
                case .pull: try await inspector.pull(in: repository)
                case .publish, .push: try await inspector.push(in: repository)
                case .addRemoteAndPublish(let name, let url):
                    try await inspector.addRemoteAndPublish(
                        named: name,
                        url: url,
                        in: repository
                    )
                case .publishTo(let remote):
                    try await inspector.publish(to: remote, in: repository)
                }
                guard generation == inspectionGeneration else { return }
                apply(updatedRepository, showWorkspaceOnSuccess: false)
                let cacheID = repositoryCacheID(for: updatedRepository.rootURL)
                libraryRepositoryActivities[cacheID] = nil
                libraryRepositoryActivityErrors[cacheID] = nil
            } catch is CancellationError {
                return
            } catch let error as RepositoryFetchError {
                guard generation == inspectionGeneration else { return }
                if operation == .automaticFetch {
                    setAutomaticFetchEnabled(false)
                    present(error)
                } else if case .fetch(remote: nil, pruning: let pruning) = operation,
                   case .remoteSelectionRequired(let remotes) = error
                {
                    repositorySheetRequest = .chooseFetchRemote(
                        repositoryRootURL: repository.rootURL,
                        remotes: remotes,
                        pruning: pruning
                    )
                } else {
                    present(error)
                }
            } catch let error as RepositoryPushError {
                guard generation == inspectionGeneration else { return }
                if operation == .publish {
                    switch error {
                    case .noRemote:
                        repositorySheetRequest = .addRemote(
                            repositoryRootURL: repository.rootURL
                        )
                    case .remoteSelectionRequired(let remotes):
                        repositorySheetRequest = .choosePublishRemote(
                            repositoryRootURL: repository.rootURL,
                            remotes: remotes
                        )
                    default:
                        present(error)
                    }
                } else {
                    present(error)
                }
            } catch {
                guard generation == inspectionGeneration else { return }
                if operation == .automaticFetch {
                    setAutomaticFetchEnabled(false)
                }
                if operation == .pull,
                   let refreshedRepository = try? await inspector.inspect(at: repository.rootURL),
                   generation == inspectionGeneration
                {
                    apply(refreshedRepository, showWorkspaceOnSuccess: false)
                }
                present(error)
            }
        }
        remoteTask = task
        return task
    }

    func loadLocalBranches() async {
        guard let repository else {
            localBranchesState = .notLoaded
            return
        }
        let rootURL = repository.rootURL
        let revision = repositoryRevision
        localBranchesState = .loading

        do {
            let branches = try await inspector.localBranches(in: repository)
            guard
                revision == repositoryRevision,
                self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true
            else {
                return
            }
            localBranchesState = .loaded(branches)
        } catch is CancellationError {
            return
        } catch {
            guard
                revision == repositoryRevision,
                self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true
            else {
                return
            }
            localBranchesState = .failed(Self.message(for: error))
        }
    }

    func switchBranch(to branch: String) async -> Bool {
        guard
            !isLoading,
            let repository,
            case .loaded(let branches) = localBranchesState,
            branches.contains(branch)
        else {
            return false
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.switchBranch(to: branch, in: repository)
            guard generation == inspectionGeneration else { return false }
            selectedHistoryCommitID = nil
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            let cacheID = repositoryCacheID(for: updatedRepository.rootURL)
            libraryRepositoryActivities[cacheID] = nil
            libraryRepositoryActivityErrors[cacheID] = nil
            return true
        } catch {
            guard generation == inspectionGeneration else { return false }
            present(error)
            return false
        }
    }

    func createBranch(named name: String, at startPoint: String? = nil) async -> Bool {
        let branch = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoading, !branch.isEmpty, let repository else {
            return false
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.createBranch(
                named: branch,
                at: startPoint,
                in: repository
            )
            guard generation == inspectionGeneration else { return false }
            selectedHistoryCommitID = nil
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            let cacheID = repositoryCacheID(for: updatedRepository.rootURL)
            libraryRepositoryActivities[cacheID] = nil
            libraryRepositoryActivityErrors[cacheID] = nil
            return true
        } catch {
            guard generation == inspectionGeneration else { return false }
            present(error)
            return false
        }
    }

    func integrateBranch(
        _ branch: String,
        action: RepositoryBranchIntegrationAction,
        in rootURL: URL
    ) async -> Bool {
        guard
            !isLoading,
            let repository,
            sameFileLocation(repository.rootURL, rootURL),
            case .loaded(let branches) = localBranchesState,
            branches.contains(branch)
        else {
            return false
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository: RepositorySummary
            switch action {
            case .fastForward:
                updatedRepository = try await inspector.mergeBranch(branch, in: repository)
            case .mergeCommit:
                updatedRepository = try await inspector.mergeBranchCreatingCommit(
                    branch,
                    in: repository
                )
            case .rebase:
                updatedRepository = try await inspector.rebaseCurrentBranch(
                    onto: branch,
                    in: repository
                )
            }
            guard generation == inspectionGeneration else { return false }
            selectedHistoryCommitID = nil
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            let cacheID = repositoryCacheID(for: updatedRepository.rootURL)
            libraryRepositoryActivities[cacheID] = nil
            libraryRepositoryActivityErrors[cacheID] = nil
            return true
        } catch {
            guard generation == inspectionGeneration else { return false }
            if let refreshedRepository = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return false }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            present(error)
            return false
        }
    }

    func createStash(
        message: String,
        includeUntracked: Bool,
        in rootURL: URL
    ) async throws {
        guard
            !isLoading,
            let repository,
            sameFileLocation(repository.rootURL, rootURL)
        else {
            throw RepositoryStashError.unavailable
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        let updatedRepository = try await inspector.createStash(
            message: message,
            includeUntracked: includeUntracked,
            in: repository
        )
        guard generation == inspectionGeneration else {
            throw CancellationError()
        }
        selectedStashID = nil
        apply(updatedRepository, showWorkspaceOnSuccess: false)
    }

    func applyStash(_ stash: RepositoryStash) async {
        guard
            !isLoading,
            let repository,
            selectedStash?.id == stash.id
        else {
            return
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.applyStash(stash, in: repository)
            guard generation == inspectionGeneration else { return }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            if let refreshedRepository = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            present(error)
        }
    }

    func dropStash(_ stash: RepositoryStash) async {
        guard
            !isLoading,
            let repository,
            selectedStash?.id == stash.id
        else {
            return
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.dropStash(stash, in: repository)
            guard generation == inspectionGeneration else { return }
            selectedStashID = nil
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            if let refreshedRepository = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            present(error)
        }
    }

    func revertCommit(
        _ commit: RepositoryHistory.Commit,
        mainlineParent: Int? = nil
    ) async {
        guard
            !isLoading,
            let repository,
            selectedHistoryCommit?.id == commit.id
        else {
            return
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.revertCommit(
                commit,
                mainlineParent: mainlineParent,
                in: repository
            )
            guard generation == inspectionGeneration else { return }
            selectedHistoryCommitID = nil
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            let cacheID = repositoryCacheID(for: updatedRepository.rootURL)
            libraryRepositoryActivities[cacheID] = nil
            libraryRepositoryActivityErrors[cacheID] = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            if let refreshedRepository = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            present(error)
        }
    }

    func resetCurrentBranch(
        to commit: RepositoryHistory.Commit,
        mode: RepositoryResetMode
    ) async {
        guard
            !isLoading,
            let repository,
            selectedHistoryCommit?.id == commit.id
        else {
            return
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.resetCurrentBranch(
                to: commit,
                mode: mode,
                in: repository
            )
            guard generation == inspectionGeneration else { return }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            let cacheID = repositoryCacheID(for: updatedRepository.rootURL)
            libraryRepositoryActivities[cacheID] = nil
            libraryRepositoryActivityErrors[cacheID] = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            if let refreshedRepository = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            present(error)
        }
    }

    func stageSelectedChange() async {
        guard
            !isLoading,
            let repository,
            let change = selectedChange,
            canStageSelectedChange
        else {
            return
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.stage(change, in: repository)
            guard generation == inspectionGeneration else { return }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch {
            guard generation == inspectionGeneration else { return }
            present(error)
        }
    }

    func unstageSelectedChange() async {
        guard
            !isLoading,
            let repository,
            let change = selectedChange,
            canUnstageSelectedChange
        else {
            return
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.unstage(change, in: repository)
            guard generation == inspectionGeneration else { return }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch {
            guard generation == inspectionGeneration else { return }
            present(error)
        }
    }

    func discardChange(id: RepositorySummary.Change.ID) async {
        guard
            !isLoading,
            let repository,
            let change = repository.changes.first(where: { $0.id == id }),
            change.canDiscardUnstagedChanges
        else {
            return
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.discard(change, in: repository)
            guard generation == inspectionGeneration else { return }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch {
            guard generation == inspectionGeneration else { return }
            present(error)
        }
    }

    func resolveSelectedConflict(using side: RepositoryConflictSide) async {
        guard
            !isLoading,
            let repository,
            let change = selectedChange,
            change.isConflicted
        else {
            return
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.resolveConflict(
                change,
                using: side,
                in: repository
            )
            guard generation == inspectionGeneration else { return }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            if let refreshedRepository = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            present(error)
        }
    }

    func markSelectedConflictResolved() async {
        guard
            !isLoading,
            let repository,
            let change = selectedChange,
            change.isConflicted
        else {
            return
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.markConflictResolved(
                change,
                in: repository
            )
            guard generation == inspectionGeneration else { return }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            if let refreshedRepository = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            present(error)
        }
    }

    func continueRepositoryOperation() async {
        await updateRepositoryOperation(aborting: false)
    }

    func abortRepositoryOperation() async {
        await updateRepositoryOperation(aborting: true)
    }

    private func updateRepositoryOperation(aborting: Bool) async {
        guard
            !isLoading,
            let repository,
            let operation = repository.operation,
            aborting || operation.canContinue
        else {
            return
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        let cacheID = repositoryCacheID(for: repository.rootURL)
        isLoading = true
        isWritingRepository = true
        libraryRepositoryActivities[cacheID] = nil
        libraryRepositoryActivityErrors[cacheID] = nil
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository: RepositorySummary
            if aborting {
                updatedRepository = try await inspector.abortOperation(in: repository)
            } else {
                updatedRepository = try await inspector.continueOperation(in: repository)
            }
            guard generation == inspectionGeneration else { return }
            selectedHistoryCommitID = nil
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            if let refreshedRepository = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            present(error)
        }
    }

    func updateSelectedHunk(_ hunk: RepositoryDiff.Hunk) async {
        guard !isLoading, let repository, let change = selectedChange else { return }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository: RepositorySummary
            switch hunk.scope {
            case .unstaged where canStageSelectedHunks:
                updatedRepository = try await inspector.stage(hunk, for: change, in: repository)
            case .staged where canUnstageSelectedHunks:
                updatedRepository = try await inspector.unstage(hunk, for: change, in: repository)
            default:
                return
            }
            guard generation == inspectionGeneration else { return }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch {
            guard generation == inspectionGeneration else { return }
            present(error)
        }
    }

    func commit(subject: String, body: String, amend: Bool) async -> Bool {
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !isLoading,
            let repository,
            canCommit,
            !subject.isEmpty,
            !amend || !repository.isUnborn
        else {
            return false
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.commit(
                subject: subject,
                body: body,
                amend: amend,
                in: repository
            )
            guard generation == inspectionGeneration else { return false }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            let cacheID = repositoryCacheID(for: updatedRepository.rootURL)
            libraryRepositoryActivities[cacheID] = nil
            libraryRepositoryActivityErrors[cacheID] = nil
            return true
        } catch {
            guard generation == inspectionGeneration else { return false }
            present(error)
            return false
        }
    }

    func reconnectRecentRepository(_ oldURL: URL, to newURL: URL) async {
        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = false
        defer {
            if generation == inspectionGeneration {
                isLoading = false
            }
        }

        do {
            let inspectedRepository = try await inspector.inspect(at: newURL)
            guard generation == inspectionGeneration else { return }
            try store.replaceRecentRepository(oldURL, with: inspectedRepository.rootURL)
            recentRepositories.removeAll {
                sameFileLocation($0.id, oldURL)
                    || sameFileLocation($0.id, inspectedRepository.rootURL)
            }
            recentRepositories.insert(.init(rootURL: inspectedRepository.rootURL), at: 0)
            discardUnusedCaches(for: [.init(rootURL: oldURL)])
            selectedLibrarySource = .recent
            selectedLibraryRepositoryID = inspectedRepository.rootURL
            apply(inspectedRepository, showWorkspaceOnSuccess: true)
        } catch {
            guard generation == inspectionGeneration else { return }
            present(error)
        }
    }

    func removeRecentRepository(_ url: URL) {
        store.removeRecentRepository(url)
        recentRepositories.removeAll { sameFileLocation($0.id, url) }
        discardUnusedCaches(for: [.init(rootURL: url)])
        if selectedLibrarySource == .recent,
           selectedLibraryRepositoryID.map({ sameFileLocation($0, url) }) == true {
            selectedLibraryRepositoryID = recentRepositories.first?.id
        }
        if recentRepositories.isEmpty, selectedLibrarySource == .recent {
            if let firstFolder = libraryFolders.first {
                selectLibrarySource(.folder(firstFolder.id))
            } else {
                selectLibrarySource(.recent)
            }
        }
    }

    func restoreState() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true

        let restoredFolders = store.restoreLibraryFolders()
        libraryFolders = restoredFolders.map { location in
            var folder = RepositoryLibraryFolder(url: location.url)
            if let message = location.errorMessage {
                folder.scanState = .failed(message)
            }
            return folder
        }
        sortLibraryFolders()

        let restoredRecent = store.restoreRecentRepositories()
        recentRepositories = restoredRecent.map { .init(rootURL: $0.url) }
        for location in restoredRecent where location.errorMessage != nil {
            libraryRepositorySummaryErrors[location.url] = location.errorMessage
        }

        if !recentRepositories.isEmpty {
            selectLibrarySource(.recent)
        } else if let firstFolder = libraryFolders.first {
            selectLibrarySource(.folder(firstFolder.id))
        } else {
            selectLibrarySource(.recent)
        }

        let foldersToScan = restoredFolders.compactMap { location in
            location.errorMessage == nil ? location.url : nil
        }
        if !foldersToScan.isEmpty {
            startLibraryScans(folderIDs: foldersToScan)
        }

        guard let workspace = store.restoreLastWorkspace() else { return }
        if !recentRepositories.contains(where: { sameFileLocation($0.id, workspace.url) }) {
            recentRepositories.insert(.init(rootURL: workspace.url), at: 0)
        }
        selectedLibrarySource = .recent
        selectedLibraryRepositoryID = workspace.url

        if let message = workspace.errorMessage {
            libraryRepositorySummaryErrors[workspace.url] = message
            store.clearLastWorkspace()
            screen = .library
            return
        }

        let restored = await inspect(
            workspace.url,
            rememberOnSuccess: false,
            markCurrentStaleOnFailure: false,
            showWorkspaceOnSuccess: true,
            presentFailure: false
        )
        if !restored {
            store.clearLastWorkspace()
            screen = .library
        }
    }

    func present(_ error: Error) {
        guard !(error is CancellationError) else { return }
        if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
            return
        }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func loadSelectedDiff(
        maximumOutputBytes: Int? = RepositoryInspector.maximumDisplayedDiffBytes
    ) async {
        guard
            let request = diffRequest,
            let repository,
            let change = repository.changes.first(where: { $0.id == request.changeID })
        else {
            diffState = .noSelection
            return
        }

        diffGeneration += 1
        let generation = diffGeneration
        diffState = .loading

        do {
            let diff = try await inspector.diff(
                for: change,
                in: repository,
                maximumOutputBytes: maximumOutputBytes
            )
            guard generation == diffGeneration, request == diffRequest else { return }
            diffState = .loaded(diff)
        } catch is CancellationError {
            return
        } catch {
            guard generation == diffGeneration, request == diffRequest else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            diffState = .failed(message)
        }
    }

    func loadHistory() async {
        guard let request = historyRequest, let repository else {
            historyState = .notLoaded
            selectedHistoryCommitID = nil
            selectedHistoryFileID = nil
            commitFilesState = .noSelection
            commitPatchState = .noSelection
            return
        }

        historyGeneration += 1
        let generation = historyGeneration
        historyState = .loading

        do {
            let history = try await inspector.history(in: repository)
            guard generation == historyGeneration, request == historyRequest else { return }
            historyState = .loaded(history)
            selectedHistoryCommitID = selectedHistoryCommitID.flatMap { selectedID in
                history.commits.contains(where: { $0.id == selectedID }) ? selectedID : nil
            } ?? history.headCommitID ?? history.commits.first?.id
            selectedHistoryFileID = nil
            commitFilesState = selectedHistoryCommitID == nil ? .noSelection : .loading
            commitPatchState = .noSelection
        } catch is CancellationError {
            return
        } catch {
            guard generation == historyGeneration, request == historyRequest else { return }
            historyState = .failed(Self.message(for: error))
            selectedHistoryCommitID = nil
            selectedHistoryFileID = nil
            commitFilesState = .noSelection
            commitPatchState = .noSelection
        }
    }

    func interactiveRebasePlan(
        startingAt commit: RepositoryHistory.Commit
    ) async throws -> RepositoryInteractiveRebasePlan {
        guard let repository else {
            throw RepositoryInteractiveRebasePlanError.unavailable
        }
        return try await inspector.interactiveRebasePlan(startingAt: commit, in: repository)
    }

    func executeInteractiveRebase(
        _ plan: RepositoryInteractiveRebasePlan,
        rewordMessages: [String: String],
        startingAt commit: RepositoryHistory.Commit
    ) async throws {
        guard !isLoading, let repository else {
            throw RepositoryInteractiveRebasePlanError.unavailable
        }

        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        defer {
            if generation == inspectionGeneration {
                isLoading = false
                isWritingRepository = false
            }
        }

        do {
            let updatedRepository = try await inspector.executeInteractiveRebase(
                plan,
                rewordMessages: rewordMessages,
                startingAt: commit,
                in: repository
            )
            guard generation == inspectionGeneration else { throw CancellationError() }
            selectedHistoryCommitID = nil
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            let cacheID = repositoryCacheID(for: updatedRepository.rootURL)
            libraryRepositoryActivities[cacheID] = nil
            libraryRepositoryActivityErrors[cacheID] = nil
        } catch {
            guard generation == inspectionGeneration else { throw error }
            let rootURL = repository.rootURL
            let inspector = inspector
            let refreshedRepository = try? await Task.detached {
                try await inspector.inspect(at: rootURL)
            }.value
            if let refreshedRepository {
                guard generation == inspectionGeneration else { throw error }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            throw error
        }
    }

    func loadSelectedCommitFiles() async {
        guard
            let request = commitFilesRequest,
            let repository,
            let commit = selectedHistoryCommit
        else {
            selectedHistoryFileID = nil
            commitFilesState = .noSelection
            commitPatchState = .noSelection
            return
        }

        commitFilesGeneration += 1
        let generation = commitFilesGeneration
        selectedHistoryFileID = nil
        commitFilesState = .loading
        commitPatchState = .noSelection

        do {
            let files = try await inspector.files(for: commit, in: repository)
            guard
                generation == commitFilesGeneration,
                request == commitFilesRequest
            else {
                return
            }
            commitFilesState = .loaded(files)
            selectedHistoryFileID = files.first?.id
            commitPatchState = selectedHistoryFileID == nil ? .noSelection : .loading
        } catch is CancellationError {
            return
        } catch {
            guard
                generation == commitFilesGeneration,
                request == commitFilesRequest
            else {
                return
            }
            selectedHistoryFileID = nil
            commitFilesState = .failed(Self.message(for: error))
            commitPatchState = .noSelection
        }
    }

    func loadSelectedCommitPatch(
        maximumOutputBytes: Int? = RepositoryInspector.maximumDisplayedDiffBytes
    ) async {
        guard
            let request = commitPatchRequest,
            let repository,
            let commit = selectedHistoryCommit,
            let file = selectedHistoryFile
        else {
            commitPatchState = .noSelection
            return
        }

        commitPatchGeneration += 1
        let generation = commitPatchGeneration
        commitPatchState = .loading

        do {
            let patch = try await inspector.patch(
                for: file,
                in: commit,
                repository: repository,
                maximumOutputBytes: maximumOutputBytes
            )
            guard
                generation == commitPatchGeneration,
                request == commitPatchRequest
            else {
                return
            }
            commitPatchState = .loaded(patch)
        } catch is CancellationError {
            return
        } catch {
            guard
                generation == commitPatchGeneration,
                request == commitPatchRequest
            else {
                return
            }
            commitPatchState = .failed(Self.message(for: error))
        }
    }

    func loadStashes() async {
        guard let request = stashesRequest, let repository else {
            stashesState = .notLoaded
            selectedStashID = nil
            selectedStashFileID = nil
            stashFilesState = .noSelection
            stashPatchState = .noSelection
            return
        }

        stashesGeneration += 1
        let generation = stashesGeneration
        stashesState = .loading

        do {
            let stashes = try await inspector.stashes(in: repository)
            guard generation == stashesGeneration, request == stashesRequest else { return }
            stashesState = .loaded(stashes)
            selectedStashID = selectedStashID.flatMap { selectedID in
                stashes.contains(where: { $0.id == selectedID }) ? selectedID : nil
            } ?? stashes.first?.id
            selectedStashFileID = nil
            stashFilesState = selectedStashID == nil ? .noSelection : .loading
            stashPatchState = .noSelection
        } catch is CancellationError {
            return
        } catch {
            guard generation == stashesGeneration, request == stashesRequest else { return }
            stashesState = .failed(Self.message(for: error))
            selectedStashID = nil
            selectedStashFileID = nil
            stashFilesState = .noSelection
            stashPatchState = .noSelection
        }
    }

    func loadReflog() async {
        guard let request = reflogRequest, let repository else {
            reflogState = .notLoaded
            selectedReflogEntryID = nil
            return
        }

        reflogGeneration += 1
        let generation = reflogGeneration
        reflogState = .loading

        do {
            let entries = try await inspector.reflog(in: repository)
            guard generation == reflogGeneration, request == reflogRequest else { return }
            reflogState = .loaded(entries)
            selectedReflogEntryID = entries.first?.id
        } catch is CancellationError {
            return
        } catch {
            guard generation == reflogGeneration, request == reflogRequest else { return }
            reflogState = .failed(Self.message(for: error))
            selectedReflogEntryID = nil
        }
    }

    func loadSelectedStashFiles() async {
        guard
            let request = stashFilesRequest,
            let repository,
            let stash = selectedStash
        else {
            selectedStashFileID = nil
            stashFilesState = .noSelection
            stashPatchState = .noSelection
            return
        }

        stashFilesGeneration += 1
        let generation = stashFilesGeneration
        selectedStashFileID = nil
        stashFilesState = .loading
        stashPatchState = .noSelection

        do {
            let files = try await inspector.files(for: stash, in: repository)
            guard generation == stashFilesGeneration, request == stashFilesRequest else { return }
            stashFilesState = .loaded(files)
            selectedStashFileID = files.first?.id
            stashPatchState = selectedStashFileID == nil ? .noSelection : .loading
        } catch is CancellationError {
            return
        } catch {
            guard generation == stashFilesGeneration, request == stashFilesRequest else { return }
            selectedStashFileID = nil
            stashFilesState = .failed(Self.message(for: error))
            stashPatchState = .noSelection
        }
    }

    func loadSelectedStashPatch(
        maximumOutputBytes: Int? = RepositoryInspector.maximumDisplayedDiffBytes
    ) async {
        guard
            let request = stashPatchRequest,
            let repository,
            let stash = selectedStash,
            let file = selectedStashFile
        else {
            stashPatchState = .noSelection
            return
        }

        stashPatchGeneration += 1
        let generation = stashPatchGeneration
        stashPatchState = .loading

        do {
            let patch = try await inspector.patch(
                for: file,
                in: stash,
                repository: repository,
                maximumOutputBytes: maximumOutputBytes
            )
            guard generation == stashPatchGeneration, request == stashPatchRequest else { return }
            stashPatchState = .loaded(patch)
        } catch is CancellationError {
            return
        } catch {
            guard generation == stashPatchGeneration, request == stashPatchRequest else { return }
            stashPatchState = .failed(Self.message(for: error))
        }
    }

    private func inspect(
        _ url: URL,
        rememberOnSuccess: Bool,
        markCurrentStaleOnFailure: Bool,
        showWorkspaceOnSuccess: Bool,
        presentFailure: Bool,
        addLibraryFolderWhenNotWorkingTree: Bool = false
    ) async -> Bool {
        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = false
        defer {
            if generation == inspectionGeneration {
                isLoading = false
            }
        }

        do {
            let inspectedRepository = try await inspector.inspect(at: url)
            guard generation == inspectionGeneration else { return false }
            if rememberOnSuccess {
                try store.rememberOpenedRepository(inspectedRepository.rootURL)
                recentRepositories.removeAll {
                    sameFileLocation($0.id, inspectedRepository.rootURL)
                }
                recentRepositories.insert(.init(rootURL: inspectedRepository.rootURL), at: 0)
                if selectedLibrarySource == .recent {
                    selectedLibraryRepositoryID = inspectedRepository.rootURL
                }
            }
            apply(inspectedRepository, showWorkspaceOnSuccess: showWorkspaceOnSuccess)
            return true
        } catch {
            guard generation == inspectionGeneration else { return false }
            if
                addLibraryFolderWhenNotWorkingTree,
                let inspectionError = error as? RepositoryInspectionError,
                case .notWorkingTree = inspectionError,
                !RepositoryScanner.hasRepositoryMarker(at: url)
            {
                addLibraryFolder(at: url)
                return false
            }
            if markCurrentStaleOnFailure, repository != nil {
                isRepositoryStale = true
            }
            if presentFailure {
                present(error)
            } else if !(error is CancellationError) {
                libraryRepositorySummaries[url] = nil
                libraryRepositorySummaryErrors[url] = Self.message(for: error)
            }
            return false
        }
    }

    private func apply(
        _ inspectedRepository: RepositorySummary,
        showWorkspaceOnSuccess: Bool
    ) {
        let isSameRepository = repository.map {
            sameFileLocation($0.rootURL, inspectedRepository.rootURL)
        } == true
        let previousSelection = isSameRepository
            ? selectedChangeID
            : nil
        if !isSameRepository {
            selectedHistoryCommitID = nil
            selectedStashID = nil
            selectedReflogEntryID = nil
        }
        repository = inspectedRepository
        repositoryRevision += 1
        selectedChangeID = previousSelection.flatMap { selectedID in
            inspectedRepository.changes.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? inspectedRepository.changes.first?.id
        diffState = selectedChangeID == nil ? .noSelection : .loading
        historyState = .notLoaded
        localBranchesState = .notLoaded
        remotesState = .notLoaded
        selectedHistoryFileID = nil
        commitFilesState = .noSelection
        commitPatchState = .noSelection
        stashesState = .notLoaded
        reflogState = .notLoaded
        selectedStashFileID = nil
        stashFilesState = .noSelection
        stashPatchState = .noSelection
        let cacheID = repositoryCacheID(for: inspectedRepository.rootURL)
        libraryRepositorySummaries[cacheID] = inspectedRepository
        libraryRepositorySummaryErrors[cacheID] = nil
        isRepositoryStale = false
        errorMessage = nil
        if showWorkspaceOnSuccess {
            screen = .workspace
        }
    }

    private func startLibraryScan(folderID: URL) {
        startLibraryScans(folderIDs: [folderID])
    }

    private func startLibraryScans(folderIDs: [URL]) {
        if scanTask != nil {
            cancelLibraryScan()
        }
        let folderIDs = folderIDs.compactMap { requestedID in
            libraryFolders.first { sameFileLocation($0.id, requestedID) }?.id
        }
        guard !folderIDs.isEmpty else { return }

        for folderID in folderIDs {
            updateLibraryFolder(id: folderID) { folder in
                folder.scanState = .scanning
                folder.firstFailure = nil
            }
        }

        scanGeneration += 1
        let generation = scanGeneration
        scanningFolderIDs = folderIDs
        scanTask = Task { [weak self] in
            await self?.consumeScans(folderIDs: folderIDs, generation: generation)
        }
    }

    private func consumeScans(folderIDs: [URL], generation: Int) async {
        for folderID in folderIDs {
            guard !Task.isCancelled, generation == scanGeneration else { return }
            await consumeScan(folderID: folderID, generation: generation)
        }
        guard !Task.isCancelled, generation == scanGeneration else { return }
        scanningFolderIDs = []
        scanTask = nil
    }

    private func consumeScan(folderID: URL, generation: Int) async {
        var partialFailureCount = 0
        var rootFailureMessage: String?
        var foundRepositories: [RepositoryLocation] = []

        for await event in scanner.scan(in: folderID) {
            guard !Task.isCancelled, generation == scanGeneration else { return }

            switch event {
            case .found(let repository):
                if !foundRepositories.contains(where: {
                    sameFileLocation($0.id, repository.id)
                }) {
                    foundRepositories.append(repository)
                }
                updateLibraryFolder(id: folderID) { folder in
                    guard !folder.repositories.contains(where: {
                        sameFileLocation($0.id, repository.id)
                    }) else { return }
                    folder.repositories.append(repository)
                    folder.repositories.sort {
                        $0.rootURL.path.localizedStandardCompare($1.rootURL.path) == .orderedAscending
                    }
                }
                if selectedLibraryFolderID == folderID, selectedLibraryRepositoryID == nil {
                    selectedLibraryRepositoryID = repository.id
                }
            case .failed(let failure):
                partialFailureCount += 1
                if sameFileLocation(failure.url, folderID) {
                    rootFailureMessage = failure.message
                }
                updateLibraryFolder(id: folderID) { folder in
                    folder.firstFailure = folder.firstFailure ?? failure
                }
            }
        }

        guard !Task.isCancelled, generation == scanGeneration else { return }
        let repositoriesBeforeReconciliation = libraryFolders
            .first(where: { sameFileLocation($0.id, folderID) })?
            .repositories ?? []
        let shouldReconcile = rootFailureMessage == nil || !foundRepositories.isEmpty
        if shouldReconcile {
            foundRepositories.sort {
                $0.rootURL.path.localizedStandardCompare($1.rootURL.path) == .orderedAscending
            }
        }
        updateLibraryFolder(id: folderID) { folder in
            if shouldReconcile {
                folder.repositories = foundRepositories
            }
            if let rootFailureMessage, foundRepositories.isEmpty {
                folder.scanState = .failed(rootFailureMessage)
            } else {
                folder.scanState = .completed(partialFailureCount: partialFailureCount)
            }
        }
        if shouldReconcile {
            let removedRepositories = repositoriesBeforeReconciliation.filter { repository in
                !foundRepositories.contains {
                    sameFileLocation($0.id, repository.id)
                }
            }
            discardUnusedCaches(for: removedRepositories)
            if selectedLibraryFolderID.map({ sameFileLocation($0, folderID) }) == true,
               selectedLibraryRepositoryID.map({ selectedID in
                   !foundRepositories.contains {
                       sameFileLocation($0.id, selectedID)
                   }
               }) != false {
                selectedLibraryRepositoryID = foundRepositories.first?.id
            }
        }
    }

    private func updateLibraryFolder(
        id: URL,
        _ update: (inout RepositoryLibraryFolder) -> Void
    ) {
        guard let index = libraryFolders.firstIndex(where: { $0.id == id }) else { return }
        update(&libraryFolders[index])
    }

    private func containsLibraryRepository(at url: URL) -> Bool {
        recentRepositories.contains { sameFileLocation($0.id, url) } || libraryFolders.contains { folder in
            folder.repositories.contains { sameFileLocation($0.id, url) }
        }
    }

    private func repositoryCacheID(for url: URL) -> URL {
        recentRepositories.first(where: { sameFileLocation($0.id, url) })?.id
            ?? libraryFolders.lazy
                .flatMap(\.repositories)
                .first(where: { sameFileLocation($0.id, url) })?.id
            ?? url
    }

    private func discardUnusedCaches(for repositories: [RepositoryLocation]) {
        for repository in repositories where !containsLibraryRepository(at: repository.id) {
            libraryRepositorySummaries[repository.id] = nil
            libraryRepositorySummaryErrors[repository.id] = nil
            loadingLibraryRepositorySummaries.remove(repository.id)
            libraryRepositoryActivities[repository.id] = nil
            libraryRepositoryActivityErrors[repository.id] = nil
            loadingLibraryRepositoryActivities.remove(repository.id)
        }
    }

    private func sortLibraryFolders() {
        libraryFolders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
