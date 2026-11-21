import Cocoa

/// The apps SuperOpt stays out of. While one of them is the active app, every feature
/// is turned off and the menu bar icon dims, so that app behaves as it would with
/// SuperOpt not running at all.
///
/// The active app is read once per activation rather than once per event: the event tap
/// sees a mouse move for every pointer position, and this answer only changes when the
/// user switches apps.
@MainActor
final class ExcludedApps {
    static let enabledKey = "excludedAppsEnabled"
    /// Nonisolated so the settings pane's KVO observer can remove itself in
    /// deinit (nonisolated by definition) — the same reason
    /// GnomeShortcutSettings.defaultsKey is nonisolated.
    nonisolated static let listKey = "excludedAppIDs"

    /// True while the active app is one of the listed ones.
    private(set) var isSuspended = false

    /// Called when `isSuspended` changes.
    var onChange: (() -> Void)?

    private var observer: NSObjectProtocol?
    private var activeBundleID: String?

    /// The bundle identifiers on the list, in the order the user added them.
    static func bundleIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: listKey) ?? []
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            // The app the notification names, not the one `frontmostApplication`
            // answers with: that query still returns the outgoing app when the
            // notification is delivered during a click-through focus change, which
            // puts every feature on in the excluded app and off everywhere else.
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self else { return }
                self.activeBundleID = activated?.bundleIdentifier
                    ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                self.reload()
            }
        }
        activeBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        reload()
    }

    /// Re-reads the list and the toggle, for when either changes while the app it names
    /// is the active one.
    func reload() {
        let suspended = listIncludesActiveApp()
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        onChange?()
    }

    private func listIncludesActiveApp() -> Bool {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey),
              let activeBundleID
        else { return false }
        return Self.bundleIDs().contains(activeBundleID)
    }
}
