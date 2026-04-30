import Cocoa

// MARK: - Actions

extension SnapAssistPanel {
    @objc func itemClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0, index < items.count else { return }
        tileWindow(items[index])
        dismiss()
    }

    private func tileWindow(_ item: SnapWindowItem) {
        onWillTile?()
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        let axApp = AXUIElementCreateApplication(item.pid)
        if let axWin = KeyboardUtils.findAXWindow(pid: item.pid, windowID: item.windowID) {
            AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(
                axApp, kAXFocusedWindowAttribute as CFString, axWin)
        }
        app.activate()
        let arrangeKey: Int64 = direction == .left ? 0x7C : 0x7B
        Self.waitForActivation(pid: item.pid, arrangeKey: arrangeKey)
    }

    private static func waitForActivation(pid: pid_t, arrangeKey: Int64, attempts: Int = 0) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid || attempts >= 10 {
            _ = KeyboardUtils.pressArrangeMenuItem(pid: pid, virtualKey: arrangeKey)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            waitForActivation(pid: pid, arrangeKey: arrangeKey, attempts: attempts + 1)
        }
    }
}
