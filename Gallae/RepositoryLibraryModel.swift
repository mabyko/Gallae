import Foundation
import Observation

enum RepositoryLibrarySource: Hashable, Sendable {
    case recent
    case folder(URL)
}

@MainActor
@Observable
final class RepositoryLibraryModel {
    var errorMessage: String?
    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let inspector = RepositoryInspector()

    init(
        store: LibraryStore,
        scan: @escaping @Sendable (URL) -> AsyncStream<RepositoryScanEvent> = {
            RepositoryScanner().scan(in: $0)
        }
    ) {
        self.store = store
        self.scan = scan
    }

    @ObservationIgnored private var scanningFolderIDs: [URL] = []

    @ObservationIgnored private var scanTask: Task<Void, Never>?

    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var activeScanProgress: (folderID: URL, progress: LibraryScanProgress)?

    @ObservationIgnored private let scan: @Sendable (URL) -> AsyncStream<RepositoryScanEvent>

    var libraryFolders: [RepositoryLibraryFolder] = [] {
        didSet { updateHierarchies(previousFolders: oldValue) }
    }

    private(set) var libraryHierarchies: [URL: RepositoryHierarchySnapshot] = [:]

    private func updateHierarchies(previousFolders: [RepositoryLibraryFolder]) {
        let previous = Dictionary(uniqueKeysWithValues: previousFolders.map { ($0.id, $0.repositories) })
        let currentIDs = Set(libraryFolders.map(\.id))
        for id in libraryHierarchies.keys where !currentIDs.contains(id) {
            libraryHierarchies[id] = nil
        }
        for folder in libraryFolders where previous[folder.id] != folder.repositories {
            libraryHierarchies[folder.id] = RepositoryHierarchySnapshot(
                repositories: folder.repositories, relativeTo: folder.url
            )
        }
    }

    var recentRepositories: [RepositoryLocation] = []

    var selectedLibrarySource: RepositoryLibrarySource? = .recent

    var selectedLibraryRepositoryID: URL?

    private(set) var libraryRepositorySummaries: [URL: RepositorySummary] = [:]

    private(set) var libraryRepositorySummaryErrors: [URL: String] = [:]

    private(set) var loadingLibraryRepositorySummaries: Set<URL> = []

    private(set) var libraryRepositoryActivities: [URL: RepositoryActivity] = [:]

    private(set) var libraryRepositoryActivityErrors: [URL: String] = [:]

    private(set) var loadingLibraryRepositoryActivities: Set<URL> = []

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
        if let activeScanProgress {
            publishScanProgress(activeScanProgress.progress, folderID: activeScanProgress.folderID)
            self.activeScanProgress = nil
        }
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

    func removeRecentRepository(_ url: URL) {
        removeRecentRepositories([url])
    }

