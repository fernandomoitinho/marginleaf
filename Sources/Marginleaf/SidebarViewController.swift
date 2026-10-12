import AppKit

extension Notification.Name {
    static let marginleafSidebarRootChanged = Notification.Name("marginleafSidebarRootChanged")
}

/// One folder or Markdown file in the sidebar. Children are read from disk only when the
/// folder is first opened, so a big tree costs nothing until you look inside it.
final class FileNode: NSObject {
    let url: URL
    let isDirectory: Bool
    private(set) var children: [FileNode]?

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    var name: String { url.lastPathComponent }

    static let noteExtensions: Set<String> = ["md", "markdown", "mdown"]

    func ensureLoaded() {
        if children == nil { reload() }
    }

    /// Re-reads this folder, keeping the node objects that are still there (so expanded
    /// folders stay expanded), then does the same for folders that were already loaded.
    func reload() {
        guard isDirectory else { return }
        let existing = Dictionary(uniqueKeysWithValues: (children ?? []).map { ($0.url, $0) })
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []

        var nodes: [FileNode] = []
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: Set(keys)))?.isDirectory ?? false
            if !isDir && !Self.noteExtensions.contains(entry.pathExtension.lowercased()) { continue }
            if isDir && entry.lastPathComponent == "node_modules" { continue }
            nodes.append(existing[entry] ?? FileNode(url: entry, isDirectory: isDir))
        }
        nodes.sort {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        children = nodes
        for node in nodes where node.isDirectory && node.children != nil { node.reload() }
    }
}

/// The file explorer on the left: the Markdown files of one folder, like a vault.
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let onOpen: (URL) -> Void
    private let currentFile: URL?
    private let outline = NSOutlineView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var root: FileNode?
    private var suppressSelection = false
    /// True once the user picked or navigated to a folder in this window; then it stays put.
    private var keepChosenRoot = false

    init(currentFile: URL?, onOpen: @escaping (URL) -> Void) {
        self.currentFile = currentFile
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Folder choice

    static func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        if let saved = Settings.sidebarRoot { panel.directoryURL = saved }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Settings.sidebarRoot = url
        NotificationCenter.default.post(name: .marginleafSidebarRootChanged, object: nil)
    }

    /// Keep the chosen folder while the note lives inside it; otherwise follow the note.
    private func resolveRoot() -> URL? {
        if keepChosenRoot { return Settings.sidebarRoot }
        if let saved = Settings.sidebarRoot, FileManager.default.fileExists(atPath: saved.path),
           currentFile == nil || currentFile!.path.hasPrefix(saved.path + "/") {
            return saved
        }
        if let folder = currentFile?.deletingLastPathComponent() {
            Settings.sidebarRoot = folder
            return folder
        }
        return Settings.sidebarRoot
    }

    // MARK: View

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let choose = NSButton(image: NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Open folder") ?? NSImage(),
                              target: self, action: #selector(chooseTapped))
        choose.isBordered = false
        choose.contentTintColor = .secondaryLabelColor
        choose.toolTip = "Open a different folder (Shift+Cmd+O)"

        let up = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Parent folder") ?? NSImage(),
                          target: self, action: #selector(goUp))
        up.isBordered = false
        up.contentTintColor = .secondaryLabelColor
        up.toolTip = "Go to the parent folder"

        let header = NSStackView(views: [up, titleLabel, choose])
        header.orientation = .horizontal
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        header.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.backgroundColor = .clear
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.indentationPerLevel = 14
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked)

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(header)
        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: background.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 22),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            background.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])
        view = background

        NotificationCenter.default.addObserver(self, selector: #selector(rootChanged),
                                               name: .marginleafSidebarRootChanged, object: nil)
        reloadRoot()
    }

    @objc private func chooseTapped() { Self.chooseFolder() }
    @objc private func rootChanged() {
        keepChosenRoot = true
        reloadRoot()
    }

    /// Back out of the current folder to the one above it.
    @objc private func goUp() {
        guard let current = root?.url else { return }
        let parent = current.deletingLastPathComponent()
        guard parent.path != current.path else { return }
        Settings.sidebarRoot = parent
        NotificationCenter.default.post(name: .marginleafSidebarRootChanged, object: nil)
    }

    /// Double-click a folder to make it the top of the tree.
    @objc private func doubleClicked() {
        guard outline.clickedRow >= 0, let node = outline.item(atRow: outline.clickedRow) as? FileNode,
              node.isDirectory else { return }
        Settings.sidebarRoot = node.url
        NotificationCenter.default.post(name: .marginleafSidebarRootChanged, object: nil)
    }

    // MARK: Data

    private func reloadRoot() {
        guard let url = resolveRoot() else {
            root = nil
            titleLabel.stringValue = "No folder"
            outline.reloadData()
            return
        }
        let node = FileNode(url: url, isDirectory: true)
        node.reload()
        root = node
        titleLabel.stringValue = url.lastPathComponent
        outline.reloadData()
        revealCurrentFile()
    }

    /// Picks up files added or removed outside Marginleaf. Called when the window comes forward.
    func refresh() {
        guard let root else { return }
        root.reload()
        suppressSelection = true
        outline.reloadData()
        suppressSelection = false
        revealCurrentFile()
    }

    private func revealCurrentFile() {
        guard let file = currentFile, let root, file.path.hasPrefix(root.url.path + "/") else { return }
        let relative = String(file.path.dropFirst(root.url.path.count + 1)).split(separator: "/").map(String.init)
        var node = root
        for part in relative {
            node.ensureLoaded()
            guard let next = node.children?.first(where: { $0.name == part }) else { return }
            if next.isDirectory { outline.expandItem(next) }
            node = next
        }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        suppressSelection = true
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
        suppressSelection = false
    }

    // MARK: Outline

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let node = (item as? FileNode) ?? root
        node?.ensureLoaded()
        return node?.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let node = (item as? FileNode) ?? root!
        node.ensureLoaded()
        return node.children![index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? makeCell(id)
        cell.textField?.stringValue = node.name
        let symbol = node.isDirectory ? "folder" : "doc.text"
        cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        cell.imageView?.contentTintColor = node.isDirectory ? .systemBlue : .secondaryLabelColor
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let icon = NSImageView()
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)
        cell.addSubview(label)
        cell.imageView = icon
        cell.textField = label
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection else { return }
        let row = outline.selectedRow
        guard row >= 0, let node = outline.item(atRow: row) as? FileNode else { return }
        if node.isDirectory {
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        } else {
            onOpen(node.url)
        }
    }
}
