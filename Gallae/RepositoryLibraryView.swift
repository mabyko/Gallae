import Observation
import SwiftUI

struct RepositoryLibraryView: View {
    @Bindable var model: AppModel
    let chooseLibraryFolder: () -> Void
    let reconnectLibraryFolder: (URL) -> Void
    let chooseRepository: () -> Void
    let reconnectRepository: (URL) -> Void
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        HSplitView {
            libraryFolderColumn
                .frame(
                    minWidth: theme.metrics.libraryFolderMinimumWidth,
                    idealWidth: theme.metrics.libraryFolderIdealWidth
                )

            repositoryColumn
                .frame(
                    minWidth: theme.metrics.repositoryListMinimumWidth,
                    idealWidth: theme.metrics.repositoryListIdealWidth
                )

            repositorySummaryColumn
                .frame(
                    minWidth: theme.metrics.repositorySummaryMinimumWidth,
                    idealWidth: theme.metrics.repositorySummaryIdealWidth
                )
        }
        .task(id: model.selectedLibraryRepositoryID) {
            guard let url = model.selectedLibraryRepository?.rootURL else { return }
            await model.loadLibraryRepositorySummary(at: url)
        }
        .task(id: selectedSummary?.rootURL) {
            guard let id = model.selectedLibraryRepositoryID else { return }
            await model.loadLibraryRepositoryActivity(at: id)
        }
    }

    private var libraryFolderColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Repository Library")
                    .font(.headline)
                Spacer()
                Button("Add Library Folder", systemImage: "plus", action: chooseLibraryFolder)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Add Library Folder")
                    .help("Add Library Folder")
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
                    .accessibilityLabel("Recent Repositories, \(model.recentRepositories.count)")
                }

                Section("Library Folders") {
                    ForEach(model.libraryFolders) { folder in
                        LibraryFolderRow(folder: folder)
                            .tag(RepositoryLibrarySource.folder(folder.id))
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

    @ViewBuilder
    private func scanStatus(for folder: RepositoryLibraryFolder) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            switch folder.scanState {
            case .idle:
                Text("Not scanned")
                    .foregroundStyle(.secondary)
            case .scanning:
                Text("Scanning · \(folder.repositories.count) found")
                Button("Cancel Scan") {
                    model.cancelLibraryScan()
                }
            case .completed(let partialFailureCount):
                Text("\(folder.repositories.count) Repositories")
                if partialFailureCount > 0 {
                    Label(
                        "Skipped \(partialFailureCount) unreadable locations",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(theme.colors.statusConflict)
                }
                Button("Scan Again") {
                    model.rescanSelectedLibraryFolder()
                }
            case .cancelled:
                Text("Scan stopped · \(folder.repositories.count) found")
                Button("Scan Again") {
                    model.rescanSelectedLibraryFolder()
                }
            case .failed(let message):
                Label("Couldn’t Scan Folder", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(theme.colors.statusConflict)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let failure = folder.firstFailure,
               case .completed(let count) = folder.scanState,
               count > 0 {
                Text(failure.url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(failure.message)
            }

            Button("Remove Folder", role: .destructive) {
                model.removeLibraryFolder(folder.id)
            }
            .accessibilityHint("Remove this saved Library Folder without changing files on disk")
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
        }
    }

    @ViewBuilder
    private var repositoryListContent: some View {
        if model.selectedLibrarySource == .recent {
            if model.recentRepositories.isEmpty {
                ContentUnavailableView {
                    Label("No Recent Repositories", systemImage: "clock")
                } description: {
                    Text("Repositories you open will appear here.")
                } actions: {
                    Button("Open Repository…", action: chooseRepository)
                        .accessibilityLabel("Open Repository")
                    Button("Add Library Folder…", action: chooseLibraryFolder)
                        .accessibilityLabel("Add Library Folder")
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
                repositoryList(folder.repositories)
            }
        } else {
            ContentUnavailableView {
                Label("Choose a Library Folder", systemImage: "sidebar.left")
            } description: {
                Text("Select a registered folder or add a new one.")
            } actions: {
                Button("Add Folder…", action: chooseLibraryFolder)
                    .accessibilityLabel("Add Library Folder")
                Button("Open Repository…", action: chooseRepository)
                    .accessibilityLabel("Open Repository")
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
                isLoading: model.loadingLibraryRepositorySummaries.contains(repository.id)
            )
            .tag(repository.id)
            .contentShape(.rect)
            .onTapGesture(count: 2) {
                Task { await model.openLibraryRepository(at: repository.rootURL) }
            }
            .task(id: repository.id) {
                await model.loadLibraryRepositorySummary(at: repository.rootURL)
            }
        }
        .listStyle(.inset)
        .accessibilityLabel("Repositories, \(repositories.count)")
    }

    private var repositorySummaryColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Repository")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            if let repository = model.selectedLibraryRepository {
                ScrollView {
                    selectedRepositorySummary(repository)
                        .padding(16)
                }

                Divider()
                Button("Open Repository") {
                    Task { await model.openSelectedLibraryRepository() }
                }
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
                    systemImage: "folder",
                    description: Text("Selection updates this summary without opening a Workspace.")
                )
            }
        }
    }

    @ViewBuilder
    private func selectedRepositorySummary(_ repository: RepositoryLocation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label(repository.name, systemImage: "folder")
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
                        LabeledContent("Upstream", value: upstream.label)
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
                            Text("\(commit.id.prefix(8)) · \(commit.committedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
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
            }
            Spacer()
            Text(folder.repositories.count, format: .number)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folder.name), \(folder.repositories.count) Repositories, \(folder.url.path)")
    }
}

private struct RepositoryLibraryRow: View {
    let repository: RepositoryLocation
    let summary: RepositorySummary?
    let errorMessage: String?
    let isLoading: Bool
    @Environment(\.gallaeTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(repository.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(repository.rootURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let summary {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(summary.head.label)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    Text(summary.changes.isEmpty ? "Clean" : "\(summary.changes.count) changes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
