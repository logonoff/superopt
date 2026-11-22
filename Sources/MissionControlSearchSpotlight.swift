import Cocoa

// MARK: - Spotlight readiness

/// Split out of `MissionControlSearchHandler.swift` to stay under the
/// SwiftLint file-length limit.
extension MissionControlSearchHandler {
    /// On macOS 27 the Spotlight UI lives in Siri AI.app.
    private static let spotlightBundleID = "com.apple.campo"

    /// True once Spotlight is both on screen and focused on its search field.
    ///
    /// The window alone is not enough: Siri AI keeps its panel window around after
    /// Spotlight is dismissed, hidden by dropping its alpha to 0 rather than by
    /// ordering it out, so a plain on-screen check matches a closed Spotlight too.
    /// The focused field alone is not enough either, because that field stays focused
    /// after dismissal.
    func isSpotlightReady() -> Bool { spotlightField() != nil }

    /// True once the injected text has shown up in Spotlight's field. Only emptiness
    /// is checked, not the exact contents: Spotlight is empty when it opens, so
    /// anything at all means the text landed, and matching exactly would be brittle
    /// if Spotlight ever completed or reformatted the query.
    func spotlightFieldIsPopulated() -> Bool {
        !(spotlightFieldValue() ?? "").isEmpty
    }

    /// Spotlight's field text, or nil when it cannot be read. After the first
    /// chunk, only the change between two reads is ever interpreted, so a
    /// completion rewriting the query reads the same as (and is as good as)
    /// the injected text landing.
    func spotlightFieldValue() -> String? {
        guard let field = spotlightField() else { return nil }
        var value: AnyObject?
        AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value)
        return value as? String
    }

    /// Spotlight's focused search field, or nil if Spotlight is not up and ready.
    private func spotlightField() -> AXUIElement? {
        guard let pid = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.spotlightBundleID).first?.processIdentifier,
            spotlightWindowVisible(pid: pid),
            let (field, fieldPID) = focusedTextField(), fieldPID == pid
        else { return nil }
        return field
    }

    private func spotlightWindowVisible(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return list.contains { info in
            info[kCGWindowOwnerPID as String] as? pid_t == pid
                && (info[kCGWindowLayer as String] as? Int ?? 0) > 0
                && (info[kCGWindowAlpha as String] as? Double ?? 0) > 0
        }
    }

    private func focusedTextField() -> (AXUIElement, pid_t)? {
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            KeyboardUtils.systemWide, kAXFocusedUIElementAttribute as CFString,
            &focused) == .success,
            let element = focused.flatMap(KeyboardUtils.toAXElement)
        else { return nil }

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, "AXSearchField"]
        guard let role = roleRef as? String, textRoles.contains(role) else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return (element, pid)
    }
}
