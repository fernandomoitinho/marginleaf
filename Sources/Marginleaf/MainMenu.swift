import AppKit

/// The menu bar, built in code (no nib to load, which keeps launch quick).
enum MainMenu {
    static func install() {
        let main = NSMenu()
        main.addItem(wrap(appMenu()))
        main.addItem(wrap(fileMenu()))
        main.addItem(wrap(editMenu()))
        main.addItem(wrap(viewMenu()))
        let window = windowMenu()
        main.addItem(wrap(window))
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }

    // MARK: Helpers

    private static func wrap(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func item(_ title: String,
                             _ action: Selector?,
                             _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = [.command],
                             tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        item.tag = tag
        return item
    }

    // MARK: Menus

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Marginleaf")
        menu.addItem(item("About Marginleaf", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Hide Marginleaf", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Marginleaf", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))

        // AppKit fills this submenu with recent files because of the "Clear Menu" item.
        let recent = NSMenu(title: "Open Recent")
        recent.addItem(item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:))))
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        menu.addItem(recentItem)

        menu.addItem(item("Open Folder…", #selector(AppDelegate.openFolder(_:)), "o", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]))
        menu.addItem(item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())

        let finder = Selector(("performTextFinderAction:"))
        let find = NSMenu(title: "Find")
        find.addItem(item("Find…", finder, "f", tag: NSTextFinder.Action.showFindInterface.rawValue))
        find.addItem(item("Find and Replace…", #selector(AppDelegate.findAndReplace(_:)), "f", [.command, .option]))
        find.addItem(item("Find Next", finder, "g", tag: NSTextFinder.Action.nextMatch.rawValue))
        find.addItem(item("Find Previous", finder, "g", [.command, .shift], tag: NSTextFinder.Action.previousMatch.rawValue))
        find.addItem(.separator())
        find.addItem(item("Replace", finder, "", tag: NSTextFinder.Action.replace.rawValue))
        find.addItem(item("Replace and Find Next", finder, "", tag: NSTextFinder.Action.replaceAndFind.rawValue))
        find.addItem(item("Replace All", finder, "", tag: NSTextFinder.Action.replaceAll.rawValue))
        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findItem.submenu = find
        menu.addItem(findItem)
        menu.addItem(.separator())
        menu.addItem(item("Add Comment", #selector(AppDelegate.addComment(_:)), "m", [.command, .option]))
        menu.addItem(item("Copy All Comments", #selector(AppDelegate.copyComments(_:)), "c", [.command, .shift]))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Show Source", #selector(AppDelegate.toggleMode(_:)), "e"))
        menu.addItem(item("Toggle Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]))
        menu.addItem(item("Show Outline", #selector(AppDelegate.toggleOutline(_:)), "o", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Zoom In", #selector(AppDelegate.zoomIn(_:)), "="))
        menu.addItem(item("Zoom Out", #selector(AppDelegate.zoomOut(_:)), "-"))
        menu.addItem(item("Actual Size", #selector(AppDelegate.zoomReset(_:)), "0"))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