    func removeRecentRepositories(_ urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        for url in urls {
            store.removeRecentRepository(url)
        }
        let removedRepositories = recentRepositories.filter { repository in
            urls.contains { sameFileLocation($0, repository.id) }
        }
        recentRepositories.removeAll { repository in
            urls.contains { sameFileLocation($0, repository.id) }
        }
        discardUnusedCaches(for: removedRepositories)
        if selectedLibrarySource == .recent,
           selectedLibraryRepositoryID == nil
            || selectedLibraryRepositoryID.map({ selectedID in
                urls.contains { sameFileLocation($0, selectedID) }
            }) == true {
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
        let progress = LibraryScanProgress(existing: libraryFolders.first { $0.id == folderID }?.repositories ?? [])
        activeScanProgress = (folderID, progress)
        var pendingPublication: Task<Void, Never>?
        defer {
            pendingPublication?.cancel()
            if activeScanProgress?.progress === progress { activeScanProgress = nil }
        }

        for await event in scan(folderID) {
            guard !Task.isCancelled, generation == scanGeneration else { return }

            switch event {
            case .found(let repository):
                progress.append(repository)
                if !progress.pending.isEmpty {
                    // Show the first result immediately, then publish at most every 100 ms,
                    // including when a slow filesystem scan is waiting on its next result.
                    if progress.publishedCount == 0 {
                        pendingPublication?.cancel()
                        pendingPublication = nil
                        publishScanProgress(progress, folderID: folderID)
                    } else if pendingPublication == nil {
                        pendingPublication = Task { [weak self] in
                            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                            guard let self, generation == self.scanGeneration else { return }
                            self.publishScanProgress(progress, folderID: folderID)
                            pendingPublication = nil
                        }
                    }
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

        pendingPublication?.cancel()
        guard !Task.isCancelled, generation == scanGeneration else { return }
        let repositoriesBeforeReconciliation = libraryFolders.first { $0.id == folderID }?.repositories ?? []
        let shouldReconcile = rootFailureMessage == nil || !progress.found.isEmpty
        let foundRepositories = progress.found.sorted {
            $0.rootURL.path.localizedStandardCompare($1.rootURL.path) == .orderedAscending
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
            let removedRepositories = repositoriesBeforeReconciliation.filter {
                !progress.foundPaths.contains($0.id.standardizedFileURL.path)
            }
            discardUnusedCaches(for: removedRepositories)
            if selectedLibraryFolderID.map({ sameFileLocation($0, folderID) }) == true,
               selectedLibraryRepositoryID.map({
                   !progress.foundPaths.contains($0.standardizedFileURL.path)
               }) != false {
                selectedLibraryRepositoryID = foundRepositories.first?.id
            }
        }
    }

    private func publishScanProgress(_ progress: LibraryScanProgress, folderID: URL) {
        guard !progress.pending.isEmpty else { return }
        let batch = progress.pending
        progress.pending.removeAll(keepingCapacity: true)
        progress.publishedCount += batch.count
        updateLibraryFolder(id: folderID) { folder in
            folder.repositories.append(contentsOf: batch)
            folder.repositories.sort {
                $0.rootURL.path.localizedStandardCompare($1.rootURL.path) == .orderedAscending
            }
        }
        if selectedLibraryFolderID == folderID, selectedLibraryRepositoryID == nil {
            selectedLibraryRepositoryID = batch.first?.id
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

    func restore() -> RestoredLocation? {
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

        guard let workspace = store.restoreLastWorkspace() else { return nil }
        if !recentRepositories.contains(where: { sameFileLocation($0.id, workspace.url) }) {
            recentRepositories.insert(.init(rootURL: workspace.url), at: 0)
        }
        selectedLibrarySource = .recent
        selectedLibraryRepositoryID = workspace.url

        return workspace
    }

    func record(_ summary: RepositorySummary) {
        let id = repositoryCacheID(for: summary.rootURL)
        libraryRepositorySummaries[id] = summary
        libraryRepositorySummaryErrors[id] = nil
    }

    func recordFailure(_ message: String, at url: URL) {
        libraryRepositorySummaries[url] = nil
        libraryRepositorySummaryErrors[url] = message
    }

    func invalidateActivity(at url: URL) {
        let id = repositoryCacheID(for: url)
        libraryRepositoryActivities[id] = nil
        libraryRepositoryActivityErrors[id] = nil
    }

    func rememberOpenedRepository(_ url: URL) throws {
        try store.rememberOpenedRepository(url)
        recentRepositories.removeAll { sameFileLocation($0.id, url) }
        recentRepositories.insert(.init(rootURL: url), at: 0)
        if selectedLibrarySource == .recent { selectedLibraryRepositoryID = url }
    }

    func reconnectRecentRepository(_ oldURL: URL, to summary: RepositorySummary) throws {
        try store.replaceRecentRepository(oldURL, with: summary.rootURL)
        recentRepositories.removeAll { sameFileLocation($0.id, oldURL) || sameFileLocation($0.id, summary.rootURL) }
        recentRepositories.insert(.init(rootURL: summary.rootURL), at: 0)
        discardUnusedCaches(for: [.init(rootURL: oldURL)])
        selectedLibrarySource = .recent
        selectedLibraryRepositoryID = summary.rootURL
    }

    private func present(_ error: Error) {
        guard !(error is CancellationError), (error as? CocoaError)?.code != .userCancelled else { return }
        errorMessage = Self.message(for: error)
    }


    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

struct RepositoryHierarchyNode: Equatable, Identifiable, Sendable {
    let id: URL
    let name: String
    var children: [RepositoryHierarchyNode]?
    let repository: RepositoryLocation?

    var repositoryCount: Int {
        (repository == nil ? 0 : 1) + (children?.reduce(0) { $0 + $1.repositoryCount } ?? 0)
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
        let root = Builder(url: rootURL)
        for repository in repositories {
            let url = repository.rootURL.standardizedFileURL
            let components = url.pathComponents
            guard components.starts(with: rootComponents) else { continue }
            var parent = root
            for component in components.dropFirst(rootComponents.count).dropLast() {
                if let existing = parent.folders[component] {
                    parent = existing
                } else {
                    let folder = Builder(url: parent.url.appending(path: component, directoryHint: .isDirectory))
                    parent.folders[component] = folder
                    parent = folder
                }
            }
            if parent.repositories[url.path] == nil { parent.repositories[url.path] = repository }
        }
        return root.nodes()
    }

    private final class Builder {
        let url: URL
        var folders: [String: Builder] = [:]
        var repositories: [String: RepositoryLocation] = [:]

        init(url: URL) { self.url = url }

        func nodes() -> [RepositoryHierarchyNode] {
            let folderPaths = Set(folders.values.map { $0.url.standardizedFileURL.path })
            let children = folders.values.map {
                RepositoryHierarchyNode(id: $0.url, name: $0.url.lastPathComponent,
                                        children: $0.nodes(), repository: repositories[$0.url.standardizedFileURL.path])
            } + repositories.filter { !folderPaths.contains($0.key) }.values.map {
                RepositoryHierarchyNode(id: $0.id, name: $0.name, children: nil, repository: $0)
            }
            return children.sorted {
                let comparison = $0.name.localizedStandardCompare($1.name)
                if comparison == .orderedSame { return $0.repository == nil && $1.repository != nil }
                return comparison == .orderedAscending
            }
        }
    }
}

/// Derived once when a folder's repository list changes; selection and status updates reuse it.
final class RepositoryHierarchySnapshot: Sendable {
    let nodes: [RepositoryHierarchyNode]
    private let nodesByPath: [String: RepositoryHierarchyNode]

    init(repositories: [RepositoryLocation], relativeTo rootURL: URL) {
        nodes = RepositoryHierarchyNode.make(repositories, relativeTo: rootURL)
        var index: [String: RepositoryHierarchyNode] = [:]
        func indexNodes(_ nodes: [RepositoryHierarchyNode]) {
            for node in nodes {
                let path = node.id.standardizedFileURL.path
                index[path] = node
                if let children = node.children { indexNodes(children) }
            }
        }
        indexNodes(nodes)
        nodesByPath = index
    }

    func node(matching id: URL) -> RepositoryHierarchyNode? {
        nodesByPath[id.standardizedFileURL.path]
    }
}

@MainActor
private final class LibraryScanProgress {
    var found: [RepositoryLocation] = []
    var foundPaths: Set<String> = []
    var pending: [RepositoryLocation] = []
    var publishedCount: Int
    private var publishedPaths: Set<String>

    init(existing: [RepositoryLocation]) {
        publishedPaths = Set(existing.map { $0.id.standardizedFileURL.path })
        publishedCount = existing.count
    }

    func append(_ repository: RepositoryLocation) {
        let path = repository.id.standardizedFileURL.path
        guard foundPaths.insert(path).inserted else { return }
        found.append(repository)
        if publishedPaths.insert(path).inserted { pending.append(repository) }
    }
}
