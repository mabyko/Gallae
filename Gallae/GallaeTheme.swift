import SwiftUI

/// How the one Gallae theme answers macOS accessibility settings; see DESIGN_SYSTEM.md “재질과 접근성 응답”.
enum GallaeMaterialResponse: Equatable, Sendable {
    /// System material on the sidebar and toolbar.
    case standard
    /// Opaque neutral chrome: Reduce Transparency is on, or the Translucent setting is off.
    case reducedTransparency
    /// Opaque chrome plus stronger dividers, badges, and diff colors: Increase Contrast is on.
    case increasedContrast

    static func resolve(
        reduceTransparency: Bool,
        increasedContrast: Bool,
        translucentChrome: Bool
    ) -> GallaeMaterialResponse {
        if increasedContrast { return .increasedContrast }
        if reduceTransparency || !translucentChrome { return .reducedTransparency }
        return .standard
    }
}

struct GallaeTheme: Sendable {
    struct Colors: Sendable {
        let statusConflict: Color
        let statusModified: Color
        let statusAdded: Color
        let statusDeleted: Color
        let statusRenamed: Color
        let statusUntracked: Color
        let badgeBackground: Color
        let historyGraphLanes: [Color]
        let authorBadgeColors: [Color]
        let diffText: Color
        let diffMetadataText: Color
        let diffHunkText: Color
        let diffAdditionBackground: Color
        let diffDeletionBackground: Color
        let diffHunkBackground: Color
        /// Opaque chrome color used for the sidebar when the system material is not shown.
        let opaqueChrome: Color
    }

    struct Metrics: Sendable {
        let libraryFolderMinimumWidth: CGFloat
        let libraryFolderIdealWidth: CGFloat
        let libraryFolderMaximumWidth: CGFloat
        let repositoryListMinimumWidth: CGFloat
        let repositoryListIdealWidth: CGFloat
        let repositorySummaryMinimumWidth: CGFloat
        let repositorySummaryIdealWidth: CGFloat
        let repositorySummaryMaximumWidth: CGFloat
        let changeListMinimumWidth: CGFloat
        let changeListIdealWidth: CGFloat
        let historyGraphWidth: CGFloat
        let diffFontSize: CGFloat
        /// Width of the leading color bar on added and deleted diff lines; 0 hides it.
        let diffChangeBarWidth: CGFloat
        /// Vertical padding of Changes, History, Stashes, and Reflog rows.
        let rowVerticalPadding: CGFloat
    }

    struct Materials: Sendable {
        let response: GallaeMaterialResponse
        /// Sidebar and toolbar keep the system material; false paints them opaque.
        var translucentChrome: Bool { response == .standard }
    }

    let colors: Colors
    let metrics: Metrics
    let materials: Materials

    static let standard = resolve(response: .standard, compactRows: false)

    /// The single theme, mapped for one Material Response and row density.
    static func resolve(response: GallaeMaterialResponse, compactRows: Bool) -> GallaeTheme {
        let contrast = response == .increasedContrast
        return GallaeTheme(
            colors: .init(
                statusConflict: .red,
                statusModified: .orange,
                statusAdded: .green,
                statusDeleted: .red,
                statusRenamed: .purple,
                statusUntracked: .teal,
                badgeBackground: .secondary.opacity(contrast ? 0.22 : 0.12),
                historyGraphLanes: [.blue, .purple, .teal, .orange, .pink, .green, .indigo, .brown],
                authorBadgeColors: [.indigo, .teal, .orange, .blue, .pink, .green, .purple, .brown],
                diffText: .primary,
                diffMetadataText: contrast ? .primary : .secondary,
                diffHunkText: .accentColor,
                diffAdditionBackground: .green.opacity(contrast ? 0.24 : 0.12),
                diffDeletionBackground: .red.opacity(contrast ? 0.24 : 0.12),
                diffHunkBackground: .accentColor.opacity(contrast ? 0.16 : 0.08),
                opaqueChrome: Color(nsColor: .windowBackgroundColor)
            ),
            metrics: .init(
                libraryFolderMinimumWidth: 200,
                libraryFolderIdealWidth: 210,
                libraryFolderMaximumWidth: 240,
                repositoryListMinimumWidth: 280,
                repositoryListIdealWidth: 380,
                repositorySummaryMinimumWidth: 230,
                repositorySummaryIdealWidth: 290,
                repositorySummaryMaximumWidth: 340,
                changeListMinimumWidth: 320,
                changeListIdealWidth: 320,
                historyGraphWidth: 44,
                diffFontSize: contrast ? 11 : NSFont.systemFontSize,
                diffChangeBarWidth: contrast ? 3 : 0,
                rowVerticalPadding: compactRows ? 3 : 7
            ),
            materials: .init(response: response)
        )
    }
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
