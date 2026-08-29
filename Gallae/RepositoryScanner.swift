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
    func scan(in rootURL: URL) -> AsyncStream<RepositoryScanEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                Self.scanSynchronously(in: rootURL.standardizedFileURL, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private static func scanSynchronously(
        in rootURL: URL,
        continuation: AsyncStream<RepositoryScanEvent>.Continuation
    ) {
        defer { continuation.finish() }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]

        do {
            switch try disposition(of: rootURL, resourceKeys: keys) {
            case .repository(let repositoryURL):
                continuation.yield(.found(.init(rootURL: repositoryURL)))
                return
            case .skip:
                return
            case .descend:
                break
            }
        } catch {
            continuation.yield(.failed(.init(url: rootURL, message: error.localizedDescription)))
            return
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
            return
        }

        while !isCurrentTaskCancelled, let url = enumerator.nextObject() as? URL {
            do {
                switch try disposition(of: url, resourceKeys: keys) {
                case .repository(let repositoryURL):
                    enumerator.skipDescendants()
                    continuation.yield(.found(.init(rootURL: repositoryURL)))
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
    }

    private static func disposition(
        of url: URL,
        resourceKeys: Set<URLResourceKey>
    ) throws -> DirectoryDisposition {
        let values = try url.resourceValues(forKeys: resourceKeys)
        guard values.isDirectory == true else { return .skip }
        guard values.isSymbolicLink != true, values.isPackage != true else { return .skip }
        guard isPotentialRepository(at: url) else { return .descend }

        do {
            let rootURL = try RepositoryInspector.workingTreeRoot(at: url)
            guard rootURL.standardizedFileURL == url.standardizedFileURL else {
                return .descend
            }
            return .repository(rootURL)
        } catch let error as RepositoryInspectionError {
            switch error {
            case .bareRepository:
                return .skip
            case .notWorkingTree:
                return .descend
            default:
                throw error
            }
        }
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
    case repository(URL)
    case skip
    case descend
}
