import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@MainActor @Observable
final class VisualDiffSession: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private(set) var document: VisualDiffDocument?
    private(set) var isLoading = false
    private(set) var isFullScreen = false
    var lens = "architecture"
    var errorMessage: String?
    var statusMessage: String?
    @ObservationIgnored var selectFile: (String) -> Bool = { _ in false }
    @ObservationIgnored private var webView: WKWebView?
    @ObservationIgnored private var isReady = false
    @ObservationIgnored private var pendingDocument: VisualDiffDocument?
    @ObservationIgnored private var renderedLens = "architecture"
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private weak var embeddedHost: NSView?
    @ObservationIgnored private weak var sourceWindow: NSWindow?
    @ObservationIgnored private var fullScreenWindow: NSWindow?
    @ObservationIgnored private var isTransitioningFullScreen = false
    @ObservationIgnored private var wantsFullScreenExit = false
    @ObservationIgnored private var themeName = "light"
    @ObservationIgnored private var selectedPath: String?
    @ObservationIgnored private var reduceMotion = false
    @ObservationIgnored private var presentationTheme = GallaeTheme.resolve(response: .standard, compactRows: false)

    func importGraph() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a PR Lens graph.json or drawn.graph.json. Rendering stays on this Mac."
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            self?.load(url)
        }
        if let window = embeddedHost?.window { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    func loadExample() {
        guard let url = Bundle.main.url(forResource: "example.graph", withExtension: "json", subdirectory: "VisualDiff") else { return }
        load(url)
    }

    func load(_ url: URL) {
        do {
            pendingDocument = try VisualDiffDocument.read(from: url)
            lens = pendingDocument?.lenses.first ?? "architecture"
            isLoading = true
            statusMessage = nil
            ensureWebView()
            renderPendingDocument()
        } catch { errorMessage = error.localizedDescription }
    }

    func reset() {
        exitFullScreen()
        generation += 1
        document = nil
        pendingDocument = nil
        isLoading = false
        errorMessage = nil
        statusMessage = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "visualDiff")
        webView?.removeFromSuperview()
        webView = nil
        isReady = false
    }

    func attach(to host: NSView) {
        embeddedHost = host
        ensureWebView()
        if !isFullScreen, let webView { install(webView, in: host) }
    }

    func detach(from host: NSView) {
        guard embeddedHost === host else { return }
        exitFullScreen()
        embeddedHost = nil
        if !isFullScreen { webView?.removeFromSuperview() }
    }

    func update(theme: GallaeTheme, dark: Bool, path: String?, reduceMotion: Bool) {
        presentationTheme = theme
        let newTheme = dark ? "dark" : "light"
        let needsRender = themeName != newTheme
        themeName = newTheme
        selectedPath = path
        self.reduceMotion = reduceMotion
        if needsRender { renderPendingDocument() }
        applyOptions()
    }

    func changeLens(_ value: String) {
        lens = value
        renderPendingDocument()
    }

    private func ensureWebView() {
        guard webView == nil else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(VisualDiffBridge(session: self), name: "visualDiff")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        webView = view
        guard let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "VisualDiff") else {
            errorMessage = "The bundled Visual Diff renderer is missing."
            isLoading = false
            return
        }
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    private func renderPendingDocument() {
        guard isReady, let candidate = pendingDocument ?? document, let webView else { return }
        generation += 1
        let request = generation
        webView.callAsyncJavaScript(
            "return window.GallaeLens.load(json, lens, theme);",
            arguments: ["json": candidate.json, "lens": lens, "theme": themeName],
            in: nil, in: .page
        ) { [weak self] result in
            guard let self, self.generation == request else { return }
            self.isLoading = false
            switch result {
            case .success:
                self.document = candidate
                self.pendingDocument = nil
                self.renderedLens = self.lens
                self.applyOptions()
            case .failure(let error):
                self.pendingDocument = nil
                self.lens = self.renderedLens
                self.errorMessage = "This graph could not be rendered. \(error.localizedDescription)"
            }
        }
    }

    private func applyOptions() {
        guard isReady else { return }
        webView?.callAsyncJavaScript(
            "window.GallaeLens.options({path, reduceMotion});",
            arguments: ["path": selectedPath.map { $0 as Any } ?? NSNull(), "reduceMotion": reduceMotion],
            in: nil, in: .page
        )
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: String] else { return }
        switch body["type"] {
        case "ready":
            isReady = true
            renderPendingDocument()
        case "escape": exitFullScreen()
        case "file":
            guard let path = body["path"] else { return }
            if !selectFile(path) { statusMessage = "\(path) is not in this review’s changed files." }
        default: break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "VisualDiff")
        return navigationAction.request.url == page ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        errorMessage = "Couldn’t load the local diagram viewer. \(error.localizedDescription)"
    }

    // Move the same WKWebView rather than rendering a second copy. Its camera and selection survive.
    func enterFullScreen() {
        guard fullScreenWindow == nil, document != nil, let webView, let host = embeddedHost else { return }
        sourceWindow = host.window
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = document?.title ?? "Visualize Changes"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.appearance = sourceWindow?.appearance
        window.delegate = self
        let container = NSView()
        let header = NSHostingView(rootView: VisualDiffFullScreenHeader(session: self).environment(\.gallaeTheme, presentationTheme))
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 64),
            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container
        fullScreenWindow = window
        isFullScreen = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
        isTransitioningFullScreen = true
        window.toggleFullScreen(nil)
    }

    func exitFullScreen() {
        guard let window = fullScreenWindow else { return }
        wantsFullScreenExit = true
        guard !isTransitioningFullScreen else { return }
        if window.styleMask.contains(.fullScreen) {
            isTransitioningFullScreen = true
            window.toggleFullScreen(nil)
        }
        else { finishFullScreen() }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isTransitioningFullScreen = false
        if wantsFullScreenExit { exitFullScreen() }
    }
    func windowDidExitFullScreen(_ notification: Notification) { finishFullScreen() }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { finishFullScreen() }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { isTransitioningFullScreen = false }
    func windowShouldClose(_ sender: NSWindow) -> Bool { exitFullScreen(); return false }

    private func finishFullScreen() {
        guard let window = fullScreenWindow else { return }
        if let webView {
            webView.removeFromSuperview()
            if let host = embeddedHost { install(webView, in: host) }
        }
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        fullScreenWindow = nil
        isTransitioningFullScreen = false
        wantsFullScreenExit = false
        isFullScreen = false
        sourceWindow?.makeKeyAndOrderFront(nil)
    }

    private func install(_ view: NSView, in host: NSView) {
        guard view.superview !== host else { return }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor), view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor), view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
    }
}

