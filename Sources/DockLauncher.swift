import Cocoa

@MainActor
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

    // Virtual key codes for number keys 1–9
    private static let numberKeyCodes: [Int64: Int] = [
        0x12: 1, 0x13: 2, 0x14: 3, 0x15: 4, 0x17: 5, 0x16: 6, 0x1A: 7, 0x1C: 8, 0x19: 9
    ]

    func handleKeyDown(event: CGEvent, finderPosition: Int) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard event.flags.contains(.maskAlternate),
              !event.flags.contains(.maskCommand),
              !event.flags.contains(.maskControl),
              !event.flags.contains(.maskShift),
              let number = Self.numberKeyCodes[keyCode]
        else { return false }
        let position = number == finderPosition ? 1 : (number < finderPosition ? number + 1 : number)
        launch(position: position)
        return true
    }

    func launch(position: Int) {
        guard let url = appURL(at: position) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}
