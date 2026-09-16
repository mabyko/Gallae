// Run from the repository root after building Gallae:
// xcrun swiftc Gallae/LibraryStore.swift scripts/check-list-reentrancy.swift -o /tmp/check-list-reentrancy
// /tmp/check-list-reentrancy /path/to/Gallae.app/Contents/MacOS/Gallae [file-count]
import Foundation

@main
struct CheckListReentrancy {
    static func main() {
        do { try check() }
        catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    static func check() throws {
        setbuf(stdout, nil)
        let arguments = CommandLine.arguments
        guard (2...3).contains(arguments.count),
              let count = Int(arguments.count == 3 ? arguments[2] : "13000"), count > 0 else {
            throw NSError(domain: "Pass the built Gallae executable and an optional positive file count", code: 1)
        }
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: "GallaeListRegression-\(UUID())")
        try files.createDirectory(at: root.appending(path: "files"), withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["init", "-q", root.path]
        try git.run()
        git.waitUntilExit()
        guard git.terminationStatus == 0 else { throw NSError(domain: "git init failed", code: 1) }
        for index in 0..<count {
            try Data().write(to: root.appending(path: "files/\(index).txt"))
        }

        let suite = "GallaeListRegression-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try LibraryStore(defaults: defaults).rememberOpenedRepository(root)
        let bookmark = defaults.data(forKey: "lastWorkspaceBookmark.v1")!
        let argument = "<" + bookmark.map { String(format: "%02x", $0) }.joined() + ">"

        // Argument-domain overrides keep the fixture out of the user's saved repositories.
        // Keep logs outside the repository so Gallae's file watcher does not refresh on log writes.
        let logURL = root.appendingPathExtension("log")
        defer { try? files.removeItem(at: logURL) }
        files.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        let app = Process()
        app.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        app.arguments = [
            "-lastWorkspaceBookmark.v1", argument,
            "-recentRepositoryBookmarks.v1", "",
            "-libraryFolderBookmarks.v1", "",
            "-automaticFetchEnabled.v1", "NO"
        ]
        app.standardOutput = log
        app.standardError = log
        try app.run()
        defer {
            if app.isRunning { app.terminate() }
            app.waitUntilExit()
        }
        print("Checking \(count) untracked files (PID \(app.processIdentifier))…")
        Thread.sleep(forTimeInterval: 10)
        guard app.isRunning else { throw NSError(domain: "Gallae exited during startup", code: 1) }
        let output = try String(contentsOf: logURL, encoding: .utf8)
        guard !output.contains("reentrant operation in its NSTableView delegate") else {
            print(output)
            throw NSError(domain: "NSTableView reentrancy", code: 1)
        }
        print("PASS: no NSTableView delegate reentrancy warning")
    }
}
