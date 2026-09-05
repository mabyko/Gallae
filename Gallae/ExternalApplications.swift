import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum TerminalApplication: String, CaseIterable, Identifiable {
    case terminal = "com.apple.Terminal"
    case ghostty = "com.mitchellh.ghostty"
    case warp = "dev.warp.Warp-Stable"
    case iTerm = "com.googlecode.iterm2"
    case cmux = "com.cmuxterm.app"
    case kaku = "fun.tw93.kaku"
    case wezTerm = "com.github.wez.wezterm"
    case kitty = "net.kovidgoyal.kitty"
    case alacritty = "org.alacritty"
    case rio = "com.raphaelamorim.rio"
    case custom = "custom"

    static let storageKey = "terminalApplication"
    static let customPathKey = "customTerminalApplicationPath"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        case .iTerm: "iTerm2"
        case .cmux: "cmux"
        case .kaku: "Kaku"
        case .wezTerm: "WezTerm"
        case .kitty: "kitty"
        case .alacritty: "Alacritty"
        case .rio: "Rio"
        case .custom: "Custom Terminal"
        }
    }

    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue)
    }

    func displayName(customPath: String) -> String {
        guard self == .custom, !customPath.isEmpty else { return title }
        return URL(fileURLWithPath: customPath).deletingPathExtension().lastPathComponent
    }

    /// Nil uses Open Documents; arguments are passed directly to the app, never through a shell.
    func launchArguments(for directory: URL) -> [String]? {
        switch self {
        case .kaku, .wezTerm: ["start", "--always-new-process", "--cwd", directory.path]
        case .kitty: ["--directory", directory.path]
        case .alacritty: ["--working-directory", directory.path]
        case .rio: ["--working-dir", directory.path]
        default: nil
        }
    }
}

enum EditorApplication: String, CaseIterable, Identifiable {
    case vscode = "com.microsoft.VSCode"
    case zed = "dev.zed.Zed"
    case custom = "custom"

    static let storageKey = "editorApplication"
    static let customPathKey = "customEditorApplicationPath"
    static var defaultApplication: Self { vscode.applicationURL != nil ? .vscode : zed.applicationURL != nil ? .zed : .vscode }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vscode: "VS Code"
        case .zed: "Zed"
        case .custom: "Custom Editor"
        }
    }
    var applicationURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) }
    func displayName(customPath: String) -> String {
        guard self == .custom, !customPath.isEmpty else { return title }
        return URL(fileURLWithPath: customPath).deletingPathExtension().lastPathComponent
    }
}

enum MergeTool: String, CaseIterable, Identifiable, Sendable {
    case git, vscode, sublimeMerge

    static let storageKey = "mergeTool"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .git: "Use Git Configuration"
        case .vscode: "VS Code"
        case .sublimeMerge: "Sublime Merge"
        }
    }

    @MainActor var executableURL: URL? {
        let identifier: String
        let binary: String
        switch self {
        case .git: return nil
        case .vscode:
            identifier = "com.microsoft.VSCode"
            binary = "Contents/Resources/app/bin/code"
        case .sublimeMerge:
            identifier = "com.sublimemerge"
            binary = "Contents/SharedSupport/bin/smerge"
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return nil }
        let url = app.appending(path: binary)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    func arguments(base: URL, ours: URL, theirs: URL, merged: URL) -> [String] {
        switch self {
        case .git: []
        case .vscode: ["--wait", "--merge", theirs.path, ours.path, base.path, merged.path]
        case .sublimeMerge: ["mergetool", base.path, ours.path, theirs.path, "-o", merged.path]
        }
    }
}

struct MergeToolPicker: View {
    @AppStorage(MergeTool.storageKey) private var tool = MergeTool.git

