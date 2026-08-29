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
            let candidates = collectCandidates(in: scope, continuation: continuation)
            let descendantRoots = await validateCandidates(
                candidates,
                continuation: continuation
            )
            scopes.append(contentsOf: descendantRoots.map {
                RepositoryScanScope(url: $0, includesRoot: false)
            })
        }
    }

    private static func collectCandidates(
        in scope: RepositoryScanScope,
        continuation: AsyncStream<RepositoryScanEvent>.Continuation
    ) -> [URL] {
        let rootURL = scope.url

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]

        if scope.includesRoot {
            do {
                switch try disposition(of: rootURL, resourceKeys: keys) {
                case .candidate:
                    return [rootURL]
                case .skip:
                    return []
                case .descend:
                    break
                }
            } catch {
                continuation.yield(.failed(.init(
                    url: rootURL,
                    message: error.localizedDescription
                )))
                return []
            }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                guard !isCurrentTaskCancelled else { return false }
                continuation.yield(.failed(.init(url: url, message: error.localizedDescription)))
                return true
            }
        ) else {
            continuation.yield(.failed(.init(
                url: rootURL,
                message: "The Library Folder could not be read."
            )))
            return []
        }

        var candidates: [URL] = []
        while !isCurrentTaskCancelled, let url = enumerator.nextObject() as? URL {
            do {
                switch try disposition(of: url, resourceKeys: keys) {
                case .candidate:
                    enumerator.skipDescendants()
                    candidates.append(url)
                case .skip:
                    enumerator.skipDescendants()
                case .descend:
                    break
                }
            } catch {
                enumerator.skipDescendants()
                continuation.yield(.failed(.init(url: url, message: error.localizedDescription)))
            }
        }
        return candidates
    }

    private static func validateCandidates(
        _ candidates: [URL],
        continuation: AsyncStream<RepositoryScanEvent>.Continuation
    ) async -> [URL] {
        guard !candidates.isEmpty, !isCurrentTaskCancelled else { return [] }

        var descendantRoots: [URL] = []
        await withTaskGroup(of: RepositoryCandidateValidation.self) { group in
            var candidateIndex = 0
            while candidateIndex < min(maximumConcurrentValidations, candidates.count) {
                let candidate = candidates[candidateIndex]
                candidateIndex += 1
                group.addTask(priority: .utility) {
                    validateCandidate(at: candidate)
                }
            }

            while let validation = await group.next() {
                if isCurrentTaskCancelled {
                    group.cancelAll()
                    break
                }

                switch validation {
                case .found(let repositoryURL):
                    continuation.yield(.found(.init(rootURL: repositoryURL)))
                case .descend(let url):
                    descendantRoots.append(url)
                case .skip:
                    break
                case .failed(let failure):
                    continuation.yield(.failed(failure))
                }

                if candidateIndex < candidates.count {
                    let candidate = candidates[candidateIndex]
                    candidateIndex += 1
                    group.addTask(priority: .utility) {
                        validateCandidate(at: candidate)
                    }
                }
            }
        }
        return descendantRoots
    }

    private static func validateCandidate(at url: URL) -> RepositoryCandidateValidation {
        do {
            let rootURL = try RepositoryInspector.workingTreeRoot(at: url)
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
