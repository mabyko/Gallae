import AppKit
import SwiftUI

struct RepositoryNavigatorView: View {
    @Bindable var model: AppModel
    /// The screen axis: which of Changes, History, Stashes, Reflog fills the body. Always set.
    @Binding var screen: RepositoryWorkspaceSection
    /// The selected reference is revealed in History without changing its filter.
    @Binding var scope: RepositoryHistoryScope?
    /// Inside the floating panel the panel paints the background, so the list stays transparent.
    var isFloating = false
    @Environment(\.gallaeTheme) private var theme
    @Environment(\.controlActiveState) private var controlActiveState
    @FocusState private var isScreenListFocused: Bool
    @FocusState private var isReferenceListFocused: Bool
    @State private var filterText = ""
    @State private var collapsedRemotes: Set<String> = []
    @State private var pendingWorktreeRemoval: WorktreeRemovalRequest?
    @State private var pendingBranchDeletion: String?
    @State private var pendingRemoteBranchDeletion: String?
    @State private var pendingTrackingReferenceRemoval: String?
    @State private var pendingRemoteRemoval: String?
    @State private var removalErrorMessage: String?
    @State private var editedRemote: RepositoryRemote?
    @State private var isCreatingBranch = false
    @State private var worktreeCreation: WorktreeCreationRequest?

