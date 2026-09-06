import Foundation
import Observation

enum AppScreen: Equatable, Sendable {
    case library
    case workspace
}

enum RepositoryMergeIntoBranchResult: Equatable, Sendable {
    case completed
    case conflictedInWorktree(RepositorySummary)
    case failed
}

enum RepositoryRemoteOperation: Equatable, Sendable {
    case fetch(remote: String?, pruning: Bool)
    case automaticFetch
    case pull
    case publish
    case push
    case addRemoteAndPublish(name: String, url: String)
    case publishTo(remote: String)
    case deleteRemoteBranch(trackingRef: String)

    /// Fetch, automatic Fetch, and Pull all bring remote refs down.
    var fetchesRemote: Bool {
        switch self {
        case .fetch, .automaticFetch, .pull: true
        default: false
        }
    }

    var progressTitle: String {
        switch self {
        case .fetch(let remote, let pruning):
            pruning
                ? remote.map { "Fetching & Pruning from \($0)…" } ?? "Fetching & Pruning…"
                : remote.map { "Fetching from \($0)…" } ?? "Fetching Remote Changes…"
        case .automaticFetch: "Fetching Automatically…"
        case .pull: "Pulling Remote Changes…"
        case .publish: "Publishing Local Branch…"
        case .push: "Pushing Local Commits…"
        case .addRemoteAndPublish: "Adding Remote and Publishing…"
        case .publishTo(let remote): "Publishing to \(remote)…"
        case .deleteRemoteBranch(let trackingRef): "Deleting \(trackingRef) on Remote…"
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
        case .deleteRemoteBranch: "Cancel Remote Deletion"
        }
    }

    var failureTitle: String {
        switch self {
        case .fetch: "Couldn’t Fetch"
        case .automaticFetch: "Couldn’t Fetch Automatically"
        case .pull: "Couldn’t Pull"
        case .push: "Couldn’t Push"
        case .publish, .addRemoteAndPublish, .publishTo: "Couldn’t Publish"
        case .deleteRemoteBranch: "Couldn’t Delete Remote Branch"
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
        case .deleteRemoteBranch:
            "Stop deleting the remote branch and keep the Repository open"
        }
    }
}

extension RepositoryRemoteOperation {
    /// Result line for the activity capsule, computed from the Repository state before the operation.
    func successTitle(before repository: RepositorySummary) -> String? {
        switch self {
        case .fetch(let remote, _): remote.map { "Fetched from \($0)" } ?? "Fetched"
        case .automaticFetch: nil
        case .pull:
            if let behind = repository.upstream?.behind, behind > 0 {
                "Pulled \(behind) commit\(behind == 1 ? "" : "s")"
            } else {
                "Pulled"
            }
        case .push:
            if let ahead = repository.upstream?.ahead, ahead > 0 {
                "Pushed \(ahead) commit\(ahead == 1 ? "" : "s")"
            } else {
                "Pushed"
            }
        case .publish: "Published"
        case .addRemoteAndPublish(let name, _): "Published to \(name)"
        case .publishTo(let remote): "Published to \(remote)"
        case .deleteRemoteBranch(let trackingRef): "Deleted \(trackingRef) on remote"
        }
    }

    var isFetch: Bool {
        switch self {
        case .fetch, .automaticFetch: true
        default: false
        }
    }

    var isPush: Bool {
        switch self {
        case .push, .publish, .addRemoteAndPublish, .publishTo: true
        default: false
        }
    }
}

enum RepositorySheetRequest: Identifiable, Equatable, Sendable {
    case addRemote(repositoryRootURL: URL, publishAfterAdding: Bool = true)
    case createTag(repositoryRootURL: URL)
    case createStash(repositoryRootURL: URL)
    case integrateBranch(repositoryRootURL: URL, branch: String?)
    case chooseFetchRemote(repositoryRootURL: URL, remotes: [String], pruning: Bool)
    case choosePublishRemote(repositoryRootURL: URL, remotes: [String])

    var id: String {
        switch self {
        case .addRemote(let repositoryRootURL, let publishAfterAdding):
            "add:\(repositoryRootURL.path):\(publishAfterAdding)"
        case .createTag(let repositoryRootURL):
            "create-tag:\(repositoryRootURL.path)"
        case .createStash(let repositoryRootURL):
            "create-stash:\(repositoryRootURL.path)"
        case .integrateBranch(let repositoryRootURL, _):
            "integrate-branch:\(repositoryRootURL.path)"
        case .chooseFetchRemote(let repositoryRootURL, _, let pruning):
            "choose-fetch:\(repositoryRootURL.path):\(pruning)"
        case .choosePublishRemote(let repositoryRootURL, _):
            "choose-publish:\(repositoryRootURL.path)"
        }
    }
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
    /// Fully qualified ref that narrows History to one branch or tag; nil reads every ref.
    var reference: String? = nil
    var focusReference: String? = nil
    var navigationRevision: Int = 0
    var limit: Int = RepositoryInspector.maximumHistoryCommits
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

enum RepositoryTagsLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded([String])
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
    let library: RepositoryLibraryModel
    var screen: AppScreen = .library
    var repository: RepositorySummary?
    var selectedChangeID: String?
    var diffState: RepositoryDiffLoadState = .noSelection
    var selectedHistoryCommitID: String? {
        didSet {
            guard selectedHistoryCommitID != oldValue else { return }
            selectedHistoryFileID = nil
            commitFilesState = .noSelection
            commitPatchState = .noSelection
        }
    }
    var historyState: RepositoryHistoryLoadState = .notLoaded
    /// Explicit filtering is independent of the reference selected in the Navigator.
    var historyScope: RepositoryHistoryScope? {
        didSet {
            guard historyScope != oldValue else { return }
            historyLimit = RepositoryInspector.maximumHistoryCommits
            selectedHistoryCommitID = nil
            if let historyScope { historySelection = historyScope }
            else { historyNavigationRevision += 1 }
        }
    }
    var historySelection: RepositoryHistoryScope? {
        didSet {
            selectedWorktreeURL = nil
            historyNavigationRevision += 1
            historyNavigationMessage = nil
        }
    }
    private(set) var historyNavigationRevision = 0
    private var appliedHistoryNavigationRevision = -1
    private var appliedHistoryReference: String?
    private(set) var historyScrollRevision = 0
    private(set) var historyNavigationMessage: String?
    private var historyLimit = RepositoryInspector.maximumHistoryCommits
    var historyReference: String? { historyScope?.historyReference }
    var tagsState: RepositoryTagsLoadState = .notLoaded
    var localBranchesState: RepositoryLocalBranchesLoadState = .notLoaded
    private(set) var localBranches: [String] = []
    private(set) var remoteBranchesByRemote: [String: [String]] = [:]
    private(set) var worktrees: [RepositoryWorktree] = []
    private(set) var selectedWorktreeURL: URL?
    var localBranchWorktreeURLs: [String: URL] { RepositoryWorktree.branchURLs(in: worktrees) }

