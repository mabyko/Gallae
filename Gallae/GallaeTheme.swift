import SwiftUI

/// System colors adapt to Light, Dark, and Increase Contrast appearances.
enum GallaeHistoryColor: String, CaseIterable, Identifiable, Sendable {
    case blue, purple, teal, orange, pink, green, indigo, brown

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .teal: .teal
        case .orange: .orange
        case .pink: .pink
        case .green: .green
        case .indigo: .indigo
        case .brown: .brown
        }
    }

    var graphPalette: [Color] {
        ([self] + Self.allCases.filter { $0 != self }).map(\.color)
    }
}

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
        let accent: Color
        let customAccent: Color?
        let statusConflict: Color
        let statusModified: Color
        let statusAdded: Color
        let statusDeleted: Color
        let statusRenamed: Color
        let statusUntracked: Color
        let badgeBackground: Color
        let historyLocalBranch: Color
        let historyRemoteBranch: Color
        let historyTag: Color
        let historyGraphLanes: [Color]
        let authorBadgeColors: [Color]
        let diffText: Color
        let diffMetadataText: Color
        /// Neutral, never the accent: a hunk header is a label about the diff, not part of it, and an accent
        /// that happens to be green or red would read as an added or deleted line.
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
    static func resolve(
        response: GallaeMaterialResponse, compactRows: Bool,
        graphColor: GallaeHistoryColor = .blue, localBranchColor: GallaeHistoryColor = .blue,
        remoteBranchColor: GallaeHistoryColor = .teal, tagColor: GallaeHistoryColor = .purple,
        accentColor: GallaeHistoryColor? = nil
    ) -> GallaeTheme {
        let contrast = response == .increasedContrast
        return GallaeTheme(
            colors: .init(
                accent: accentColor?.color ?? .accentColor,
                customAccent: accentColor?.color,
                statusConflict: .red,
                statusModified: .orange,
                statusAdded: .green,
                statusDeleted: .red,
                statusRenamed: .purple,
                statusUntracked: .teal,
                badgeBackground: .secondary.opacity(contrast ? 0.22 : 0.12),
                historyLocalBranch: localBranchColor.color,
                historyRemoteBranch: remoteBranchColor.color,
                historyTag: tagColor.color,
                historyGraphLanes: graphColor.graphPalette,
                authorBadgeColors: [.indigo, .teal, .orange, .blue, .pink, .green, .purple, .brown],
                diffText: .primary,
                diffMetadataText: contrast ? .primary : .secondary,
                diffHunkText: contrast ? .primary : .secondary,
                diffAdditionBackground: .green.opacity(contrast ? 0.24 : 0.12),
                diffDeletionBackground: .red.opacity(contrast ? 0.24 : 0.12),
                diffHunkBackground: .secondary.opacity(contrast ? 0.20 : 0.10),
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

private struct GallaeSelectionBackground: ViewModifier {
    @Environment(\.gallaeTheme) private var theme
    @Environment(\.controlActiveState) private var controlActiveState
    let isSelected: Bool
    let isFocused: Bool
    let sidebar: Bool

    func body(content: Content) -> some View {
        // macOS List selection ignores .tint when a system accent is chosen. Override only the active
        // background; List still owns selection, keyboard navigation, and the inactive gray appearance.
        let color = isSelected && isFocused && controlActiveState == .key ? theme.colors.customAccent : nil
        return content.listRowBackground(color.map { color in
            RoundedRectangle(cornerRadius: sidebar ? 8 : 0)
                .fill(color)
                .padding(.horizontal, sidebar ? 10 : 0)
        })
    }
}

extension View {
    func gallaeSelectionBackground(isSelected: Bool, isFocused: Bool, sidebar: Bool = false) -> some View {
        modifier(GallaeSelectionBackground(isSelected: isSelected, isFocused: isFocused, sidebar: sidebar))
    }
}
