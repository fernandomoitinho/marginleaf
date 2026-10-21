import AppKit

extension Notification.Name {
    static let marginleafZoomChanged = Notification.Name("marginleafZoomChanged")
}

enum Settings {
    /// Whether comment highlights show in the preview. Remembered between launches.
    static var commentsVisible: Bool {
        get { UserDefaults.standard.object(forKey: "commentsVisible") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "commentsVisible") }
    }

    /// The explorer on the left: shown or hidden, and which folder it lists.
    static var sidebarVisible: Bool {
        get { UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sidebarVisible") }
    }

    static var sidebarRoot: URL? {
        get { UserDefaults.standard.string(forKey: "sidebarRoot").map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { UserDefaults.standard.set(newValue?.path, forKey: "sidebarRoot") }
    }

    private static let zoomKey = "zoom"
    static let zoomRange: ClosedRange<Double> = 0.6 ... 2.5

    /// Shared by the preview and the source view; remembered between launches.
    static var zoom: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: zoomKey)
            return stored == 0 ? 1 : min(zoomRange.upperBound, max(zoomRange.lowerBound, stored))
        }
        set {
            let clamped = min(zoomRange.upperBound, max(zoomRange.lowerBound, newValue))
            UserDefaults.standard.set(clamped, forKey: zoomKey)
            NotificationCenter.default.post(name: .marginleafZoomChanged, object: nil)
        }
    }
}

extension Settings {
    /// The outline (table of contents) on the right: shown or hidden. Off until asked for.
    static var outlineVisible: Bool {
        get { UserDefaults.standard.object(forKey: "outlineVisible") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "outlineVisible") }
    }
}