private final class VisualDiffBridge: NSObject, WKScriptMessageHandler {
    weak var session: VisualDiffSession?
    init(session: VisualDiffSession) { self.session = session }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        session?.receive(message)
    }
}

struct VisualDiffButton: View {
    @Binding var isPresented: Bool
    var body: some View {
        Button("Visualize", systemImage: "point.3.connected.trianglepath.dotted") { isPresented.toggle() }
            .tint(isPresented ? .accentColor : nil)
            .help("View an imported PR Lens diagram of the change")
            .accessibilityValue(isPresented ? "On" : "Off")
    }
}

struct VisualDiffPane: View {
    @Environment(VisualDiffSession.self) private var session
    @Environment(\.gallaeTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fullScreenButtonFocused: Bool
    let selectedPath: String?
    let selectFile: (String) -> Bool

    var body: some View {
        VStack(spacing: 0) {
            if let document = session.document {
                ViewThatFits(in: .horizontal) {
                    HStack { graphIdentity(document); Spacer(); controls(document) }
                    VStack(alignment: .leading, spacing: theme.metrics.panelSpacing) { graphIdentity(document); controls(document) }
                }
                .padding(.horizontal, theme.metrics.panelHorizontalPadding)
                .padding(.vertical, theme.metrics.panelVerticalPadding)
                .background(theme.colors.opaqueChrome)
                Divider()
            }
            if session.document != nil || session.isLoading {
                VisualDiffWebHost(session: session, theme: theme, dark: colorScheme == .dark, path: selectedPath, reduceMotion: reduceMotion, selectFile: selectFile)
                    .overlay {
                        if session.isFullScreen {
                            ContentUnavailableView { Label("Viewing in Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                            actions: { Button("Return to Diff", action: session.exitFullScreen) }
                        } else if session.isLoading { ProgressView("Loading Diagram…") }
                    }
            } else {
                ContentUnavailableView {
                    Label("Visualize Changes", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Import a PR Lens graph to explore the change visually. Graphs are snapshots and are rendered locally.")
                } actions: {
                    Button("Import Graph…", action: session.importGraph).buttonStyle(.borderedProminent)
                    Button("Show Example", action: session.loadExample)
                }
            }
            if let message = session.statusMessage {
                Text(message).gallaeFont(.caption1).foregroundStyle(.secondary)
                    .padding(theme.metrics.panelVerticalPadding)
            }
        }
        .controlSize(.small)
        .onAppear { session.selectFile = selectFile }
        .onDisappear { session.selectFile = { _ in false }; session.exitFullScreen() }
        .onChange(of: session.isFullScreen) { _, isFullScreen in
            if !isFullScreen { fullScreenButtonFocused = true }
        }
        .alert("Couldn’t Load Graph", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
    }

    private func graphIdentity(_ document: VisualDiffDocument) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(document.title).gallaeFont(.headline).lineLimit(1)
            Text("Imported snapshot · \(document.sourceDescription)")
                .gallaeFont(.caption1).foregroundStyle(.secondary).lineLimit(1).help(document.sourceDescription)
        }
    }

    private func controls(_ document: VisualDiffDocument) -> some View {
        HStack(spacing: theme.metrics.panelSpacing) {
            if document.lenses.count > 1 {
                Picker("Diagram", selection: Binding(get: { session.lens }, set: session.changeLens)) {
                    ForEach(document.lenses, id: \.self) { lens in
                        Text(lens == "architecture" ? "Architecture" : "Data Flow").tag(lens)
                    }
                }.labelsHidden().fixedSize()
            }
            Button("Import Graph…", action: session.importGraph)
            Button("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right", action: session.enterFullScreen)
                .focused($fullScreenButtonFocused)
                .help("Open the diagram in full screen. Press Esc to return here.")
                .disabled(session.isFullScreen)
        }
    }
}

private struct VisualDiffFullScreenHeader: View {
    var session: VisualDiffSession
    @Environment(\.gallaeTheme) private var theme
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.document?.title ?? "Visualize Changes").gallaeFont(.headline)
                Text("Imported snapshot · \(session.document?.sourceDescription ?? "")")
                    .gallaeFont(.caption1).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left", action: session.exitFullScreen)
                .keyboardShortcut(.cancelAction)
                .help("Return to Visualize (Esc)")
        }
        .padding(.horizontal, theme.metrics.panelHorizontalPadding)
        .background(theme.colors.opaqueChrome)
    }
}