    var body: some View {
        Picker("Merge Tool", selection: $tool) {
            ForEach(MergeTool.allCases) { item in
                let available = item == .git || item.executableURL != nil
                Text(available ? item.title : "\(item.title) (Not Installed)")
                    .tag(item).disabled(!available)
            }
        }
        Text(tool == .git
             ? "Uses merge.guitool or merge.tool from Git. The configured tool may stage resolved files. Tools requiring terminal input must be run in a terminal."
             : "Close the merge editor when finished, then review and Mark Resolved in Gallae. Opening the tool does not stage or commit the file.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

enum FolderOpening {
    enum Failure: LocalizedError {
        case notDirectory(URL)
        case missingApplication(String)
        case invalidApplication(URL)

        var errorDescription: String? {
            switch self {
            case .notDirectory(let url): "The folder is no longer available: \(url.path)"
            case .missingApplication(let name):
                "\(name) is not installed. Choose another application in Settings → General."
            case .invalidApplication(let url):
                "Choose an available macOS application: \(url.path)"
            }
        }
    }

    static func validateApplication(_ url: URL) throws {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw Failure.invalidApplication(url)
        }
    }

    static func validateDirectory(_ url: URL) throws {
        guard url.isFileURL, try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw Failure.notDirectory(url)
        }
    }

    @MainActor
    static func open(_ url: URL, inEditor editor: EditorApplication, customPath: String = "") async throws {
        try validateDirectory(url)
        let selectedURL = editor == .custom && !customPath.isEmpty
            ? URL(fileURLWithPath: customPath) : editor.applicationURL
        guard let applicationURL = selectedURL else { throw Failure.missingApplication(editor.title) }
        try validateApplication(applicationURL)
        _ = try await NSWorkspace.shared.open(
            [url], withApplicationAt: applicationURL, configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @MainActor
    static func open(_ url: URL, in terminal: TerminalApplication?, customPath: String = "") async throws {
        try validateDirectory(url)
        if let terminal {
            let selectedURL = terminal == .custom && !customPath.isEmpty
                ? URL(fileURLWithPath: customPath) : terminal.applicationURL
            guard let applicationURL = selectedURL else {
                throw Failure.missingApplication(terminal.title)
            }
            try validateApplication(applicationURL)
            // A supported app chosen through Other… still gets its directory arguments.
            let detected = TerminalApplication(rawValue: Bundle(url: applicationURL)?.bundleIdentifier ?? "")
            let configuration = NSWorkspace.OpenConfiguration()
            if let arguments = (detected ?? terminal).launchArguments(for: url) {
                configuration.arguments = arguments
                // Launch arguments are ignored when merely activating an existing instance.
                configuration.createsNewApplicationInstance = true
                _ = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
            } else {
                _ = try await NSWorkspace.shared.open(
                    [url], withApplicationAt: applicationURL, configuration: configuration
                )
            }
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

struct TerminalApplicationPicker: View {
    @AppStorage(TerminalApplication.storageKey) private var terminal = TerminalApplication.terminal
    @AppStorage(TerminalApplication.customPathKey) private var customPath = ""

    var body: some View {
        ExternalApplicationPicker(kind: "Terminal",
                                  applications: TerminalApplication.allCases.filter { $0 != .custom }.map { ($0.rawValue, $0.title) },
                                  selection: Binding(get: { terminal.rawValue }, set: { terminal = TerminalApplication(rawValue: $0) ?? .terminal }),
                                  customPath: $customPath)
        Text(terminal == .custom
             ? "Open in sends the folder to this app. Custom apps must support opening folders."
             : "Open in uses this terminal to start a session in the selected repository or Worktree folder.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct EditorApplicationPicker: View {
    @AppStorage(EditorApplication.storageKey) private var editor = EditorApplication.defaultApplication
    @AppStorage(EditorApplication.customPathKey) private var customPath = ""

    var body: some View {
        ExternalApplicationPicker(kind: "Editor",
                                  applications: EditorApplication.allCases.filter { $0 != .custom }.map { ($0.rawValue, $0.title) },
                                  selection: Binding(get: { editor.rawValue }, set: { editor = EditorApplication(rawValue: $0) ?? .vscode }),
                                  customPath: $customPath)
        Text("Open in opens the selected repository or Worktree folder in this editor. Custom apps must support opening folders.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

/// Both preferences use the same installed-app list and native Other… chooser.
private struct ExternalApplicationPicker: View {
    let kind: String
    let applications: [(id: String, title: String)]
    @Binding var selection: String
    @Binding var customPath: String
    @State private var selectionError: String?

    var body: some View {
        Picker("\(kind) Application", selection: Binding(
            get: { selection },
            set: { value in
                if value == "choose" { chooseApplication() }
                else { selection = value }
            }
        )) {
            ForEach(applications.filter { applicationURL(for: $0.id) != nil || $0.id == selection }, id: \.id) { app in
                Text(applicationURL(for: app.id) == nil ? "\(app.title) (Not Installed)" : app.title)
                    .tag(app.id)
                    .disabled(applicationURL(for: app.id) == nil)
            }
            if !customPath.isEmpty || selection == "custom" {
                Text(customPath.isEmpty ? "Custom \(kind)" : URL(fileURLWithPath: customPath).deletingPathExtension().lastPathComponent)
                    .tag("custom")
            }
            Divider()
            Text("Other…").tag("choose")
        }
        .alert("Couldn’t Select \(kind)", isPresented: Binding(
            get: { selectionError != nil }, set: { if !$0 { selectionError = nil } }
        )) {
            Button("OK", role: .cancel) { selectionError = nil }
        } message: { Text(selectionError ?? "") }
    }

    private func applicationURL(for identifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose \(kind) Application"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try FolderOpening.validateApplication(url)
                if let identifier = Bundle(url: url)?.bundleIdentifier,
                   applications.contains(where: { $0.id == identifier }),
                   let installed = applicationURL(for: identifier),
                   sameFileLocation(installed.resolvingSymlinksInPath(), url.resolvingSymlinksInPath()) {
                    selection = identifier
                } else {
                    customPath = url.path
                    selection = "custom"
                }
            } catch { selectionError = error.localizedDescription }
        }
    }
}

/// Folder actions share one target in the repository header and branch context menus.
struct RepositoryFolderMenu: View {
    let folderURL: URL?
    let onError: (Error) -> Void
    @AppStorage(EditorApplication.storageKey) private var editor = EditorApplication.defaultApplication
    @AppStorage(EditorApplication.customPathKey) private var customEditorPath = ""
    @AppStorage(TerminalApplication.storageKey) private var terminal = TerminalApplication.terminal
    @AppStorage(TerminalApplication.customPathKey) private var customPath = ""

    var body: some View {
        Menu("Open in", systemImage: "arrow.up.forward.app") {
            Button("Finder", systemImage: "folder") { open(in: nil) }
            Button(terminal.displayName(customPath: customPath), systemImage: "terminal") { open(in: terminal) }
            Button(editor.displayName(customPath: customEditorPath), systemImage: "chevron.left.forwardslash.chevron.right") {
                guard let folderURL else { return }
                Task {
                    do { try await FolderOpening.open(folderURL, inEditor: editor, customPath: customEditorPath) }
                    catch { onError(error) }
                }
            }
        }
        .disabled(folderURL == nil)
        .help(folderURL?.path ?? "This branch is not checked out in a local folder.")

        Button("Copy Path", systemImage: "doc.on.doc") {
            guard let folderURL else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(folderURL.path, forType: .string)
        }
        .disabled(folderURL == nil)
        .help(folderURL?.path ?? "This branch is not checked out in a local folder.")
    }

    private func open(in terminal: TerminalApplication?) {
        guard let folderURL else { return }
        Task {
            do { try await FolderOpening.open(folderURL, in: terminal, customPath: customPath) }
            catch { onError(error) }
        }
    }
}