    func selectWorktree(_ worktree: RepositoryWorktree) {
        historySelection = nil
        selectedWorktreeURL = worktree.url
    }

    func canRemoveWorktree(at url: URL) -> Bool {
        guard let repository, !isLoading, !isSyncing,
              let worktree = worktrees.first(where: { sameFileLocation($0.url, url) }) else { return false }
        return worktree.removalRestriction(currentURL: repository.rootURL) == nil
    }
    var remotesState: RepositoryRemotesLoadState = .notLoaded
    var selectedHistoryFileID: String?
    var commitFilesState: RepositoryCommitFilesLoadState = .noSelection
    var commitPatchState: RepositoryCommitPatchLoadState = .noSelection
    private(set) var selectedCommitSignature: RepositoryCommitSignature?
    var selectedStashID: String? {
        didSet {
            guard selectedStashID != oldValue else { return }
            selectedStashFileID = nil
            stashFilesState = .noSelection
            stashPatchState = .noSelection
        }
    }
    var stashesState: RepositoryStashesLoadState = .notLoaded
    var selectedReflogEntryID: String?
    var reflogState: RepositoryReflogLoadState = .notLoaded
    var selectedStashFileID: String?
    var stashFilesState: RepositoryCommitFilesLoadState = .noSelection
    var stashPatchState: RepositoryCommitPatchLoadState = .noSelection
    var isLoading = false
    var isWritingRepository = false
    var activeMergeTool: String?
    var remoteOperation: RepositoryRemoteOperation?
    /// Short result of the last remote operation, shown briefly in the activity capsule.
    var remoteOperationResult: String?
    /// When each Repository last fetched in this session, for the context bar. Not persisted.
    var lastFetchDates: [URL: Date] = [:]
    var lastFetchDate: Date? {
        repository.flatMap { lastFetchDates[$0.rootURL] }
    }
    /// A user-started remote operation is running: sync commands and branch changes wait, Stage,
    /// Commit, and reading keep working. Automatic Fetch never locks anything.
    var isSyncing: Bool {
        remoteOperation != nil && remoteOperation != .automaticFetch
    }
    @ObservationIgnored private var remoteOperationID: UUID?
    @ObservationIgnored private var remoteResultTask: Task<Void, Never>?
    var automaticFetchEnabled: Bool
    var repositorySheetRequest: RepositorySheetRequest?
    var isRepositoryStale = false
    var errorTitle: String?
    var errorMessage: String?
    // ponytail: 임시 Worktree 추적은 세션 안에서만 유지한다. 재실행 뒤 남은
    // 임시 Worktree는 일반 Worktree로 취급해 기존 흐름에서 다룬다(명세 6D-3).
    private(set) var temporaryWorktrees: [URL: URL] = [:]
    var pendingTemporaryWorktreeRemovalURL: URL?
    private(set) var repositoryRevision = 0

    var pushTitle: String {
        guard let upstream = repository?.upstream else { return "Publish" }
        guard let ahead = upstream.ahead, ahead > 0 else { return "Push" }
        return "Push \(ahead)"
    }

    var canPushRepository: Bool {
        guard let repository, !repository.isUnborn else { return false }
        guard case .branch = repository.head else { return false }
        return true
    }

    var canPullRepository: Bool {
        guard let repository, repository.upstream != nil else { return false }
        guard case .branch = repository.head else { return false }
        return true
    }

    var canIntegrateBranch: Bool {
        guard let repository, !repository.isUnborn else { return false }
        guard case .branch = repository.head else { return false }
        return true
    }

    @ObservationIgnored private let inspector = RepositoryInspector()
    @ObservationIgnored private let inspectRepository: @Sendable (URL) async throws -> RepositorySummary
    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private var didAttemptRestore = false
    @ObservationIgnored private var inspectionGeneration = 0
    @ObservationIgnored private var diffGeneration = 0
    @ObservationIgnored private var localBranchesGeneration = 0
    @ObservationIgnored private var remotesGeneration = 0
    @ObservationIgnored private var tagsGeneration = 0
    @ObservationIgnored private var historyGeneration = 0
    @ObservationIgnored private var commitFilesGeneration = 0
    @ObservationIgnored private var commitSignatureGeneration = 0
    @ObservationIgnored private var commitPatchGeneration = 0
    @ObservationIgnored private var stashesGeneration = 0
    @ObservationIgnored private var reflogGeneration = 0
    @ObservationIgnored private var stashFilesGeneration = 0
    @ObservationIgnored private var stashPatchGeneration = 0
    @ObservationIgnored private var remoteTask: Task<Void, Never>?

    init(
        store: LibraryStore = LibraryStore(),
        inspectRepository: @escaping @Sendable (URL) async throws -> RepositorySummary = {
            try await RepositoryInspector().inspect(at: $0)
        }
    ) {
        self.store = store
        library = RepositoryLibraryModel(store: store)
        self.inspectRepository = inspectRepository
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
        let focusReference: String?
        if let selectedWorktreeURL {
            let headID = worktrees.first(where: { $0.url == selectedWorktreeURL })?.headID
            focusReference = headID?.contains(where: { $0 != "0" }) == true ? headID : nil
        }
        else if case .remote = historySelection { focusReference = nil }
        else { focusReference = historySelection?.historyReference }
        return .init(
            rootURL: repository.rootURL, revision: repositoryRevision, reference: historyReference,
            focusReference: focusReference, navigationRevision: historyNavigationRevision, limit: historyLimit
        )
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
        guard let repository else { return nil }
        return .init(rootURL: repository.rootURL, revision: repositoryRevision)
    }

