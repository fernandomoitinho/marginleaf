import AppKit
import WebKit
import MarginleafCore

/// The preview, with "Comment" added to the right-click menu when text is selected.
final class PreviewWebView: WKWebView {
    var onComment: (() -> Void)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        let hasSelection = menu.items.contains { $0.identifier?.rawValue == "WKMenuItemIdentifierCopy" }
        guard hasSelection else { return }
        let item = NSMenuItem(title: "Comment", action: #selector(commentFromMenu), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "plus.bubble", accessibilityDescription: nil)
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }

    @objc private func commentFromMenu() { onComment?() }
}

/// Hosts an existing view as the main pane of the split view.
private final class ContentViewController: NSViewController {
    init(content: NSView) {
        super.init(nibName: nil, bundle: nil)
        // Without this the view's current size becomes a fixed size and the window can't be resized.
        content.translatesAutoresizingMaskIntoConstraints = false
        view = content
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

final class DocumentWindowController: NSWindowController, NSTextViewDelegate, WKNavigationDelegate, NSToolbarDelegate {
    private enum Mode { case preview, source }

    private weak var markdownDoc: MarkdownDocument?

    private let container = NSView()
    private let webView: PreviewWebView
    private let assets: AssetSchemeHandler
    private let scrollView: NSScrollView
    private let textView: NSTextView
    private let highlighter = MarkdownHighlighter()
    private let comments: CommentsController
    private var commentsMenuItem: NSMenuToolbarItem?
    private var sidebar: SidebarViewController?
    private var splitController: NSSplitViewController?
    private var sidebarObserver: NSKeyValueObservation?
    private let outlinePanel = OutlineViewController()
    private var outlineItem: NSSplitViewItem?
    private var outlineObserver: NSKeyValueObservation?
    private var outlineRefresh: DispatchWorkItem?

    private var mode: Mode = .preview
    /// Bumped on every change to the text; the preview re-renders only when it is behind.
    private var textVersion = 0
    private var renderedVersion = -1
    /// The source view is filled lazily, the first time it is shown (keeps opening fast).
    private var sourceIsStale = true
    private var sourceHasPendingEdits = false
    private var pendingPreviewFraction: Double?

    var isShowingSource: Bool { mode == .source }

    // MARK: Toolbar (Preview | Source)

    private static let modeItemID = NSToolbarItem.Identifier("marginleaf.mode")
    private static let toggleCommentsID = NSToolbarItem.Identifier("marginleaf.toggleComments")
    private static let addCommentID = NSToolbarItem.Identifier("marginleaf.addComment")
    private static let commentsID = NSToolbarItem.Identifier("marginleaf.comments")
    private static let outlineID = NSToolbarItem.Identifier("marginleaf.outline")

    // Comments (preview only for now)
    var canAddComment: Bool { true }
    var hasComments: Bool { comments.hasComments }
    func addComment() {
        guard canAddComment else { return }
        if !Settings.commentsVisible {
            Settings.commentsVisible = true
            commentsToggle.state = .on
            comments.applyVisibility()
        }
        if mode == .source { comments.beginAddFromSource() } else { comments.beginAdd() }
    }
    func copyComments() { comments.copyAll() }

    private lazy var commentsToggle: NSButton = {
        let image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: "Show comments")
        let button = NSButton(image: image ?? NSImage(), target: self, action: #selector(commentsToggled(_:)))
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .texturedRounded
        button.state = Settings.commentsVisible ? .on : .off
        button.toolTip = "Show or hide comment highlights"
        return button
    }()

    @objc private func commentsToggled(_ sender: NSButton) {
        Settings.commentsVisible = sender.state == .on
        comments.applyVisibility()
        comments.applySourceHighlights()
    }

    @objc private func sourceClicked(_ gesture: NSClickGestureRecognizer) {
        comments.sourceClicked(at: gesture.location(in: textView))
    }

    @objc private func addCommentTapped() { addComment() }

    private lazy var modeControl: NSSegmentedControl = {
        let control = NSSegmentedControl(labels: ["Preview", "Source"], trackingMode: .selectOne,
                                         target: self, action: #selector(modeControlChanged(_:)))
        control.selectedSegment = 0
        control.segmentStyle = .automatic
        return control
    }()

    @objc private func modeControlChanged(_ sender: NSSegmentedControl) {
        if (sender.selectedSegment == 1) != (mode == .source) { toggleMode() }
    }

    private func installToolbar(in window: NSWindow) {
        let toolbar = NSToolbar(identifier: "marginleaf.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, Self.modeItemID, Self.toggleCommentsID, Self.addCommentID, Self.commentsID, .flexibleSpace, Self.outlineID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, Self.modeItemID, Self.toggleCommentsID, Self.addCommentID, Self.commentsID, Self.outlineID]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case Self.modeItemID:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = modeControl
            item.label = "View"
            item.toolTip = "Switch between Preview and Source (Cmd+E)"
            return item
        case Self.toggleCommentsID:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = commentsToggle
            item.label = "Comments"
            item.toolTip = "Show or hide comment highlights"
            return item
        case Self.addCommentID:
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = NSImage(systemSymbolName: "plus.bubble", accessibilityDescription: "Add comment")
            item.label = "Comment"
            item.toolTip = "Comment on the selected text (Option+Cmd+M)"
            item.target = self
            item.action = #selector(addCommentTapped)
            item.isBordered = true
            return item
        case Self.commentsID:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Comments")
            item.label = "Comments"
            item.toolTip = "List, copy or delete comments"
            item.menu = comments.makeMenu()
            commentsMenuItem = item
            return item
        case Self.outlineID:
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Outline")
            item.label = "Outline"
            item.toolTip = "Show or hide the outline (Option+Cmd+O)"
            item.target = self
            item.action = #selector(toggleOutlineTapped)
            item.isBordered = true
            return item
        default:
            return nil
        }
    }

    /// How far down the preview is scrolled, 0...1.
    private static let previewFractionJS =
        "window.scrollY / Math.max(1, document.documentElement.scrollHeight - window.innerHeight)"

    // MARK: Setup

    init(document: MarkdownDocument) {
        let handler = AssetSchemeHandler()
        let config = WKWebViewConfiguration()
        let commentsController = CommentsController(noteURL: document.fileURL)
        commentsController.install(in: config)
        config.setURLSchemeHandler(handler, forURLScheme: "marginleaf")
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = PreviewWebView(frame: .zero, configuration: config)
        web.underPageBackgroundColor = .textBackgroundColor

        let scroll = NSTextView.scrollableTextView()
        guard let text = scroll.documentView as? NSTextView else {
            fatalError("scrollableTextView() did not contain an NSTextView")
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: (Settings.sidebarVisible ? 1090 : 860) + (Settings.outlineVisible ? 250 : 0), height: 920),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isRestorable = false
        window.minSize = NSSize(width: 420, height: 320)
        window.center()

        self.markdownDoc = document
        self.assets = handler
        self.comments = commentsController
        self.webView = web
        self.scrollView = scroll
        self.textView = text
        super.init(window: window)

        shouldCascadeWindows = true
        comments.webView = web
        web.onComment = { [weak self] in self?.addComment() }
        comments.textView = text
        comments.window = window
        comments.onChange = { [weak self] in
            guard let self else { return }
            self.commentsMenuItem?.menu = self.comments.makeMenu()
            if self.mode == .source { self.comments.applySourceHighlights() }
        }
        configureViews(in: window)
        installToolbar(in: window)
        if Settings.outlineVisible { refreshOutline() }

        // Reading is the common case; an empty (new) note starts in the editor.
        if document.text.isEmpty {
            show(.source, fraction: 0)
        } else {
            show(.preview, fraction: 0)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(applyZoom), name: .marginleafZoomChanged, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func configureViews(in window: NSWindow) {
        let sidebarController = SidebarViewController(currentFile: markdownDoc?.fileURL) { [weak self] url in
            self?.openFromSidebar(url)
        }
        sidebar = sidebarController
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 170
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true
        sidebarItem.isCollapsed = !Settings.sidebarVisible
        let contentItem = NSSplitViewItem(viewController: ContentViewController(content: container))
        contentItem.minimumThickness = 360
        let outlineItem = NSSplitViewItem(viewController: outlinePanel)
        outlineItem.minimumThickness = 170
        outlineItem.maximumThickness = 420
        outlineItem.canCollapse = true
        outlineItem.isCollapsed = !Settings.outlineVisible
        outlineItem.holdingPriority = NSLayoutConstraint.Priority(260)
        outlineItem.preferredThicknessFraction = 0.24
        self.outlineItem = outlineItem
        outlinePanel.onSelect = { [weak self] item in self?.goToHeading(item) }
        outlinePanel.onClose = { [weak self] in self?.toggleOutline() }
        let split = NSSplitViewController()
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(contentItem)
        split.addSplitViewItem(outlineItem)
        let frame = window.frame
        splitController = split
        window.contentViewController = split
        window.setFrame(frame, display: false)
        if !sidebarItem.isCollapsed {
            split.view.layoutSubtreeIfNeeded()
            split.splitView.setPosition(230, ofDividerAt: 0)
        }
        window.contentMinSize = NSSize(width: 420, height: 320)
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        sidebarObserver = sidebarItem.observe(\.isCollapsed) { item, _ in
            Settings.sidebarVisible = !item.isCollapsed
        }
        outlineObserver = outlineItem.observe(\.isCollapsed) { [weak self] item, _ in
            Settings.outlineVisible = !item.isCollapsed
            if !item.isCollapsed { DispatchQueue.main.async { self?.refreshOutline() } }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in self?.sidebar?.refresh() }

        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.pageZoom = Settings.zoom
        container.addSubview(webView)

        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        container.addSubview(scrollView)

        // TextKit 1 on purpose: comment highlights use its display-only attributes.
        _ = textView.layoutManager
        textView.delegate = self
        let click = NSClickGestureRecognizer(target: self, action: #selector(sourceClicked(_:)))
        click.delaysPrimaryMouseButtonEvents = false
        textView.addGestureRecognizer(click)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.textStorage?.delegate = highlighter
        highlighter.baseSize = 13 * Settings.zoom
        textView.font = .monospacedSystemFont(ofSize: highlighter.baseSize, weight: .regular)
        textView.textColor = .labelColor
    }

    /// A click in the explorer. The note replaces this one in the same place on screen,
    /// unless this one has unsaved edits, in which case it stays and the new one opens beside it.
    private func openFromSidebar(_ url: URL) {
        guard url != markdownDoc?.fileURL else { return }
        let oldFrame = window?.frame
        let old = markdownDoc
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, alreadyOpen, error in
            guard let doc else {
                if let error { NSApp.presentError(error) }
                return
            }
            if !alreadyOpen {
                if let frame = oldFrame { doc.windowControllers.first?.window?.setFrame(frame, display: true) }
                if let old, old !== doc, !old.isDocumentEdited { old.close() }
            }
        }
    }

    // MARK: Switching views

    /// Cmd+E.
    func toggleMode() {
        switch mode {
        case .preview:
            webView.evaluateJavaScript(Self.previewFractionJS) { [weak self] result, _ in
                self?.show(.source, fraction: (result as? Double) ?? 0)
            }
        case .source:
            show(.preview, fraction: sourceFraction())
        }
    }

    /// Replace only makes sense in the source, so from Preview we switch there first.
    func showFindAndReplace() {
        let open = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.textView)
            let sender = NSMenuItem()
            sender.tag = NSTextFinder.Action.showReplaceInterface.rawValue
            self.textView.performTextFinderAction(sender)
        }
        if mode == .source {
            open()
        } else {
            toggleMode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: open)
        }
    }

    private func show(_ newMode: Mode, fraction: Double) {
        mode = newMode
        modeControl.selectedSegment = newMode == .source ? 1 : 0
        switch newMode {
        case .source:
            ensureSourceLoaded()
            comments.applySourceHighlights()
            webView.isHidden = true
            scrollView.isHidden = false
            window?.makeFirstResponder(textView)
            // Layout of a freshly shown text view settles on the next turn of the run loop.
            DispatchQueue.main.async { [weak self] in self?.setSourceFraction(fraction) }
        case .preview:
            commitEdits()
            scrollView.isHidden = true
            webView.isHidden = false
            window?.makeFirstResponder(webView)
            if renderedVersion != textVersion {
                renderPreview(restoring: fraction)
            } else {
                setPreviewFraction(fraction)
            }
        }
    }

    // MARK: Preview

    private func renderPreview(restoring fraction: Double?) {
        pendingPreviewFraction = fraction
        assets.root = markdownDoc?.fileURL?.deletingLastPathComponent()
        let page = Renderer.page(from: markdownDoc?.text ?? "")
        webView.loadHTMLString(page, baseURL: URL(string: "marginleaf://doc/"))
        renderedVersion = textVersion
    }

    private func setPreviewFraction(_ fraction: Double) {
        let js = "window.scrollTo(0, \(fraction) * Math.max(0, document.documentElement.scrollHeight - window.innerHeight))"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let fraction = pendingPreviewFraction {
            pendingPreviewFraction = nil
            setPreviewFraction(fraction)
        }
        comments.applyHighlights()
        if let out = ProcessInfo.processInfo.environment["MARGINLEAF_SELFTEST"] { runSelfTest(writingTo: out) }
    }

    /// CI only: select the first paragraph, ask the comment script about it, highlight it,
    /// write what came back and quit. Proves the injected script runs with page JS disabled.
    private func runSelfTest(writingTo path: String) {
        let js = """
        (function () {
          var p = document.querySelector('article p'), r = document.createRange();
          r.selectNodeContents(p);
          var s = getSelection(); s.removeAllRanges(); s.addRange(r);
          var sel = marginleafSelection();
          var res = marginleafHighlight([{ id: 't', quote: sel.text, start: sel.start }]);
          var p0 = document.querySelector('article > p');
          var pr = p0.getBoundingClientRect();
          var plus = marginleafProbe(pr.left - 10, pr.top + 5) && !marginleafProbe(pr.left + 200, pr.top + 5);
          // Edited passage: same opening, different ending -> should still be found (fuzzy).
          var long = sel.text + ' and then this sentence was added after the comment was written';
          var fuzzy = marginleafHighlight([{ id: 'f', quote: long + ' ' + long, alt: '', start: sel.start }]);
          return JSON.stringify({ sel: sel, res: res, plus: plus, fuzzy: fuzzy, marks: document.querySelectorAll('mark.fc').length });
        })()
        """
        webView.evaluateJavaScript(js, in: nil, in: .defaultClient) { [weak self] result in
            guard let self else { return }
            let text: String
            switch result {
            case .success(let value): text = "\(value)"
            case .failure(let error): text = "ERROR: \(error)"
            }
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
            self.writeWindowDiagnostics(to: path + ".window")
            self.runOutlineSelfTest(writingTo: path + ".outline")
        }
    }

    /// CI only: why can't the window grow taller? Dumps its size limits and constraints.
    private func writeWindowDiagnostics(to path: String) {
        guard let window, let split = splitController else { return }
        var out: [String] = []
        out.append("frame \(window.frame) min \(window.minSize) max \(window.maxSize)")
        out.append("contentMin \(window.contentMinSize) contentMax \(window.contentMaxSize)")
        out.append("split fitting \(split.view.fittingSize) frame \(split.view.frame)")
        out.append("container fitting \(container.fittingSize) constraints \(container.constraints.count)")
        for c in split.view.constraints { out.append("split constraint: \(c)") }
        for c in container.constraints { out.append("container constraint: \(c)") }
        if let side = sidebar?.view { out.append("sidebar fitting \(side.fittingSize)"); for c in side.constraints { out.append("sidebar constraint: \(c)") } }
        for target in [300.0, 450.0, 600.0] {
            var f = window.frame
            f.origin.y += f.height - target
            f.size.height = target
            window.setFrame(f, display: true)
            out.append("asked height \(target) -> got \(window.frame.height)")
        }
        try? out.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)

        switch url.scheme {
        case "http", "https", "mailto":
            NSWorkspace.shared.open(url)
        case "marginleaf":
            // A relative link to another note opens it in Marginleaf. Anything else is ignored.
            if let file = assets.fileURL(for: url),
               ["md", "markdown", "mdown"].contains(file.pathExtension.lowercased()),
               FileManager.default.fileExists(atPath: file.path) {
                NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { _, _, _ in }
            }
        default:
            break
        }
    }

    // MARK: Source

    private func ensureSourceLoaded() {
        guard sourceIsStale, let storage = textView.textStorage else { return }
        textView.string = markdownDoc?.text ?? ""
        highlighter.highlightAll(storage)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        sourceIsStale = false
        sourceHasPendingEdits = false
    }

    /// Copies what's been typed into the document model. Cheap when nothing changed.
    func commitEdits() {
        guard sourceHasPendingEdits else { return }
        markdownDoc?.text = textView.string
        sourceHasPendingEdits = false
    }

    func textDidChange(_ notification: Notification) {
        sourceHasPendingEdits = true
        textVersion += 1
        scheduleOutlineRefresh()
    }

    /// Right-click in the source: "Comment" first, when there is a selection.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        guard view.selectedRange().length > 0 else { return menu }
        let item = NSMenuItem(title: "Comment", action: #selector(commentFromContextMenu), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "plus.bubble", accessibilityDescription: nil)
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc private func commentFromContextMenu() { addComment() }

    /// Undo goes through the document so the title bar's edited dot stays right.
    func undoManager(for view: NSTextView) -> UndoManager? {
        markdownDoc?.undoManager
    }

    /// The file was re-read from disk (revert, or an outside change with no local edits).
    func documentDidReload() {
        textVersion += 1
        sourceIsStale = true
        refreshOutline()
        markdownDoc?.undoManager?.removeAllActions()
        switch mode {
        case .preview:
            webView.evaluateJavaScript(Self.previewFractionJS) { [weak self] result, _ in
                self?.renderPreview(restoring: result as? Double)
            }
        case .source:
            let fraction = sourceFraction()
            ensureSourceLoaded()
            comments.applySourceHighlights()
            DispatchQueue.main.async { [weak self] in self?.setSourceFraction(fraction) }
        }
    }

    private func sourceFraction() -> Double {
        let clip = scrollView.contentView
        let scrollable = max(1, textView.frame.height - clip.bounds.height)
        return Double(min(1, max(0, clip.bounds.origin.y / scrollable)))
    }

    private func setSourceFraction(_ fraction: Double) {
        let clip = scrollView.contentView
        let scrollable = max(0, textView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: CGFloat(fraction) * scrollable))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: Outline

    var isOutlineVisible: Bool { !(outlineItem?.isCollapsed ?? true) }

    /// Option+Cmd+O.
    func toggleOutline() {
        guard let item = outlineItem else { return }
        item.animator().isCollapsed = !item.isCollapsed
    }

    @objc private func toggleOutlineTapped() { toggleOutline() }

    /// What the note says right now, including edits not yet copied into the document.
    private var currentText: String {
        sourceHasPendingEdits ? textView.string : (markdownDoc?.text ?? "")
    }

    private func refreshOutline() {
        outlineRefresh?.cancel()
        guard isOutlineVisible else { return }
        outlinePanel.update(Outline.headings(in: currentText))
    }

    /// While typing, rebuild the outline once the typing pauses.
    private func scheduleOutlineRefresh() {
        guard isOutlineVisible else { return }
        outlineRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshOutline() }
        outlineRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// A click in the outline: scroll the visible view so the heading is at the top.
    private func goToHeading(_ item: OutlineItem) {
        switch mode {
        case .preview:
            webView.evaluateJavaScript(Self.scrollToHeadingJS(line: item.line, smooth: true), completionHandler: nil)
        case .source:
            scrollSource(toLine: item.line)
        }
    }

    /// Finds the heading the preview tagged with this source line (cmark's `data-sourcepos`).
    private static func scrollToHeadingJS(line: Int, smooth: Bool) -> String {
        """
        (function (line) {
          var hs = document.querySelectorAll('h1,h2,h3,h4,h5,h6'), el = null;
          for (var i = 0; i < hs.length; i++) {
            var sp = hs[i].getAttribute('data-sourcepos');
            if (sp && sp.indexOf(line + ':') === 0) { el = hs[i]; break; }
          }
          if (!el) return JSON.stringify({ found: false });
          var top = Math.max(0, el.getBoundingClientRect().top + window.scrollY - 24);
          window.scrollTo({ top: top, behavior: '\(smooth ? "smooth" : "auto")' });
          return JSON.stringify({ found: true, top: top, y: window.scrollY });
        })(\(line))
        """
    }

    private func scrollSource(toLine line: Int) {
        ensureSourceLoaded()
        let text = textView.string as NSString
        // Lines end at \n, \r\n or a lone \r, the same as cmark counts them.
        var index = 0
        var current = 1
        while current < line, index < text.length {
            let c = text.character(at: index)
            index += 1
            if c == 13 {
                if index < text.length, text.character(at: index) == 10 { index += 1 }
                current += 1
            } else if c == 10 {
                current += 1
            }
        }
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
        let glyphs = layout.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        let y = min(maxY, max(0, rect.minY + textView.textContainerOrigin.y - 16))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            clip.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
        }
        scrollView.reflectScrolledClipView(clip)
        textView.setSelectedRange(NSRange(location: index, length: 0))
        window?.makeFirstResponder(textView)
    }

    /// CI only: ask the preview to scroll to the last heading and report where it landed.
    private func runOutlineSelfTest(writingTo path: String) {
        guard let last = Outline.headings(in: markdownDoc?.text ?? "").last else {
            try? "no headings".write(toFile: path, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
            return
        }
        webView.evaluateJavaScript(Self.scrollToHeadingJS(line: last.line, smooth: false)) { result, error in
            let text = error.map { "ERROR: \($0)" } ?? "line \(last.line) -> \(result ?? "nil")"
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    // MARK: Zoom

    @objc private func applyZoom() {
        webView.pageZoom = Settings.zoom
        highlighter.baseSize = 13 * Settings.zoom
        textView.font = .monospacedSystemFont(ofSize: highlighter.baseSize, weight: .regular)
        if !sourceIsStale, let storage = textView.textStorage {
            highlighter.highlightAll(storage)
        }
    }
}
