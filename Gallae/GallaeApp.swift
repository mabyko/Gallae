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

private struct GallaeSettingsView: View {
    @Environment(\.gallaeTheme) private var theme
    @State private var installedURL: URL?
    @State private var errorMessage: String?

    var body: some View {
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
        .frame(width: 480)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        installedURL = CommandLineToolInstaller.installedLocation()
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
