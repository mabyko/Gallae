import Foundation

struct RepositoryLocation: Equatable, Identifiable, Sendable {
    let rootURL: URL

    var id: URL { rootURL }
    var name: String { rootURL.lastPathComponent }
}

struct RepositoryScanFailure: Equatable, Sendable {
    let url: URL
    let message: String
}

enum RepositoryScanEvent: Equatable, Sendable {
    case found(RepositoryLocation)
    case failed(RepositoryScanFailure)
}

enum LibraryFolderScanState: Equatable, Sendable {
    case idle
    case scanning
    case completed(partialFailureCount: Int)
    case cancelled
    case failed(String)
}

struct RepositoryLibraryFolder: Equatable, Identifiable, Sendable {
    let url: URL
    var repositories: [RepositoryLocation] = []
    var scanState: LibraryFolderScanState = .idle
    var firstFailure: RepositoryScanFailure?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct RepositoryScanner: Sendable {
    private static let maximumConcurrentValidations = 4

    func scan(in rootURL: URL) -> AsyncStream<RepositoryScanEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                await Self.scan(in: rootURL.standardizedFileURL, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private static func scan(
        in rootURL: URL,
        continuation: AsyncStream<RepositoryScanEvent>.Continuation
    ) async {
        defer { continuation.finish() }

        var scopes = [RepositoryScanScope(url: rootURL, includesRoot: true)]
        var scopeIndex = 0
        while !isCurrentTaskCancelled, scopeIndex < scopes.count {
            let scope = scopes[scopeIndex]
            scopeIndex += 1
            let candidates = CandidateIterator(scope: scope, continuation: continuation)
            let descendantRoots = await validateCandidates(nextCandidate: candidates.next, continuation: continuation)
            scopes.append(contentsOf: descendantRoots.map {
                RepositoryScanScope(url: $0, includesRoot: false)
            })
        }
    }

    /// The iterator remains on this detached scan task. At most four validation tasks exist;
    /// workers publish directly, so a long next filesystem traversal cannot hold a ready result.
    static func validateCandidates(
        nextCandidate: () -> URL?,
        continuation: AsyncStream<RepositoryScanEvent>.Continuation,
        workingTreeRoot: @escaping @Sendable (URL) throws -> URL = { try RepositoryInspector.workingTreeRoot(at: $0) }
    ) async -> [URL] {
        var descendantRoots: [URL] = []
        await withTaskGroup(of: URL?.self) { group in
            var inFlight = 0
            while !isCurrentTaskCancelled, let candidate = nextCandidate() {
                guard !isCurrentTaskCancelled else { break }
                group.addTask(priority: .utility) {
                    let validation: RepositoryCandidateValidation
                    do {
                        validation = try await CommandRunner.read {
                            validateCandidate(at: candidate, workingTreeRoot: workingTreeRoot)
                        }
                    } catch { return nil }
                    guard !Task.isCancelled else { return nil }
                    switch validation {
                    case .found(let url): continuation.yield(.found(.init(rootURL: url)))
                    case .failed(let failure): continuation.yield(.failed(failure))
                    case .descend(let url): return url
                    case .skip: break
                    }
                    return nil
                }
                inFlight += 1
                if inFlight == maximumConcurrentValidations {
                    if let result = await group.next(), let url = result { descendantRoots.append(url) }
                    inFlight -= 1
                }
                await Task.yield()
            }
            if isCurrentTaskCancelled { group.cancelAll() }
            while let result = await group.next() {
                if let url = result { descendantRoots.append(url) }
            }
        }
        return descendantRoots
    }

    private final class CandidateIterator {
        private let scope: RepositoryScanScope
        private let continuation: AsyncStream<RepositoryScanEvent>.Continuation
        private let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isRegularFileKey, .isSymbolicLinkKey]
        private var started = false
        private var enumerator: FileManager.DirectoryEnumerator?

        init(scope: RepositoryScanScope, continuation: AsyncStream<RepositoryScanEvent>.Continuation) {
            self.scope = scope
            self.continuation = continuation
        }

        func next() -> URL? {
            guard !isCurrentTaskCancelled else { return nil }
            if !started {
                started = true
                if scope.includesRoot {
                    do {
                        switch try disposition(of: scope.url, resourceKeys: keys) {
                        case .candidate: return scope.url
                        case .skip: return nil
                        case .descend: break
                        }
                    } catch {
                        continuation.yield(.failed(.init(url: scope.url, message: error.localizedDescription)))
                        return nil
                    }
                }
                enumerator = FileManager.default.enumerator(
                    at: scope.url, includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { [continuation] url, error in
                        guard !isCurrentTaskCancelled else { return false }
                        continuation.yield(.failed(.init(url: url, message: error.localizedDescription)))
                        return true
                    }
                )
                if enumerator == nil {
                    continuation.yield(.failed(.init(url: scope.url, message: "The Library Folder could not be read.")))
                }
            }
            while !isCurrentTaskCancelled, let url = enumerator?.nextObject() as? URL {
                do {
                    switch try disposition(of: url, resourceKeys: keys) {
                    case .candidate:
                        enumerator?.skipDescendants()
                        return url
                    case .skip: enumerator?.skipDescendants()
                    case .descend: break
                    }
                } catch {
                    enumerator?.skipDescendants()
                    continuation.yield(.failed(.init(url: url, message: error.localizedDescription)))
                }
            }
            return nil
        }
    }

    private static func validateCandidate(
        at url: URL, workingTreeRoot: (URL) throws -> URL
    ) -> RepositoryCandidateValidation {
        do {
            let rootURL = try workingTreeRoot(url)
            guard rootURL.standardizedFileURL == url.standardizedFileURL else {
                return .descend(url)
            }
            return .found(rootURL)
        } catch let error as RepositoryInspectionError {
            switch error {
            case .bareRepository:
                return .skip
            case .notWorkingTree:
                return .descend(url)
            default:
                return .failed(.init(url: url, message: error.localizedDescription))
            }
        } catch {
            return .failed(.init(url: url, message: error.localizedDescription))
        }
    }

    private static func disposition(
        of url: URL,
        resourceKeys: Set<URLResourceKey>
    ) throws -> DirectoryDisposition {
        let values = try url.resourceValues(forKeys: resourceKeys)
        guard values.isDirectory == true else { return .skip }
        guard values.isSymbolicLink != true, values.isPackage != true else { return .skip }
        guard isPotentialRepository(at: url) else { return .descend }
        return .candidate
    }

    static func hasRepositoryMarker(at url: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: url.appending(path: ".git").path)
            || fileManager.fileExists(atPath: url.appending(path: "HEAD").path)
            && fileManager.fileExists(atPath: url.appending(path: "objects").path)
    }

    private static func isPotentialRepository(at url: URL) -> Bool {
        guard hasRepositoryMarker(at: url) else { return false }
        let gitURL = url.appending(path: ".git")
        guard FileManager.default.fileExists(atPath: gitURL.path) else { return true }
        let values = try? gitURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == false
    }

    private static var isCurrentTaskCancelled: Bool {
        withUnsafeCurrentTask { $0?.isCancelled == true }
    }
}

private enum DirectoryDisposition {
    case candidate
    case skip
    case descend
}

private struct RepositoryScanScope: Sendable {
    let url: URL
    let includesRoot: Bool
}

private enum RepositoryCandidateValidation: Sendable {
    case found(URL)
    case descend(URL)
    case skip
    case failed(RepositoryScanFailure)
}
