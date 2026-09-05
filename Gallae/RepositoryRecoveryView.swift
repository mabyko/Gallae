import AppKit
import SwiftUI

struct RepositoryStashesView: View {
    @Bindable var model: AppModel
    @FocusState private var isListFocused: Bool
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        ResizableHSplit(
            leadingMinimum: theme.metrics.changeListMinimumWidth,
            leadingIdeal: theme.metrics.changeListIdealWidth,
            trailingMinimum: 400,
            storageKey: "stashes"
        ) {
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
                .listHeaderInset()

                Divider()

                stashList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } trailing: {
            RepositoryStashDetailView(model: model)
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
                    .gallaeSelectionBackground(isSelected: model.selectedStashID == stash.id, isFocused: isListFocused)
                    .listRowInsets(.init(top: 0, leading: 12, bottom: 0, trailing: 12))
            }
            .listStyle(.plain)
            .focused($isListFocused)
                .legacyScrollerAware()
            .accessibilityLabel("Stashes, \(stashes.count) items")
        }
    }
}

struct RepositoryReflogView: View {
    @Bindable var model: AppModel
    @FocusState private var isListFocused: Bool
    @Environment(\.gallaeTheme) private var theme
    @State private var recoveryEntry: RepositoryReflogEntry?

    var body: some View {
        ResizableHSplit(
            leadingMinimum: theme.metrics.changeListMinimumWidth,
            leadingIdeal: theme.metrics.changeListIdealWidth,
            trailingMinimum: 400,
            storageKey: "reflog"
        ) {
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
                .listHeaderInset()

                Divider()

                reflogList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } trailing: {
            RepositoryReflogDetailView(
                entry: model.selectedReflogEntry,
                onRecover: { recoveryEntry = $0 }
            )
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
                    .gallaeSelectionBackground(isSelected: model.selectedReflogEntryID == entry.id, isFocused: isListFocused)
                    .listRowInsets(.init(top: 0, leading: 12, bottom: 0, trailing: 12))
            }
            .listStyle(.plain)
            .focused($isListFocused)
                .legacyScrollerAware()
            .accessibilityLabel("Reflog, \(entries.count) recovery points")
        }
    }
}

private struct RepositoryReflogRow: View {
    @Environment(\.gallaeTheme) private var theme
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
            .padding(.vertical, theme.metrics.rowVerticalPadding)

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
    @Environment(\.gallaeTheme) private var theme
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
            .padding(.vertical, theme.metrics.rowVerticalPadding)

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
