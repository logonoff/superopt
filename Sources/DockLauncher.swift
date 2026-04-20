import Cocoa

class DockLauncher {
    /// Returns the Nth app in the dock (1-indexed). Position 1 is always Finder.
    func appURL(at position: Int) -> URL? {
        guard position >= 1 else { return nil }

        if position == 1 {
            return URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        }

        guard let plistPath = NSHomeDirectory().appending("/Library/Preferences/com.apple.dock.plist") as String?,
              let plistData = NSDictionary(contentsOfFile: plistPath),
              let apps = plistData["persistent-apps"] as? [[String: Any]] else {
            return nil
        }

        let index = position - 2 // offset for Finder at position 1
        guard index < apps.count else { return nil }

        guard let tileData = apps[index]["tile-data"] as? [String: Any],
              let fileData = tileData["file-data"] as? [String: Any],
              let urlString = fileData["_CFURLString"] as? String else {
            return nil
        }

        return URL(string: urlString) ?? URL(fileURLWithPath: urlString)
    }

    func launch(position: Int) {
        guard let url = appURL(at: position) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}
