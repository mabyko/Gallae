import SwiftUI

extension FocusedValues {
    @Entry var openRepository: (() -> Void)?
}

private struct GallaeCommands: Commands {
    @FocusedValue(\.openRepository) private var openRepository

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Repository…") {
                openRepository?()
            }
            .keyboardShortcut("o")
            .disabled(openRepository == nil)
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
    }
}
