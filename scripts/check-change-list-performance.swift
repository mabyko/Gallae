// Native regression check; build Release first and grant the invoking terminal Accessibility access.
// xcrun swiftc Gallae/LibraryStore.swift scripts/check-change-list-performance.swift -o /tmp/check-change-list-performance
// /tmp/check-change-list-performance /path/to/Gallae.app/Contents/MacOS/Gallae [file-count]
// The isolated app/settings and synthetic repository are removed after normal Quit.
import AppKit
import ApplicationServices

@main
struct CheckChangeListPerformance {
    static func main() {
        do { try check() }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    static func elements(_ root: AXUIElement) -> [AXUIElement] {
        var result = string(root, kAXRoleAttribute) == kAXApplicationRole
            ? attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? [] : [root]
        var index = 0
        while index < result.count && result.count < 3000 {
            result += attribute(result[index], kAXChildrenAttribute) as? [AXUIElement] ?? []
            index += 1
        }
        return result
    }

    static func label(_ element: AXUIElement) -> String {
        [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute]
            .map { string(element, $0) }.filter { !$0.isEmpty }.joined(separator: " | ")
    }

    static func wait(_ message: String, _ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        throw NSError(domain: message, code: 1)
    }

    static func check() throws {
        setbuf(stdout, nil)
        try require(AXIsProcessTrusted(), "Grant Accessibility permission to the invoking terminal before running this check")
        guard let executable = CommandLine.arguments.dropFirst().first else {
            throw NSError(domain: "Supply the built Release app executable", code: 1)
        }
        try require(FileManager.default.isExecutableFile(atPath: executable), "Build Gallae first: \(executable)")
        let files = FileManager.default
        let sandbox = files.temporaryDirectory.appending(path: "GallaeChangeListCheck-\(UUID())")
        try files.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let count = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 0 : 13_000
        try require(count > 0, "Supply a positive file count")
        let root = sandbox.appending(path: "repository")
        let bundleURL = URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try require(Bundle(url: bundleURL) != nil, "Executable must be inside Gallae.app")
        let fixtureApp = sandbox.appending(path: "Gallae.app")
        let bundleID = "forked.gallae.local.changelist-\(UUID().uuidString)"
        var launchedProcess: Process?
        print("| QA cleanup target | Decision |")
        print("| --- | --- |")
        print("| \(fixtureApp.path) (\(bundleID)) | Remove disposable copy after normal Quit and exact LS unregister verification |")
        print("| \(executable) | Preserve build input until checks complete |")
        print("| \(bundleID) preferences | Remove test-only domain |")
        print("| com.mabyko.gallae.epilo9er preferences / user apps | Preserve |")
        defer {
            do {
                if let launchedProcess, launchedProcess.isRunning {
                    let fixture = NSRunningApplication(processIdentifier: launchedProcess.processIdentifier)
                    try require(fixture?.bundleURL?.standardizedFileURL == fixtureApp.standardizedFileURL, "Cleanup PID no longer belongs to the fixture bundle")
                    try require(fixture?.terminate() == true, "Fixture refused normal Quit; preserved its bundle")
                    try wait("Fixture did not finish normal Quit; preserved its bundle") { !launchedProcess.isRunning }
                }
                let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
                func registration(_ arguments: [String]) throws -> String {
                    let task = Process()
                    let output = Pipe()
                    task.executableURL = URL(fileURLWithPath: lsregister)
                    task.arguments = arguments
                    task.standardOutput = output
                    task.standardError = FileHandle.nullDevice
                    try task.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    task.waitUntilExit()
                    try require(task.terminationStatus == 0, "Launch Services cleanup failed")
                    return String(decoding: data, as: UTF8.self)
                }
                _ = try registration(["-u", fixtureApp.path])
                try require(!registration(["-dump"]).contains(fixtureApp.path), "Fixture remains registered; preserved its bundle")
                UserDefaults(suiteName: bundleID)?.removePersistentDomain(forName: bundleID)
                try? files.removeItem(at: files.temporaryDirectory.appending(path: "\(bundleID).savedState"))
                try files.removeItem(at: sandbox)
                print("Cleanup: fixture quit, exact Launch Services entry absent, disposable bundle/preferences removed")
            } catch {
                fputs("FAIL: cleanup \(error); retained \(sandbox.path) for inspection\n", stderr)
                exit(1)
            }
        }
        try files.copyItem(at: bundleURL, to: fixtureApp)
        let infoURL = fixtureApp.appending(path: "Contents/Info.plist")
        var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as! [String: Any]
        info["CFBundleIdentifier"] = bundleID
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: infoURL)
        // A sacrificial local ID and ad hoc signature never register an Apple App ID.
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", "--identifier", bundleID, "--preserve-metadata=entitlements", "--timestamp=none", fixtureApp.path]
        sign.standardOutput = FileHandle.nullDevice
        sign.standardError = FileHandle.nullDevice
        try sign.run()
        sign.waitUntilExit()
        try require(sign.terminationStatus == 0, "Ad hoc fixture signing failed")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["init", "-q", root.path]
        try git.run()
        git.waitUntilExit()
        try require(git.terminationStatus == 0, "Fixture git init failed")
        for index in 0..<count {
            try Data("fixture\n".utf8).write(to: root.appending(path: "file-\(index).txt"))
        }

        let suite = "GallaeChangeListCheck-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try LibraryStore(defaults: defaults).rememberOpenedRepository(root)
        let bookmark = defaults.data(forKey: "lastWorkspaceBookmark.v1")!
        let argument = "<" + bookmark.map { String(format: "%02x", $0) }.joined() + ">"
        let logURL = sandbox.appending(path: "app.log")
        files.createFile(atPath: logURL.path, contents: nil)
        defer { try? files.removeItem(at: logURL) }
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        let process = Process()
        process.executableURL = fixtureApp.appending(path: "Contents/MacOS/\(URL(fileURLWithPath: executable).lastPathComponent)")
        var environment = ProcessInfo.processInfo.environment
        environment["NSUnbufferedIO"] = "YES"
        process.environment = environment
        UserDefaults(suiteName: bundleID)?.set(false, forKey: "labs.visualDiff")
        // Argument-domain overrides keep fixture bookmarks and settings out of the user's saved state.
        process.arguments = ["-lastWorkspaceBookmark.v1", argument, "-recentRepositoryBookmarks.v1", "", "-libraryFolderBookmarks.v1", "", "-automaticFetchEnabled.v1", "NO", "-narrowNavigatorStyle", "floatingPanel", "-navigatorWidth", "240", "-historyLayout", "sideBySide", "-ApplePersistenceIgnoreState", "YES", "-AppleShowScrollBars", "Always", "-loadGitHubAvatars", "NO"]
        process.standardOutput = log
        process.standardError = log
        let started = Date()
        try process.run()
        launchedProcess = process
        let pid = process.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 30)
        var longestResponse = 0.0
        var window: AXUIElement?
        // Probe throughout startup, including the status -> workspace transition.
        for _ in 0..<25 {
            let before = Date()
            window = (attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first
            longestResponse = max(longestResponse, Date().timeIntervalSince(before))
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        try require(window != nil, "Workspace window did not appear")
        let nodes = elements(window!)
        try require(nodes.prefix(200).contains { label($0).replacingOccurrences(of: ",", with: "").contains("Changes by status \(count) files") },
                    "Expected change list did not load")
        print("Files: \(count); longest UI response: \(String(format: "%.3f", longestResponse))s; elapsed: \(String(format: "%.3f", Date().timeIntervalSince(started)))s")
        try require(longestResponse < 2, "Repository opening blocked UI longer than 2 seconds")
        print("PASS: large change list remains responsive")
    }
}
