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

    var systemImage: String {
        switch self {
        case .changes: "list.bullet"
        case .history: "clock"
        case .stashes: "archivebox"
        case .reflog: "arrow.uturn.backward"
        }
    }
}

/// Two panes with a draggable divider, laid out by SwiftUI so the detail column never carries a hard minimum
/// width. `HSplitView` is NSSplitView underneath, and macOS's `NavigationSplitView` counts the sidebar width into
/// its detail minimum twice: with a hard minimum the window grows when the Navigator opens, and with a minimum plus
/// ideal the trailing pane stops short of the window once the sidebar passes half the free width. With no minimum a
/// narrow container squeezes the panes instead: the leading pane yields to its minimum first, then both shrink.
struct ResizableHSplit<Leading: View, Trailing: View>: View {
    let leadingMinimum: CGFloat
    let leadingMaximum: CGFloat?
    let trailingMinimum: CGFloat
    private let leading: () -> Leading
    private let trailing: () -> Trailing
    @SceneStorage private var leadingWidth: Double
    @State private var dragStartWidth: CGFloat?

    init(
        leadingMinimum: CGFloat,
        leadingIdeal: CGFloat,
        leadingMaximum: CGFloat? = nil,
        trailingMinimum: CGFloat,
        storageKey: String,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.leadingMinimum = leadingMinimum
        self.leadingMaximum = leadingMaximum
        self.trailingMinimum = trailingMinimum
        self.leading = leading
        self.trailing = trailing
        _leadingWidth = SceneStorage(wrappedValue: Double(leadingIdeal), "resizableSplit.\(storageKey).leadingWidth")
    }

    var body: some View {
        GeometryReader { proxy in
            let width = ResizableHSplitLayout.leadingWidth(
                preferred: CGFloat(leadingWidth),
                leadingMinimum: leadingMinimum,
                leadingMaximum: leadingMaximum,
                trailingMinimum: trailingMinimum,
                total: proxy.size.width
            )
            HStack(spacing: 0) {
                leading()
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .clipped()

                Divider()
                    .overlay {
                        Color.clear
                            .frame(width: 9)
                            .contentShape(.rect)
                            .onHover { inside in
                                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                            }
                            .gesture(
                                // Global coordinates: the divider moves with the drag, so a local translation
                                // would shift with it and the panes would oscillate.
                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { value in
                                        let start = dragStartWidth ?? width
                                        dragStartWidth = start
                                        leadingWidth = Double(ResizableHSplitLayout.leadingWidth(
                                            preferred: start + value.translation.width,
                                            leadingMinimum: leadingMinimum,
                                            leadingMaximum: leadingMaximum,
                                            trailingMinimum: trailingMinimum,
                                            total: proxy.size.width
                                        ))
                                    }
                                    .onEnded { _ in dragStartWidth = nil }
                            )
                    }
                    .accessibilityHidden(true)

                trailing()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
    }
}

/// Keeps the sidebar within `maximum`. `navigationSplitViewColumnWidth(max:)` binds programmatic positions only:
/// the split view item's maximum thickness is kept set so drags stop there, and a wider frame AppKit restores at
/// launch is moved back once the view attaches.
private struct SidebarWidthClamp: NSViewRepresentable {
    let maximum: CGFloat
    let generation: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ClampView {
        let view = ClampView(frame: .zero)
        view.maximum = maximum
        return view
    }

    func updateNSView(_ view: ClampView, context: Context) {
        view.maximum = maximum
        guard context.coordinator.handledGeneration != generation else { return }
        context.coordinator.handledGeneration = generation
        view.clampSoon()
    }

    final class Coordinator { var handledGeneration = 0 }

    /// Clamps once attached, for the frame AppKit restores at launch, and whenever asked after a drag.
    final class ClampView: NSView {
        var maximum: CGFloat = .infinity
        private var thicknessObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { clampSoon() }
        }

        func clampSoon() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.clampIfNeeded() }
        }

