import AppKit
import SwiftUI

enum RepositoryNavigatorSelection: Hashable {
    case reference(RepositoryHistoryScope)
    case worktree(URL)
}

struct WorktreeCreationRequest: Identifiable {
    let id = UUID()
    var branch: String? = nil
}

struct RepositoryWorktreesSection: View {
    @Bindable var model: AppModel
    var filter: String
    var isFocused: Bool
    var select: (RepositoryWorktree) -> Void
    var create: () -> Void
    @AppStorage("worktreesExpanded") private var isExpanded = true
    @State private var pendingRemoval: RepositoryWorktree?

    private var visibleWorktrees: [RepositoryWorktree] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.worktrees.filter {
            !$0.isBare && (query.isEmpty || $0.url.path.localizedCaseInsensitiveContains(query)
                          || $0.headLabel.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        if model.worktrees.contains(where: { !$0.isPrimary && !$0.isBare }) {
            Section {
                if isExpanded {
                    if case .failed(let message) = model.localBranchesState {
                        Label("Couldn’t Refresh Worktrees", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.secondary).help(message).selectionDisabled()
                    }
                    if visibleWorktrees.isEmpty {
                        Text("No Matching Worktrees").foregroundStyle(.secondary).selectionDisabled()
                    }
                    ForEach(visibleWorktrees) { worktree in
                        row(worktree)
                    }
                }
            } header: {
                RepositoryNavigatorSectionHeader(title: "Worktrees", actionsLabel: "Worktree Actions",
                                                 isExpanded: $isExpanded,
                                                 actionsDisabled: model.isLoading || model.isSyncing) {
                    Button("New Worktree…", systemImage: "folder.badge.plus", action: create)
                }
            }
            .confirmationDialog("Remove Worktree?", isPresented: Binding(
                get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
            ), titleVisibility: .visible, presenting: pendingRemoval) { worktree in
                Button("Remove Worktree", role: .destructive) {
                    Task { await model.removeWorktree(at: worktree.url) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { worktree in
                Text("Remove \(worktree.url.path)? The branch and commits are kept. Git refuses removal if the folder contains uncommitted or untracked files.")
            }
        }
    }

    private func row(_ worktree: RepositoryWorktree) -> some View {
        let current = worktree.url.resolvingSymlinksInPath().path == model.repository?.rootURL.resolvingSymlinksInPath().path
        let duplicateName = model.worktrees.filter { $0.name == worktree.name }.count > 1
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: worktree.isAvailable ? "folder" : "exclamationmark.triangle")
            VStack(alignment: .leading, spacing: 2) {
                Text(worktree.name).fontWeight(current ? .bold : .regular)
                    .lineLimit(1).truncationMode(.middle)
                Text(worktree.headLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if duplicateName {
                    Text(worktree.url.deletingLastPathComponent().path)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 2)
            if current {
                Image(systemName: "checkmark").font(.caption.bold()).help("Current Worktree")
            } else if worktree.isPrimary {
                Text("Primary").font(.caption2).foregroundStyle(.secondary).fixedSize()
            }
            if let reason = worktree.lockedReason {
                Image(systemName: "lock").font(.caption).help(reason.isEmpty ? "Locked Worktree" : reason)
            }
        }
        .tag(RepositoryNavigatorSelection.worktree(worktree.url))
        .contentShape(.rect)
        .gallaeSelectionBackground(isSelected: model.selectedWorktreeURL == worktree.url, isFocused: isFocused, sidebar: true)
        .help(worktree.url.path + (worktree.isAvailable ? "" : "\nFolder unavailable"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(worktree.name), \(worktree.headLabel)\(current ? ", Current Worktree" : "")\(worktree.isPrimary ? ", Primary" : "")\(worktree.isAvailable ? "" : ", Folder unavailable")")
        .accessibilityHint("Select to reveal in History. Double-click or press Return to open the folder.")
        .simultaneousGesture(TapGesture().onEnded { select(worktree) })
        .simultaneousGesture(TapGesture(count: 2).onEnded { open(worktree) })
        .contextMenu {
            Button("Open Worktree", systemImage: "folder") { open(worktree) }
                .disabled(current || !worktree.isAvailable || model.isLoading || model.isSyncing)
            RepositoryFolderMenu(folderURL: worktree.isAvailable ? worktree.url : nil) {
                model.present($0, title: "Couldn’t Open Folder")
            }
            if !worktree.isPrimary {
                Divider()
                Button("Remove Worktree…", systemImage: "folder.badge.minus", role: .destructive) {
                    pendingRemoval = worktree
                }
                .disabled(!model.canRemoveWorktree(at: worktree.url))
                .help(worktree.removalRestriction(currentURL: model.repository?.rootURL ?? worktree.url) ?? "")
            }
        }
        .accessibilityAction(named: "Open Worktree") { open(worktree) }
    }

    private func open(_ worktree: RepositoryWorktree) {
        guard worktree.isAvailable, !model.isLoading, !model.isSyncing,
              worktree.url.resolvingSymlinksInPath().path != model.repository?.rootURL.resolvingSymlinksInPath().path else { return }
        Task { _ = await model.openWorktree(at: worktree.url) }
    }
}

struct CreateWorktreeSheet: View {
    @Bindable var model: AppModel
    var existingBranch: String?
    @Environment(\.dismiss) private var dismiss
    @State private var createsBranch = true
    @State private var name = ""
    @State private var branch = ""
    @State private var startPoint = "HEAD"
    @State private var parentURL: URL?
    @State private var folderName = ""
    @State private var opensAfterCreation = true
    @State private var isCreating = false
    @FocusState private var isNameFocused: Bool

    private var branches: [String] {
        if case .loaded(let branches) = model.localBranchesState { branches } else { [] }
    }
    private var selectedBranch: String { (createsBranch ? name : branch).trimmingCharacters(in: .whitespacesAndNewlines) }
    private var occupied: Bool { !createsBranch && model.worktrees.contains { $0.branch == branch } }
    private var destination: URL? {
        guard let parentURL, !folderName.isEmpty, folderName != ".", folderName != "..",
              !folderName.contains("/"), !folderName.contains("\0") else { return nil }
        return parentURL.appending(path: folderName, directoryHint: .isDirectory)
    }
    private var destinationExists: Bool { destination.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Worktree").font(.headline)
            Text("Create a separate working folder. Changes in the current folder stay here.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Picker("Branch", selection: $createsBranch) {
                    Text("New Branch").tag(true)
                    Text("Existing Branch").tag(false)
                }.pickerStyle(.segmented)
                if createsBranch {
                    TextField("New branch name", text: $name).focused($isNameFocused)
                        .accessibilityLabel("Worktree Branch Name")
                    TextField("Starting point", text: $startPoint).accessibilityLabel("Worktree Starting Point")
                    Text("Start from HEAD, a branch, tag, or commit.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Branch", selection: $branch) {
                        Text("Choose a branch").tag("")
                        ForEach(branches, id: \.self) { item in
                            let inUse = model.worktrees.contains { $0.branch == item }
                            Text(item + (inUse ? " · In Use" : "")).tag(item).disabled(inUse)
                        }
                    }
                    if occupied { Text("This branch already has a working folder.").font(.caption).foregroundStyle(.secondary) }
                }
                LabeledContent("Location") {
                    Button(action: chooseParent) {
                        Label(parentURL?.path ?? "Choose Folder…", systemImage: "folder")
                            .lineLimit(1).truncationMode(.middle)
                    }.help(parentURL?.path ?? "")
                }
                TextField("New folder name", text: $folderName).accessibilityLabel("Worktree Folder Name")
                if let destination {
                    Text(destination.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if destinationExists {
                    Text("That folder already exists. Choose a new folder name.").font(.caption).foregroundStyle(.red)
                }
                Toggle("Open after creation", isOn: $opensAfterCreation)
            }.disabled(isCreating)
            HStack {
                if isCreating { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isCreating)
                Button("Create Worktree", action: create).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCreating || model.isLoading || model.isSyncing || selectedBranch.isEmpty || occupied
                              || destination == nil || destinationExists || (createsBranch && startPoint.isEmpty))
            }
        }
        .textFieldStyle(.roundedBorder).padding(20).frame(width: 440)
        .interactiveDismissDisabled(isCreating)
        .onAppear {
            createsBranch = existingBranch == nil
            branch = existingBranch ?? ""
            parentURL = model.repository?.rootURL.deletingLastPathComponent()
            folderName = suggestedFolder(for: branch)
            isNameFocused = createsBranch
        }
        .onChange(of: selectedBranch) { previous, next in
            if folderName.isEmpty || folderName == suggestedFolder(for: previous) {
                folderName = suggestedFolder(for: next)
            }
        }
        .task { await model.loadLocalBranches() }
    }

    private func suggestedFolder(for branch: String) -> String {
        branch.isEmpty ? "" : (model.repository?.name ?? "Repository") + "-" + branch.replacingOccurrences(of: "/", with: "-")
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = parentURL
        panel.prompt = "Choose"
        panel.begin { response in
            if response == .OK { parentURL = panel.url }
        }
    }

    private func create() {
        guard let destination, !isCreating else { return }
        isCreating = true
        Task {
            let url = await model.createWorktree(at: destination, branch: selectedBranch,
                                                creatingBranch: createsBranch, startPoint: startPoint)
            isCreating = false
            guard let url else { return }
            dismiss()
            if opensAfterCreation { _ = await model.openWorktree(at: url) }
        }
    }
}

/// Section controls keep the collapse toggle next to the title and actions at the trailing edge.
struct RepositoryNavigatorSectionHeader<Actions: View>: View {
    let title: String
    let actionsLabel: String
    var isExpanded: Binding<Bool>? = nil
    var actionsDisabled = false
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 4) {
            if let isExpanded {
                Button {
                    isExpanded.wrappedValue.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(title)
                        // Keep the native header height: a taller first row shifts List's initial scroll position.
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("\(isExpanded.wrappedValue ? "Collapse" : "Expand") \(title)")
                .accessibilityLabel("\(title) disclosure")
                .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
            } else {
                Text(title)
            }
            Spacer(minLength: 4)
            Menu(content: actions) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22).contentShape(.rect)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).controlSize(.small)
            .fixedSize().foregroundStyle(.secondary).padding(.trailing, 4)
            .help(actionsLabel).accessibilityLabel(actionsLabel)
            .disabled(actionsDisabled)
        }
    }
}
