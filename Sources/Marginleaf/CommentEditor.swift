import AppKit

/// Text view that commits on Cmd+Return (and Enter on the keypad), like Google Docs.
private final class CommentTextView: NSTextView {
    var onCommit: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           event.keyCode == 36 || event.keyCode == 76 {
            onCommit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The small popover for writing, editing or deleting one comment.
final class CommentEditor: NSViewController {
    private let quote: String
    private let initialBody: String
    private let canDelete: Bool
    private let onSave: (String) -> Void
    private let onDelete: () -> Void
    private let onCancel: () -> Void
    private var textView: NSTextView!
    private var commentView: CommentTextView { textView as! CommentTextView }

    init(quote: String, body: String, canDelete: Bool,
         onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.quote = quote
        self.initialBody = body
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let shown = quote.count > 240 ? String(quote.prefix(240)) + "…" : quote
        let quoteLabel = NSTextField(wrappingLabelWithString: "“\(shown)”")
        quoteLabel.font = .systemFont(ofSize: 11)
        quoteLabel.textColor = .secondaryLabelColor
        quoteLabel.maximumNumberOfLines = 3
        quoteLabel.lineBreakMode = .byTruncatingTail

        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let field = CommentTextView(frame: NSRect(x: 0, y: 0, width: 336, height: 96))
        field.minSize = NSSize(width: 0, height: 96)
        field.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        field.isVerticallyResizable = true
        field.autoresizingMask = .width
        field.textContainer?.widthTracksTextView = true
        field.textContainerInset = NSSize(width: 4, height: 4)
        field.onCommit = { [weak self] in self?.saveTapped() }
        scroll.documentView = field
        textView = field
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.string = initialBody
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        scroll.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        save.keyEquivalent = "\r"
        save.keyEquivalentModifierMask = .command
        save.bezelStyle = .rounded
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        if canDelete {
            let delete = NSButton(title: "Delete", target: self, action: #selector(deleteTapped))
            delete.bezelStyle = .rounded
            delete.contentTintColor = .systemRed
            buttons.addArrangedSubview(delete)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(save)

        let stack = NSStackView(views: [quoteLabel, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [quoteLabel, scroll, buttons] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 360),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
        ])
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }

    @objc private func saveTapped() {
        let body = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { NSSound.beep(); return }
        onSave(body)
    }

    @objc private func cancelTapped() { onCancel() }
    @objc private func deleteTapped() { onDelete() }
}