    var reflogRequest: RepositoryHistoryRequest? {
        stashesRequest
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

    func canStageChanges(ids: Set<RepositorySummary.Change.ID>) -> Bool {
        repository?.changes.contains {
            ids.contains($0.id) && !$0.isConflicted && $0.unstaged != nil
        } == true
    }

    func canUnstageChanges(ids: Set<RepositorySummary.Change.ID>) -> Bool {
        repository?.changes.contains {
            ids.contains($0.id) && !$0.isConflicted && $0.staged != nil
        } == true
    }

    var canDiscardSelectedChange: Bool {
        selectedChange?.canDiscardUnstagedChanges == true
    }

    var canResolveSelectedConflict: Bool {
        selectedChange?.isConflicted == true
    }

    /// Hunks and lines of a modified file go to the index; an untracked file's lines create its index entry.
    var canStageSelectedHunks: Bool {
        selectedChange.map { !$0.isConflicted && ($0.unstaged == .modified || $0.unstaged == .untracked) } ?? false
    }

    /// A newly added file can have part of its index entry taken back too; the patch is rewritten so it no
    /// longer claims to create the file. Renames and deletions still move as a whole.
    var canUnstageSelectedHunks: Bool {
        selectedChange.map { !$0.isConflicted && ($0.staged == .modified || $0.staged == .added) } ?? false
    }

    var canCommit: Bool {
        repository.map {
            $0.changes.contains(where: { $0.staged != nil })
                && !$0.changes.contains(where: \.isConflicted)
        } ?? false
    }

    func showLibrary() {
        screen = .library
    }

    func openLibraryRepository(at url: URL) async {
        await openRepository(at: url)
    }

    @discardableResult
    func openRepository(at url: URL) async -> Bool {
        await inspect(
            url,
            rememberOnSuccess: true,
            markCurrentStaleOnFailure: false,
            showWorkspaceOnSuccess: true,
            presentFailure: true,
            failureTitle: "Couldn’t Open Repository"
        ) == .opened
    }

    func openWorktree(at url: URL) async -> Bool {
        let opened = await inspect(
            url,
            rememberOnSuccess: true,
            markCurrentStaleOnFailure: false,
            showWorkspaceOnSuccess: true,
            presentFailure: true,
            failureTitle: "Couldn’t Open Worktree",
            preservingHistoryScope: true
        ) == .opened
        if opened {
            if case .branch(let name) = repository?.head { historySelection = .branch(name) }
            else {
                await loadLocalBranches()
                if let worktree = worktrees.first(where: { sameFileLocation($0.url, url) }) {
                    selectWorktree(worktree)
                } else { historySelection = nil }
            }
        }
        return opened
    }

    func openOrAddFolder(at url: URL) async {
        _ = await inspect(
            url,
            rememberOnSuccess: true,
            markCurrentStaleOnFailure: false,
            showWorkspaceOnSuccess: true,
            presentFailure: true,
            failureTitle: "Couldn’t Open Repository",
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
            presentFailure: true,
            failureTitle: "Couldn’t Refresh Repository"
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

    func showIntegrateBranch(preselecting branch: String? = nil) {
        guard canIntegrateBranch, let repository else { return }
        repositorySheetRequest = .integrateBranch(repositoryRootURL: repository.rootURL, branch: branch)
    }

    /// Workspace owns these reads even when its Navigator is hidden or shown as a floating panel.
    func loadNavigator() async {
        guard !Task.isCancelled, let rootURL = repository?.rootURL else { return }
        async let branches: Void = loadLocalBranches()
        async let remotes: Void = loadRemotes(in: rootURL)
        async let tags: Void = loadTags()
        async let stashes: Void = loadStashes()
        _ = await (branches, remotes, tags, stashes)
    }

    func loadTags() async {
        guard !Task.isCancelled else { return }
        guard let repository else {
            tagsState = .notLoaded
            return
        }
        let rootURL = repository.rootURL
        let revision = repositoryRevision
        tagsGeneration += 1
        let generation = tagsGeneration
        if case .loaded = tagsState {
            // Keep the current rows while this Repository refreshes.
        } else {
            tagsState = .loading
        }

        do {
            let tags = try await inspector.tags(in: repository)
            guard
                generation == tagsGeneration,
                revision == repositoryRevision,
                self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true
            else {
                return
            }
            tagsState = .loaded(tags)
            if case .tag(let name) = historySelection, !tags.contains(name) {
                historySelection = nil
            }
        } catch is CancellationError {
            return
        } catch {
            guard
                generation == tagsGeneration,
                revision == repositoryRevision,
                self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true
            else {
                return
            }
            tagsState = .failed(Self.message(for: error))
        }
    }

    func showCreateStash() {
        guard !isLoading, let repository else { return }
        repositorySheetRequest = .createStash(repositoryRootURL: repository.rootURL)
    }

    func loadRemotes(in rootURL: URL) async {
        guard !Task.isCancelled else { return }
        guard let repository else {
            remotesState = .notLoaded
            return
        }
        guard sameFileLocation(repository.rootURL, rootURL) else { return }
        let revision = repositoryRevision
        remotesGeneration += 1
        let generation = remotesGeneration
        if case .loaded = remotesState {
            // Keep expanded remote branches mounted while this Repository refreshes.
        } else {
            remotesState = .loading
        }

        do {
            let remotes = try await inspector.remotes(in: repository)
            guard
                generation == remotesGeneration,
                revision == repositoryRevision,
                self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true
            else {
                return
            }
            remotesState = .loaded(remotes)
            let names = Set(remotes.map(\.name))
            remoteBranchesByRemote = remoteBranchesByRemote.filter { names.contains($0.key) }
            if let selected = historySelection?.remoteName, !names.contains(selected) {
                historySelection = nil
            }
            let inspector = inspector
            let branches = await withTaskGroup(of: (String, [String]?).self) { group in
                for remote in remotes {
                    group.addTask {
                        (remote.name, try? await inspector.remoteBranches(of: remote.name, in: repository))
                    }
                }
                var result: [String: [String]] = [:]
                for await (name, branches) in group {
                    if let branches { result[name] = branches }
                }
                return result
            }
            guard !Task.isCancelled, generation == remotesGeneration, revision == repositoryRevision,
                  self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true else { return }
            remoteBranchesByRemote.merge(branches) { _, updated in updated }
            if case .remoteBranch(let name) = historySelection,
               let remote = historySelection?.remoteName, let loaded = branches[remote],
               !loaded.contains(name) {
                historySelection = .remote(remote)
            }
        } catch is CancellationError {
            return
        } catch {
            guard
                generation == remotesGeneration,
                revision == repositoryRevision,
                self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true
            else {
                return
            }
            remotesState = .failed(Self.message(for: error))
        }
    }

    func addRemote(named name: String, url: String, in rootURL: URL) async throws {
        guard !isLoading, !isSyncing, let repository, sameFileLocation(repository.rootURL, rootURL) else {
            throw RepositoryRemoteError.unavailable
        }
        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }
        let updated = try await inspector.addRemote(named: name, url: url, in: repository)
        guard generation == inspectionGeneration else { return }
        apply(updated, showWorkspaceOnSuccess: false)
        await loadRemotes(in: rootURL)
    }

    func createTag(named name: String, at target: String, in rootURL: URL) async throws {
        guard !isLoading, !isSyncing, let repository, sameFileLocation(repository.rootURL, rootURL) else {
            throw RepositoryTagCreationError.failed("This Repository is no longer available.")
        }
        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }
        let updated = try await inspector.createTag(named: name, at: target, in: repository)
        guard generation == inspectionGeneration else { return }
        apply(updated, showWorkspaceOnSuccess: false)
        await loadTags()
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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        let updatedRepository = try await inspector.removeRemote(named: name, in: repository)
        guard
            generation == inspectionGeneration,
            self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true
        else {
            throw CancellationError()
        }
        apply(updatedRepository, showWorkspaceOnSuccess: false)
        library.invalidateActivity(at: updatedRepository.rootURL)
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
        guard !isLoading, let repository else { return nil }
        if remoteTask != nil {
            // A user-started operation takes over a running automatic Fetch; anything else waits.
            guard remoteOperation == .automaticFetch, operation != .automaticFetch else { return nil }
            remoteTask?.cancel()
        }

        // ponytail: only Pull writes the index and working tree, so only Pull takes the local lock.
        // Fetch and Push leave Stage, Commit, and reading available while they run.
        let writesWorkingTree = operation == .pull
        let operationID = UUID()
        let startGeneration = inspectionGeneration
        if writesWorkingTree {
            inspectionGeneration += 1
            isLoading = true
            isWritingRepository = true
        }
        let generation = inspectionGeneration
        remoteOperationID = operationID
        remoteOperation = operation
        remoteOperationResult = nil
        remoteResultTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if remoteOperationID == operationID {
                    remoteOperationID = nil
                    remoteTask = nil
                    remoteOperation = nil
                    if writesWorkingTree, generation == inspectionGeneration {
                        isLoading = false
                        isWritingRepository = false
                    }
                }
            }

            let acceptsCompletion = {
                self.remoteOperationID == operationID &&
                    self.repository.map({ sameFileLocation($0.rootURL, repository.rootURL) }) == true &&
                    (!writesWorkingTree || self.inspectionGeneration == generation)
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
                case .deleteRemoteBranch(let trackingRef):
                    try await inspector.deleteRemoteBranch(trackingRef: trackingRef, in: repository)
                }
                guard remoteOperationID == operationID else { return }
                if operation.fetchesRemote { lastFetchDates[updatedRepository.rootURL] = .now }
                library.invalidateActivity(at: updatedRepository.rootURL)
                guard acceptsCompletion() else { return }
                if writesWorkingTree || inspectionGeneration == startGeneration {
                    apply(updatedRepository, showWorkspaceOnSuccess: false)
                } else if !isLoading {
                    // Something else read the Repository while the remote operation ran; read once
                    // more so both results show. A local operation still in flight reads by itself.
                    _ = await inspect(
                        updatedRepository.rootURL,
                        rememberOnSuccess: false,
                        markCurrentStaleOnFailure: true,
                        showWorkspaceOnSuccess: false,
                        presentFailure: false
                    )
                }
                guard acceptsCompletion() else { return }
                showRemoteOperationResult(operation.successTitle(before: repository))
            } catch is CancellationError {
                return
            } catch let error as RepositoryFetchError {
                guard acceptsCompletion() else { return }
                if operation == .automaticFetch {
                    setAutomaticFetchEnabled(false)
                    present(error, title: operation.failureTitle)
                } else if case .fetch(remote: nil, pruning: let pruning) = operation,
                   case .remoteSelectionRequired(let remotes) = error
                {
                    repositorySheetRequest = .chooseFetchRemote(
                        repositoryRootURL: repository.rootURL,
                        remotes: remotes,
                        pruning: pruning
                    )
                } else {
                    present(error, title: operation.failureTitle)
                }
            } catch let error as RepositoryPushError {
                guard acceptsCompletion() else { return }
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
                        present(error, title: operation.failureTitle)
                    }
                } else {
                    present(error, title: operation.failureTitle)
                }
            } catch {
                guard acceptsCompletion() else { return }
                if operation == .automaticFetch {
                    setAutomaticFetchEnabled(false)
                }
                if writesWorkingTree {
                    let refreshedRepository = try? await inspector.inspect(at: repository.rootURL)
                    guard acceptsCompletion() else { return }
                    if let refreshedRepository {
                        apply(refreshedRepository, showWorkspaceOnSuccess: false)
                    }
                }
                present(error, title: operation.failureTitle)
            }
        }
        remoteTask = task
        return task
    }

    private func showRemoteOperationResult(_ title: String?) {
        remoteResultTask?.cancel()
        remoteOperationResult = title
        guard title != nil else { return }
        remoteResultTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled else { return }
            remoteOperationResult = nil
        }
    }

    func folderURL(for branch: String) -> URL? {
        guard let repository else { return nil }
        if repository.head == .branch(branch) { return repository.rootURL }
        return localBranchWorktreeURLs[branch]
    }

    func loadLocalBranches() async {
        guard !Task.isCancelled else { return }
        guard let repository else {
            localBranchesState = .notLoaded
            localBranches = []
            worktrees = []
            selectedWorktreeURL = nil
            return
        }
        let rootURL = repository.rootURL
        let revision = repositoryRevision
        localBranchesGeneration += 1
        let generation = localBranchesGeneration
        if case .loaded = localBranchesState {} else { localBranchesState = .loading }
        // Keep the last known Worktree indicators while this Repository reloads.

        do {
            async let branchesRequest = inspector.localBranches(in: repository)
            async let worktreesRequest = inspector.worktrees(in: repository)
            let (branches, worktrees) = try await (branchesRequest, worktreesRequest)
            guard
                !Task.isCancelled, generation == localBranchesGeneration,
                revision == repositoryRevision,
                self.repository.map({ sameFileLocation($0.rootURL, rootURL) }) == true
            else {
                return
            }
            if let selectedWorktreeURL {
                let previous = self.worktrees.first { $0.url == selectedWorktreeURL }
                let updated = worktrees.first { $0.url == selectedWorktreeURL }
                if previous?.headID != updated?.headID { historyNavigationRevision += 1 }
                if updated == nil { self.selectedWorktreeURL = nil }
            }
            self.worktrees = worktrees
            localBranches = branches
            localBranchesState = .loaded(branches)
            if case .branch(let name) = historySelection, !branches.contains(name) {
                historySelection = nil
            }
        } catch is CancellationError {
            return
        } catch {
            guard
                generation == localBranchesGeneration,
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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let updatedRepository = try await inspector.switchBranch(to: branch, in: repository)
            guard generation == inspectionGeneration else { return false }
            selectedHistoryCommitID = nil
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            historySelection = .branch(branch)
            library.invalidateActivity(at: updatedRepository.rootURL)
            return true
        } catch {
            guard generation == inspectionGeneration else { return false }
            present(error, title: "Couldn’t Switch Branch")
            return false
        }
    }

    func createBranch(named name: String, at startPoint: String? = nil) async -> Bool {
        let branch = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoading, !branch.isEmpty, let repository else {
            return false
        }

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let updatedRepository = try await inspector.createBranch(
                named: branch,
                at: startPoint,
                in: repository
            )
            guard generation == inspectionGeneration else { return false }
            selectedHistoryCommitID = nil
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            library.invalidateActivity(at: updatedRepository.rootURL)
            return true
        } catch {
            guard generation == inspectionGeneration else { return false }
            present(error, title: "Couldn’t Create Branch")
            return false
        }
    }

    func createWorktree(at destination: URL, branch: String, creatingBranch: Bool, startPoint: String) async -> URL? {
        guard !isLoading, !isSyncing, let repository else { return nil }
        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }
        do {
            let url = try await inspector.createWorktree(
                at: destination, branch: branch.trimmingCharacters(in: .whitespacesAndNewlines),
                creatingBranch: creatingBranch, startPoint: startPoint, in: repository
            )
            guard generation == inspectionGeneration else { return url }
            repositoryRevision += 1
            await loadLocalBranches()
            return url
        } catch {
            if generation == inspectionGeneration { present(error, title: "Couldn’t Create Worktree") }
            return nil
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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

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
            library.invalidateActivity(at: updatedRepository.rootURL)
            return true
        } catch {
            guard generation == inspectionGeneration else { return false }
            if let refreshedRepository = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return false }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            let title = switch action {
            case .fastForward: "Couldn’t Fast-Forward"
            case .mergeCommit: "Couldn’t Create Merge Commit"
            case .rebase: "Couldn’t Rebase"
            }
            present(error, title: title)
            return false
        }
    }

    func fastForwardBranchToCurrent(_ branch: String) async -> Bool {
        guard !isLoading, let repository else { return false }

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let worktrees = try await inspector.localBranchWorktrees(in: repository)
            guard generation == inspectionGeneration else { return false }
            let updatedRepository: RepositorySummary
            if let worktreeURL = worktrees[branch] {
                updatedRepository = try await inspector.fastForwardBranch(
                    branch,
                    inWorktreeAt: worktreeURL,
                    toCurrentIn: repository
                )
            } else {
                updatedRepository = try await inspector.fastForwardBranch(
                    branch,
                    toCurrentIn: repository
                )
            }
            guard generation == inspectionGeneration else { return false }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            library.invalidateActivity(at: updatedRepository.rootURL)
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard generation == inspectionGeneration else { return false }
            present(error, title: "Couldn’t Fast-Forward \(branch)")
            return false
        }
    }

    func mergePrediction(into branch: String) async -> RepositoryMergePrediction? {
        guard let repository else { return nil }
        return try? await inspector.mergePrediction(into: branch, in: repository)
    }

    var isCurrentWorkspaceTemporaryWorktree: Bool {
        guard let repository else { return false }
        return temporaryWorktreeEntry(for: repository.rootURL) != nil
    }

    private func temporaryWorktreeEntry(for url: URL) -> (worktree: URL, origin: URL)? {
        temporaryWorktrees
            .first { sameFileLocation($0.key, url) }
            .map { ($0.key, $0.value) }
    }

    func mergeCurrentBranchIntoBranch(_ branch: String) async -> RepositoryMergeIntoBranchResult {
        guard !isLoading, let repository else { return .failed }

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let worktrees = try await inspector.localBranchWorktrees(in: repository)
            guard generation == inspectionGeneration else { return .failed }
            let updatedRepository: RepositorySummary
            if let worktreeURL = worktrees[branch] {
                updatedRepository = try await inspector.mergeCurrentBranch(
                    into: branch,
                    inWorktreeAt: worktreeURL,
                    in: repository
                )
            } else {
                updatedRepository = try await inspector.createMergeCommit(
                    on: branch,
                    in: repository
                )
            }
            guard generation == inspectionGeneration else { return .failed }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            library.invalidateActivity(at: updatedRepository.rootURL)
            return .completed
        } catch is CancellationError {
            return .failed
        } catch RepositoryBranchError.mergeInWorktreeConflicted(let worktreeURL) {
            let worktree = try? await inspector.inspect(at: worktreeURL)
            guard generation == inspectionGeneration else { return .failed }
            guard let worktree, worktree.operation?.kind == .merge else {
                present(RepositoryOperationError.unavailable, title: "Couldn’t Inspect Merge")
                return .failed
            }
            return .conflictedInWorktree(worktree)
        } catch {
            guard generation == inspectionGeneration else { return .failed }
            present(error, title: "Couldn’t Create Merge Commit")
            return .failed
        }
    }

    func abortMergeInWorktree(_ worktree: RepositorySummary) async {
        guard !isLoading, let repository else { return }
        guard worktree.operation?.kind == .merge else {
            present(RepositoryOperationError.unavailable, title: "Couldn’t Abort Merge")
            return
        }

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            _ = try await inspector.abortOperation(in: worktree)
            guard generation == inspectionGeneration else { return }
            let updatedRepository = try await inspector.inspect(at: repository.rootURL)
            guard generation == inspectionGeneration else { return }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            present(error, title: "Couldn’t Abort Merge")
        }
    }

    func mergeInTemporaryWorktree(_ branch: String) async -> Bool {
        guard !isLoading, let repository else { return false }
        let originRootURL = repository.rootURL

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let worktreeURL = try await inspector.addTemporaryWorktree(for: branch, in: repository)
            guard generation == inspectionGeneration else { return false }
            do {
                let updatedRepository = try await inspector.mergeCurrentBranch(
                    into: branch,
                    inWorktreeAt: worktreeURL,
                    in: repository
                )
                guard generation == inspectionGeneration else { return false }
                // 충돌 없이 끝났으면 임시 Worktree를 바로 제거한다(명세 6D-3).
                let cleanedRepository = try await inspector.removeWorktree(
                    at: worktreeURL,
                    in: updatedRepository
                )
                guard generation == inspectionGeneration else { return false }
                apply(cleanedRepository, showWorkspaceOnSuccess: false)
                library.invalidateActivity(at: cleanedRepository.rootURL)
                return true
            } catch RepositoryBranchError.mergeInWorktreeConflicted {
                guard generation == inspectionGeneration else { return false }
                temporaryWorktrees[worktreeURL] = originRootURL
                return await inspect(
                    worktreeURL,
                    rememberOnSuccess: false,
                    markCurrentStaleOnFailure: false,
                    showWorkspaceOnSuccess: true,
                    presentFailure: true,
                    failureTitle: "Couldn’t Open Temporary Worktree"
                ) == .opened
            }
        } catch is CancellationError {
            return false
        } catch {
            guard generation == inspectionGeneration else { return false }
            present(error, title: "Couldn’t Merge in Temporary Worktree")
            return false
        }
    }

    func trackingRemoteBranch(for branch: String) async -> String? {
        guard let repository else { return nil }
        return (try? await inspector.trackingBranch(of: branch, in: repository)) ?? nil
    }

    func deleteRemoteBranch(_ trackingRef: String) {
        startRemoteOperation(.deleteRemoteBranch(trackingRef: trackingRef))
    }

    func removeTrackingReference(_ trackingRef: String) async {
        guard !isLoading, let repository else { return }

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let updatedRepository = try await inspector.removeRemoteTrackingReference(
                trackingRef,
                in: repository
            )
            guard generation == inspectionGeneration else { return }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            present(error, title: "Couldn’t Remove Tracking Reference")
        }
    }

    // 각 단계는 앞 단계 성공 뒤에만 실행하며, 실패하면 완료된 앞 단계는 되돌리지 않는다.
    func removeWorktree(
        at worktreeURL: URL,
        deletingBranch branch: String?,
        deletingRemoteTrackingRef trackingRef: String?
    ) async {
        guard await removeWorktree(at: worktreeURL) else { return }
        if let branch {
            guard await deleteBranch(branch) else { return }
        }
        if let trackingRef,
           let task = startRemoteOperation(.deleteRemoteBranch(trackingRef: trackingRef)) {
            await task.value
        }
    }

    @discardableResult
    func removeWorktree(at worktreeURL: URL) async -> Bool {
        guard !isLoading, let repository else { return false }

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let updatedRepository = try await inspector.removeWorktree(
                at: worktreeURL,
                in: repository
            )
            guard generation == inspectionGeneration else { return false }
            temporaryWorktrees.removeValue(forKey: worktreeURL)
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard generation == inspectionGeneration else { return false }
            present(error, title: "Couldn’t Remove Worktree")
            return false
        }
    }

    @discardableResult
    func deleteBranch(_ branch: String) async -> Bool {
        guard !isLoading, let repository else { return false }

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let updatedRepository = try await inspector.deleteBranch(named: branch, in: repository)
            guard generation == inspectionGeneration else { return false }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard generation == inspectionGeneration else { return false }
            present(error, title: "Couldn’t Delete Branch")
            return false
        }
    }

    func removeTemporaryWorktree(at worktreeURL: URL) async {
        guard let entry = temporaryWorktreeEntry(for: worktreeURL) else { return }
        pendingTemporaryWorktreeRemovalURL = nil

        guard await inspect(
            entry.origin,
            rememberOnSuccess: false,
            markCurrentStaleOnFailure: false,
            showWorkspaceOnSuccess: true,
            presentFailure: true,
            failureTitle: "Couldn’t Open Repository"
        ) == .opened, let repository else {
            return
        }

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let updatedRepository = try await inspector.removeWorktree(
                at: entry.worktree,
                in: repository
            )
            guard generation == inspectionGeneration else { return }
            temporaryWorktrees.removeValue(forKey: entry.worktree)
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            present(error, title: "Couldn’t Remove Worktree")
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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

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
            present(error, title: "Couldn’t Apply Stash")
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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

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
            present(error, title: "Couldn’t Delete Stash")
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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let updatedRepository = try await inspector.revertCommit(
                commit,
                mainlineParent: mainlineParent,
                in: repository
            )
            guard generation == inspectionGeneration else { return }
            selectedHistoryCommitID = nil
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            library.invalidateActivity(at: updatedRepository.rootURL)
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            if let refreshedRepository = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            present(error, title: "Couldn’t Revert Commit")
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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let updatedRepository = try await inspector.resetCurrentBranch(
                to: commit,
                mode: mode,
                in: repository
            )
            guard generation == inspectionGeneration else { return }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            library.invalidateActivity(at: updatedRepository.rootURL)
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            if let refreshedRepository = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            present(error, title: "Couldn’t Reset Branch")
        }
    }

    func stageSelectedChange() async {
        guard let selectedChangeID else { return }
        await stageChanges(ids: [selectedChangeID])
    }

    /// Every unstaged and untracked change that isn't a conflict.
    func stageAllChanges() async {
        guard let repository else { return }
        await stageChanges(ids: Set(repository.changes.filter { $0.unstaged != nil && !$0.isConflicted }.map(\.id)))
    }

    func stageChanges(ids: Set<RepositorySummary.Change.ID>) async {
        guard
            !isLoading,
            let repository,
            !ids.isEmpty
        else {
            return
        }
        let changes = repository.changes.filter {
            ids.contains($0.id) && !$0.isConflicted && $0.unstaged != nil
        }
        guard !changes.isEmpty else { return }

        await performRepositoryWrite(in: repository, failureTitle: "Couldn’t Stage Changes") {
            try await inspector.stage(changes, in: repository)
        }
    }

    func unstageSelectedChange() async {
        guard let selectedChangeID else { return }
        await unstageChanges(ids: [selectedChangeID])
    }

    func unstageChanges(ids: Set<RepositorySummary.Change.ID>) async {
        guard
            !isLoading,
            let repository,
            !ids.isEmpty
        else {
            return
        }
        let changes = repository.changes.filter {
            ids.contains($0.id) && !$0.isConflicted && $0.staged != nil
        }
        guard !changes.isEmpty else { return }

        await performRepositoryWrite(in: repository, failureTitle: "Couldn’t Unstage Changes") {
            try await inspector.unstage(changes, in: repository)
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

        await performRepositoryWrite(in: repository, failureTitle: "Couldn’t Discard Changes") {
            try await inspector.discard(change, in: repository)
        }
    }

    func openSelectedConflictInMergeTool() async {
        guard !isLoading, let repository, let change = selectedChange, change.isConflicted else { return }
        let tool = MergeTool(rawValue: UserDefaults.standard.string(forKey: MergeTool.storageKey) ?? "") ?? .git
        let executableURL = tool.executableURL
        inspectionGeneration += 1
        let generation = inspectionGeneration
        isLoading = true
        isWritingRepository = true
        activeMergeTool = tool.title
        defer {
            activeMergeTool = nil
            if generation == inspectionGeneration { isLoading = false; isWritingRepository = false }
        }
        do {
            let updated = try await inspector.openMergeTool(for: change, in: repository, tool: tool, executableURL: executableURL)
            guard generation == inspectionGeneration else { return }
            apply(updated, showWorkspaceOnSuccess: false)
        } catch {
            guard generation == inspectionGeneration else { return }
            if let updated = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return }
                apply(updated, showWorkspaceOnSuccess: false)
            }
            present(error, title: "Couldn’t Complete Merge Tool")
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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

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
            present(error, title: "Couldn’t Resolve Conflict")
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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

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
            present(error, title: "Couldn’t Resolve Conflict")
        }
    }

    func continueRepositoryOperation(in repository: RepositorySummary) async {
        await updateRepositoryOperation(in: repository, aborting: false)
    }

    func abortRepositoryOperation(in repository: RepositorySummary) async {
        await updateRepositoryOperation(in: repository, aborting: true)
    }

    private func updateRepositoryOperation(in repository: RepositorySummary, aborting: Bool) async {
        guard !isLoading else { return }
        guard
            let activeRepository = self.repository,
            sameFileLocation(activeRepository.rootURL, repository.rootURL),
            let operation = repository.operation
        else {
            present(RepositoryOperationError.unavailable, title: "Couldn’t Update Repository Operation")
            return
        }

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }
        library.invalidateActivity(at: repository.rootURL)

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
            if updatedRepository.operation == nil,
               let entry = temporaryWorktreeEntry(for: updatedRepository.rootURL) {
                pendingTemporaryWorktreeRemovalURL = entry.worktree
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            if let refreshedRepository = try? await inspector.inspect(at: repository.rootURL) {
                guard generation == inspectionGeneration else { return }
                apply(refreshedRepository, showWorkspaceOnSuccess: false)
            }
            let kindName = operation.kind == .merge ? "Merge" : "Rebase"
            present(error, title: aborting ? "Couldn’t Abort \(kindName)" : "Couldn’t Continue \(kindName)")
        }
    }

    func updateSelectedHunk(_ hunk: RepositoryDiff.Hunk) async {
        guard !isLoading, let repository, let change = selectedChange else { return }

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let updatedRepository: RepositorySummary
            switch hunk.scope {
            case .unstaged where canStageSelectedHunks, .untracked where canStageSelectedHunks:
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
            present(
                error,
                title: hunk.scope == .staged ? "Couldn’t Unstage Hunk" : "Couldn’t Stage Hunk"
            )
        }
    }

    /// Rewrites the working tree file without one hunk or its chosen lines. The caller confirms first.
    func discardSelectedHunk(_ hunk: RepositoryDiff.Hunk) async {
        guard !isLoading, let repository, let change = selectedChange, hunk.scope == .unstaged else { return }

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let updatedRepository = try await inspector.discard(hunk, for: change, in: repository)
            guard generation == inspectionGeneration else { return }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
        } catch {
            guard generation == inspectionGeneration else { return }
            present(error, title: "Couldn’t Discard Lines")
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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

        do {
            let updatedRepository = try await inspector.commit(
                subject: subject,
                body: body,
                amend: amend,
                in: repository
            )
            guard generation == inspectionGeneration else { return false }
            apply(updatedRepository, showWorkspaceOnSuccess: false)
            library.invalidateActivity(at: updatedRepository.rootURL)
            return true
        } catch {
            guard generation == inspectionGeneration else { return false }
            present(error, title: amend ? "Couldn’t Amend Commit" : "Couldn’t Commit")
            return false
        }
    }

    func headCommitMessage() async -> RepositoryCommitMessage? {
        guard let repository, !repository.isUnborn else { return nil }
        return try? await inspector.headCommitMessage(in: repository)
    }

    func branchDivergence(from branch: String) async -> RepositoryBranchDivergence? {
        guard let repository else { return nil }
        return try? await inspector.divergence(from: branch, in: repository)
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
            try library.reconnectRecentRepository(oldURL, to: inspectedRepository)
            apply(inspectedRepository, showWorkspaceOnSuccess: true)
        } catch {
            guard generation == inspectionGeneration else { return }
            present(error, title: "Couldn’t Open Repository")
        }
    }

    func restoreState() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true

        guard let workspace = library.restore() else { return }

        if let message = workspace.errorMessage {
            library.recordFailure(message, at: workspace.url)
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
        if restored == .failed {
            store.clearLastWorkspace()
            screen = .library
        }
    }

    func present(_ error: Error, title: String? = nil) {
        guard !(error is CancellationError) else { return }
        if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
            return
        }
        errorTitle = title
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // 250ms 안에 끝나는 로드는 이전 내용을 유지해 스피너 깜빡임을 만들지 않는다.
    private func delayedSpinner(_ show: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            show()
        }
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
        var pendingSpinner: Task<Void, Never>?
        if case .loaded = diffState {
            pendingSpinner = delayedSpinner { [self] in
                guard generation == diffGeneration else { return }
                diffState = .loading
            }
        } else {
            diffState = .loading
        }
        defer { pendingSpinner?.cancel() }

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

    func loadMoreHistory() {
        if case .loaded(let history) = historyState {
            historyLimit = history.commits.count + RepositoryInspector.maximumHistoryCommits
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
        if case .loaded = historyState {
            // Keep the current revision available while refreshing its list.
        } else {
            historyState = .loading
        }

        do {
            let isNavigation = request.navigationRevision != appliedHistoryNavigationRevision
            let previousCount: Int
            if appliedHistoryReference == request.reference, case .loaded(let previous) = historyState {
                previousCount = previous.commits.count
            }
            else { previousCount = 0 }
            let history = try await inspector.history(
                in: repository, reference: request.reference,
                focusReference: isNavigation ? request.focusReference : nil,
                limit: max(request.limit, previousCount)
            )
            guard generation == historyGeneration, request == historyRequest else { return }
            historyState = .loaded(history)
            // A branch or tag scope may not contain HEAD; its tip comes first in topo order.
            let headID = history.headCommitID.flatMap { headID in
                history.commits.contains(where: { $0.id == headID }) ? headID : nil
            }
            let focusedID = history.focusedCommitID.flatMap { id in
                history.commits.contains(where: { $0.id == id }) ? id : nil
            }
            if isNavigation {
                historyNavigationMessage = request.focusReference != nil && focusedID == nil
                    ? "This reference is outside the current filter." : nil
            }
            selectedHistoryCommitID = focusedID ?? selectedHistoryCommitID.flatMap { selectedID in
                history.commits.contains(where: { $0.id == selectedID }) ? selectedID : nil
            } ?? headID ?? history.commits.first?.id
            appliedHistoryNavigationRevision = request.navigationRevision
            appliedHistoryReference = request.reference
            if isNavigation { historyScrollRevision += 1 }
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

        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }

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
            library.invalidateActivity(at: updatedRepository.rootURL)
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

    func loadSelectedCommitSignature() async {
        commitSignatureGeneration += 1
        let generation = commitSignatureGeneration
        selectedCommitSignature = nil
        guard let repository, let commit = selectedHistoryCommit else { return }

        let signature = try? await inspector.commitSignature(for: commit, in: repository)
        guard
            generation == commitSignatureGeneration,
            selectedHistoryCommit?.id == commit.id
        else {
            return
        }
        selectedCommitSignature = signature
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
        var pendingSpinner: Task<Void, Never>?
        if case .loaded = commitFilesState {
            pendingSpinner = delayedSpinner { [self] in
                guard generation == commitFilesGeneration else { return }
                commitFilesState = .loading
            }
        } else {
            commitFilesState = .loading
        }
        defer { pendingSpinner?.cancel() }

        do {
            let files = try await inspector.files(for: commit, in: repository)
            guard
                generation == commitFilesGeneration,
                request == commitFilesRequest
            else {
                return
            }
            commitFilesState = .loaded(files)
            let previousSelection = selectedHistoryFileID
            selectedHistoryFileID = previousSelection.flatMap { id in
                files.contains { $0.id == id } ? id : nil
            } ?? files.first?.id
            if selectedHistoryFileID == nil {
                commitPatchState = .noSelection
            } else if selectedHistoryFileID != previousSelection {
                commitPatchState = .loading
            }
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
        var pendingSpinner: Task<Void, Never>?
        if case .loaded = commitPatchState {
            pendingSpinner = delayedSpinner { [self] in
                guard generation == commitPatchGeneration else { return }
                commitPatchState = .loading
            }
        } else {
            commitPatchState = .loading
        }
        defer { pendingSpinner?.cancel() }

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
        guard !Task.isCancelled else { return }
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
        if case .loaded = stashesState {
            // Keep the current revision available while refreshing its list.
        } else {
            stashesState = .loading
        }

        do {
            let stashes = try await inspector.stashes(in: repository)
            guard generation == stashesGeneration, request == stashesRequest else { return }
            stashesState = .loaded(stashes)
            selectedStashID = selectedStashID.flatMap { selectedID in
                stashes.contains(where: { $0.id == selectedID }) ? selectedID : nil
            } ?? stashes.first?.id
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
        var pendingSpinner: Task<Void, Never>?
        if case .loaded = stashFilesState {
            pendingSpinner = delayedSpinner { [self] in
                guard generation == stashFilesGeneration else { return }
                stashFilesState = .loading
            }
        } else {
            stashFilesState = .loading
        }
        defer { pendingSpinner?.cancel() }

        do {
            let files = try await inspector.files(for: stash, in: repository)
            guard generation == stashFilesGeneration, request == stashFilesRequest else { return }
            stashFilesState = .loaded(files)
            let previousSelection = selectedStashFileID
            selectedStashFileID = previousSelection.flatMap { id in
                files.contains { $0.id == id } ? id : nil
            } ?? files.first?.id
            if selectedStashFileID == nil {
                stashPatchState = .noSelection
            } else if selectedStashFileID != previousSelection {
                stashPatchState = .loading
            }
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
        var pendingSpinner: Task<Void, Never>?
        if case .loaded = stashPatchState {
            pendingSpinner = delayedSpinner { [self] in
                guard generation == stashPatchGeneration else { return }
                stashPatchState = .loading
            }
        } else {
            stashPatchState = .loading
        }
        defer { pendingSpinner?.cancel() }

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

    private func beginRepositoryWrite() -> Int {
        inspectionGeneration += 1
        isLoading = true
        isWritingRepository = true
        return inspectionGeneration
    }

    private func finishRepositoryWrite(_ generation: Int) {
        guard generation == inspectionGeneration else { return }
        isLoading = false
        isWritingRepository = false
    }

    /// Common completion for local file writes. Operations with conflict recovery keep their own completion.
    private func performRepositoryWrite(
        in repository: RepositorySummary,
        failureTitle: String,
        operation: () async throws -> RepositorySummary
    ) async {
        guard !isLoading, self.repository.map({ sameFileLocation($0.rootURL, repository.rootURL) }) == true else { return }
        let generation = beginRepositoryWrite()
        defer { finishRepositoryWrite(generation) }
        do {
            let updated = try await operation()
            guard generation == inspectionGeneration else { return }
            apply(updated, showWorkspaceOnSuccess: false)
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectionGeneration else { return }
            present(error, title: failureTitle)
        }
    }

    private enum InspectionOutcome {
        case opened, failed, discarded
    }

    private func inspect(
        _ url: URL,
        rememberOnSuccess: Bool,
        markCurrentStaleOnFailure: Bool,
        showWorkspaceOnSuccess: Bool,
        presentFailure: Bool,
        failureTitle: String? = nil,
        addLibraryFolderWhenNotWorkingTree: Bool = false,
        preservingHistoryScope: Bool = false
    ) async -> InspectionOutcome {
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
            let inspectedRepository = try await inspectRepository(url)
            guard !Task.isCancelled, generation == inspectionGeneration else { return .discarded }
            if rememberOnSuccess {
                try library.rememberOpenedRepository(inspectedRepository.rootURL)
            }
            apply(inspectedRepository, showWorkspaceOnSuccess: showWorkspaceOnSuccess,
                  preservingHistoryScope: preservingHistoryScope)
            return .opened
        } catch is CancellationError {
            return .discarded
        } catch {
            guard !Task.isCancelled, generation == inspectionGeneration else { return .discarded }
            if
                addLibraryFolderWhenNotWorkingTree,
                let inspectionError = error as? RepositoryInspectionError,
                case .notWorkingTree = inspectionError,
                !RepositoryScanner.hasRepositoryMarker(at: url)
            {
                library.addLibraryFolder(at: url)
                return .failed
            }
            if markCurrentStaleOnFailure, repository != nil {
                isRepositoryStale = true
            }
            if presentFailure {
                present(error, title: failureTitle)
            } else {
                library.recordFailure(Self.message(for: error), at: url)
            }
            return .failed
        }
    }

    private func apply(
        _ inspectedRepository: RepositorySummary,
        showWorkspaceOnSuccess: Bool,
        preservingHistoryScope: Bool = false
    ) {
        let isSameRepository = repository.map {
            sameFileLocation($0.rootURL, inspectedRepository.rootURL)
        } == true
        let previousSelection = isSameRepository
            ? selectedChangeID
            : nil
        // Refresh keeps the reader's context; opening another repository resets it.
        if !isSameRepository {
            if !preservingHistoryScope {
                historyScope = nil
                historySelection = nil
                historyLimit = RepositoryInspector.maximumHistoryCommits
            }
            historyState = .notLoaded
            stashesState = .notLoaded
            reflogState = .notLoaded
            selectedHistoryFileID = nil
            commitFilesState = .noSelection
            commitPatchState = .noSelection
            selectedStashFileID = nil
            stashFilesState = .noSelection
            stashPatchState = .noSelection
            selectedHistoryCommitID = nil
            selectedStashID = nil
            selectedReflogEntryID = nil
        }
        repository = inspectedRepository
        repositoryRevision += 1
        selectedChangeID = previousSelection.flatMap { selectedID in
            inspectedRepository.changes.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? inspectedRepository.changes.first?.id
        if selectedChangeID == nil {
            diffState = .noSelection
        } else if selectedChangeID != previousSelection {
            diffState = .loading
        } else if case .loaded = diffState {
            // 같은 파일이 그대로 선택돼 있으면 현재 diff를 유지하고 reload가 제자리에서 교체한다.
        } else {
            diffState = .loading
        }
        reflogState = .notLoaded
        if !isSameRepository {
            localBranchesState = .notLoaded
            localBranches = []
            remoteBranchesByRemote = [:]
            worktrees = []
            selectedWorktreeURL = nil
            remotesState = .notLoaded
            tagsState = .notLoaded
        }
        library.record(inspectedRepository)
        isRepositoryStale = false
        errorTitle = nil
        errorMessage = nil
        if showWorkspaceOnSuccess {
            screen = .workspace
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
