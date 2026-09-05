import AppKit
import SwiftUI

/// Two panes with a draggable divider, laid out by SwiftUI so the detail column never carries a hard minimum
/// width. `HSplitView` is NSSplitView underneath, and macOS's `NavigationSplitView` counts the sidebar width into
/// its detail minimum twice: with a hard minimum the window grows when the Navigator opens, and with a minimum plus
/// ideal the trailing pane stops short of the window once the sidebar passes half the free width. With no minimum a
/// narrow container squeezes the panes instead: the leading pane yields to its minimum first, then both shrink.
struct ResizableHSplit<Leading: View, Trailing: View>: View {
    let leadingMinimum: CGFloat
    let leadingMaximum: CGFloat?
    let trailingMinimum: CGFloat
    private let leading: () -> Leading
    private let trailing: () -> Trailing
    @SceneStorage private var leadingWidth: Double
    @State private var dragStartWidth: CGFloat?
    @FocusState private var isDividerFocused: Bool

    init(
        leadingMinimum: CGFloat,
        leadingIdeal: CGFloat,
        leadingMaximum: CGFloat? = nil,
        trailingMinimum: CGFloat,
        storageKey: String,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.leadingMinimum = leadingMinimum
        self.leadingMaximum = leadingMaximum
        self.trailingMinimum = trailingMinimum
        self.leading = leading
        self.trailing = trailing
        _leadingWidth = SceneStorage(wrappedValue: Double(leadingIdeal), "resizableSplit.\(storageKey).leadingWidth")
    }

    var body: some View {
        GeometryReader { proxy in
            let width = ResizableHSplitLayout.leadingWidth(
                preferred: CGFloat(leadingWidth),
                leadingMinimum: leadingMinimum,
                leadingMaximum: leadingMaximum,
                trailingMinimum: trailingMinimum,
                total: proxy.size.width
            )
            HStack(spacing: 0) {
                leading()
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .clipped()

                Divider()
                    .overlay {
                        Color.clear
                            .frame(width: 9)
                            .contentShape(.rect)
                            .onHover { inside in
                                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                            }
                            .gesture(
                                // Global coordinates: the divider moves with the drag, so a local translation
                                // would shift with it and the panes would oscillate.
                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { value in
                                        let start = dragStartWidth ?? width
                                        dragStartWidth = start
                                        leadingWidth = Double(ResizableHSplitLayout.leadingWidth(
                                            preferred: start + value.translation.width,
                                            leadingMinimum: leadingMinimum,
                                            leadingMaximum: leadingMaximum,
                                            trailingMinimum: trailingMinimum,
                                            total: proxy.size.width
                                        ))
                                    }
                                    .onEnded { _ in dragStartWidth = nil }
                            )
                    }
                    .overlay {
                        if isDividerFocused {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(.tint, lineWidth: 2)
                                .frame(width: 9)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Resize panels")
                    .accessibilityValue("Left panel \(Int(width)) points")
                    .accessibilityHint("Use Left and Right Arrow to resize the panels")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: adjustWidth(by: 20, current: width, total: proxy.size.width)
                        case .decrement: adjustWidth(by: -20, current: width, total: proxy.size.width)
                        @unknown default: break
                        }
                    }
                    .focusable()
                    .focused($isDividerFocused)
                    .onKeyPress(.leftArrow) {
                        adjustWidth(by: -20, current: width, total: proxy.size.width)
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        adjustWidth(by: 20, current: width, total: proxy.size.width)
                        return .handled
                    }

                trailing()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
    }

    private func adjustWidth(by amount: CGFloat, current: CGFloat, total: CGFloat) {
        leadingWidth = Double(ResizableHSplitLayout.leadingWidth(
            preferred: current + amount,
            leadingMinimum: leadingMinimum,
            leadingMaximum: leadingMaximum,
            trailingMinimum: trailingMinimum,
            total: total
        ))
    }

}

/// Keeps the sidebar within `maximum`. `navigationSplitViewColumnWidth(max:)` binds programmatic positions only:
/// the split view item's maximum thickness is kept set so drags stop there, and a wider frame AppKit restores at
/// launch is moved back once the view attaches.
struct SidebarWidthClamp: NSViewRepresentable {
    let maximum: CGFloat
    let generation: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ClampView {
        let view = ClampView(frame: .zero)
        view.maximum = maximum
        return view
    }

    func updateNSView(_ view: ClampView, context: Context) {
        view.maximum = maximum
        guard context.coordinator.handledGeneration != generation else { return }
        context.coordinator.handledGeneration = generation
        view.clampSoon()
    }

    final class Coordinator { var handledGeneration = 0 }

    /// Clamps once attached, for the frame AppKit restores at launch, and whenever asked after a drag.
    final class ClampView: NSView {
        var maximum: CGFloat = .infinity
        private var thicknessObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { clampSoon() }
        }

        func clampSoon() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.clampIfNeeded() }
        }

