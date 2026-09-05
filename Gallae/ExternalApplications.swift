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

enum FolderOpening {
    enum Failure: LocalizedError {
        case notDirectory(URL)
        case missingApplication(String)
        case invalidApplication(URL)

        var errorDescription: String? {
            switch self {
            case .notDirectory(let url): "The folder is no longer available: \(url.path)"
            case .missingApplication(let name):
                "\(name) is not installed. Choose another terminal in Settings → General."
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
    @State private var selectionError: String?

    var body: some View {
        Picker("Terminal Application", selection: Binding(
            get: { terminal.rawValue },
            set: { value in
                if value == "choose" { chooseApplication() }
                else if let selected = TerminalApplication(rawValue: value) { terminal = selected }
            }
        )) {
            ForEach(TerminalApplication.allCases.filter { $0 != .custom && ($0.applicationURL != nil || $0 == terminal) }) { app in
                Text(app.applicationURL == nil ? "\(app.title) (Not Installed)" : app.title)
                    .tag(app.rawValue)
                    .disabled(app.applicationURL == nil)
            }
            if !customPath.isEmpty || terminal == .custom {
                Text(TerminalApplication.custom.displayName(customPath: customPath))
                    .tag(TerminalApplication.custom.rawValue)
            }
            Divider()
            Text("Other…").tag("choose")
        }
        Text(terminal == .custom
             ? "Open in sends the folder to this app. Custom apps must support opening folders."
             : "Open in uses this terminal to start a session in the selected repository or Worktree folder.")
            .font(.caption)
            .foregroundStyle(.secondary)
        .alert("Couldn’t Select Terminal", isPresented: Binding(
            get: { selectionError != nil }, set: { if !$0 { selectionError = nil } }
        )) {
            Button("OK", role: .cancel) { selectionError = nil }
        } message: { Text(selectionError ?? "") }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose Terminal Application"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try FolderOpening.validateApplication(url)
                if let known = TerminalApplication(rawValue: Bundle(url: url)?.bundleIdentifier ?? ""),
                   known.applicationURL?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() {
                    terminal = known
                } else {
                    customPath = url.path
                    terminal = .custom
                }
            } catch { selectionError = error.localizedDescription }
        }
    }
}

/// Folder actions share one target in the repository header and branch context menus.
struct RepositoryFolderMenu: View {
    let folderURL: URL?
    let onError: (Error) -> Void
    @AppStorage(TerminalApplication.storageKey) private var terminal = TerminalApplication.terminal
    @AppStorage(TerminalApplication.customPathKey) private var customPath = ""

    var body: some View {
        Menu("Open in", systemImage: "arrow.up.forward.app") {
            Button("Finder", systemImage: "folder") { open(in: nil) }
            Button(terminal.displayName(customPath: customPath), systemImage: "terminal") { open(in: terminal) }
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