        private func clampIfNeeded() {
            var candidate = superview
            while let current = candidate, !(current is NSSplitView) { candidate = current.superview }
            guard let splitView = candidate as? NSSplitView, let sidebar = splitView.arrangedSubviews.first else { return }
            // SwiftUI leaves the item's maximum thickness unset and clears it again on its updates, so the value
            // is put back whenever it changes; the controller then stops drags at the maximum.
            if thicknessObservation == nil, let controller = splitView.delegate as? NSSplitViewController,
               let item = controller.splitViewItems.first {
                let maximum = self.maximum
                // AppKit changes the item on the main thread; the guard ends the re-entrant notification.
                nonisolated(unsafe) let boundItem = item
                thicknessObservation = item.observe(\.maximumThickness, options: [.initial, .new]) { _, _ in
                    MainActor.assumeIsolated {
                        guard boundItem.maximumThickness != maximum else { return }
                        boundItem.maximumThickness = maximum
                    }
                }
            }
            guard sidebar.frame.width > maximum else { return }
            splitView.setPosition(maximum, ofDividerAt: 0)
        }
    }
}

/// With the system's always-visible scroll bars a list's rows end a scroller's width before the pane edge. Headers
/// above a list take the same inset, and the list keeps its scroller shown so the two never drift apart.
private enum LegacyScrollerStyle {
    static var isLegacy: Bool { NSScroller.preferredScrollerStyle == .legacy }
    static var width: CGFloat { isLegacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0 }
}

private struct ListHeaderInset: ViewModifier {
    @State private var inset = LegacyScrollerStyle.width

    func body(content: Content) -> some View {
        content
            .padding(.trailing, inset)
            .onReceive(NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)) { _ in
                inset = LegacyScrollerStyle.width
            }
    }
}

private struct ListScrollerPolicy: NSViewRepresentable {
    func makeNSView(context: Context) -> PolicyView { PolicyView(frame: .zero) }
    func updateNSView(_ view: PolicyView, context: Context) {}

    final class PolicyView: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            apply()
            observer = observer ?? NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.apply() }
        }

        /// The list's scroll view is the smallest one under the window that contains this view's center.
        private func apply() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let root = self.window?.contentView else { return }
                let center = self.convert(CGPoint(x: self.bounds.midX, y: self.bounds.midY), to: nil)
                let candidates = Self.scrollViews(in: root).filter { $0.convert($0.bounds, to: nil).contains(center) }
                guard let scrollView = candidates.min(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { return }
                scrollView.autohidesScrollers = !LegacyScrollerStyle.isLegacy
            }
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            view.subviews.flatMap { ($0 as? NSScrollView).map { [$0] } ?? scrollViews(in: $0) }
        }
    }
}

extension View {
    /// For a header above a list, so its trailing content lines up with the rows beside a legacy scroller.
    func listHeaderInset() -> some View { modifier(ListHeaderInset()) }
    /// For a list with a header above it; see `ListHeaderInset`.
    func legacyScrollerAware() -> some View { background(ListScrollerPolicy()) }
}

enum ResizableHSplitLayout {
    static let dividerWidth: CGFloat = 1

    /// The leading pane's width in a container `total` points wide: the preferred width while both minimums fit,
    /// else the leading pane yields down to its minimum, else both panes shrink in the ratio of their minimums.
    static func leadingWidth(
        preferred: CGFloat,
        leadingMinimum: CGFloat,
        leadingMaximum: CGFloat?,
        trailingMinimum: CGFloat,
        total: CGFloat
    ) -> CGFloat {
        // Whole points only: a lazy stack proposed a fractional width such as 940.8 falls back to its
        // intrinsic width for that frame, so the diff flickered between narrow and full while dragging.
        let available = max(total - dividerWidth, 0).rounded(.down)
        let clamped = min(max(preferred, leadingMinimum), leadingMaximum ?? .infinity).rounded()
        if clamped + trailingMinimum <= available { return clamped }
        let yielded = available - trailingMinimum
        if yielded >= leadingMinimum { return yielded }
        return (available * leadingMinimum / (leadingMinimum + trailingMinimum)).rounded(.down)
    }
}

/// What History is narrowed to: one branch, remote, remote branch, or tag chosen in the Navigator's scope list.
/// The screen (Changes, History, Stashes, Reflog) is the other axis and lives in `RepositoryWorkspaceSection`.
enum RepositoryHistoryScope: Hashable {
    case branch(String)
    case remote(String)
    /// Remote-tracking name such as `origin/main`.
    case remoteBranch(String)
    case tag(String)

    var name: String {
        switch self {
        case .branch(let name), .remote(let name), .remoteBranch(let name), .tag(let name): name
        }
    }

