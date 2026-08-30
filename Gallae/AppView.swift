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
                ProgressView(model.isWritingRepository ? "Updating Repository…" : "Reading Repository…")
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
}

enum AppScreen: Equatable, Sendable {
    case library
    case workspace
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
    let revision: Int
}

enum RepositoryHistoryLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded(RepositoryHistory)
    case failed(String)
}

enum RepositoryCommitPatchLoadState: Equatable, Sendable {
    case noSelection
    case loading
    case loaded(RepositoryCommitPatch)
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
    var commitPatchState: RepositoryCommitPatchLoadState = .noSelection
    var isLoading = false
    var isWritingRepository = false
    var isRepositoryStale = false
    var errorMessage: String?
    var libraryFolders: [RepositoryLibraryFolder] = []
    var recentRepositories: [RepositoryLocation] = []
    var selectedLibrarySource: RepositoryLibrarySource? = .recent
    var selectedLibraryRepositoryID: URL?
    private(set) var repositoryRevision = 0
    private(set) var libraryRepositorySummaries: [URL: RepositorySummary] = [:]
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
    @ObservationIgnored private var commitPatchGeneration = 0
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanningFolderIDs: [URL] = []

    init(store: LibraryStore = LibraryStore()) {
        self.store = store
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

    var commitPatchRequest: RepositoryCommitPatchRequest? {
        guard let repository, let selectedHistoryCommit else { return nil }
        return .init(
            rootURL: repository.rootURL,
            commitID: selectedHistoryCommit.id,
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
        guard let rootURL = repository?.rootURL else { return }
        _ = await inspect(
            rootURL,
            rememberOnSuccess: false,
            markCurrentStaleOnFailure: true,
            showWorkspaceOnSuccess: false,
            presentFailure: true
        )
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
            } ?? history.commits.first?.id
            commitPatchState = selectedHistoryCommitID == nil ? .noSelection : .loading
        } catch is CancellationError {
            return
        } catch {
            guard generation == historyGeneration, request == historyRequest else { return }
            historyState = .failed(Self.message(for: error))
            selectedHistoryCommitID = nil
            commitPatchState = .noSelection
        }
    }

    func loadSelectedCommitPatch(
        maximumOutputBytes: Int? = RepositoryInspector.maximumDisplayedDiffBytes
    ) async {
        guard
            let request = commitPatchRequest,
            let repository,
            let commit = selectedHistoryCommit
        else {
            commitPatchState = .noSelection
            return
        }

        commitPatchGeneration += 1
        let generation = commitPatchGeneration
        commitPatchState = .loading

        do {
            let patch = try await inspector.patch(
                for: commit,
                in: repository,
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
        }
        repository = inspectedRepository
        repositoryRevision += 1
        selectedChangeID = previousSelection.flatMap { selectedID in
            inspectedRepository.changes.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? inspectedRepository.changes.first?.id
        diffState = selectedChangeID == nil ? .noSelection : .loading
        historyState = .notLoaded
        commitPatchState = .noSelection
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
