import AppKit
import MarginleafCore

/// One row of the outline: the heading, indented by how deep it sits.
private final class OutlineCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private var leading: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        textField = label
        leading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        NSLayoutConstraint.activate([
            leading,
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(title: String, depth: Int) {
        label.stringValue = title
        label.toolTip = title
        leading.constant = 8 + CGFloat(min(depth, 5)) * 12
        label.font = .systemFont(ofSize: depth == 0 ? 12.5 : 12, weight: depth == 0 ? .semibold : .regular)
        label.textColor = depth <= 1 ? .labelColor : .secondaryLabelColor
    }
}

/// The table of contents on the right of the note. Click a heading to jump to it.
final class OutlineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "No headings in this note")
    private var items: [OutlineItem] = []
    private var baseLevel = 1

    var onSelect: ((OutlineItem) -> Void)?
    var onClose: (() -> Void)?

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow

        let title = NSTextField(labelWithString: "Outline")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Hide outline") ?? NSImage(),
                             target: self, action: #selector(closeTapped))
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.toolTip = "Hide the outline (Option+Cmd+O)"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [title, spacer, close])
        header.orientation = .horizontal
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)
        header.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("heading"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.style = .sourceList
        table.rowSizeStyle = .default
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(header)
        background.addSubview(scroll)
        background.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: background.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 22),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: background.leadingAnchor, constant: 12),
            background.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])
        view = background
        emptyLabel.isHidden = !items.isEmpty
    }

    func update(_ newItems: [OutlineItem]) {
        guard newItems != items else { return }
        items = newItems
        baseLevel = newItems.map(\.level).min() ?? 1
        if isViewLoaded {
            table.reloadData()
            emptyLabel.isHidden = !items.isEmpty
        }
    }

    @objc private func closeTapped() { onClose?() }

    @objc private func rowClicked() {
        let row = table.clickedRow
        guard row >= 0, row < items.count else { return }
        onSelect?(items[row])
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("outlineCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? OutlineCell) ?? {
            let made = OutlineCell(frame: .zero)
            made.identifier = id
            return made
        }()
        let item = items[row]
        cell.configure(title: item.title, depth: item.level - baseLevel)
        return cell
    }
}