    var kind: String {
        switch self {
        case .branch: "Local branch"
        case .remote: "Remote"
        case .remoteBranch: "Remote branch"
        case .tag: "Tag"
        }
    }

    var systemImage: String {
        switch self {
        case .branch, .remoteBranch: "arrow.triangle.branch"
        case .remote: "network"
        case .tag: "tag"
        }
    }

    /// Fully qualified so a tag and a branch sharing a name never resolve to each other; a remote reads every
    /// branch it tracks.
    var historyReference: String {
        switch self {
        case .branch(let name): "refs/heads/\(name)"
        case .tag(let name): "refs/tags/\(name)"
        case .remoteBranch(let name): "refs/remotes/\(name)"
        case .remote(let name): "--remotes=\(name)/"
        }
    }

    /// The remote this scope belongs to, if any.
    var remoteName: String? {
        switch self {
        case .remote(let name): name
        case .remoteBranch(let name): name.split(separator: "/", maxSplits: 1).first.map(String.init)
        case .branch, .tag: nil
        }
    }
}

/// The context bar's location label when the Navigator is folded: the screen, and for History its scope.
struct RepositoryNavigatorLocation {
    var screen: RepositoryWorkspaceSection
    var scope: RepositoryHistoryScope?

    var title: String {
        if screen == .history, let scope { "\(scope.name) · \(scope.kind)" } else { screen.title }
    }

    var systemImage: String {
        if screen == .history, let scope { scope.systemImage } else { screen.systemImage }
    }
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
    /// The Navigator's scope axis; the screen axis is `workspaceSection`. Choosing a scope shows History.
    @State private var scope: RepositoryHistoryScope?
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