        private func clampIfNeeded() {
            var candidate = superview
            while let current = candidate, !(current is NSSplitView) { candidate = current.superview }
            guard let splitView = candidate as? NSSplitView, let sidebar = splitView.arrangedSubviews.first else { return }
            // SwiftUI leaves the item's maximum thickness unset and clears it again on its updates, so the value
            // is put back whenever it changes; the controller then stops drags at the maximum.
            if thicknessObservation == nil, let controller = splitView.delegate as? NSSplitViewController,
               let item = controller.splitViewItems.first {
                let maximum = self.maximum
                // AppKit changes the item on the main thread; the guard ends the re-entrant notification.
                nonisolated(unsafe) let boundItem = item
                thicknessObservation = item.observe(\.maximumThickness, options: [.initial, .new]) { _, _ in
                    MainActor.assumeIsolated {
                        guard boundItem.maximumThickness != maximum else { return }
                        boundItem.maximumThickness = maximum
                    }
                }
            }
            guard sidebar.frame.width > maximum else { return }
            splitView.setPosition(maximum, ofDividerAt: 0)
        }
    }
}

/// With the system's always-visible scroll bars a list's rows end a scroller's width before the pane edge. Headers
/// above a list take the same inset, and the list keeps its scroller shown so the two never drift apart.
@MainActor
private enum LegacyScrollerStyle {
    static var isLegacy: Bool { NSScroller.preferredScrollerStyle == .legacy }
    static var width: CGFloat { isLegacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0 }
}

private struct ListHeaderInset: ViewModifier {
    @State private var inset = LegacyScrollerStyle.width

    func body(content: Content) -> some View {
        content
            .padding(.trailing, inset)
            .onReceive(NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)) { _ in
                inset = LegacyScrollerStyle.width
            }
    }
}

private struct ListScrollerPolicy: NSViewRepresentable {
    func makeNSView(context: Context) -> PolicyView { PolicyView(frame: .zero) }
    func updateNSView(_ view: PolicyView, context: Context) {}

    final class PolicyView: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            apply()
            observer = observer ?? NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
        }

        /// The list's scroll view is the smallest one under the window that contains this view's center.
        private func apply() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let root = self.window?.contentView else { return }
                let center = self.convert(CGPoint(x: self.bounds.midX, y: self.bounds.midY), to: nil)
                let candidates = Self.scrollViews(in: root).filter { $0.convert($0.bounds, to: nil).contains(center) }
                guard let scrollView = candidates.min(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { return }
                scrollView.autohidesScrollers = !LegacyScrollerStyle.isLegacy
            }
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            view.subviews.flatMap { ($0 as? NSScrollView).map { [$0] } ?? scrollViews(in: $0) }
        }
    }
}

extension View {
    /// For a header above a list, so its trailing content lines up with the rows beside a legacy scroller.
    func listHeaderInset() -> some View { modifier(ListHeaderInset()) }
    /// For a list with a header above it; see `ListHeaderInset`.
    func legacyScrollerAware() -> some View { background(ListScrollerPolicy()) }
}

enum ResizableHSplitLayout {
    static let dividerWidth: CGFloat = 1

    /// The leading pane's width in a container `total` points wide: the preferred width while both minimums fit,
    /// else the leading pane yields down to its minimum, else both panes shrink in the ratio of their minimums.
    static func leadingWidth(
        preferred: CGFloat,
        leadingMinimum: CGFloat,
        leadingMaximum: CGFloat?,
        trailingMinimum: CGFloat,
        total: CGFloat
    ) -> CGFloat {
        // Whole points only: a lazy stack proposed a fractional width such as 940.8 falls back to its
        // intrinsic width for that frame, so the diff flickered between narrow and full while dragging.
        let available = max(total - dividerWidth, 0).rounded(.down)
        let clamped = min(max(preferred, leadingMinimum), leadingMaximum ?? .infinity).rounded()
        if clamped + trailingMinimum <= available { return clamped }
        let yielded = available - trailingMinimum
        if yielded >= leadingMinimum { return yielded }
        return (available * leadingMinimum / (leadingMinimum + trailingMinimum)).rounded(.down)
    }
}

/// Keeps both panes alive when changing layout or expanding review, including the hidden list's size.
struct RepositoryHistorySplit<History: View, Review: View>: View {
    let layout: GallaeAppearanceSettings.HistoryLayout
    let isReviewExpanded: Bool
    @ViewBuilder let history: () -> History
    @ViewBuilder let review: () -> Review
    @SceneStorage("resizableSplit.history.leadingWidth") private var historyWidth = 320.0
    @SceneStorage("historySplit.topHeight") private var historyHeight = 260.0
    @State private var dragStart: CGFloat?
    @FocusState private var dividerFocused: Bool
    private var isStacked: Bool { layout == .stacked }
    private var isExpanded: Bool { isStacked && isReviewExpanded }

