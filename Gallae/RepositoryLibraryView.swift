import Observation
import SwiftUI

struct RepositoryLibraryView: View {
    @Bindable var model: AppModel
    let chooseFolder: () -> Void
    let chooseLibraryFolder: () -> Void
    let reconnectLibraryFolder: (URL) -> Void
    let reconnectRepository: (URL) -> Void
    @Binding var expandedHierarchyFolderIDs: Set<URL>
    @State private var selectedHierarchyNodeID: URL?
    @FocusState private var isRepositoryListFocused: Bool
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            HSplitView {
                libraryFolderColumn
                    .frame(
                        minWidth: theme.metrics.libraryFolderMinimumWidth,
                        idealWidth: theme.metrics.libraryFolderIdealWidth,
                        maxWidth: theme.metrics.libraryFolderMaximumWidth
                    )
                    .frame(height: proxy.size.height)

                if isLibraryEmpty {
                    libraryWelcome
                        .frame(
                            minWidth: theme.metrics.repositoryListMinimumWidth
                                + theme.metrics.repositorySummaryMinimumWidth,
                            maxWidth: .infinity
                        )
                        .frame(height: proxy.size.height)
                        .layoutPriority(1)
                } else {
                    repositoryColumn
                        .frame(
                            minWidth: theme.metrics.repositoryListMinimumWidth,
                            idealWidth: theme.metrics.repositoryListIdealWidth
                        )
                        .frame(height: proxy.size.height)
                        .layoutPriority(1)

                    repositorySummaryColumn
                        .frame(
                            minWidth: theme.metrics.repositorySummaryMinimumWidth,
                            idealWidth: theme.metrics.repositorySummaryIdealWidth,
                            maxWidth: theme.metrics.repositorySummaryMaximumWidth
                        )
                        .frame(height: proxy.size.height)
                }
            }
        }
        .task(id: selectedSummary?.rootURL) {
            guard let id = model.selectedLibraryRepositoryID else { return }
            await model.loadLibraryRepositoryActivity(at: id)
        }
        .onChange(of: model.selectedLibraryFolderID) {
            selectedHierarchyNodeID = model.selectedLibraryRepositoryID
        }
        .onChange(of: model.selectedLibraryRepositoryID) {
            selectedHierarchyNodeID = model.selectedLibraryRepositoryID
        }
        .task {
            selectedHierarchyNodeID = nil
            await Task.yield()
            selectedHierarchyNodeID = model.selectedLibraryRepositoryID
            isRepositoryListFocused = model.selectedLibraryRepositoryID != nil
        }
    }

    private var libraryFolderColumn: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .font(.headline)
                    Text("Recent and folders")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            List(
                selection: Binding(
                    get: { model.selectedLibrarySource },
                    set: { source in model.selectLibrarySource(source) }
                )
            ) {
                Section {
                    HStack {
                        Label("Recent", systemImage: "clock")
                        Spacer()
                        Text(model.recentRepositories.count, format: .number)
                            .foregroundStyle(.secondary)
                    }
                    .tag(RepositoryLibrarySource.recent)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Recent Repositories, \(model.recentRepositories.count)")
                }

                Section("Library Folders") {
                    ForEach(model.libraryFolders) { folder in
                        LibraryFolderRow(folder: folder)
                            .tag(RepositoryLibrarySource.folder(folder.id))
                            .contextMenu {
                                Button(
                                    "Remove \(folder.name) from Library",
                                    systemImage: "folder.badge.minus",
                                    role: .destructive
                                ) {
                                    model.removeLibraryFolder(folder.id)
                                }
                                .accessibilityHint(
                                    "Remove this saved Library Folder without changing files on disk"
                                )
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel(
                "Repository Library, \(model.recentRepositories.count) recent Repositories, \(model.libraryFolders.count) folders"
            )

            if let folder = model.selectedLibraryFolder {
                Divider()
                scanStatus(for: folder)
                    .padding(10)
            }
        }
    }

    private var libraryWelcome: some View {
        ContentUnavailableView {
            Label("Start with a Repository", systemImage: "folder.badge.plus")
        } description: {
            Text("Choose a Repository to open it, or a parent folder to add it to the Library.")
        } actions: {
            Button("Choose Folder…", action: chooseFolder)
                .buttonStyle(.borderedProminent)
                .accessibilityHint(
                    "Open a Git Repository, or add the selected folder to the Library"
                )
        }
    }

    @ViewBuilder
    private func scanStatus(for folder: RepositoryLibraryFolder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                switch folder.scanState {
                case .idle:
                    Text("Not scanned")
                        .foregroundStyle(.secondary)
                case .scanning:
                    Text("Scanning · \(folder.repositories.count) found")
                case .completed:
                    Text("\(folder.repositories.count) Repositories")
                case .cancelled:
                    Text("Stopped · \(folder.repositories.count) found")
                case .failed:
                    Label("Scan Failed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(theme.colors.statusConflict)
                }

                Spacer(minLength: 8)

                Menu {
                    Button(
                        "Remove \(folder.name) from Library",
                        systemImage: "folder.badge.minus",
                        role: .destructive
                    ) {
                        model.removeLibraryFolder(folder.id)
                    }
                    .accessibilityHint(
                        "Remove this saved Library Folder without changing files on disk"
                    )
                } label: {
                    Label("Folder Actions", systemImage: "ellipsis")
                }
                .labelStyle(.iconOnly)
                .menuStyle(.button)
                .controlSize(.small)
                .help("Folder Actions")

                Group {
                    switch folder.scanState {
                    case .scanning:
                        Button("Cancel Scan", systemImage: "xmark") {
                            model.cancelLibraryScan()
                        }
                        .help("Cancel Scan")
                    case .completed, .cancelled:
                        Button("Scan Again", systemImage: "arrow.clockwise") {
                            model.rescanSelectedLibraryFolder()
                        }
                        .help("Scan Again")
                    case .idle, .failed:
                        EmptyView()
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.caption.weight(.medium))

            if case .failed(let message) = folder.scanState {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(message)
            }

            if case .completed(let partialFailureCount) = folder.scanState,
               partialFailureCount > 0 {
                Label(
                    "Skipped \(partialFailureCount) unreadable locations",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption2)
                .foregroundStyle(theme.colors.statusConflict)
            }

            if let failure = folder.firstFailure,
               case .completed(let count) = folder.scanState,
               count > 0 {
                Text(failure.url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help("\(failure.url.path)\n\(failure.message)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var repositoryColumn: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedLibrarySource == .recent ? "Recent Repositories" : "Repositories")
                        .font(.headline)
                    if let folder = model.selectedLibraryFolder {
                        Text(folder.url.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(folder.url.path)
                    } else if model.selectedLibrarySource == .recent {
                        Text("Most recent first")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if case .scanning = model.selectedLibraryFolder?.scanState {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Scanning Library Folder")
                }
                Text(model.displayedLibraryRepositories.count, format: .number)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()
            repositoryListContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var repositoryListContent: some View {
        if model.selectedLibrarySource == .recent {
            if model.recentRepositories.isEmpty {
                ContentUnavailableView {
                    Label("No Repositories Yet", systemImage: "clock")
                } description: {
                    Text("Choose a Repository to open it, or a parent folder to add it to the Library.")
                } actions: {
                    Button("Choose Folder…", action: chooseFolder)
                        .accessibilityHint(
                            "Open a Git Repository, or add the selected folder to the Library"
                        )
                }
            } else {
                repositoryList(model.recentRepositories)
            }
        } else if let folder = model.selectedLibraryFolder {
            if folder.repositories.isEmpty {
                switch folder.scanState {
                case .scanning:
                    VStack(spacing: 12) {
                        ProgressView("Looking for Repositories…")
                        Button("Cancel") {
                            model.cancelLibraryScan()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Folder Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") {
                            model.rescanSelectedLibraryFolder()
                        }
                        .accessibilityLabel("Try Again")
                        Button("Reconnect…") {
                            reconnectLibraryFolder(folder.id)
                        }
                        .accessibilityLabel("Reconnect Library Folder")
                    }
                case .completed:
                    ContentUnavailableView {
                        Label("No Repositories Found", systemImage: "folder")
                    } description: {
                        Text("The scan finished inside the allowed folder.")
                    } actions: {
                        Button("Scan Again") {
                            model.rescanSelectedLibraryFolder()
                        }
                        .accessibilityLabel("Scan Again")
                        Button("Choose Another Folder…", action: chooseLibraryFolder)
                            .accessibilityLabel("Choose Another Library Folder")
                    }
                case .cancelled:
                    ContentUnavailableView {
                        Label("Scan Stopped", systemImage: "pause.circle")
                    } description: {
                        Text("No Repositories were found before the scan stopped.")
                    } actions: {
                        Button("Scan Again") {
                            model.rescanSelectedLibraryFolder()
                        }
                        .accessibilityLabel("Scan Again")
                    }
                case .idle:
                    ContentUnavailableView("Not Scanned", systemImage: "folder")
                }
            } else {
                repositoryHierarchyList(folder.repositories, relativeTo: folder.url)
            }
        } else {
            ContentUnavailableView {
                Label("Choose a Library Folder", systemImage: "sidebar.left")
            } description: {
                Text("Select a registered folder or choose a new folder.")
            } actions: {
                Button("Choose Folder…", action: chooseFolder)
                    .accessibilityHint(
                        "Open a Git Repository, or add the selected folder to the Library"
                    )
            }
        }
    }

    private func repositoryList(_ repositories: [RepositoryLocation]) -> some View {
        List(
            repositories,
            selection: Binding(
                get: { model.selectedLibraryRepositoryID },
                set: { id in model.selectLibraryRepository(id) }
            )
        ) { repository in
            RepositoryLibraryRow(
                repository: repository,
                summary: model.libraryRepositorySummaries[repository.id],
                errorMessage: model.libraryRepositorySummaryErrors[repository.id],
                isLoading: model.loadingLibraryRepositorySummaries.contains(repository.id),
                showsPath: true
            )
            .tag(repository.id)
            .contentShape(.rect)
            .accessibilityAction(named: "Remove from Recent") {
                model.removeRecentRepository(repository.id)
            }
            .task(id: repository.id) {
                guard model.selectedLibraryRepositoryID.map({
                    sameFileLocation($0, repository.id)
                }) != true else { return }
                await model.loadLibraryRepositorySummary(at: repository.rootURL)
            }
            .listRowInsets(.init(top: 7, leading: 12, bottom: 7, trailing: 12))
        }
        .listStyle(.plain)
        .focused($isRepositoryListFocused)
        .contextMenu(forSelectionType: URL.self) { selection in
            if let repositoryID = selection.first {
                Button("Remove from Recent", systemImage: "minus.circle", role: .destructive) {
                    model.removeRecentRepository(repositoryID)
                }
            }
        } primaryAction: { selection in
            guard let repositoryID = selection.first else { return }
            Task { await model.openLibraryRepository(at: repositoryID) }
        }
        .accessibilityLabel("Repositories, \(repositories.count)")
    }

    private func repositoryHierarchyList(
        _ repositories: [RepositoryLocation],
        relativeTo folderURL: URL
    ) -> some View {
        let nodes = RepositoryHierarchyNode.make(repositories, relativeTo: folderURL)
        return List(
            selection: Binding(
                get: { selectedHierarchyNodeID },
                set: { id in
                    selectedHierarchyNodeID = id
                    guard let id else {
                        model.selectLibraryRepository(nil)
                        return
                    }
                    guard repositories.contains(where: { sameFileLocation($0.id, id) }) else {
                        return
                    }
                    model.selectLibraryRepository(id)
                }
            )
        ) {
            ForEach(nodes) { node in
                repositoryHierarchyBranch(node)
            }
        }
        .listStyle(.plain)
        .focused($isRepositoryListFocused)
        .contextMenu(forSelectionType: URL.self) { selection in
            if
                let id = selection.first,
                let repository = repositories.first(where: { sameFileLocation($0.id, id) })
            {
                Button("Open Repository", systemImage: "arrow.right.circle") {
                    Task { await model.openLibraryRepository(at: repository.rootURL) }
                }
            }
        } primaryAction: { selection in
            guard let id = selection.first else { return }
            if let repository = repositories.first(where: { sameFileLocation($0.id, id) }) {
                Task { await model.openLibraryRepository(at: repository.rootURL) }
            } else {
                toggleHierarchyFolder(id)
            }
        }
        .accessibilityLabel("Repository hierarchy, \(repositories.count) Repositories")
    }

    private func repositoryHierarchyBranch(_ node: RepositoryHierarchyNode) -> AnyView {
        if let children = node.children {
            return AnyView(
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedHierarchyFolderIDs.contains(node.id) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedHierarchyFolderIDs.insert(node.id)
                            } else {
                                expandedHierarchyFolderIDs.remove(node.id)
                            }
                        }
                    )
                ) {
                    ForEach(children) { child in
                        repositoryHierarchyBranch(child)
                    }
                } label: {
                    RepositoryHierarchyFolderRow(node: node)
                }
                .tag(node.id)
                .listRowInsets(.init(top: 7, leading: 12, bottom: 7, trailing: 12))
            )
        }

        return AnyView(
            repositoryHierarchyRow(node)
                .listRowInsets(.init(top: 7, leading: 12, bottom: 7, trailing: 12))
        )
    }

    private func toggleHierarchyFolder(_ id: URL) {
        if expandedHierarchyFolderIDs.contains(id) {
            expandedHierarchyFolderIDs.remove(id)
        } else {
            expandedHierarchyFolderIDs.insert(id)
        }
    }

    @ViewBuilder
    private func repositoryHierarchyRow(_ node: RepositoryHierarchyNode) -> some View {
        if let repository = node.repository {
            RepositoryLibraryRow(
                repository: repository,
                summary: model.libraryRepositorySummaries[repository.id],
                errorMessage: model.libraryRepositorySummaryErrors[repository.id],
                isLoading: model.loadingLibraryRepositorySummaries.contains(repository.id),
                showsPath: false
            )
            .tag(repository.id)
            .contentShape(.rect)
            .task(id: repository.id) {
                guard model.selectedLibraryRepositoryID.map({
                    sameFileLocation($0, repository.id)
                }) != true else { return }
                await model.loadLibraryRepositorySummary(at: repository.rootURL)
            }
        } else {
            RepositoryHierarchyFolderRow(node: node)
        }
    }

    private var repositorySummaryColumn: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedHierarchyFolder == nil ? "Repository" : "Folder")
                        .font(.headline)
                    Text("Selection summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            if let folder = selectedHierarchyFolder {
                ScrollView {
                    selectedFolderSummary(folder)
                        .padding(16)
                }
            } else if let repository = model.selectedLibraryRepository {
                ScrollView {
                    selectedRepositorySummary(repository)
                        .padding(16)
                }
                .task(id: repository.id) {
                    await model.loadLibraryRepositorySummary(at: repository.rootURL)
                }

                Divider()
                Button {
                    Task { await model.openSelectedLibraryRepository() }
                } label: {
                    Label("Open Repository", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    model.isLoading
                        || model.libraryRepositorySummaryErrors[repository.id] != nil
                )
                .accessibilityHint("Open the selected Repository in this window")
                .padding(12)
            } else {
                ContentUnavailableView(
                    "Select a Repository",
                    systemImage: "arrow.triangle.branch",
                    description: Text("Selection updates this summary without opening a Workspace.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func selectedFolderSummary(_ folder: RepositoryHierarchyNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label(folder.name, systemImage: "folder")
                    .font(.title2.weight(.semibold))
                Text(folder.id.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Divider()
            LabeledContent("Repositories", value: folder.repositoryCount.formatted())
            Text("Select a Repository in this folder to see its Git status.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func selectedRepositorySummary(_ repository: RepositoryLocation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label(repository.name, systemImage: "arrow.triangle.branch")
                    .font(.title2.weight(.semibold))
                Text(repository.rootURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let summary = model.libraryRepositorySummaries[repository.id] {
                VStack(alignment: .leading, spacing: 9) {
                    LabeledContent("HEAD", value: summary.head.label)
                    LabeledContent(
                        "Working tree",
                        value: summary.changes.isEmpty
                            ? "Clean"
                            : "\(summary.changes.count) changes"
                    )
                    if summary.isUnborn {
                        LabeledContent("History", value: "No commits yet")
                    } else if let upstream = summary.upstream {
                        LabeledContent("Tracking", value: upstream.label)
                    }
                }

                Divider()
                activityContent(for: repository.id)
            } else if let message = model.libraryRepositorySummaryErrors[repository.id] {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Repository Unavailable", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(theme.colors.statusConflict)
                    Text(message)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await model.retryLibraryRepositorySummary(at: repository.rootURL) }
                    }
                    if model.selectedRepositoryIsRecent {
                        Button("Reconnect…") {
                            reconnectRepository(repository.id)
                        }
                        Button("Remove from Recent", role: .destructive) {
                            model.removeRecentRepository(repository.id)
                        }
                        .accessibilityHint("Forget this saved location without changing files on disk")
                    }
                }
            } else {
                ProgressView("Reading Repository…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func activityContent(for repositoryID: URL) -> some View {
        if let activity = model.libraryRepositoryActivities[repositoryID] {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Commits", value: activity.commitCount.formatted())
                Text("Recent Activity")
                    .font(.subheadline.weight(.semibold))
                if activity.recentCommits.isEmpty {
                    Text("No commits yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activity.recentCommits) { commit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commit.subject.isEmpty ? "Untitled commit" : commit.subject)
                                .lineLimit(2)
                                .help(commit.subject.isEmpty ? "Untitled commit" : commit.subject)
                            Text("\(commit.id.prefix(8)) · \(commit.committedAt, style: .relative)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .help(commit.committedAt.formatted(date: .abbreviated, time: .shortened))
                                .accessibilityLabel(
                                    "Commit \(commit.id.prefix(8)), \(commit.committedAt.formatted(date: .abbreviated, time: .shortened))"
                                )
                        }
                    }
                }
            }
        } else if let message = model.libraryRepositoryActivityErrors[repositoryID] {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent Activity Unavailable")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { await model.retryLibraryRepositoryActivity(at: repositoryID) }
                }
            }
        } else {
            ProgressView("Reading recent activity…")
                .controlSize(.small)
        }
    }

    private var selectedSummary: RepositorySummary? {
        guard let id = model.selectedLibraryRepositoryID else { return nil }
        return model.libraryRepositorySummaries[id]
    }

    private var selectedHierarchyFolder: RepositoryHierarchyNode? {
        guard
            let selectedHierarchyNodeID,
            let folder = model.selectedLibraryFolder
        else { return nil }

        return RepositoryHierarchyNode.make(folder.repositories, relativeTo: folder.url)
            .lazy
            .compactMap { $0.node(matching: selectedHierarchyNodeID) }
            .first(where: { $0.repository == nil })
    }

    private var isLibraryEmpty: Bool {
        model.recentRepositories.isEmpty && model.libraryFolders.isEmpty
    }
}

private struct LibraryFolderRow: View {
    let folder: RepositoryLibraryFolder

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .lineLimit(1)
                Text(folder.url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(folder.repositories.count, format: .number)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folder.name), \(folder.repositories.count) Repositories, \(folder.url.path)")
        .help(folder.url.path)
    }
}

private struct RepositoryLibraryRow: View {
    let repository: RepositoryLocation
    let summary: RepositorySummary?
    let errorMessage: String?
    let isLoading: Bool
    let showsPath: Bool
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(repository.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if showsPath {
                    Text(repository.rootURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if let summary {
                HStack(spacing: 8) {
                    Text(summary.head.label)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(summary.head.label)
                    Text(summary.changes.isEmpty ? "Clean" : "\(summary.changes.count) changes")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.colors.badgeBackground, in: .capsule)
                }
            } else if errorMessage != nil {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.colors.statusConflict)
                    .help(errorMessage ?? "Repository unavailable")
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Reading \(repository.name)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .help(repository.rootURL.path)
    }

    private var accessibilityLabel: String {
        if let summary {
            let state = summary.changes.isEmpty ? "clean" : "\(summary.changes.count) changes"
            return "\(repository.name), \(summary.head.label), \(state), \(repository.rootURL.path)"
        }
        if errorMessage != nil {
            return "\(repository.name), unavailable, \(repository.rootURL.path)"
        }
        return "\(repository.name), reading status, \(repository.rootURL.path)"
    }
}

private struct RepositoryHierarchyFolderRow: View {
    let node: RepositoryHierarchyNode

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
            Text(node.repositoryCount, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityValue("\(node.name), folder, \(node.repositoryCount) Repositories")
        .help(node.id.path)
    }
}

struct RepositoryHierarchyNode: Equatable, Identifiable, Sendable {
    let id: URL
    let name: String
    var children: [RepositoryHierarchyNode]?
    let repository: RepositoryLocation?

    var repositoryCount: Int {
        repository == nil
            ? children?.reduce(0) { $0 + $1.repositoryCount } ?? 0
            : 1
    }

    func node(matching id: URL) -> RepositoryHierarchyNode? {
        if sameFileLocation(self.id, id) {
            return self
        }
        return children?.lazy.compactMap { $0.node(matching: id) }.first
    }

    static func make(
        _ repositories: [RepositoryLocation],
        relativeTo rootURL: URL
    ) -> [RepositoryHierarchyNode] {
        let rootURL = rootURL.standardizedFileURL
        let rootComponents = rootURL.pathComponents
        var nodes: [RepositoryHierarchyNode] = []

        for repository in repositories {
            let repositoryComponents = repository.rootURL.standardizedFileURL.pathComponents
            guard repositoryComponents.starts(with: rootComponents) else { continue }
            let relativeComponents = repositoryComponents.dropFirst(rootComponents.count)
            insert(
                repository,
                below: relativeComponents.dropLast(),
                parentURL: rootURL,
                into: &nodes
            )
        }

        sort(&nodes)
        return nodes
    }

    private static func insert(
        _ repository: RepositoryLocation,
        below components: ArraySlice<String>,
        parentURL: URL,
        into nodes: inout [RepositoryHierarchyNode]
    ) {
        guard let component = components.first else {
            guard !nodes.contains(where: { sameFileLocation($0.id, repository.id) }) else {
                return
            }
            nodes.append(.init(
                id: repository.id,
                name: repository.name,
                children: nil,
                repository: repository
            ))
            return
        }

        let folderURL = parentURL
            .appending(path: component, directoryHint: .isDirectory)
            .standardizedFileURL
        if let index = nodes.firstIndex(where: {
            $0.repository == nil && sameFileLocation($0.id, folderURL)
        }) {
            var children = nodes[index].children ?? []
            insert(
                repository,
                below: components.dropFirst(),
                parentURL: folderURL,
                into: &children
            )
            nodes[index].children = children
        } else {
            var children: [RepositoryHierarchyNode] = []
            insert(
                repository,
                below: components.dropFirst(),
                parentURL: folderURL,
                into: &children
            )
            nodes.append(.init(
                id: folderURL,
                name: component,
                children: children,
                repository: nil
            ))
        }
    }

    private static func sort(_ nodes: inout [RepositoryHierarchyNode]) {
        for index in nodes.indices where nodes[index].children != nil {
            var children = nodes[index].children ?? []
            sort(&children)
            nodes[index].children = children
        }
        nodes.sort {
            let comparison = $0.name.localizedStandardCompare($1.name)
            if comparison == .orderedSame {
                return $0.repository == nil && $1.repository != nil
            }
            return comparison == .orderedAscending
        }
    }
}
