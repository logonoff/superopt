import Cocoa

// MARK: - Chromium focused-editor detection
// Split out of MiddleClickPasteWindow.swift to stay under the SwiftLint
// file-length limit. Chromium editors are invisible to the AX hit test and
// answer no focused-element query until opted in, so reaching them takes a
// small toolbox of its own.

extension MiddleClickPasteHandler {
    /// The app's focused element of any role, opting Chromium apps into
    /// accessibility on the way — they answer no focused-element query until
    /// asked.
    static func focusedElement(of pid: pid_t) -> AXUIElement? {
        guard pid != 0 else { return nil }
        var focusedRef: AnyObject?
        var result = AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &focusedRef)
        if result != .success {
            enableAccessibility(for: pid)
            result = AXUIElementCopyAttributeValue(
                AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &focusedRef)
        }
        guard result == .success, let ref = focusedRef,
            let focused = KeyboardUtils.toAXElement(ref) else { return nil }
        return focused
    }

    /// Chromium editors hit-test as plain `AXGroup`s, but their app still
    /// reports the focused editor as an `AXTextArea` once its accessibility
    /// tree exists. Used to reach editors that never expose a text role
    /// under the pointer.
    static func focusedTextElement(of pid: pid_t) -> AXUIElement? {
        guard let focused = focusedElement(of: pid) else { return nil }
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleValue)
        guard let role = roleValue as? String, KeyboardUtils.textRoles.contains(role),
            !isSecureTextField(focused) else { return nil }
        return focused
    }

    /// Password fields report a plain text role with the `AXSecureTextField`
    /// subrole. They are not paste targets: pasting into one is unwanted, and
    /// a masked selection is nothing to be reading out.
    static func isSecureTextField(_ element: AXUIElement) -> Bool {
        var subroleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        return (subroleRef as? String) == kAXSecureTextFieldSubrole
    }

    /// Whether an element belongs to a Chromium app: only Chromium answers
    /// the private `AXDOMClassList` attribute — the same discriminator
    /// `ElectronTerminalDetector` uses for the integrated terminal. No public
    /// AX attribute identifies a Chromium element, so this is the only
    /// discriminator; AppKit elements answer `-25205`.
    static func isChromiumElement(_ element: AXUIElement) -> Bool {
        var classListRef: AnyObject?
        return AXUIElementCopyAttributeValue(
            element, "AXDOMClassList" as CFString, &classListRef) == .success
    }

    /// Whether the point sits on the focused text element or the part of the
    /// page it belongs to. Chromium reports the focused editor's own frame as
    /// just the current line, so the check walks the parent chain — the
    /// ancestors cover the editor viewport. The role is checked before the
    /// frame each step: the walk stops at the window, whose frame would
    /// cover the sidebar and tabs as well, and at the web area, whose frame
    /// in a browser covers the whole page and would classify any click in
    /// it as a paste target — ancestor frames are nested supersets, so a
    /// containment check run first would match before the stop is reached.
    static func textElementCovers(_ element: AXUIElement, _ point: CGPoint) -> Bool {
        var current = element
        for _ in 0..<5 {
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String
            if role == kAXWindowRole || role == "AXWebArea" { return false }
            if KeyboardUtils.axWindowFrame(current).contains(point) { return true }
            var parentRef: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef)
            guard let parent = parentRef,
                  let parentElement = KeyboardUtils.toAXElement(parent)
            else { break }
            current = parentElement
        }
        return false
    }

    /// Only ever touched from the CGEvent tap callback, its timers, and the
    /// app-termination observer — all on the main run loop. Matches
    /// ElectronTerminalDetector's pattern.
    nonisolated(unsafe) private static var accessibilityEnabledPIDs: Set<pid_t> = []
    nonisolated(unsafe) private static var pidCleanupInstalled = false

    /// Chromium apps build no accessibility tree until an assistive client
    /// asks for one, so the focused element query fails and their editors
    /// are invisible to the paste. `AXManualAccessibility` is Chromium's
    /// opt-in for that — the same switch a screen reader would flip, and the
    /// one ElectronTerminalDetector uses. Set once per process: the
    /// attribute reads back as `0` even once it has taken effect, so whether
    /// it is on has to be tracked here rather than queried. Pids are
    /// recycled, so entries are dropped when their process terminates.
    private static func enableAccessibility(for pid: pid_t) {
        installPidCleanupIfNeeded()
        guard !accessibilityEnabledPIDs.contains(pid) else { return }
        // Recorded only when there is no point trying again: on success, and
        // when the app does not implement the attribute at all (Chrome never
        // has). Anything else — the app mid-launch, an AX timeout against a
        // backgrounded window — is transient and must be retried on the next
        // query, or the app's editors stay invisible to the paste for as
        // long as it lives.
        let result = AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(pid),
            "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if result == .success || result == .attributeUnsupported {
            accessibilityEnabledPIDs.insert(pid)
        }
    }

    /// Without this, a Chromium app later handed a recycled pid would be
    /// skipped forever and its editors would stay invisible to the paste.
    private static func installPidCleanupIfNeeded() {
        guard !pidCleanupInstalled else { return }
        pidCleanupInstalled = true
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
                accessibilityEnabledPIDs.remove(app.processIdentifier)
            }
        }
    }
}
