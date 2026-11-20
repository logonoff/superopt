import Cocoa

// MARK: - Window enumeration
// Split out of SnapAssistPanel.swift to stay under the SwiftLint file-length
// limit.

extension SnapAssistPanel {
    static func collectWindows(screen: NSScreen, excludeWID: UInt32) -> [SnapWindowItem] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let screenFrame = screen.frame
        let primaryHeight = KeyboardUtils.primaryScreenHeight()
        var result: [SnapWindowItem] = []
        var seenWIDs: Set<UInt32> = []

        for info in windowList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != myPID, wid != excludeWID, !seenWIDs.contains(wid),
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let originX = bounds["X"], let originY = bounds["Y"],
                  let winWidth = bounds["Width"], let winHeight = bounds["Height"],
                  winWidth > 100, winHeight > 100
            else { continue }

            let center = NSPoint(
                x: originX + winWidth / 2, y: primaryHeight - (originY + winHeight / 2))
            guard screenFrame.contains(center) else { continue }

            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            let appName = app.localizedName ?? ""
            let windowTitle = axWindowTitle(pid: pid, windowID: wid)
                ?? info[kCGWindowName as String] as? String ?? ""
            guard !appName.isEmpty || !windowTitle.isEmpty else { continue }

            seenWIDs.insert(wid)
            let icon = app.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
            result.append(SnapWindowItem(
                pid: pid, windowID: wid, title: windowTitle, appName: appName, icon: icon))
        }
        return result
    }

    private static func axWindowTitle(pid: pid_t, windowID: UInt32) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref)
        guard let windows = ref as? [AXUIElement],
              let getWindow = KeyboardUtils.axGetWindow else { return nil }
        for win in windows {
            var axWID: UInt32 = 0
            guard getWindow(win, &axWID) == 0, axWID == windowID else { continue }
            var titleRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
            return titleRef as? String
        }
        return nil
    }
}
