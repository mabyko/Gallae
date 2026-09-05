import AppKit
import SwiftUI

/// File identity stays readable; actions move below it when the pane cannot fit both.
private struct RepositoryDiffHeader<Actions: View>: View {
    let path: String
    let originalPath: String?
    let content: RepositoryDiff.Section.Content?
    let actions: Actions
    @Environment(\.gallaeTheme) private var theme

    init(
        path: String,
        originalPath: String? = nil,
        content: RepositoryDiff.Section.Content?,
        @ViewBuilder actions: () -> Actions
    ) {
        self.path = path
        self.originalPath = originalPath
        self.content = content
        self.actions = actions()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                fileIdentity.frame(minWidth: 180)
                Spacer(minLength: 0)
                actions.fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                fileIdentity
                HStack {
                    Spacer(minLength: 0)
                    actions
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .controlSize(.small)
    }

    private var fileIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(path.split(separator: "/").last.map(String.init) ?? path)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                let directory = (path as NSString).deletingLastPathComponent
                Text(directory.isEmpty ? "Repository root" : directory)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let counts = content?.lineChangeCounts, counts.added + counts.removed > 0 {
                    HStack(spacing: 6) {
                        Text("+\(counts.added)").foregroundStyle(theme.colors.statusAdded)
                        Text("−\(counts.removed)").foregroundStyle(theme.colors.statusDeleted)
                    }
                    .font(.caption.monospacedDigit().weight(.medium))
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Line changes: \(counts.added) added, \(counts.removed) deleted")
                    .help("Line changes in the displayed diff")
                }
            }
            if let originalPath {
                Text("From \(originalPath)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(originalPath)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(path)
        .textSelection(.enabled)
        .contextMenu {
            Button("Copy Relative Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
    }
}

struct RepositoryRevisionChangesView: View {
    let filesState: RepositoryCommitFilesLoadState
    @Binding var selectedFileID: String?
    let selectedFile: RepositoryCommitFile?
    let patchState: RepositoryCommitPatchLoadState
    let retryFiles: () -> Void
    let retryPatch: () -> Void
    let loadExpandedPatch: () -> Void
    @AppStorage(RepositoryDiffLayout.storageKey) private var layout = RepositoryDiffLayout.unified
    @FocusState private var isFileListFocused: Bool
    @Environment(\.gallaeTheme) private var theme

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
        GeometryReader { proxy in
            // Keep the diff readable when the saved-changes pane cannot fit both lists and code.
            if proxy.size.width < 560 {
                VStack(spacing: 0) {
                    Picker("Changed Files", selection: $selectedFileID) {
                        ForEach(files) { file in
                            Text(file.path).tag(Optional(file.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .accessibilityLabel("Changed Files, \(files.count) files")
                    Divider()
                    revisionDetail
                }
            } else {
                ResizableHSplit(leadingMinimum: 160, leadingIdeal: 200, leadingMaximum: 280, trailingMinimum: 400, storageKey: "revisionFiles") {
                    revisionFileList(files)
                } trailing: {
                    revisionDetail
                }
            }
        }
    }

    private func revisionFileList(_ files: [RepositoryCommitFile]) -> some View {
            VStack(spacing: 0) {
                HStack {
                    Text("Changed Files")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(files.count, format: .number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .listHeaderInset()

                Divider()

                List(files, selection: $selectedFileID) { file in
                    RepositoryCommitFileRow(file: file)
                        .tag(file.id)
                        .gallaeSelectionBackground(isSelected: selectedFileID == file.id, isFocused: isFileListFocused)
                        .listRowInsets(.init(
                            top: theme.metrics.rowVerticalPadding,
                            leading: 12,
                            bottom: theme.metrics.rowVerticalPadding,
                            trailing: 12
                        ))
                }
                .listStyle(.plain)
                .focused($isFileListFocused)
                .legacyScrollerAware()
                .accessibilityLabel("Changed Files, \(files.count) files")
            }
    }

    private var revisionDetail: some View {
            VStack(spacing: 0) {
                if let file = selectedFile {
                    RepositoryDiffHeader(path: file.path, originalPath: file.originalPath, content: selectedContent) {
                        RepositoryDiffLayoutPicker(presentation: presentation, preferred: $layout)
                    }

                    Divider()
                }

                revisionPatchContent
            }
    }

    private var selectedContent: RepositoryDiff.Section.Content? {
        guard case .loaded(let patch) = patchState else { return nil }
        return patch.content
    }

    private var presentation: RepositoryDiffPresentation {
        .init(content: selectedContent, preferred: layout)
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
        let layout = presentation.layout
        switch content {
        case .text(let lines):
            GeometryReader { proxy in
                ScrollView(layout == .split ? [.vertical] : [.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        RepositoryDiffLinesView(lines: lines, layout: layout)
                    }
                    // The height keeps a short diff at the top. Switching layouts changes the scroll
                    // view's axes, and the rebuilt scroll view forgets `defaultScrollAnchor`, centring
                    // content smaller than the pane; filling the height leaves nothing to centre.
                    .frame(
                        minWidth: proxy.size.width.rounded(.down),
                        maxWidth: layout == .split ? proxy.size.width.rounded(.down) : nil,
                        minHeight: proxy.size.height.rounded(.down),
                        alignment: .topLeading
                    )
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

            Text(file.state.shortLabel)
                .font(.caption2.monospaced().weight(.medium))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .frame(width: 22)
                .padding(.vertical, 1)
                .fixedSize()
                .background(theme.colors.badgeBackground, in: .capsule)
                .help(file.state.label)
                .accessibilityLabel(file.state.label)
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

struct RepositoryDiffView: View {
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
    let discardHunk: (RepositoryDiff.Hunk) -> Void
    let retry: () -> Void
    let loadExpanded: () -> Void
    @AppStorage(RepositoryDiffLayout.storageKey) private var layout = RepositoryDiffLayout.unified
    @State private var isConfirmingDiscard = false
    @State private var pendingConflictResolution: ConflictResolutionConfirmation?
    /// Which side the reader asked for. nil follows the file: a file with one side needs no choice, and the
    /// choice is dropped when another file is selected.
    @State private var chosenScope: RepositoryDiff.Scope?
    @Environment(\.gallaeTheme) private var theme

    /// Staged and Working Tree are the two sides a file can be on; the rest are conflict versions, which the
    /// comparison view handles.
    private static let switchableScopes: [RepositoryDiff.Scope] = [.staged, .unstaged, .untracked]

    private func shownScope(in diff: RepositoryDiff) -> RepositoryDiff.Scope {
        let available = diff.sections.map(\.scope).filter(Self.switchableScopes.contains)
        if let chosenScope, available.contains(chosenScope) { return chosenScope }
        // A side the reader was on that has just emptied stays selected, so the emptying is visible rather
        // than looking like an unasked-for jump to the other side.
        if let chosenScope, available.count == 1, chosenScope != available[0] { return chosenScope }
        // Otherwise the working tree leads: it is where the next action happens.
        return available.first { $0 != .staged } ?? available.first ?? .unstaged
    }

    /// The side not being shown, when there is one worth naming.
    private func otherScope(in diff: RepositoryDiff, than shown: RepositoryDiff.Scope) -> RepositoryDiff.Scope? {
        let available = diff.sections.map(\.scope).filter(Self.switchableScopes.contains)
        guard available.count > 1 || (available.count == 1 && available[0] != shown) else { return nil }
        return available.first { $0 != shown }
    }

    private func changedLines(in diff: RepositoryDiff, scope: RepositoryDiff.Scope) -> Int {
        diff.sections.first { $0.scope == scope }?.changedLineCount ?? 0
    }

    @ViewBuilder
    private func scopeSwitcher(
        in diff: RepositoryDiff,
        shown: RepositoryDiff.Scope,
        other: RepositoryDiff.Scope
    ) -> some View {
        let ordered = [shown, other].sorted { $0 == .staged && $1 != .staged }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Picker("Diff Side", selection: Binding(get: { shown }, set: { chosenScope = $0 })) {
                    ForEach(ordered, id: \.self) { scope in
                        Text("\(scope.label)  \(changedLines(in: diff, scope: scope))").tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .help("Choose whether to read what is staged for the next commit, or what is not")

                Text(shown == .staged ? "in the next commit" : "not in the next commit yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // The side that is off screen still says what it holds, so staging a hunk reads as "it moved
            // there" rather than "it vanished".
            Button {
                chosenScope = other
            } label: {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(other == .staged ? theme.colors.statusAdded : theme.colors.statusModified)
                        .frame(width: 3)
                    Text(other.label)
                        .font(.caption.weight(.semibold))
                    Text(changedLineSummary(changedLines(in: diff, scope: other), scope: other))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                }
                .frame(height: 18)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .foregroundStyle(other == .staged ? theme.colors.statusAdded : theme.colors.statusModified)
            .accessibilityLabel(
                "\(other.label): \(changedLineSummary(changedLines(in: diff, scope: other), scope: other)). Show it"
            )
        }
        .background(theme.colors.badgeBackground)
    }

    private func changedLineSummary(_ count: Int, scope: RepositoryDiff.Scope) -> String {
        let lines = count == 1 ? "1 line" : "\(count) lines"
        return scope == .staged ? "\(lines) · in the next commit" : "\(lines) · not in it yet"
    }

    @ViewBuilder
    private func emptyScope(_ scope: RepositoryDiff.Scope) -> some View {
        ContentUnavailableView {
            Label(
                scope == .staged ? "Nothing Staged" : "Nothing Left Here",
                systemImage: "checkmark.circle"
            )
        } description: {
            Text(
                scope == .staged
                    ? "None of this file's changes are in the next commit."
                    : "Every change in this file is already in the next commit."
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }


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
        let shown = shownScope(in: diff)
        let presentation = RepositoryDiffPresentation(
            content: diff.sections.first { $0.scope == shown }?.content,
            preferred: layout
        )
        let effectiveLayout = presentation.layout
        return VStack(spacing: 0) {
            RepositoryDiffHeader(
                path: diff.path,
                originalPath: diff.originalPath,
                content: diff.sections.first { $0.scope == shown }?.content
            ) {
                HStack(spacing: 8) {
                    if !diff.sections.allSatisfy(\.scope.isConflictVersion) {
                        RepositoryDiffLayoutPicker(presentation: presentation, preferred: $layout)
                    }

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

                    if canUnstage {
                        Button("Unstage File", action: unstage)
                            .disabled(isBusy)
                            .help("Remove this file from the next commit without changing it on disk")
                            .accessibilityHint(
                                "Remove this file from the next commit without changing its working tree content"
                            )
                    }
                    if canStage {
                        Button("Stage File", action: stage)
                            .buttonStyle(.borderedProminent)
                            .disabled(isBusy)
                            .help("Add this file to the next commit")
                            .accessibilityHint("Add this file’s current changes to the next commit")
                    }
                    if canDiscard {
                        Menu {
                            Button("Discard Unstaged Changes…", role: .destructive) {
                                isConfirmingDiscard = true
                            }
                            .disabled(isBusy)
                        } label: {
                            Label("File Actions", systemImage: "ellipsis")
                        }
                        .labelStyle(.iconOnly)
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("More actions for this file")
                        .accessibilityLabel("File Actions")
                    }
                }
            }

            Divider()

            if diff.sections.allSatisfy(\.scope.isConflictVersion) {
                RepositoryConflictComparisonView(
                    sections: diff.sections,
                    loadExpanded: loadExpanded
                )
            } else {
                if let other = otherScope(in: diff, than: shown) {
                    scopeSwitcher(in: diff, shown: shown, other: other)
                    Divider()
                }
                GeometryReader { proxy in
                    ScrollView(effectiveLayout == .split ? [.vertical] : [.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if let section = diff.sections.first(where: { $0.scope == shown }) {
                                RepositoryDiffSectionView(
                                    section: section,
                                    layout: effectiveLayout,
                                    // The switcher above already names the side, and a lone section needs
                                    // no name at all: the file and its status sit right above it.
                                    showsHeader: false,
                                    fileURL: fileURL,
                                    canStageHunks: canStageHunks,
                                    canUnstageHunks: canUnstageHunks,
                                    isBusy: isBusy,
                                    updateHunk: updateHunk,
                                    discardHunk: discardHunk,
                                    loadExpanded: loadExpanded
                                )
                            } else {
                                emptyScope(shown)
                            }
                        }
                        // The height keeps a short diff at the top. Switching layouts changes the scroll
                        // view's axes, and the rebuilt scroll view forgets `defaultScrollAnchor`, centring
                        // content smaller than the pane; filling the height leaves nothing to centre.
                        .frame(
                            minWidth: proxy.size.width.rounded(.down),
                            maxWidth: effectiveLayout == .split ? proxy.size.width.rounded(.down) : nil,
                            minHeight: proxy.size.height.rounded(.down),
                            alignment: .topLeading
                        )
                        .textSelection(.enabled)
                    }
                    .defaultScrollAnchor(.topLeading, for: .alignment)
                }
            }
        }
        .onChange(of: fileURL) {
            // The side is a reading choice about one file, not a mode; another file starts fresh.
            chosenScope = nil
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
            let numberWidth = diffNumberWidth(for: lines, fontSize: theme.metrics.diffFontSize)
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            RepositoryConflictLineView(line: line, numberWidth: numberWidth)
                        }
                    }
                    .frame(minWidth: proxy.size.width.rounded(.down), alignment: .leading)
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
    let numberWidth: CGFloat
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: numberWidth, alignment: .trailing)
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

/// Unified shows one column with both line numbers; Split puts the old and new versions side by side.
enum RepositoryDiffLayout: String, CaseIterable, Identifiable {
    case unified
    case split

    static let storageKey = "diffLayout"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unified: "Unified"
        case .split: "Split"
        }
    }
}

/// One row of a split diff: a full-width metadata or hunk line, or an old/new pair. Context lines sit on
/// both sides; each run of deletions is paired in order with the additions that follow it.
struct RepositoryDiffSplitRow: Equatable, Identifiable {
    let id: Int
    let full: RepositoryDiff.Line?
    let old: RepositoryDiff.Line?
    let new: RepositoryDiff.Line?

    static func rows(from lines: [RepositoryDiff.Line]) -> [RepositoryDiffSplitRow] {
        var rows: [RepositoryDiffSplitRow] = []
        var deletions: [RepositoryDiff.Line] = []
        var additions: [RepositoryDiff.Line] = []

        func flushChanges() {
            for index in 0..<max(deletions.count, additions.count) {
                let old = index < deletions.count ? deletions[index] : nil
                let new = index < additions.count ? additions[index] : nil
                rows.append(.init(id: old?.id ?? new?.id ?? -1, full: nil, old: old, new: new))
            }
            deletions.removeAll()
            additions.removeAll()
        }

        for line in lines {
            switch line.kind {
            case .deletion:
                deletions.append(line)
            case .addition:
                additions.append(line)
            case .context:
                flushChanges()
                rows.append(.init(id: line.id, full: nil, old: line, new: line))
            case .metadata, .hunk:
                flushChanges()
                rows.append(.init(id: line.id, full: line, old: nil, new: nil))
            }
        }
        flushChanges()
        return rows
    }
}

/// One decision for the picker, scroll axes and rows, using only the visible content.
struct RepositoryDiffPresentation {
    let canSplit: Bool
    let layout: RepositoryDiffLayout

    init(content: RepositoryDiff.Section.Content?, preferred: RepositoryDiffLayout) {
        if case .text(let lines) = content {
            canSplit = !lines.isEmpty && content?.isOneSided == false
        } else {
            canSplit = false
        }
        layout = canSplit ? preferred : .unified
    }
}

/// The Unified/Split toggle in diff headers; the last choice is remembered across files and windows.
private struct RepositoryDiffLayoutPicker: View {
    /// False for a new or deleted file: there is no opposite version, so Split would draw one column and the
    /// control would claim a layout the diff is not in.
    let presentation: RepositoryDiffPresentation
    @Binding var preferred: RepositoryDiffLayout

    private var canSplit: Bool { presentation.canSplit }

    /// Reads Unified while Split is unavailable so the control never highlights a layout the diff is not in,
    /// and writes through so the remembered choice survives a file that cannot be split.
    private var shown: Binding<RepositoryDiffLayout> {
        Binding(get: { presentation.layout }, set: { preferred = $0 })
    }

    var body: some View {
        // The whole control is disabled rather than the Split segment alone: macOS ignores `disabled` on an
        // individual segment of a segmented picker, so a lone dimmed segment stays clickable.
        Picker("Diff Layout", selection: shown) {
            ForEach(RepositoryDiffLayout.allCases) { layout in
                Text(layout.title).tag(layout)
            }
        }
        .disabled(!canSplit)
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help(
            canSplit
                ? "Show the diff in one column, or the old and new versions side by side"
                : "The selected content does not support a side-by-side comparison"
        )
        .accessibilityLabel("Diff Layout")
        .accessibilityValue(canSplit ? "" : "Split unavailable for the selected content")
    }
}

private struct RepositoryDiffSectionView: View {
    let section: RepositoryDiff.Section
    let layout: RepositoryDiffLayout
    var showsHeader = true
    let fileURL: URL?
    let canStageHunks: Bool
    let canUnstageHunks: Bool
    let isBusy: Bool
    let updateHunk: (RepositoryDiff.Hunk) -> Void
    let discardHunk: (RepositoryDiff.Hunk) -> Void
    let loadExpanded: () -> Void
    @Environment(\.gallaeTheme) private var theme
    /// Addition and deletion lines ticked in the gutter; the hunk button then stages or unstages only those.
    @State private var chosenLineIDs: Set<Int> = []
    @State private var lastToggledLineID: Int?
    @State private var pendingDiscard: PendingDiscard?

    private struct PendingDiscard: Identifiable {
        let hunk: RepositoryDiff.Hunk
        let lineCount: Int?
        var id: Int { hunk.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                Label(section.scope.label, systemImage: section.scope.systemImage)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.colors.badgeBackground)

                Divider()
            }

            switch section.content {
            case .text(let lines):
                RepositoryDiffLinesView(
                    lines: lines,
                    layout: layout,
                    isBusy: isBusy,
                    hunkAction: { line in hunkAction(for: line, in: lines) },
                    hunkSecondaryAction: { line in discardAction(for: line, in: lines) },
                    lineChoice: { line in lineChoice(for: line) },
                    hunkChoice: { line in hunkChoice(for: line, in: lines) },
                    reservesChoiceColumn: choosesLines
                )
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
        .onChange(of: section) { _, _ in
            chosenLineIDs = []
            lastToggledLineID = nil
        }
        .confirmationDialog(
            pendingDiscard.map { $0.lineCount.map { "Discard \($0 == 1 ? "1 Line" : "\($0) Lines")?" } ?? "Discard Hunk?" } ?? "",
            isPresented: Binding(get: { pendingDiscard != nil }, set: { if !$0 { pendingDiscard = nil } }),
            titleVisibility: .visible,
            presenting: pendingDiscard
        ) { pending in
            Button("Discard", role: .destructive) {
                discardHunk(pending.hunk)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This rewrites the file on disk without these changes. The index is not touched, and Gallae cannot undo this action.")
        }
    }

    private var hunkVerb: String? {
        switch section.scope {
        case .staged where canUnstageHunks: "Unstage"
        case .unstaged where canStageHunks, .untracked where canStageHunks: "Stage"
        default: nil
        }
    }

    /// Gutter checkboxes belong to every stageable section in both layouts.
    private var choosesLines: Bool {
        hunkVerb != nil
    }

    /// The second hunk button on a working tree section: the whole hunk or the ticked lines, after asking.
    private func discardAction(for line: RepositoryDiff.Line, in lines: [RepositoryDiff.Line]) -> (label: String, perform: () -> Void)? {
        guard section.scope == .unstaged, canStageHunks, let hunk = section.hunks.first(where: { $0.id == line.id }) else { return nil }
        let chosen = chosenLineIDs.intersection(changeLineIDs(ofHunkStartingAt: line.id, in: lines))
        guard !chosen.isEmpty else {
            return ("Discard Hunk…", { pendingDiscard = .init(hunk: hunk, lineCount: nil) })
        }
        let label = chosen.count == 1 ? "Discard 1 Line…" : "Discard \(chosen.count) Lines…"
        return (label, {
            if let partial = section.partialHunk(id: hunk.id, keeping: chosen, direction: .revert) {
                pendingDiscard = .init(hunk: partial, lineCount: chosen.count)
            }
        })
    }

    /// The hunk button: the whole hunk while nothing is ticked, otherwise only the ticked lines of that hunk.
    private func hunkAction(for line: RepositoryDiff.Line, in lines: [RepositoryDiff.Line]) -> (label: String, perform: () -> Void)? {
        guard let hunkVerb, let hunk = section.hunks.first(where: { $0.id == line.id }) else { return nil }
        let chosen = chosenLineIDs.intersection(changeLineIDs(ofHunkStartingAt: line.id, in: lines))
        guard choosesLines, !chosen.isEmpty else {
            return ("\(hunkVerb) Hunk", { updateHunk(hunk) })
        }
        let label = chosen.count == 1 ? "\(hunkVerb) 1 Line" : "\(hunkVerb) \(chosen.count) Lines"
        return (label, {
            let direction: RepositoryDiff.Section.PartialDirection = section.scope == .staged ? .revert : .apply
            if let partial = section.partialHunk(id: hunk.id, keeping: chosen, direction: direction) {
                updateHunk(partial)
            }
        })
    }

    private func lineChoice(for line: RepositoryDiff.Line) -> (isOn: Bool, toggle: () -> Void)? {
        guard choosesLines, line.kind == .addition || line.kind == .deletion else { return nil }
        return (chosenLineIDs.contains(line.id), { toggle(line.id) })
    }

    private func hunkChoice(for line: RepositoryDiff.Line, in lines: [RepositoryDiff.Line]) -> (isOn: Bool, toggle: () -> Void)? {
        guard choosesLines, line.kind == .hunk else { return nil }
        let ids = changeLineIDs(ofHunkStartingAt: line.id, in: lines)
        guard !ids.isEmpty else { return nil }
        let allChosen = ids.isSubset(of: chosenLineIDs)
        return (allChosen, {
            if allChosen { chosenLineIDs.subtract(ids) } else { chosenLineIDs.formUnion(ids) }
            lastToggledLineID = nil
        })
    }

    /// Shift-click ticks or unticks every change line between the last toggled line and this one.
    private func toggle(_ lineID: Int) {
        let turningOn = !chosenLineIDs.contains(lineID)
        let isRange = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        if isRange, let lastToggledLineID, case .text(let lines) = section.content {
            let range = min(lastToggledLineID, lineID)...max(lastToggledLineID, lineID)
            let ids = lines.filter { range.contains($0.id) && ($0.kind == .addition || $0.kind == .deletion) }.map(\.id)
            if turningOn { chosenLineIDs.formUnion(ids) } else { chosenLineIDs.subtract(ids) }
        } else if turningOn {
            chosenLineIDs.insert(lineID)
        } else {
            chosenLineIDs.remove(lineID)
        }
        lastToggledLineID = lineID
    }

    private func changeLineIDs(ofHunkStartingAt hunkID: Int, in lines: [RepositoryDiff.Line]) -> Set<Int> {
        guard let start = lines.firstIndex(where: { $0.id == hunkID }) else { return [] }
        let end = lines[(start + 1)...].firstIndex { $0.kind == .hunk } ?? lines.endIndex
        return Set(lines[(start + 1)..<end].filter { $0.kind == .addition || $0.kind == .deletion }.map(\.id))
    }
}

/// Text diff lines in either layout. `hunkAction` returns a button for hunk header lines that can be staged.
private struct RepositoryDiffLinesView: View {
    let lines: [RepositoryDiff.Line]
    let layout: RepositoryDiffLayout
    var isBusy = false
    var hunkAction: (RepositoryDiff.Line) -> (label: String, perform: () -> Void)? = { _ in nil }
    /// A second, destructive button on the hunk header (Discard…); it asks before acting.
    var hunkSecondaryAction: (RepositoryDiff.Line) -> (label: String, perform: () -> Void)? = { _ in nil }
    /// A gutter checkbox for an addition or deletion line, and one on the hunk header for all of its lines.
    var lineChoice: (RepositoryDiff.Line) -> (isOn: Bool, toggle: () -> Void)? = { _ in nil }
    var hunkChoice: (RepositoryDiff.Line) -> (isOn: Bool, toggle: () -> Void)? = { _ in nil }
    /// Keeps the checkbox column on every unified line so numbers line up whether or not a line has one.
    var reservesChoiceColumn = false
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        let lines = lines.filter { !$0.isPatchHeader }
        let numberWidth = diffNumberWidth(for: lines, fontSize: theme.metrics.diffFontSize)
        switch layout {
        case .unified:
            ForEach(lines) { line in
                fullWidthLine(line, numberWidth: numberWidth)
            }
        case .split:
            ForEach(RepositoryDiffSplitRow.rows(from: lines)) { row in
                if let full = row.full {
                    fullWidthLine(full, numberWidth: numberWidth)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        RepositoryDiffLineView(
                            line: row.old,
                            side: .old,
                            numberWidth: numberWidth,
                            choice: row.old.flatMap(lineChoice),
                            reservesChoiceColumn: reservesChoiceColumn,
                            choiceLabel: "Choose deleted line \(row.old?.oldLineNumber ?? 0)"
                        )
                        Divider()
                        RepositoryDiffLineView(
                            line: row.new,
                            side: .new,
                            numberWidth: numberWidth,
                            choice: row.new.flatMap(lineChoice),
                            reservesChoiceColumn: reservesChoiceColumn,
                            choiceLabel: "Choose added line \(row.new?.newLineNumber ?? 0)"
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fullWidthLine(_ line: RepositoryDiff.Line, numberWidth: CGFloat) -> some View {
        if let action = hunkAction(line) {
            HStack(spacing: 8) {
                RepositoryDiffLineView(
                    line: line,
                    fillsWidth: false,
                    singleNumberColumn: layout == .split,
                    numberWidth: numberWidth,
                    choice: hunkChoice(line),
                    reservesChoiceColumn: reservesChoiceColumn,
                    choiceLabel: "Choose every line in this hunk",
                    overrideText: line.hunkLocation,
                    truncatesText: layout == .split
                )
                if line.hunkLocation != nil {
                    // The raw header stays for readers who know it, quiet enough not to lead.
                    Text(line.text)
                        .font(.system(size: theme.metrics.diffFontSize - 1, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Button(action.label, action: action.perform)
                    .controlSize(.small)
                    .disabled(isBusy)
                    .help("\(action.label) without changing the working tree file")
                    .accessibilityHint("Update only these lines in the Git index")
                if let secondary = hunkSecondaryAction(line) {
                    Button(secondary.label, role: .destructive, action: secondary.perform)
                        .controlSize(.small)
                        .disabled(isBusy)
                        .help("Rewrite the file on disk without these changes; asks first")
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.diffHunkBackground)
        } else {
            RepositoryDiffLineView(
                line: line,
                singleNumberColumn: layout == .split,
                numberWidth: numberWidth,
                choice: lineChoice(line),
                reservesChoiceColumn: reservesChoiceColumn,
                choiceLabel: line.kind == .deletion
                    ? "Choose deleted line \(line.oldLineNumber ?? 0)"
                    : "Choose added line \(line.newLineNumber ?? 0)",
                truncatesText: layout == .split
            )
        }
    }
}

/// Width of a diff's line-number column: exactly as wide as its largest line number, so a six-digit file is
/// never truncated and a short file is not padded out to a fixed five digits. One value per diff keeps every
/// row, and both halves of the split layout, on the same gutter.
func diffNumberWidth(for lines: [RepositoryDiff.Line], fontSize: CGFloat) -> CGFloat {
    let largest = lines.reduce(0) { max($0, $1.oldLineNumber ?? 0, $1.newLineNumber ?? 0) }
    let digits = max(2, String(largest).count)
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    return (CGFloat(digits) * font.maximumAdvancement.width).rounded(.up)
}

private struct RepositoryDiffLineView: View {
    enum Side {
        case old
        case new
    }

    /// nil draws an empty cell opposite an unpaired change in the split layout.
    let line: RepositoryDiff.Line?
    /// nil is the unified layout with both line numbers; a side shows only its own number and wraps long lines.
    var side: Side? = nil
    var fillsWidth = true
    /// Split's full-width rows are metadata and hunk headers, which carry no line number. One empty number
    /// column instead of two lines their text up with the code in the halves beside them.
    var singleNumberColumn = false
    /// Shared by every row of one diff; see `diffNumberWidth(for:fontSize:)`.
    var numberWidth: CGFloat
    /// A gutter checkbox that picks this line for a partial stage or unstage.
    var choice: (isOn: Bool, toggle: () -> Void)? = nil
    var reservesChoiceColumn = false
    var choiceLabel = ""
    /// Replaces the line's own text; the hunk header uses it to show a location instead of `@@ …`.
    var overrideText: String? = nil
    /// Split clamps the diff to the pane's width, so a full-width row has no horizontal scroll to spill into:
    /// it truncates instead of drawing over the row beside it. Unified keeps its rigid width and scrolls.
    var truncatesText = false
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if reservesChoiceColumn {
                Group {
                    if let choice {
                        Toggle(choiceLabel, isOn: Binding(get: { choice.isOn }, set: { _ in choice.toggle() }))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .controlSize(.small)
                            .accessibilityLabel(choiceLabel)
                            .help("Tick lines, then use the hunk button. Shift-click ticks a range")
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 18, height: 14)
                .padding(.leading, 2)
            }
            if side != .new, !singleNumberColumn {
                Text(line?.oldLineNumber.map(String.init) ?? "")
                    .frame(width: numberWidth, alignment: .trailing)
                    .padding(.trailing, side == nil ? 6 : 8)
            }
            if side != .old {
                Text(line?.newLineNumber.map(String.init) ?? "")
                    .frame(width: numberWidth, alignment: .trailing)
                    .padding(.trailing, 8)
            }
            let shown = overrideText ?? line.map { $0.displayText.isEmpty ? " " : $0.displayText } ?? " "
            if side == nil, truncatesText {
                Text(shown)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if side == nil {
                Text(shown)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Text(shown)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, theme.metrics.diffChangeBarWidth)
        .font(.system(size: theme.metrics.diffFontSize, design: .monospaced))
        .foregroundStyle(foregroundColor)
        .frame(minWidth: 0, maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .background(backgroundColor)
        .overlay(alignment: .leading) {
            if theme.metrics.diffChangeBarWidth > 0, let changeBarColor {
                changeBarColor.frame(width: theme.metrics.diffChangeBarWidth)
            }
        }
        .accessibilityElement(children: choice == nil ? .ignore : .contain)
        .accessibilityLabel(line?.accessibilityLabel ?? "")
        .accessibilityHidden(line == nil)
    }

    private var foregroundColor: Color {
        switch line?.kind {
        case .metadata: theme.colors.diffMetadataText
        case .hunk: theme.colors.diffHunkText
        case .context, .addition, .deletion, nil: theme.colors.diffText
        }
    }

    private var backgroundColor: Color {
        switch line?.kind {
        case .addition: theme.colors.diffAdditionBackground
        case .deletion: theme.colors.diffDeletionBackground
        case .hunk: theme.colors.diffHunkBackground
        case .metadata, .context: .clear
        case nil: theme.colors.badgeBackground.opacity(0.5)
        }
    }

    private var changeBarColor: Color? {
        switch line?.kind {
        case .addition: theme.colors.statusAdded
        case .deletion: theme.colors.statusDeleted
        default: nil
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


private extension RepositoryDiff {
    var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
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

        // The kind is already spoken, so the patch prefix would only repeat it; a hunk says where it is.
        let spoken = hunkLocation ?? displayText
        return location.isEmpty ? "\(kindLabel): \(spoken)" : "\(kindLabel), \(location): \(spoken)"
    }
}
