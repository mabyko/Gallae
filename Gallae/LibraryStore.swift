import Foundation

func sameFileLocation(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
}

struct RestoredLocation: Equatable, Sendable {
    let url: URL
    let errorMessage: String?
}

struct LibraryStore {
    private struct BookmarkRecord: Codable, Equatable {
        let bookmark: Data
        let lastKnownPath: String
    }

    private enum Key {
        static let libraryFolders = "libraryFolderBookmarks.v1"
        static let recentRepositories = "recentRepositoryBookmarks.v1"
        static let lastWorkspace = "lastWorkspaceBookmark.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restoreLibraryFolders() -> [RestoredLocation] {
        restoreLocations(forKey: Key.libraryFolders)
    }

    func restoreRecentRepositories() -> [RestoredLocation] {
        restoreLocations(forKey: Key.recentRepositories)
    }

    func restoreLastWorkspace() -> RestoredLocation? {
        restoreLocations(forKey: Key.lastWorkspace).first
    }

    func addLibraryFolder(_ url: URL) throws {
        try replaceLocation(nil, with: url, forKey: Key.libraryFolders)
    }

    func replaceLibraryFolder(_ oldURL: URL, with newURL: URL) throws {
        try replaceLocation(oldURL, with: newURL, forKey: Key.libraryFolders)
    }

    func removeLibraryFolder(_ url: URL) {
        removeLocation(url, forKey: Key.libraryFolders)
    }

    func rememberOpenedRepository(_ url: URL) throws {
        let record = try makeRecord(for: url)
        var recent = records(forKey: Key.recentRepositories)
        recent.removeAll { matches($0, url: url) }
        recent.insert(record, at: 0)

        defaults.set(try PropertyListEncoder().encode(recent), forKey: Key.recentRepositories)
        defaults.set(try PropertyListEncoder().encode([record]), forKey: Key.lastWorkspace)
    }

    func replaceRecentRepository(_ oldURL: URL, with newURL: URL) throws {
        let record = try makeRecord(for: newURL)
        var recent = records(forKey: Key.recentRepositories)
        recent.removeAll { matches($0, url: oldURL) || matches($0, url: newURL) }
        recent.insert(record, at: 0)

        defaults.set(try PropertyListEncoder().encode(recent), forKey: Key.recentRepositories)
        defaults.set(try PropertyListEncoder().encode([record]), forKey: Key.lastWorkspace)
    }

    func removeRecentRepository(_ url: URL) {
        removeLocation(url, forKey: Key.recentRepositories)
        if records(forKey: Key.lastWorkspace).contains(where: { matches($0, url: url) }) {
            clearLastWorkspace()
        }
    }

    func clearLastWorkspace() {
        defaults.removeObject(forKey: Key.lastWorkspace)
    }

    private func replaceLocation(
        _ oldURL: URL?,
        with newURL: URL,
        forKey key: String
    ) throws {
        let record = try makeRecord(for: newURL)
        var saved = records(forKey: key)
        saved.removeAll { existing in
            matches(existing, url: newURL) || oldURL.map { matches(existing, url: $0) } == true
        }
        saved.append(record)
        defaults.set(try PropertyListEncoder().encode(saved), forKey: key)
    }

    private func removeLocation(_ url: URL, forKey key: String) {
        let remaining = records(forKey: key).filter { !matches($0, url: url) }
        if remaining.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? PropertyListEncoder().encode(remaining) {
            defaults.set(data, forKey: key)
        }
    }

    private func restoreLocations(forKey key: String) -> [RestoredLocation] {
        let saved = records(forKey: key)
        var refreshed: [BookmarkRecord] = []
        var locations: [RestoredLocation] = []
        var seenPaths = Set<String>()

        for record in saved {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: record.bookmark,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ).standardizedFileURL
                guard seenPaths.insert(url.path).inserted else { continue }
                let currentRecord = isStale ? (try makeRecord(for: url)) : record
                refreshed.append(currentRecord)
                locations.append(.init(url: url, errorMessage: nil))
            } catch {
                let url = URL(fileURLWithPath: record.lastKnownPath).standardizedFileURL
                guard seenPaths.insert(url.path).inserted else { continue }
                refreshed.append(record)
                locations.append(.init(
                    url: url,
                    errorMessage: "The saved location could not be resolved. Choose it again or remove it."
                ))
            }
        }

        if refreshed != saved, let data = try? PropertyListEncoder().encode(refreshed) {
            defaults.set(data, forKey: key)
        }
        return locations
    }

    private func records(forKey key: String) -> [BookmarkRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? PropertyListDecoder().decode([BookmarkRecord].self, from: data)) ?? []
    }

    private func makeRecord(for url: URL) throws -> BookmarkRecord {
        let standardizedURL = url.standardizedFileURL
        return try .init(
            bookmark: standardizedURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ),
            lastKnownPath: standardizedURL.path
        )
    }

    private func matches(_ record: BookmarkRecord, url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        if sameFileLocation(URL(fileURLWithPath: record.lastKnownPath), standardizedURL) {
            return true
        }
        var isStale = false
        let resolved = try? URL(
            resolvingBookmarkData: record.bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return resolved.map { sameFileLocation($0, standardizedURL) } == true
    }
}
