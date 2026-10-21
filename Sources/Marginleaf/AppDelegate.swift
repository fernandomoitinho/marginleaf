import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    // A reader opens a file, not a blank page. Cmd+N still makes a new note.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    // Not automatic: the Open panel is a window too, so closing it after a pick would quit the
    // app before the document window appears. We quit ourselves when a note window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func quitWhenLastNoteCloses() {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard (note.object as? NSWindow)?.windowController is DocumentWindowController else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let panelOpen = NSApp.windows.contains { $0 is NSOpenPanel && $0.isVisible }
                if NSDocumentController.shared.documents.isEmpty && !panelOpen {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitWhenLastNoteCloses()
        // Option+Cmd+M, as in Google Docs. The system also uses it (Minimize All), so catch it first.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command, .option], event.keyCode == 46, let controller = self?.currentController {
                controller.addComment()
                return nil
            }
            return event
        }
        // Launched from Finder with a file, the document exists by now. Launched bare, ask for one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.openDocument(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSDocumentController.shared.openDocument(nil) }
        return false
    }

    // MARK: Menu actions (routed here so they work whatever has focus)

    private var currentController: DocumentWindowController? {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.windowController as? DocumentWindowController
    }

    @objc func toggleMode(_ sender: Any?) {
        currentController?.toggleMode()
    }

    @objc func findAndReplace(_ sender: Any?) {
        currentController?.showFindAndReplace()
    }

    @objc func openFolder(_ sender: Any?) { SidebarViewController.chooseFolder() }

    @objc func addComment(_ sender: Any?) { currentController?.addComment() }
    @objc func copyComments(_ sender: Any?) { currentController?.copyComments() }

    @objc func toggleOutline(_ sender: Any?) { currentController?.toggleOutline() }

    @objc func zoomIn(_ sender: Any?) { Settings.zoom += 0.1 }
    @objc func zoomOut(_ sender: Any?) { Settings.zoom -= 0.1 }
    @objc func zoomReset(_ sender: Any?) { Settings.zoom = 1 }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleMode(_:)):
            guard let controller = currentController else {
                item.title = "Show Source"
                return false
            }
            item.title = controller.isShowingSource ? "Show Preview" : "Show Source"
            return true
        case #selector(toggleOutline(_:)):
            guard let controller = currentController else {
                item.title = "Show Outline"
                return false
            }
            item.title = controller.isOutlineVisible ? "Hide Outline" : "Show Outline"
            return true
        case #selector(addComment(_:)):
            return currentController?.canAddComment ?? false
        case #selector(copyComments(_:)):
            return currentController?.hasComments ?? false
        case #selector(findAndReplace(_:)):
            return currentController != nil
        case #selector(zoomIn(_:)):
            return Settings.zoom < Settings.zoomRange.upperBound - 0.001
        case #selector(zoomOut(_:)):
            return Settings.zoom > Settings.zoomRange.lowerBound + 0.001
        default:
            return true
        }
    }
}
