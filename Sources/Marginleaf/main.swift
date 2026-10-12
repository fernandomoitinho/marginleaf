import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

// Registers the document types from Info.plist before the first open event arrives.
_ = NSDocumentController.shared

MainMenu.install()
app.run()
