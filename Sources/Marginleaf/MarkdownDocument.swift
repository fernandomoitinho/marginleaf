import AppKit
import MarginleafCore

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    /// The text as last pushed from the source view (see `syncFromViews`).
    var text = ""
    private var usesCRLF = false
    private var hasBOM = false
    private var isAskingAboutExternalChange = false

    // Cmd+S saves, the title shows the edited dot. No versions browser, no silent autosave.
    override class var autosavesInPlace: Bool { false }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    // Write on a background thread so a slow disk (cloud or network folder) never freezes the window.
    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String,
                                         for saveOperation: NSDocument.SaveOperationType) -> Bool { true }

    private var controller: DocumentWindowController? {
        windowControllers.compactMap { $0 as? DocumentWindowController }.first
    }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    // MARK: Reading and writing

    override func read(from data: Data, ofType typeName: String) throws {
        guard let decoded = TextCodec.decode(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding, userInfo: [
                NSLocalizedDescriptionKey:
                    "This file isn't UTF-8 text. Marginleaf won't open it, because saving could change its contents.",
            ])
        }
        text = decoded.text
        usesCRLF = decoded.usesCRLF
        hasBOM = decoded.hasBOM
        // Also runs on revert; on the first open there is no window yet.
        controller?.documentDidReload()
    }

    /// What gets written. Captured on the main thread when a save starts, because the write
    /// itself may run on a background thread while the user keeps typing.
    private var snapshot: (text: String, crlf: Bool, bom: Bool)?
    private let snapshotLock = NSLock()

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        syncFromViews()
        snapshotLock.lock()
        snapshot = (text, usesCRLF, hasBOM)
        snapshotLock.unlock()
        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }

    override func data(ofType typeName: String) throws -> Data {
        snapshotLock.lock()
        let snap = snapshot
        snapshotLock.unlock()
        if let snap { return TextCodec.encode(snap.text, usesCRLF: snap.crlf, hasBOM: snap.bom) }
        syncFromViews()
        return TextCodec.encode(text, usesCRLF: usesCRLF, hasBOM: hasBOM)
    }

    /// Pulls pending keystrokes out of the source view into `text`.
    func syncFromViews() {
        controller?.commitEdits()
    }

    // MARK: Changes made outside Marginleaf (git, Obsidian, an agent...)

    override func presentedItemDidChange() {
        super.presentedItemDidChange()
        DispatchQueue.main.async { [weak self] in self?.handleExternalChange() }
    }

    private func handleExternalChange() {
        guard let url = fileURL, let known = fileModificationDate else { return }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let onDisk = (try? url.resourceValues(forKeys: keys))?.contentModificationDate,
              onDisk > known,
              let data = try? Data(contentsOf: url),
              let decoded = TextCodec.decode(data)
        else { return }

        syncFromViews()
        // Our own save, or a touch with no content change.
        if decoded.text == text {
            fileModificationDate = onDisk
            return
        }

        if !isDocumentEdited {
            try? revert(toContentsOf: url, ofType: fileType ?? "net.daringfireball.markdown")
            return
        }
        askAboutExternalChange(onDisk: onDisk, url: url)
    }

    private func askAboutExternalChange(onDisk: Date, url: URL) {
        guard !isAskingAboutExternalChange else { return }
        isAskingAboutExternalChange = true

        let alert = NSAlert()
        alert.messageText = "“\(displayName ?? "This file")” changed on disk."
        alert.informativeText = "It was edited somewhere else, and you have unsaved changes here."
        alert.addButton(withTitle: "Keep mine")
        alert.addButton(withTitle: "Reload from disk")

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isAskingAboutExternalChange = false
            if response == .alertSecondButtonReturn {
                try? self.revert(toContentsOf: url, ofType: self.fileType ?? "net.daringfireball.markdown")
            } else {
                // Stop asking about this version of the file; saving will overwrite it.
                self.fileModificationDate = onDisk
            }
        }
        if let window = controller?.window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}