private struct VisualDiffWebHost: NSViewRepresentable {
    let session: VisualDiffSession
    let theme: GallaeTheme
    let dark: Bool
    let path: String?
    let reduceMotion: Bool
    let selectFile: (String) -> Bool
    func makeCoordinator() -> VisualDiffSession { session }
    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        session.attach(to: host)
        return host
    }
    func updateNSView(_ host: NSView, context: Context) {
        session.selectFile = selectFile
        session.attach(to: host)
        session.update(theme: theme, dark: dark, path: path, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ host: NSView, coordinator: VisualDiffSession) { coordinator.detach(from: host) }
}

struct GallaeLabsSettings: View {
    @AppStorage(GallaeLabs.visualDiffKey) private var visualDiffEnabled = false
    var body: some View {
        Form {
            Section("Experimental Features") {
                Toggle("Visual Diff · PR Lens", isOn: $visualDiffEnabled)
                    .accessibilityHint("Adds Visualize to the Diff toolbar")
                Text("Explore imported PR Lens graphs in Diff. Includes architecture and data-flow views, zoom, file navigation, and full screen with Esc to return.")
                    .gallaeFont(.caption1).foregroundStyle(.secondary)
                Text("Graphs render locally. This experiment does not analyze or upload your code; generate a graph with your coding agent or PR Lens, then import its JSON.")
                    .gallaeFont(.caption1).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