    var body: some View {
        GeometryReader { proxy in
            let frames = RepositoryHistoryFrames(
                size: proxy.size, stacked: isStacked, expanded: isExpanded,
                preferredWidth: historyWidth, preferredHeight: historyHeight
            )
            ZStack(alignment: .topLeading) {
                history()
                    .frame(width: frames.history.width, height: frames.history.height)
                    .clipped()
                    .opacity(isExpanded ? 0 : 1)
                    .allowsHitTesting(!isExpanded)
                    .disabled(isExpanded)
                    .accessibilityHidden(isExpanded)

                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: frames.divider.width, height: frames.divider.height)
                    .overlay {
                        Color.clear
                            .frame(width: isStacked ? frames.divider.width : 9,
                                   height: isStacked ? 9 : frames.divider.height)
                            .contentShape(.rect)
                            .onHover { inside in
                                if inside { (isStacked ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push() }
                                else { NSCursor.pop() }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { value in
                                        let current = isStacked ? frames.history.height : frames.history.width
                                        let start = dragStart ?? current
                                        dragStart = start
                                        resize(to: start + (isStacked ? value.translation.height : value.translation.width),
                                               size: proxy.size)
                                    }
                                    .onEnded { _ in dragStart = nil }
                            )
                    }
                    .overlay {
                        if dividerFocused {
                            RoundedRectangle(cornerRadius: 3).stroke(.tint, lineWidth: 2)
                                .frame(width: isStacked ? frames.divider.width : 9,
                                       height: isStacked ? 9 : frames.divider.height)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(isStacked ? "Resize History height" : "Resize panels")
                    .accessibilityValue("\(Int(isStacked ? frames.history.height : frames.history.width)) points")
                    .accessibilityHint(isStacked ? "Use Up and Down Arrow to resize History" : "Use Left and Right Arrow to resize History")
                    .accessibilityAdjustableAction { direction in
                        let current = isStacked ? frames.history.height : frames.history.width
                        switch direction {
                        case .increment: resize(to: current + 20, size: proxy.size)
                        case .decrement: resize(to: current - 20, size: proxy.size)
                        @unknown default: break
                        }
                    }
                    .focusable()
                    .focused($dividerFocused)
                    .onKeyPress(.upArrow) {
                        guard isStacked else { return .ignored }
                        resize(to: frames.history.height - 20, size: proxy.size)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        guard isStacked else { return .ignored }
                        resize(to: frames.history.height + 20, size: proxy.size)
                        return .handled
                    }
                    .onKeyPress(.leftArrow) {
                        guard !isStacked else { return .ignored }
                        resize(to: frames.history.width - 20, size: proxy.size)
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        guard isStacked == false else { return .ignored }
                        resize(to: frames.history.width + 20, size: proxy.size)
                        return .handled
                    }
                    .offset(x: frames.divider.minX, y: frames.divider.minY)
                    .opacity(isExpanded ? 0 : 1)
                    .allowsHitTesting(!isExpanded)
                    .disabled(isExpanded)
                    .accessibilityHidden(isExpanded)

                review()
                    .frame(width: frames.review.width, height: frames.review.height)
                    .clipped()
                    .offset(x: frames.review.minX, y: frames.review.minY)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .onChange(of: layout) { dragStart = nil; dividerFocused = false }
        .onChange(of: isReviewExpanded) { dividerFocused = false }
    }

    private func resize(to preferred: CGFloat, size: CGSize) {
        let frames = RepositoryHistoryFrames(
            size: size, stacked: isStacked, expanded: false,
            preferredWidth: isStacked ? historyWidth : preferred,
            preferredHeight: isStacked ? preferred : historyHeight
        )
        if isStacked { historyHeight = frames.history.height }
        else { historyWidth = frames.history.width }
    }
}

struct RepositoryHistoryFrames {
    let history: CGRect
    let divider: CGRect
    let review: CGRect

    init(size: CGSize, stacked: Bool, expanded: Bool, preferredWidth: CGFloat, preferredHeight: CGFloat) {
        let width = max(0, size.width.rounded(.down))
        let height = max(0, size.height.rounded(.down))
        let total = stacked ? height : width
        let leading = ResizableHSplitLayout.leadingWidth(
            preferred: stacked ? preferredHeight : preferredWidth,
            leadingMinimum: stacked ? 160 : 320, leadingMaximum: nil,
            trailingMinimum: stacked ? 220 : 400, total: total
        )
        let gap = min(1, total)
        history = CGRect(x: 0, y: 0, width: stacked ? width : leading, height: stacked ? leading : height)
        divider = CGRect(x: stacked ? 0 : leading, y: stacked ? leading : 0,
                         width: stacked ? width : gap, height: stacked ? gap : height)
        if stacked && expanded {
            review = CGRect(x: 0, y: 0, width: width, height: height)
        } else {
            review = CGRect(x: stacked ? 0 : leading + gap, y: stacked ? leading + gap : 0,
                            width: stacked ? width : max(0, width - leading - gap),
                            height: stacked ? max(0, height - leading - gap) : height)
        }
    }
}

/// Navigation is restricted to the currently scoped and searched History.
enum RepositoryHistoryNavigation {
    static func adjacent(to selected: String?, offset: Int, in visibleIDs: [String]) -> String? {
        guard let selected, let index = visibleIDs.firstIndex(of: selected),
              offset == -1 || offset == 1 else { return nil }
        let target = index + offset
        return visibleIDs.indices.contains(target) ? visibleIDs[target] : nil
    }
}
