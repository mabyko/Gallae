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
            ) { [weak self] _ in self?.apply() }
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
