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
    }
}