    var body: some View {
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
                        RepositoryHistoryView(model: model, scope: scope)
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
            await model.loadLocalBranches()
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
        .onChange(of: model.repository?.rootURL, initial: true) {
            commitSubject = ""
            commitBody = ""
            isAmending = false
            amendPrefill = nil
            isConfirmingOperationAbort = false
            selectedChangeIDs = model.selectedChangeID.map { [$0] } ?? []
            // The scope belonged to the previous Repository; the remembered screen stays.
            scope = nil
            if model.repository?.changes.isEmpty == true, workspaceSection == .changes {
                workspaceSection = .history
            }
        }
        .onChange(of: workspaceSection) { _, _ in
            isNavigatorPanelPresented = false
        }
        .onChange(of: scope, initial: true) { _, scope in
            model.historyReference = scope?.historyReference
            isNavigatorPanelPresented = false
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
                        Label(repository.head.label, systemImage: repository.head.systemImage)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(.callout.weight(.medium))
                    .help("Switch, create, or integrate local branches")
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
        if case .loaded(let branches) = model.localBranchesState {
            let otherBranches = branches.filter { $0 != currentBranch }
            if !otherBranches.isEmpty {
                Section("Switch To") {
                    ForEach(otherBranches, id: \.self) { branch in
                        if let worktreeURL = model.localBranchWorktreeURLs[branch] {
                            Button(branch, systemImage: "folder") {
                                Task { _ = await model.openRepository(at: worktreeURL) }
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
        RepositoryNavigatorView(model: model, screen: $workspaceSection, scope: $scope)
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

            RepositoryNavigatorView(model: model, screen: $workspaceSection, scope: $scope, isFloating: true)
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

    /// Choosing a screen drops the scope, so History from the screen list is always the whole Repository and the
    /// scope list never shows a branch the body isn't about.
    private func show(_ section: RepositoryWorkspaceSection) {
        workspaceSection = section
        scope = nil
    }

    /// Checked while History shows this scope; choosing it shows History.
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

private struct RepositoryNavigatorView: View {
    @Bindable var model: AppModel
    /// The screen axis: which of Changes, History, Stashes, Reflog fills the body. Always set.
    @Binding var screen: RepositoryWorkspaceSection
    /// The scope axis: the branch, remote, remote branch, or tag History is narrowed to. Choosing one shows History.
    @Binding var scope: RepositoryHistoryScope?
    /// Inside the floating panel the panel paints the background, so the list stays transparent.
    var isFloating = false
    @Environment(\.gallaeTheme) private var theme
    @FocusState private var isScreenListFocused: Bool
    @State private var filterText = ""
    @State private var branches: [String] = []
    @State private var remoteBranches: [String: [String]] = [:]
    @State private var expandedRemotes: Set<String> = []
    @State private var pendingWorktreeRemoval: WorktreeRemovalRequest?
    @State private var pendingBranchDeletion: String?
    @State private var pendingRemoteBranchDeletion: String?
    @State private var pendingTrackingReferenceRemoval: String?
    @State private var pendingRemoteRemoval: String?
    @State private var removalErrorMessage: String?
    @State private var editedRemote: RepositoryRemote?
    @State private var isCreatingBranch = false

    var body: some View {
        VStack(spacing: 0) {
            // Two lists, two selections: the screen list keeps its selection while a scope is chosen, and macOS
            // draws the list without keyboard focus in gray. The screen list is four rows, so it is a plain stack
            // that takes focus itself rather than a List sized by guesswork.
            screenList

            Divider()
                .padding(.horizontal, 10)

            List(selection: scopeSelection) {
                Section {
                    branchRows
                } header: {
                    HStack {
                        Text("Branches")
                        Spacer()
                        // A 22pt target a little in from the edge; the glyph alone was too small to hit.
                        Button {
                            isCreatingBranch = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                        .help("New Branch…")
                        .accessibilityLabel("New Branch")
                        .disabled(model.isLoading || model.isSyncing || model.repository == nil)
                    }
                }

                Section("Remotes") {
                    remoteRows
                }

                Section("Tags") {
                    tagRows
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(theme.materials.translucentChrome && !isFloating ? .automatic : .hidden)
            .accessibilityLabel("Navigator")

            Divider()

            TextField("Filter", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(8)
                .accessibilityLabel("Filter Branches, Remotes, and Tags")
        }
        // Reduced Transparency and Increased Contrast paint the sidebar opaque instead of the system material.
        .background(theme.materials.translucentChrome || isFloating ? Color.clear : theme.colors.opaqueChrome)
        .task(id: model.repositoryRevision) {
            guard let rootURL = model.repository?.rootURL else { return }
            await model.loadRemotes(in: rootURL)
            await model.loadTags()
            await model.loadStashes()
        }
        .onChange(of: model.localBranchesState, initial: true) { _, state in
            // ponytail: keep the last loaded list while a reload is in flight so the sidebar never blinks.
            guard case .loaded(let loaded) = state else { return }
            branches = loaded
            if case .branch(let branch) = scope, !loaded.contains(branch) {
                scope = nil
            }
        }
        .onChange(of: model.remotesState, initial: true) { _, state in
            guard case .loaded(let remotes) = state else { return }
            for remote in remotes where remoteBranches[remote.name] == nil {
                expandedRemotes.insert(remote.name)
            }
            if let remoteName = scope?.remoteName, !remotes.contains(where: { $0.name == remoteName }) {
                scope = nil
            }
        }
        .onChange(of: model.tagsState) { _, state in
            guard case .loaded(let tags) = state, case .tag(let name) = scope else { return }
            if !tags.contains(name) {
                scope = nil
            }
        }
        .onChange(of: model.repository?.rootURL) { _, _ in
            branches = []
            remoteBranches = [:]
            expandedRemotes = []
            filterText = ""
        }
        .sheet(isPresented: $isCreatingBranch) {
            CreateBranchSheet(model: model)
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
        let isActive = isSelected && isScreenListFocused
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
                    .fill(isActive ? Color.accentColor : isSelected ? Color.secondary.opacity(0.25) : .clear)
            )
            .foregroundStyle(isActive ? .white : .primary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("\(section.title) (⌘\(section.rawValue + 1))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(badge > 0 ? "\(section.title), \(badge)" : section.title)
    }

    /// Choosing a screen drops the scope: the two selections never disagree about what the body shows.
    private func show(_ section: RepositoryWorkspaceSection) {
        screen = section
        scope = nil
    }

    // MARK: - Scope list

    /// Setting a scope also shows History, the only screen that reads it.
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
        if branches.isEmpty {
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
                    .foregroundStyle(Color.accentColor)
                    .fixedSize()
            } else if let worktreeURL {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help(worktreeURL.path)
            }
        }
        .contentShape(.rect)
        .tag(RepositoryHistoryScope.branch(branch))
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
            if !isCurrent {
                if let worktreeURL {
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

                Button("Integrate…", systemImage: "arrow.triangle.merge") {
                    model.showIntegrateBranch(preselecting: branch)
                }
                .disabled(!model.canIntegrateBranch || model.isLoading || model.isSyncing)

                Divider()

                if let worktreeURL {
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
                    .disabled(model.isLoading)
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
                get: { expandedRemotes.contains(name) },
                set: { if $0 { expandedRemotes.insert(name) } else { expandedRemotes.remove(name) } }
            )
        ) {
            ForEach(filtered(remoteBranches[name] ?? []), id: \.self) { branch in
                Label(branch.hasPrefix("\(name)/") ? String(branch.dropFirst(name.count + 1)) : branch,
                      systemImage: "arrow.triangle.branch")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(branch)
                    .contentShape(.rect)
                    .tag(RepositoryHistoryScope.remoteBranch(branch))
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
                .badge(remoteBranches[name]?.count ?? 0)
                .help(fetchURL)
                .contentShape(.rect)
                .tag(RepositoryHistoryScope.remote(name))
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
        .task(id: "\(model.repositoryRevision):\(name)") {
            guard let loaded = try? await model.remoteBranches(of: name), !Task.isCancelled else { return }
            remoteBranches[name] = loaded
            if case .remoteBranch(let branch) = scope, branch.hasPrefix("\(name)/"), !loaded.contains(branch) {
                scope = .remote(name)
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
                        .tag(RepositoryHistoryScope.tag(tag))
                }
            }
        }
    }

    private var filteredBranches: [String] {
        filtered(branches)
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

    /// Switching or opening a Worktree changes HEAD only; the screen and the scope stay where they were.
    private func performPrimaryAction(for branch: String) {
        guard branch != currentBranch, !model.isLoading, !model.isSyncing else { return }
        Task {
            if let worktreeURL = model.localBranchWorktreeURLs[branch] {
                _ = await model.openRepository(at: worktreeURL)
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

private struct CreateBranchSheet: View {
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
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
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
    let trackingRef: String?

    var confirmationMessage: String {
        var message = "This removes the Worktree folder at \(worktreeURL.path); git keeps it if changes or an operation remain inside. Removing the branch is a safe delete that keeps unmerged branches."
        if let trackingRef {
            message += " Deleting \(trackingRef) also removes it on the remote for everyone using it."
        }
        return message
    }
}

private struct RepositoryHistoryView: View {
    @Bindable var model: AppModel
    /// History of every ref, or the log of the scope chosen in the Navigator.
    var scope: RepositoryHistoryScope?
    @State private var editedRemote: RepositoryRemote?
    @Environment(\.gallaeTheme) private var theme
    @State private var searchText = ""
    @State private var isCreatingBranch = false
    @State private var pendingWorktreeRemoval: WorktreeRemovalRequest?
    @State private var pendingBranchDeletion: String?
    @State private var pendingRemoteBranchDeletion: String?
    @State private var pendingTrackingReferenceRemoval: String?

    var body: some View {
        ResizableHSplit(
            leadingMinimum: theme.metrics.changeListMinimumWidth,
            leadingIdeal: theme.metrics.changeListIdealWidth,
            trailingMinimum: 400,
            storageKey: "history"
        ) {
            VStack(spacing: 0) {
                VStack(spacing: 7) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(headerTitle)
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.middle)
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
        } trailing: {
            RepositoryCommitDetailView(model: model)
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
            switch scope {
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

    private var headerTitle: String {
        scope?.name ?? "History"
    }

    private var headerSubtitle: String {
        switch scope {
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
            "Branches & Tags · latest 100"
        }
    }

    /// Switch, Open Worktree, and Integrate for a branch; New Branch… for a tag or remote branch; Fetch, Fetch &
    /// Prune, and Edit… for a remote. Removing a remote lives in its context menu and the Edit… sheet.
    @ViewBuilder
    private var headerTools: some View {
        let isBusy = model.isLoading || model.isSyncing
        switch scope {
        case .branch(let name) where name != currentBranchName:
            if let worktreeURL = model.localBranchWorktreeURLs[name] {
                Button("Open Worktree") {
                    Task { _ = await model.openRepository(at: worktreeURL) }
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
                        .listRowInsets(.init(top: 0, leading: 12, bottom: 0, trailing: 12))
                    }
                    .listStyle(.plain)
                .legacyScrollerAware()
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

/// Confirmations for the two destructive remote-branch actions, shared by History rows and the remote screen.
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

private extension View {
    func remoteBranchDialogs(
        model: AppModel,
        deletion: Binding<String?>,
        trackingRemoval: Binding<String?>
    ) -> some View {
        modifier(RemoteBranchDialogs(model: model, deletion: deletion, trackingRemoval: trackingRemoval))
    }
}

private struct RepositoryStashesView: View {
    @Bindable var model: AppModel
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
                .legacyScrollerAware()
            .accessibilityLabel("Stashes, \(stashes.count) items")
        }
    }
}

private struct RepositoryReflogView: View {
    @Bindable var model: AppModel
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
                    .listRowInsets(.init(top: 0, leading: 12, bottom: 0, trailing: 12))
            }
            .listStyle(.plain)
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
    var requestRemoteBranchDeletion: (String) -> Void = { _ in }
    var requestTrackingReferenceRemoval: (String) -> Void = { _ in }

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
            .padding(.vertical, theme.metrics.rowVerticalPadding)

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
            // ponytail: regular-size buttons plus the author badge exceed the 400pt detail minimum by a few points.
            .controlSize(.small)
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
    @AppStorage(RepositoryDiffLayout.storageKey) private var layout = RepositoryDiffLayout.unified
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
        ResizableHSplit(leadingMinimum: 160, leadingIdeal: 200, leadingMaximum: 280, trailingMinimum: 230, storageKey: "revisionFiles") {
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
                        .listRowInsets(.init(
                            top: theme.metrics.rowVerticalPadding,
                            leading: 12,
                            bottom: theme.metrics.rowVerticalPadding,
                            trailing: 12
                        ))
                }
                .listStyle(.plain)
                .legacyScrollerAware()
                .accessibilityLabel("Changed Files, \(files.count) files")
            }
        } trailing: {
            VStack(spacing: 0) {
                if let file = selectedFile {
                    HStack(alignment: .center, spacing: 12) {
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

                        RepositoryDiffLayoutPicker()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()
                }

                revisionPatchContent
            }
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

                RepositoryDiffLayoutPicker()

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
                let shown = shownScope(in: diff)
                if let other = otherScope(in: diff, than: shown) {
                    scopeSwitcher(in: diff, shown: shown, other: other)
                    Divider()
                }
                GeometryReader { proxy in
                    ScrollView(layout == .split ? [.vertical] : [.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if let section = diff.sections.first(where: { $0.scope == shown }) {
                                RepositoryDiffSectionView(
                                    section: section,
                                    layout: layout,
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
                            maxWidth: layout == .split ? proxy.size.width.rounded(.down) : nil,
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

/// The Unified/Split toggle in diff headers; the last choice is remembered across files and windows.
private struct RepositoryDiffLayoutPicker: View {
    @AppStorage(RepositoryDiffLayout.storageKey) private var layout = RepositoryDiffLayout.unified

    var body: some View {
        Picker("Diff Layout", selection: $layout) {
            ForEach(RepositoryDiffLayout.allCases) { layout in
                Text(layout.title).tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help("Show the diff in one column, or the old and new versions side by side")
        .accessibilityLabel("Diff Layout")
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
                    reservesChoiceColumn: choosesLines,
                    isOneSided: section.isOneSided
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
    /// A new or deleted file has no opposite version, so Split draws one column rather than half a screen
    /// of empty cells.
    var isOneSided = false
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
                } else if isOneSided {
                    let only = row.new ?? row.old
                    RepositoryDiffLineView(
                        line: only,
                        side: row.new != nil ? .new : .old,
                        numberWidth: numberWidth,
                        choice: only.flatMap(lineChoice),
                        reservesChoiceColumn: reservesChoiceColumn,
                        choiceLabel: row.new != nil
                            ? "Choose added line \(row.new?.newLineNumber ?? 0)"
                            : "Choose deleted line \(row.old?.oldLineNumber ?? 0)"
                    )
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

        // The kind is already spoken, so the patch prefix would only repeat it; a hunk says where it is.
        let spoken = hunkLocation ?? displayText
        return location.isEmpty ? "\(kindLabel): \(spoken)" : "\(kindLabel), \(location): \(spoken)"
    }
}
