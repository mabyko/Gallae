import SwiftUI

struct GallaeTheme: Sendable {
    struct Colors: Sendable {
        let statusConflict: Color
        let badgeBackground: Color
        let diffText: Color
        let diffMetadataText: Color
        let diffHunkText: Color
        let diffAdditionBackground: Color
        let diffDeletionBackground: Color
        let diffHunkBackground: Color
    }

    struct Metrics: Sendable {
        let libraryFolderMinimumWidth: CGFloat
        let libraryFolderIdealWidth: CGFloat
        let repositoryListMinimumWidth: CGFloat
        let repositoryListIdealWidth: CGFloat
        let repositorySummaryMinimumWidth: CGFloat
        let repositorySummaryIdealWidth: CGFloat
        let changeListMinimumWidth: CGFloat
        let changeListIdealWidth: CGFloat
        let diffLineNumberWidth: CGFloat
    }

    let colors: Colors
    let metrics: Metrics

    static let standard = GallaeTheme(
        colors: .init(
            statusConflict: .orange,
            badgeBackground: .secondary.opacity(0.12),
            diffText: .primary,
            diffMetadataText: .secondary,
            diffHunkText: .accentColor,
            diffAdditionBackground: .green.opacity(0.12),
            diffDeletionBackground: .red.opacity(0.12),
            diffHunkBackground: .accentColor.opacity(0.08)
        ),
        metrics: .init(
            libraryFolderMinimumWidth: 170,
            libraryFolderIdealWidth: 210,
            repositoryListMinimumWidth: 280,
            repositoryListIdealWidth: 380,
            repositorySummaryMinimumWidth: 230,
            repositorySummaryIdealWidth: 290,
            changeListMinimumWidth: 260,
            changeListIdealWidth: 320,
            diffLineNumberWidth: 44
        )
    )
}

private struct GallaeThemeKey: EnvironmentKey {
    static let defaultValue = GallaeTheme.standard
}

extension EnvironmentValues {
    var gallaeTheme: GallaeTheme {
        get { self[GallaeThemeKey.self] }
        set { self[GallaeThemeKey.self] = newValue }
    }
}
