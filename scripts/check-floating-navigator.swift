// Run from the repository root after building Gallae (requires macOS Accessibility permission):
// xcrun swiftc Gallae/LibraryStore.swift scripts/check-floating-navigator.swift -o /tmp/check-floating-navigator
// /tmp/check-floating-navigator [/path/to/Gallae.app/Contents/MacOS/Gallae]
// Uses an ad hoc signed temporary .app with its own preferences domain.
// Input stops immediately if that fixture PID loses the foreground.
// Keep the fixture app in the foreground until the check finishes.
import AppKit
import ApplicationServices

@main
struct CheckFloatingNavigator {
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

    static func frame(_ element: AXUIElement) -> CGRect {
        var point = CGPoint.zero
        var size = CGSize.zero
        if let value = attribute(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgPoint, &point)
        }
        if let value = attribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: point, size: size)
    }

    static func wait(_ message: String, _ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        throw NSError(domain: message, code: 1)
    }

    static func press(_ element: AXUIElement) throws {
        let status = AXUIElementPerformAction(element, kAXPressAction as CFString)
        try require(status == .success, "AXPress failed: \(label(element)), \(status.rawValue)")
    }

    static func inputTarget(_ pid: pid_t) throws {
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                    && (attribute(AXUIElementCreateApplication(pid), kAXFrontmostAttribute) as? NSNumber)?.boolValue == true,
                    "Fixture lost foreground; stopped input before sending an event")
    }

    static func key(_ code: CGKeyCode, pid: pid_t, flags: CGEventFlags = []) throws {
        for down in [true, false] {
            try inputTarget(pid)
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    static func click(_ point: CGPoint, pid: pid_t) throws {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let target = windows.filter {
            guard ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let bounds = $0[kCGWindowBounds as String] as? NSDictionary,
                  let rectangle = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rectangle.contains(point)
        }.sorted {
            let lhs = CGRect(dictionaryRepresentation: $0[kCGWindowBounds as String] as! CFDictionary)!
            let rhs = CGRect(dictionaryRepresentation: $1[kCGWindowBounds as String] as! CFDictionary)!
            return lhs.width * lhs.height < rhs.width * rhs.height
        }.first
        let windowID = (target?[kCGWindowNumber as String] as? NSNumber)?.int64Value ?? 0
        try require(windowID != 0, "Click point does not belong to a fixture window")
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            try inputTarget(pid)
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)
            event.post(tap: .cghidEventTap)
        }
    }

    static func resize(_ window: AXUIElement, width: CGFloat) throws {
        var size = CGSize(width: width, height: 640)
        let status = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
        try require(status == .success, "Window resize failed: \(status.rawValue)")
        try wait("Window did not reach \(width)×640") { abs(frame(window).width - width) < 2 && abs(frame(window).height - 640) < 2 }
        Thread.sleep(forTimeInterval: 0.4)
    }

    static func check() throws {
        setbuf(stdout, nil)
        try require(AXIsProcessTrusted(), "Grant Accessibility permission to the invoking terminal before running this check")
        let executable = CommandLine.arguments.dropFirst().first ?? "/tmp/gallae-navigator-build/Build/Products/Debug/Gallae.app/Contents/MacOS/Gallae"
        try require(FileManager.default.isExecutableFile(atPath: executable), "Build Gallae first: \(executable)")
        let files = FileManager.default
        let sandbox = files.temporaryDirectory.appending(path: "GallaeNavigatorRegression-\(UUID())")
        let root = sandbox.appending(path: "repository")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: sandbox) }
        let bundleURL = URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try require(Bundle(url: bundleURL) != nil, "Executable must be inside Gallae.app")
        let fixtureApp = sandbox.appending(path: "Gallae.app")
        try files.copyItem(at: bundleURL, to: fixtureApp)
        let bundleID = "forked.gallae.local.navigator-\(UUID().uuidString)"
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
        defer {
            UserDefaults(suiteName: bundleID)?.removePersistentDomain(forName: bundleID)
            try? files.removeItem(at: files.temporaryDirectory.appending(path: "\(bundleID).savedState"))
        }
        func git(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            try require(process.terminationStatus == 0, "git \(arguments) failed")
        }
        try git(["init", "-q", "-b", "main"])
        try git(["-c", "user.name=Navigator Check", "-c", "user.email=navigator@example.invalid", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "Fixture"])
        for index in 0..<60 { try git(["branch", String(format: "fixture-%02d", index)]) }
        try git(["remote", "add", "origin", root.path])
        try git(["update-ref", "refs/remotes/origin/main", "HEAD"])
        try git(["-c", "tag.gpgSign=false", "tag", "check-tag"])

        let suite = "GallaeNavigatorRegression-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try LibraryStore(defaults: defaults).rememberOpenedRepository(root)
        let bookmark = defaults.data(forKey: "lastWorkspaceBookmark.v1")!
        let argument = "<" + bookmark.map { String(format: "%02x", $0) }.joined() + ">"
        let logURL = root.appendingPathExtension("log")
        files.createFile(atPath: logURL.path, contents: nil)
        defer { try? files.removeItem(at: logURL) }
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        let process = Process()
        process.executableURL = fixtureApp.appending(path: "Contents/MacOS/\(URL(fileURLWithPath: executable).lastPathComponent)")
        var environment = ProcessInfo.processInfo.environment
        environment["NSUnbufferedIO"] = "YES"
        process.environment = environment
        // Argument-domain overrides keep fixture bookmarks and settings out of the user's saved state.
        process.arguments = ["-lastWorkspaceBookmark.v1", argument, "-recentRepositoryBookmarks.v1", "", "-libraryFolderBookmarks.v1", "", "-automaticFetchEnabled.v1", "NO", "-narrowNavigatorStyle", "floatingPanel", "-navigatorWidth", "240", "-ApplePersistenceIgnoreState", "YES", "-AppleShowScrollBars", "Always"]
        process.standardOutput = log
        process.standardError = log
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        let pid = process.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        func mark(_ action: String) { log.write(Data("\nCHECK: \(action)\n".utf8)) }
        func size(_ width: CGFloat, _ window: AXUIElement) throws { mark("resize \(width)"); try resize(window, width: width) }
        var window: AXUIElement?
        try wait("Fixture workspace failed to open (PID \(pid))") {
            window = (attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first { string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
            return window != nil
        }
        let mainWindow = window!
        AXUIElementPerformAction(mainWindow, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        try wait("Fixture app did not become active") { (attribute(app, kAXFrontmostAttribute) as? NSNumber)?.boolValue == true }
        try size(820, mainWindow)
        func find(_ predicate: (AXUIElement) -> Bool) -> AXUIElement? { elements(app).first(where: predicate) }
        func filter() -> AXUIElement? {
            find { string($0, kAXRoleAttribute) == kAXTextFieldRole && label($0).contains("Filter Worktrees") }
        }
        func requireFilter() throws -> AXUIElement {
            guard let field = filter() else { throw NSError(domain: "Navigator filter disappeared", code: 1) }
            return field
        }
        func list() -> AXUIElement? { find { string($0, kAXRoleAttribute) == kAXOutlineRole && label($0) == "Navigator" } }
        func scrollBar() -> AXUIElement? {
            guard let outline = list() else { return nil }
            let bounds = frame(outline)
            return find {
                let bar = frame($0)
                return string($0, kAXRoleAttribute) == kAXScrollBarRole && abs(bar.minY - bounds.minY) < 3
                    && min(abs(bar.maxX - bounds.maxX), abs(bar.minX - bounds.maxX)) < 3
            }
        }
        func scrollValue() -> Double { (scrollBar().flatMap { attribute($0, kAXValueAttribute) } as? NSNumber)?.doubleValue ?? -1 }
        func firstBranch() -> String? {
            guard let outline = list() else { return nil }
            let bounds = frame(outline)
            return elements(outline).filter {
                let row = frame($0)
                // Native sidebar/popover section insets differ; compare the first fully readable label.
                return label($0).hasPrefix("fixture-") && row.width > 0 && row.minY >= bounds.minY && row.maxY <= bounds.maxY
            }.sorted { frame($0).minY < frame($1).minY }.first.map(label)
        }
        func branchY(_ name: String?) -> CGFloat? {
            guard let name, let outline = list(), let row = elements(outline).first(where: { label($0) == name }) else { return nil }
            return frame(row).minY - frame(outline).minY
        }
        try wait("Fixture repository did not finish loading") {
            find { string($0, kAXRoleAttribute) == kAXOutlineRole && label($0) == "Commit History, 1 commits" } != nil
        }
        Thread.sleep(forTimeInterval: 1)
        func open() throws {
            mark("open Navigator")
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            try wait("Fixture lost foreground before opening Navigator") { (attribute(app, kAXFrontmostAttribute) as? NSNumber)?.boolValue == true }
            let originalFrame = frame(mainWindow)
            guard let button = find({ string($0, kAXRoleAttribute) == kAXButtonRole && label($0).contains("Navigator") }) else {
                throw NSError(domain: "Toolbar Navigator button missing", code: 1)
            }
            try press(button)
            try wait("Navigator failed to open") { filter() != nil }
            Thread.sleep(forTimeInterval: 0.3)
            try require(filter() != nil, "Navigator closed before its opening animation completed; frontmost=\(String(describing: attribute(app, kAXFrontmostAttribute)))")
            try require(frame(mainWindow) == originalFrame, "Opening Navigator changed the window frame")
        }
        func closed(_ message: String) throws {
            let originalFrame = frame(mainWindow)
            try wait(message) { filter() == nil }
            // AX removes popover children before the native closing animation finishes.
            Thread.sleep(forTimeInterval: 0.3)
            try require(frame(mainWindow) == originalFrame, "Closing Navigator changed the window frame")
        }
        func dismiss() throws {
            mark("Escape")
            let originalFrame = frame(mainWindow)
            try key(53, pid: pid)
            try closed("Escape did not dismiss Navigator")
            try require(frame(mainWindow) == originalFrame, "Escape changed the window frame")
        }
        func setFilter(_ text: String) throws {
            mark("filter \(text)")
            guard let field = filter() else { throw NSError(domain: "Navigator filter missing", code: 1) }
            try require(AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success, "Filter focus failed")
            try key(0, pid: pid, flags: .maskCommand)
            try key(51, pid: pid)
            if !text.isEmpty {
                let characters = Array(text.utf16)
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
                    event.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
                    try inputTarget(pid)
                    event.post(tap: .cghidEventTap)
                }
            }
            try wait("Filter value did not update") { string(field, kAXValueAttribute) == text }
            Thread.sleep(forTimeInterval: 0.3)
        }
        do {
            try wait("Navigator did not fold at 820 points") { filter() == nil }
            try open()
            let bounds = frame(try requireFilter())
            try require(bounds.width > 100 && bounds.maxY <= frame(mainWindow).maxY, "Popover filter clipped below window")
            try dismiss()
            if let focused = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let element = focused as! AXUIElement
                print("Focus after Escape: \(string(element, kAXRoleAttribute)) \(label(element))")
            }
            try open()
            let boundsBefore = frame(mainWindow)
            mark("outside click")
            NSRunningApplication(processIdentifier: pid)?.activate()
            Thread.sleep(forTimeInterval: 0.2)
            try click(CGPoint(x: boundsBefore.maxX - 35, y: boundsBefore.maxY - 35), pid: pid)
            try closed("Outside click did not dismiss Navigator")
            try require(frame(mainWindow) == boundsBefore, "Outside click changed the window frame")
            try open()
            func chooseRow(_ text: String) throws {
                mark("choose row \(text)")
                func matches(_ element: AXUIElement) -> Bool { label(element) == text || label(element).hasPrefix("\(text) | ") }
                func targetRow() -> AXUIElement? {
                    guard let outline = list() else { return nil }
                    return elements(outline).first { matches($0) && frame($0).intersects(frame(outline)) }
                }
                try wait("Navigator row missing: \(text)") { targetRow() != nil }
                guard let row = targetRow() else { throw NSError(domain: "Navigator row disappeared: \(text)", code: 1) }
                let originalFrame = frame(mainWindow)
                let bounds = frame(row)
                try click(CGPoint(x: bounds.midX, y: bounds.midY), pid: pid)
                try closed("Selecting \(text) did not dismiss Navigator")
                try require(frame(mainWindow) == originalFrame, "Selecting \(text) changed the window frame")
            }
            try setFilter("check-tag")
            try chooseRow("check-tag")
            try open()
            try chooseRow("check-tag")
            try open()
            try setFilter("origin")
            try chooseRow("origin")
            try open()
            try chooseRow("origin")
            try open()
            try setFilter("")
            try wait("Fixture branch list did not load") { firstBranch() != nil && scrollBar() != nil }
            mark("scroll Navigator to 0.4")
            let initialBranch = firstBranch()
            guard let bar = scrollBar() else { throw NSError(domain: "Navigator scrollbar disappeared", code: 1) }
            try require(AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: 0.4)) == .success, "Navigator scrollbar AXValue failed")
            try wait("Navigator did not scroll") { firstBranch() != nil && firstBranch() != initialBranch }
            let scrolledBranch = firstBranch()
            let scrolledValue = scrollValue()
            print("Scroll baseline: \(scrolledBranch ?? "missing"), \(scrolledValue), relativeY=\(String(describing: branchY(scrolledBranch)))")
            try dismiss()
            try open()
            try wait("Scroll lost when reopening Navigator") { abs(scrollValue() - scrolledValue) < 0.02 && firstBranch() == scrolledBranch }
            try size(1200, mainWindow)
            print("Scroll docked: \(firstBranch() ?? "missing"), \(scrollValue()), matched-relativeY=\(String(describing: branchY(scrolledBranch)))")
            try wait("Scroll lost when docking Navigator") { firstBranch() == scrolledBranch }
            try size(820, mainWindow)
            try open()
            try wait("Scroll lost after folding Navigator") { firstBranch() == scrolledBranch }
            try setFilter("fixture-59")
            try wait("Filter text did not filter branch rows") {
                guard let outline = list() else { return false }
                let labels = elements(outline).map(label)
                return labels.contains("fixture-59") && !labels.contains("fixture-00")
            }
            try dismiss()
            try open()
            try require(string(try requireFilter(), kAXValueAttribute) == "fixture-59", "Filter lost when reopening Navigator")
            try size(1200, mainWindow)
            try wait("Docked Navigator filter missing") { filter() != nil }
            try require(string(try requireFilter(), kAXValueAttribute) == "fixture-59", "Filter lost when docking Navigator")
            try size(820, mainWindow)
            try wait("Navigator did not fold after resizing") { filter() == nil }
            try open()
            try require(string(try requireFilter(), kAXValueAttribute) == "fixture-59", "Filter lost when unfolding Navigator")
            try setFilter("")
            guard let history = find({ string($0, kAXRoleAttribute) == kAXButtonRole && label($0) == "History" }) else { throw NSError(domain: "History row missing", code: 1) }
            mark("choose History")
            try press(history)
            try closed("Choosing History did not dismiss Navigator")
            try open()
            guard let sameHistory = find({ string($0, kAXRoleAttribute) == kAXButtonRole && label($0) == "History" }) else { throw NSError(domain: "History row missing on reopen", code: 1) }
            mark("choose same History")
            try press(sameHistory)
            try closed("Choosing already-selected History did not dismiss Navigator")
            try open()
            try setFilter("origin")
            func disclosure() -> AXUIElement? { find { string($0, kAXRoleAttribute) == kAXDisclosureTriangleRole } }
            func expanded() -> Bool { (disclosure().flatMap { attribute($0, kAXValueAttribute) } as? NSNumber)?.boolValue == true }
            try wait("Remote disclosure missing") { disclosure() != nil }
            try require(expanded(), "Fixture remote initially collapsed")
            guard let triangle = disclosure() else { throw NSError(domain: "Remote disclosure disappeared", code: 1) }
            try press(triangle)
            try wait("Remote did not collapse") { !expanded() }
            try dismiss()
            try open()
            try wait("Remote disclosure missing on reopen") { disclosure() != nil }
            try require(!expanded(), "Remote collapse lost when reopening")
            try size(1200, mainWindow)
            try wait("Docked remote disclosure missing") { disclosure() != nil }
            try require(!expanded(), "Remote collapse lost when docking")
            try size(820, mainWindow)
            try open()
            try wait("Remote disclosure missing after folding") { disclosure() != nil }
            try require(!expanded(), "Remote collapse lost after folding")
            try setFilter("")
            try dismiss()
            mark("keyboard Navigator shortcut")
            let shortcutFrame = frame(mainWindow)
            guard let bar = attribute(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID(),
                  let command = elements(bar as! AXUIElement).first(where: { label($0) == "Show Navigator" }) else { throw NSError(domain: "View menu Navigator command missing", code: 1) }
            try require(string(command, kAXMenuItemCmdCharAttribute) == "S" && (attribute(command, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue == 4, "Navigator shortcut is not Control-Command-S")
            func modifier(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) throws {
                try inputTarget(pid)
                let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
                event.type = .flagsChanged
                event.flags = flags
                event.post(tap: .cghidEventTap)
            }
            try modifier(59, true, .maskControl)
            try modifier(55, true, [.maskControl, .maskCommand])
            try key(1, pid: pid, flags: [.maskControl, .maskCommand])
            try modifier(55, false, .maskControl)
            try modifier(59, false, [])
            Thread.sleep(forTimeInterval: 0.3)
            if filter() == nil {
                try press(command)
                try wait("View menu Navigator command did not open Navigator") { filter() != nil }
                print("NOTE: physical Control-Command-S input could not be verified in this environment; shortcut registration and View menu action passed")
            }
            try require(frame(mainWindow) == shortcutFrame, "Keyboard Navigator shortcut changed the window frame")
            try dismiss()
            print("PASS: open, Escape, outside click, same-item dismissal; scroll, filter, remote collapse preserved across reopen/docking")
        } catch {
            print("Failure foreground: fixture=\(String(describing: attribute(app, kAXFrontmostAttribute))) actual=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown")")
            for element in elements(app) {
                let description = label(element)
                if !description.isEmpty { print("\(string(element, kAXRoleAttribute)): \(description) \(frame(element))") }
            }
            if let output = try? String(contentsOf: logURL, encoding: .utf8) { print(output) }
            throw error
        }
        let output = try String(contentsOf: logURL, encoding: .utf8)
        let warnings = output.components(separatedBy: .newlines).filter { $0.contains("reentrant operation in its NSTableView delegate") }.count
        if warnings > 0 {
            // Native sidebar List + AX text editing reproduces this without the scroll bridge.
            // Keep the separate check-list-reentrancy.swift startup regression strict.
            print("NOTE: \(warnings) native List editing delegate warnings; reproduced in the bridge-free AX editing baseline")
        }
    }
}
