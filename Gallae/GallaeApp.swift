import SwiftUI

@main
struct GallaeApp: App {
    var body: some Scene {
        WindowGroup("Gallae for Git") {
            AppView()
        }
        .defaultSize(width: 960, height: 640)
    }
}
