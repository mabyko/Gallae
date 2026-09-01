import SwiftUI

extension FocusedValues {
    @Entry var openRepository: (() -> Void)?
    @Entry var appModel: AppModel?
    @Entry var workspaceSection: Binding<RepositoryWorkspaceSection>?
}

private struct GallaeCommands: Commands {
    @FocusedValue(\.openRepository) private var openRepository
    @FocusedValue(\.appModel) private var model
    @FocusedValue(\.workspaceSection) private var workspaceSection

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Repository…") {
                openRepository?()
            }
            .keyboardShortcut("o")
            .disabled(openRepository == nil)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(
                Array(RepositoryWorkspaceSection.allCases.enumerated()),
                id: \.element
            ) { index, section in
                Toggle(
                    section.title,
                    isOn: Binding(
                        get: { workspaceSection?.wrappedValue == section },
                        set: { isOn in
                            if isOn {
                                workspaceSection?.wrappedValue = section
                            }
                        }
                    )
                )
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .disabled(workspaceSection == nil)
            }
            Divider()
            Button("Show Library") {
                model?.showLibrary()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(!isWorkspaceInteractive)
        }

        CommandGroup(after: .help) {
            Divider()
            SettingsLink {
                Text("Install Command Line Tool…")
            }
        }

        CommandMenu("Repository") {
            Button("Fetch") {
                model?.fetchRepository()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(!isWorkspaceInteractive)

            Button("Fetch & Prune") {
                model?.fetchRepository(pruning: true)
            }
            .disabled(!isWorkspaceInteractive)

            Button("Pull") {
                model?.pullRepository()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(!isWorkspaceInteractive || model?.canPullRepository != true)

            Button(model?.pushTitle ?? "Push") {
                model?.pushRepository()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(!isWorkspaceInteractive || model?.canPushRepository != true)

            Divider()

            Button("Refresh Repository") {
                guard let model else { return }
                Task { await model.refreshRepository() }
            }
            .keyboardShortcut("r")
            .disabled(!isWorkspaceInteractive)
        }
    }

    private var isWorkspaceInteractive: Bool {
        guard let model else { return false }
        return model.screen == .workspace && model.repository != nil && !model.isLoading
    }
}

enum CommandLineToolError: LocalizedError, Equatable {
    case noWritableLocation([URL])

    var errorDescription: String? {
        switch self {
        case .noWritableLocation(let directories):
            "No writable install location. Copy the script manually into a PATH directory such as \(directories.map(\.path).joined(separator: " or "))."
        }
    }
}

enum CommandLineToolInstaller {
    static let scriptName = "gallae"

    static let candidateDirectories = [
        URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true)
    ]

    static let script = """
    #!/bin/sh
    # gallae — open a Git repository in Gallae for Git.
    # usage: gallae [path]   (default: current directory)
    set -eu

    case "${1:-}" in
    -h|--help)
        echo "usage: gallae [path]"
        echo "Open the Git repository at path (default: current directory) in Gallae for Git."
        exit 0
        ;;
    esac

    if [ $# -gt 1 ]; then
        echo "usage: gallae [path]" >&2
        exit 64
    fi

    target=$(cd "${1:-.}" 2>/dev/null && pwd) || {
        echo "gallae: no such directory: ${1:-.}" >&2
        exit 1
    }

    open -a "Gallae for Git" "$target" 2>/dev/null \\
        || open -a "Gallae for Git Dev" "$target" 2>/dev/null \\
        || { echo "gallae: Gallae for Git is not installed" >&2; exit 1; }
    """

    static func installedLocation(
        in directories: [URL] = candidateDirectories
    ) -> URL? {
        directories
            .map { $0.appending(path: scriptName) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    @discardableResult
    static func install(into directories: [URL] = candidateDirectories) throws -> URL {
        let fileManager = FileManager.default
        func isWritableDirectory(_ url: URL) -> Bool {
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
                && fileManager.isWritableFile(atPath: url.path)
        }

        let existingDirectory = installedLocation(in: directories)?.deletingLastPathComponent()
        let orderedDirectories = (existingDirectory.map { [$0] } ?? []) + directories
        guard let directory = orderedDirectories.first(where: isWritableDirectory) else {
            throw CommandLineToolError.noWritableLocation(directories)
        }

        let scriptURL = directory.appending(path: scriptName)
        try Data((script + "\n").utf8).write(to: scriptURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }
}

struct GPGSecretKey: Identifiable, Equatable, Sendable {
    let id: String
    let userID: String

    var shortID: String {
        String(id.suffix(8))
    }
}

enum GPGKeyParser {
    static func keys(fromColonOutput output: String) -> [GPGSecretKey] {
        var keys: [GPGSecretKey] = []
        var pendingKeyID: String?
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ":", omittingEmptySubsequences: false)
            guard let type = fields.first else { continue }
            if type == "sec", fields.count > 4 {
                pendingKeyID = String(fields[4])
            } else if type == "uid", let keyID = pendingKeyID, fields.count > 9 {
                keys.append(.init(id: keyID, userID: String(fields[9])))
                pendingKeyID = nil
            }
        }
        return keys
    }

    // 설정값은 짧은 ID·긴 ID·전체 fingerprint 어느 쪽이든 올 수 있어 양방향 접미사로 맞춘다.
    static func matchedKeyID(_ configured: String, in keys: [GPGSecretKey]) -> String? {
        let configured = configured.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !configured.isEmpty else { return nil }
        return keys.first {
            $0.id.uppercased().hasSuffix(configured) || configured.hasSuffix($0.id.uppercased())
        }?.id
    }
}

enum CommitSigningState: Equatable, Sendable {
    case loading
    case sshConfigured
    case gpgUnavailable
    case failed(String)
    case ready(keys: [GPGSecretKey], selectedKeyID: String?)
}

enum CommitSigningConfiguration {
    private static let gitPath = "/usr/bin/git"

    struct RunResult {
        let status: Int32
        let output: String
        let error: String
    }

    nonisolated static func loadSynchronously() -> CommitSigningState {
        if configValue("gpg.format") == "ssh" {
            return .sshConfigured
        }
        guard let gpgPath = gpgProgramPath() else {
            return .gpgUnavailable
        }
        let list = run(gpgPath, ["--list-secret-keys", "--with-colons"])
        guard list.status == 0 else {
            return .failed(list.error.isEmpty ? list.output : list.error)
        }
        let keys = GPGKeyParser.keys(fromColonOutput: list.output)
        let signsCommits = configValue("commit.gpgsign") == "true"
        let selectedKeyID = signsCommits
            ? GPGKeyParser.matchedKeyID(configValue("user.signingkey"), in: keys)
            : nil
        return .ready(keys: keys, selectedKeyID: selectedKeyID)
    }

    nonisolated static func applySynchronously(keyID: String?) -> String? {
        if let keyID {
            let setKey = run(gitPath, ["config", "--global", "user.signingkey", keyID])
            guard setKey.status == 0 else { return failureMessage(setKey) }
            let enable = run(gitPath, ["config", "--global", "commit.gpgsign", "true"])
            guard enable.status == 0 else { return failureMessage(enable) }
        } else {
            let disable = run(gitPath, ["config", "--global", "commit.gpgsign", "false"])
            guard disable.status == 0 else { return failureMessage(disable) }
        }
        return nil
    }

    private nonisolated static func failureMessage(_ result: RunResult) -> String {
        result.error.isEmpty
            ? "Git couldn’t update the global signing configuration."
            : result.error
    }

    private nonisolated static func configValue(_ key: String) -> String {
        let result = run(gitPath, ["config", "--get", key])
        guard result.status == 0 else { return "" }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func gpgProgramPath() -> String? {
        var candidates = ["gpg.openpgp.program", "gpg.program"]
            .map(configValue)
            .filter { $0.contains("/") }
        candidates += [
            "/opt/homebrew/bin/gpg",
            "/usr/local/bin/gpg",
            "/usr/local/MacGPG2/bin/gpg2",
            "/usr/bin/gpg"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private nonisolated static func run(_ executable: String, _ arguments: [String]) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            return .init(status: -1, output: "", error: error.localizedDescription)
        }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return .init(
            status: process.terminationStatus,
            output: String(decoding: outputData, as: UTF8.self),
            error: String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct GallaeSettingsView: View {
    @Environment(\.gallaeTheme) private var theme
    @AppStorage("loadsGitHubAvatars") private var loadsGitHubAvatars = true
    @State private var installedURL: URL?
    @State private var errorMessage: String?
    @State private var signingState: CommitSigningState = .loading
    @State private var selectedSigningKeyID: String?
    @State private var signingErrorMessage: String?

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                generalSettings
            }
            Tab("Git", systemImage: "arrow.triangle.branch") {
                gitSettings
            }
            Tab("Command Line", systemImage: "terminal") {
                commandLineSettings
            }
        }
        .frame(width: 480)
    }

    private var gitSettings: some View {
        Form {
            Section("Commit Signing") {
                switch signingState {
                case .loading:
                    Text("Reading the Git signing configuration…")
                        .foregroundStyle(.secondary)
                case .sshConfigured:
                    Label(
                        "SSH commit signing is configured in Git. Gallae keeps that configuration unchanged.",
                        systemImage: "key"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                case .gpgUnavailable:
                    Label(
                        "No GPG program was found. Install GnuPG, or set gpg.program in your Git configuration, to sign commits.",
                        systemImage: "exclamationmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(theme.colors.statusConflict)
                    Button("Try Again") {
                        Task { await loadSigningState() }
                    }
                case .ready(let keys, _):
                    Picker("Sign Commits With", selection: $selectedSigningKeyID) {
                        Text("No Signing Key").tag(String?.none)
                        ForEach(keys) { key in
                            Text("\(key.shortID) — \(key.userID)").tag(Optional(key.id))
                        }
                    }
                    .accessibilityHint(
                        "Choose the GPG key Git uses to sign new commits, or turn signing off"
                    )

                    if keys.isEmpty {
                        Text("No secret GPG keys were found. Create or import a key with GnuPG first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Applies to the global Git configuration (user.signingkey, commit.gpgsign). Repositories with their own signing setting keep it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let signingErrorMessage {
                        Label(signingErrorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(theme.colors.statusConflict)
                            .accessibilityLabel("Signing update failed: \(signingErrorMessage)")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await loadSigningState()
        }
        .onChange(of: selectedSigningKeyID) { _, newKeyID in
            guard
                case .ready(let keys, let currentKeyID) = signingState,
                currentKeyID != newKeyID
            else {
                return
            }
            Task { await applySigningKey(newKeyID, keys: keys, previousKeyID: currentKeyID) }
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Author Avatars") {
                Toggle("Load GitHub Avatars", isOn: $loadsGitHubAvatars)
                    .accessibilityHint(
                        "Look up commit authors on GitHub and show their public profile pictures"
                    )

                Text("Looks up commit authors on GitHub and shows their public avatar. Author email addresses are sent only to GitHub, results are cached per email, and authors without a public GitHub match keep the initials badge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var commandLineSettings: some View {
        Form {
            Section("Command Line Tool") {
                LabeledContent("gallae command") {
                    Text(installedURL?.path ?? "Not installed")
                        .font(.callout.monospaced())
                        .foregroundStyle(installedURL == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                }

                Text("Run “gallae [path]” in Terminal to open the Git repository at that path. The path defaults to the current directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(
                    installedURL == nil
                        ? "Install Command Line Tool"
                        : "Reinstall Command Line Tool"
                ) {
                    install()
                }
                .accessibilityHint("Copy the gallae script into a directory on PATH")

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(theme.colors.statusConflict)
                        .accessibilityLabel("Install failed: \(errorMessage)")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        installedURL = CommandLineToolInstaller.installedLocation()
    }

    private func loadSigningState() async {
        signingState = .loading
        signingErrorMessage = nil
        let state = await Task.detached(priority: .userInitiated) {
            CommitSigningConfiguration.loadSynchronously()
        }.value
        signingState = state
        if case .ready(_, let selectedKeyID) = state {
            selectedSigningKeyID = selectedKeyID
        }
    }

    private func applySigningKey(
        _ keyID: String?,
        keys: [GPGSecretKey],
        previousKeyID: String?
    ) async {
        signingErrorMessage = nil
        let failure = await Task.detached(priority: .userInitiated) {
            CommitSigningConfiguration.applySynchronously(keyID: keyID)
        }.value
        if let failure {
            signingErrorMessage = failure
            selectedSigningKeyID = previousKeyID
        } else {
            signingState = .ready(keys: keys, selectedKeyID: keyID)
        }
    }

    private func install() {
        errorMessage = nil
        do {
            installedURL = try CommandLineToolInstaller.install()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

@main
struct GallaeApp: App {
    var body: some Scene {
        Window("Gallae for Git", id: "main") {
            AppView()
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            GallaeCommands()
        }

        Settings {
            GallaeSettingsView()
        }
    }
}
