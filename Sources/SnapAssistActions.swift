import Cocoa

// MARK: - Actions

extension SnapAssistPanel {
    /// Bumped when Tile Assist is turned off or suspended: an arrange press
    /// still waiting on its app to activate is synthetic input in flight —
    /// the same category as the middle-click paste — and is abandoned rather
    /// than delivered while the feature is contractually off.
    static func cancelPendingTileActions() { tileActionGeneration &+= 1 }
    private static var tileActionGeneration = 0

    @objc func itemClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0, index < items.count else { return }
        tileWindow(items[index])
        dismiss()
    }

    private func tileWindow(_ item: SnapWindowItem) {
        onWillTile?()
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        KeyboardUtils.raiseWindow(pid: item.pid, windowID: item.windowID)
        app.activate()
        let arrangeKey: Int64 = direction == .left ? 0x7C : 0x7B
        let generation = Self.tileActionGeneration
        AppActivation.wait(for: item.pid, timeout: 1) { [suppress = onWillTile] in
            guard Self.tileActionGeneration == generation else { return }
            KeyboardUtils.raiseWindow(pid: item.pid, windowID: item.windowID)
            // The activation wait can outlast the suppress window taken when
            // the item was clicked, and a menu press that re-tiles a window
            // would read back as a fresh tile and reopen this panel behind
            // it — retake the suppression before pressing.
            suppress?()
            _ = KeyboardUtils.pressArrangeMenuItem(pid: item.pid, virtualKey: arrangeKey)
        }
    }
}