    var body: some View {
        VStack(spacing: 0) {
            // Two lists, two selections: the screen list keeps its selection while a scope is chosen, and macOS
            // draws the list without keyboard focus in gray. The screen list is four rows, so it is a plain stack
            // that takes focus itself rather than a List sized by guesswork.
            screenList

            Divider()
                .padding(.horizontal, 10)

            List(selection: navigatorSelection) {
                RepositoryWorktreesSection(model: model, filter: filterText,
                                           isFocused: isReferenceListFocused,
                                           select: selectWorktree, create: { worktreeCreation = .init() })
                Section {
                    branchRows
                } header: {
                    RepositoryNavigatorSectionHeader(title: "Branches", actionsLabel: "Branch Actions",
                                                     actionsDisabled: model.isLoading || model.isSyncing || model.repository == nil) {
                        Button("New Branch…", systemImage: "plus") { isCreatingBranch = true }
                        Button("New Worktree…", systemImage: "folder.badge.plus") { worktreeCreation = .init() }
                    }
                }

                Section {
                    remoteRows
                } header: {
                    RepositoryNavigatorSectionHeader(title: "Remotes", actionsLabel: "Remote Actions",
                                                     actionsDisabled: model.isLoading || model.isSyncing || model.repository == nil) {
                        Button("Add Remote…", systemImage: "plus") {
                            guard let rootURL = model.repository?.rootURL else { return }
                            model.repositorySheetRequest = .addRemote(repositoryRootURL: rootURL, publishAfterAdding: false)
                        }
                    }
                }

                Section {
                    tagRows
                } header: {
                    RepositoryNavigatorSectionHeader(title: "Tags", actionsLabel: "Tag Actions",
                                                     actionsDisabled: model.isLoading || model.isSyncing || model.repository == nil) {
                        Button("New Tag…", systemImage: "plus") {
                            guard let rootURL = model.repository?.rootURL else { return }
                            model.repositorySheetRequest = .createTag(repositoryRootURL: rootURL)
                        }
                        .disabled(model.repository?.isUnborn != false)
                    }
                }
            }
            // Inserting Worktrees above existing rows makes macOS preserve a stale scroll offset.
            // Rebuild only when that section appears or disappears; ordinary refreshes keep their position.
            .id(model.worktrees.contains { !$0.isPrimary && !$0.isBare })
            .listStyle(.sidebar)
            .focused($isReferenceListFocused)
            .scrollContentBackground(theme.materials.translucentChrome && !isFloating ? .automatic : .hidden)
            .accessibilityLabel("Navigator")
            .onKeyPress(.return) {
                guard let url = model.selectedWorktreeURL,
                      let worktree = model.worktrees.first(where: { $0.url == url }),
                      worktree.isAvailable, !model.isLoading, !model.isSyncing else { return .ignored }
                if url.resolvingSymlinksInPath().path != model.repository?.rootURL.resolvingSymlinksInPath().path {
                    Task { _ = await model.openWorktree(at: url) }
                }
                return .handled
            }

            Divider()

            TextField("Filter", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(8)
                .accessibilityLabel("Filter Worktrees, Branches, Remotes, and Tags")
        }
        // Reduced Transparency and Increased Contrast paint the sidebar opaque instead of the system material.
        .background(theme.materials.translucentChrome || isFloating ? Color.clear : theme.colors.opaqueChrome)
        .onChange(of: model.remotesState) { _, state in
            guard case .loaded(let remotes) = state else { return }
            collapsedRemotes.formIntersection(remotes.map(\.name))
        }
        .onChange(of: model.repository?.rootURL) { _, _ in
            collapsedRemotes = []
            filterText = ""
        }
        .sheet(isPresented: $isCreatingBranch) {
            CreateBranchSheet(model: model)
        }
        .sheet(item: $worktreeCreation) { request in
            CreateWorktreeSheet(model: model, existingBranch: request.branch)
        }
        .sheet(item: $editedRemote) { remote in
            if let rootURL = model.repository?.rootURL {
                EditRemoteSheet(model: model, repositoryRootURL: rootURL, remote: remote)
            }
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
        .confirmationDialog(
            "Remove Remote?",
            isPresented: Binding(
                get: { pendingRemoteRemoval != nil },
                set: { if !$0 { pendingRemoteRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoteRemoval
        ) { name in
            Button("Remove “\(name)”", role: .destructive) {
                Task { await removeRemote(named: name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { name in
            Text(
                "This removes “\(name)” and its local remote-tracking branches from this Repository. It doesn’t delete the remote Repository, local branches, commits, or working files."
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
        .remoteBranchDialogs(
            model: model,
            deletion: $pendingRemoteBranchDeletion,
            trackingRemoval: $pendingTrackingReferenceRemoval
        )
    }

    // MARK: - Screen list

    private var screenList: some View {
        VStack(alignment: .leading, spacing: 2) {
            screenSectionLabel("Workspace")
            screenRow(.changes, badge: model.repository?.changes.count ?? 0)
            screenRow(.history, badge: 0)
            screenSectionLabel("Recovery")
                .padding(.top, 10)
            screenRow(.stashes, badge: stashCount)
            screenRow(.reflog, badge: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .focusable()
        .focused($isScreenListFocused)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            let sections = RepositoryWorkspaceSection.allCases
            guard let index = sections.firstIndex(of: screen) else { return }
            switch direction {
            case .up where index > 0: show(sections[index - 1])
            case .down where index + 1 < sections.count: show(sections[index + 1])
            default: break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screens")
    }

    private func screenSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func screenRow(_ section: RepositoryWorkspaceSection, badge: Int) -> some View {
        let isSelected = screen == section
        let isActive = isSelected && isScreenListFocused && controlActiveState == .key
        return Button {
            show(section)
            isScreenListFocused = true
        } label: {
            HStack(spacing: 8) {
                Label(section.title, systemImage: section.systemImage)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if badge > 0 {
                    Text(badge, format: .number)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isActive ? .white.opacity(0.85) : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? theme.colors.accent : isSelected ? Color.secondary.opacity(0.25) : .clear)
            )
            .foregroundStyle(isActive ? .white : .primary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("\(section.title) (⌘\(section.rawValue + 1))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(badge > 0 ? "\(section.title), \(badge)" : section.title)
    }

    /// Switching screens clears the Navigator selection, not the History filter.
    private func show(_ section: RepositoryWorkspaceSection) {
        screen = section
        scope = nil
    }

    // MARK: - Scope list

    /// Selecting a reference reveals it in History without changing the filter.
    private func selectWorktree(_ worktree: RepositoryWorktree) {
        model.selectWorktree(worktree)
        screen = .history
        isScreenListFocused = false
    }

    private var navigatorSelection: Binding<RepositoryNavigatorSelection?> {
        Binding(get: {
            if let url = model.selectedWorktreeURL { return .worktree(url) }
            return scope.map { .reference($0) }
        }, set: { selection in
            switch selection {
            case .reference(let reference): scopeSelection.wrappedValue = reference
            case .worktree(let url):
                if let worktree = model.worktrees.first(where: { $0.url == url }) { selectWorktree(worktree) }
            case nil: break
            }
        })
    }

    private var scopeSelection: Binding<RepositoryHistoryScope?> {
        Binding(
            get: { scope },
            set: { selected in
                if let selected {
                    scope = selected
                    screen = .history
                    isScreenListFocused = false
                }
            }
        )
    }

    private var stashCount: Int {
        if case .loaded(let stashes) = model.stashesState { stashes.count } else { 0 }
    }

    private func placeholderRow(_ title: String, systemImage: String? = nil, help: String? = nil) -> some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .foregroundStyle(.secondary)
        .help(help ?? "")
        .selectionDisabled()
    }

    @ViewBuilder
    private var branchRows: some View {
        if model.localBranches.isEmpty {
            switch model.localBranchesState {
            case .failed(let message):
                placeholderRow("Couldn’t Load Branches", systemImage: "exclamationmark.triangle", help: message)
            case .loaded:
                placeholderRow("No Local Branches")
            case .notLoaded, .loading:
                placeholderRow("Loading Branches…", systemImage: "arrow.triangle.branch")
            }
        } else if filteredBranches.isEmpty {
            placeholderRow("No Matching Branches")
        } else {
            ForEach(filteredBranches, id: \.self) { branch in
                branchRow(branch)
            }
        }
    }

    private func branchRow(_ branch: String) -> some View {
        let isCurrent = branch == currentBranch
        let worktreeURL = isCurrent ? nil : model.localBranchWorktreeURLs[branch]
        // The name truncates in the middle; the HEAD mark and the Worktree icon keep their size. HEAD reads bold
        // so the checked-out branch stands apart from the selected one.
        return HStack(spacing: 6) {
            Label(branch, systemImage: "arrow.triangle.branch")
                .fontWeight(isCurrent ? .bold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if isCurrent {
                Text("HEAD")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(scope == .branch(branch) && isReferenceListFocused && controlActiveState == .key
                                     ? Color.white : theme.colors.accent)
                    .fixedSize()
            } else if let worktreeURL {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help(worktreeURL.path)
            }
        }
        .contentShape(.rect)
        .tag(RepositoryNavigatorSelection.reference(.branch(branch)))
        .gallaeSelectionBackground(isSelected: scope == RepositoryHistoryScope.branch(branch), isFocused: isReferenceListFocused, sidebar: true)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue(for: branch))
        .accessibilityHint(isCurrent ? "Current branch" : "Double-click to switch, or open the context menu")
        // ponytail: `onTapGesture` on a macOS List row takes the click away from row selection, so branch
        // rows never selected on a single click. Simultaneous gestures select by hand and still get the double.
        .simultaneousGesture(
            TapGesture().onEnded {
                scopeSelection.wrappedValue = .branch(branch)
            }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                performPrimaryAction(for: branch)
            }
        )
        .contextMenu {
            RepositoryFolderMenu(folderURL: model.folderURL(for: branch)) {
                model.present($0, title: "Couldn’t Open Folder")
            }
            if !isCurrent {
                Divider()
                if worktreeURL != nil {
                    Button("Open Worktree", systemImage: "folder") {
                        performPrimaryAction(for: branch)
                    }
                    .disabled(model.isLoading || model.isSyncing)
                } else {
                    Button("Switch", systemImage: "arrow.triangle.branch") {
                        performPrimaryAction(for: branch)
                    }
                    .disabled(model.isLoading || model.isSyncing)
                }

                if !model.worktrees.contains(where: { $0.branch == branch }) {
                    Button("New Worktree…", systemImage: "folder.badge.plus") {
                        worktreeCreation = .init(branch: branch)
                    }
                    .disabled(model.isLoading || model.isSyncing)
                }

                Button("Integrate…", systemImage: "arrow.triangle.merge") {
                    model.showIntegrateBranch(preselecting: branch)
                }
                .disabled(!model.canIntegrateBranch || model.isLoading || model.isSyncing)

                Divider()

                if let worktreeURL {
                    if model.canRemoveWorktree(at: worktreeURL) {
                        Button("Remove Worktree…", systemImage: "folder.badge.minus", role: .destructive) {
                            Task {
                                let trackingRef = await model.trackingRemoteBranch(for: branch)
                                pendingWorktreeRemoval = .init(
                                    branch: branch,
                                    worktreeURL: worktreeURL,
                                    trackingRef: trackingRef
                                )
                            }
                        }
                    }
                } else {
                    Button("Remove Branch…", systemImage: "minus.circle", role: .destructive) {
                        pendingBranchDeletion = branch
                    }
                    .disabled(model.isLoading)
                }
            }
        }
    }

    @ViewBuilder
    private var remoteRows: some View {
        switch model.remotesState {
        case .notLoaded, .loading:
            placeholderRow("Loading Remotes…", systemImage: "network")
        case .failed(let message):
            placeholderRow("Couldn’t Load Remotes", systemImage: "exclamationmark.triangle", help: message)
        case .loaded(let remotes) where remotes.isEmpty:
            placeholderRow("No Remotes")
        case .loaded(let remotes):
            let visibleRemotes = filtered(remotes.map(\.name))
            if visibleRemotes.isEmpty {
                placeholderRow("No Matching Remotes")
            } else {
                ForEach(visibleRemotes, id: \.self) { name in
                    remoteRow(name, fetchURL: remotes.first { $0.name == name }?.fetchURL ?? "")
                }
            }
        }
    }

    /// A remote is a scope of its own (every branch it tracks) and opens to its branches, each a scope too.
    private func remoteRow(_ name: String, fetchURL: String) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { !collapsedRemotes.contains(name) },
                set: { if $0 { collapsedRemotes.remove(name) } else { collapsedRemotes.insert(name) } }
            )
        ) {
            ForEach(filtered(model.remoteBranchesByRemote[name] ?? []), id: \.self) { branch in
                Label(branch.hasPrefix("\(name)/") ? String(branch.dropFirst(name.count + 1)) : branch,
                      systemImage: "arrow.triangle.branch")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(branch)
                    .contentShape(.rect)
                    .tag(RepositoryNavigatorSelection.reference(.remoteBranch(branch)))
                    .gallaeSelectionBackground(isSelected: scope == RepositoryHistoryScope.remoteBranch(branch), isFocused: isReferenceListFocused, sidebar: true)
                    .accessibilityLabel("Remote branch \(branch)")
                    .contextMenu {
                        Button("Delete on Remote…", systemImage: "trash", role: .destructive) {
                            pendingRemoteBranchDeletion = branch
                        }
                        .disabled(model.isLoading || model.isSyncing)
                        Button("Remove Tracking Reference…", systemImage: "minus.circle", role: .destructive) {
                            pendingTrackingReferenceRemoval = branch
                        }
                        .disabled(model.isLoading)
                    }
            }
        } label: {
            Label(name, systemImage: "network")
                .lineLimit(1)
                .truncationMode(.middle)
                .badge(model.remoteBranchesByRemote[name]?.count ?? 0)
                .help(fetchURL)
                .contentShape(.rect)
                .tag(RepositoryNavigatorSelection.reference(.remote(name)))
                .gallaeSelectionBackground(isSelected: scope == RepositoryHistoryScope.remote(name), isFocused: isReferenceListFocused, sidebar: true)
                .contextMenu {
                    Button("Fetch", systemImage: "arrow.down.circle") {
                        fetch(from: name, pruning: false)
                    }
                    .disabled(model.isLoading || model.isSyncing)
                    Button("Fetch & Prune", systemImage: "arrow.down.circle.dotted") {
                        fetch(from: name, pruning: true)
                    }
                    .disabled(model.isLoading || model.isSyncing)
                    Divider()
                    Button("Edit…", systemImage: "pencil") {
                        if case .loaded(let remotes) = model.remotesState {
                            editedRemote = remotes.first { $0.name == name }
                        }
                    }
                    .disabled(model.isLoading)
                    Button("Remove “\(name)”…", systemImage: "minus.circle", role: .destructive) {
                        pendingRemoteRemoval = name
                    }
                    .disabled(model.isLoading)
                }
        }

    }

    @ViewBuilder
    private var tagRows: some View {
        switch model.tagsState {
        case .notLoaded, .loading:
            placeholderRow("Loading Tags…", systemImage: "tag")
        case .failed(let message):
            placeholderRow("Couldn’t Load Tags", systemImage: "exclamationmark.triangle", help: message)
        case .loaded(let tags) where tags.isEmpty:
            placeholderRow("No Tags")
        case .loaded(let tags):
            let visibleTags = filtered(tags)
            if visibleTags.isEmpty {
                placeholderRow("No Matching Tags")
            } else {
                ForEach(visibleTags, id: \.self) { tag in
                    Label(tag, systemImage: "tag")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .tag(RepositoryNavigatorSelection.reference(.tag(tag)))
                        .gallaeSelectionBackground(isSelected: scope == RepositoryHistoryScope.tag(tag), isFocused: isReferenceListFocused, sidebar: true)
                }
            }
        }
    }

    private var filteredBranches: [String] {
        filtered(model.localBranches)
    }

    private func filtered(_ names: [String]) -> [String] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return names }
        return names.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var currentBranch: String? {
        guard let repository = model.repository else { return nil }
        guard case .branch(let branch) = repository.head else { return nil }
        return branch
    }

    private func fetch(from remote: String, pruning: Bool) {
        guard let rootURL = model.repository?.rootURL, !model.isLoading, !model.isSyncing else { return }
        model.fetch(from: remote, pruning: pruning, in: rootURL)
    }

    private func removeRemote(named name: String) async {
        guard let rootURL = model.repository?.rootURL else { return }
        do {
            try await model.removeRemote(named: name, in: rootURL)
            if scope?.remoteName == name { scope = nil }
        } catch is CancellationError {
            return
        } catch {
            removalErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Switch in this folder, or navigate to an existing Worktree, retaining the History scope in either case.
    private func performPrimaryAction(for branch: String) {
        guard branch != currentBranch, !model.isLoading, !model.isSyncing else { return }
        Task {
            if let worktreeURL = model.localBranchWorktreeURLs[branch] {
                _ = await model.openWorktree(at: worktreeURL)
            } else {
                _ = await model.switchBranch(to: branch)
            }
        }
    }

    private func accessibilityValue(for branch: String) -> String {
        if branch == currentBranch { return "Current branch" }
        guard let worktreeURL = model.localBranchWorktreeURLs[branch] else { return "" }
        return "Existing Worktree at \(worktreeURL.path)"
    }
}

struct CreateBranchSheet: View {
    @Bindable var model: AppModel
    /// Git start point for the branch; nil starts at HEAD. `startPointLabel` is what the sheet calls it.
    var startPoint: String? = nil
    var startPointLabel: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Branch")
                .font(.headline)
            Text("Creates a local branch from \(startPointLabel ?? model.repository?.head.label ?? "the current HEAD") and switches to it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Branch Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(createBranch)
                .accessibilityLabel("New Branch Name")

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    createBranch()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .accessibilityHint("Creates and switches to the new local branch")
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            isNameFocused = true
        }
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isLoading
    }

    private func createBranch() {
        guard canCreate else { return }
        Task {
            if await model.createBranch(named: name, at: startPoint) {
                dismiss()
            }
        }
    }
}

struct WorktreeRemovalRequest {
    let branch: String
    let worktreeURL: URL
    let trackingRef: String?

    var confirmationMessage: String {
        var message = "This removes the Worktree folder at \(worktreeURL.path); git keeps it if changes or an operation remain inside. Removing the branch is a safe delete that keeps unmerged branches."
        if let trackingRef {
            message += " Deleting \(trackingRef) also removes it on the remote for everyone using it."
        }
        return message
    }
}

private struct RemoteBranchDialogs: ViewModifier {
    let model: AppModel
    @Binding var deletion: String?
    @Binding var trackingRemoval: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete Remote Branch?",
                isPresented: Binding(
                    get: { deletion != nil },
                    set: { if !$0 { deletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: deletion
            ) { trackingRef in
                Button("Delete \(trackingRef)", role: .destructive) {
                    model.deleteRemoteBranch(trackingRef)
                }
                Button("Cancel", role: .cancel) {}
            } message: { trackingRef in
                Text(
                    "This deletes \(trackingRef) on its remote for everyone using that remote. Local branches and commits stay, and the server may reject deleting a protected branch."
                )
            }
            .confirmationDialog(
                "Remove Tracking Reference?",
                isPresented: Binding(
                    get: { trackingRemoval != nil },
                    set: { if !$0 { trackingRemoval = nil } }
                ),
                titleVisibility: .visible,
                presenting: trackingRemoval
            ) { trackingRef in
                Button("Remove \(trackingRef)", role: .destructive) {
                    Task { await model.removeTrackingReference(trackingRef) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { trackingRef in
                Text(
                    "This removes only the local tracking reference \(trackingRef). The branch on the remote is not changed, and Fetch can restore the reference."
                )
            }
    }
}

extension View {
    func remoteBranchDialogs(
        model: AppModel,
        deletion: Binding<String?>,
        trackingRemoval: Binding<String?>
    ) -> some View {
        modifier(RemoteBranchDialogs(model: model, deletion: deletion, trackingRemoval: trackingRemoval))
    }
}
