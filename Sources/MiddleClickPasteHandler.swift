import Cocoa

@MainActor
class MiddleClickPasteHandler {
    /// Copy and paste key codes, named so the intent is not parked in a
    /// trailing comment (FinderCutHandler's convention).
    private static let keyC: Int64 = 0x08
    /// Used by the paste delivery extension in MiddleClickPasteWindow.swift.
    static let keyV: Int64 = 0x09
    private static let keyN: Int64 = 0x2D

    /// Bumped by `reset()`; in-flight chains capture it and abandon
    /// themselves when it moves, so a feature turned off (or an app excluded)
    /// mid-flow does not go on to raise windows and inject text.
    static var generation = 0

    /// The middle press is consumed when its click is replaced, so its
    /// release is consumed too — an `otherMouseUp` with no matching down is
    /// a phantom release for apps that act on button release.
    private var awaitingMiddleUp = false

    /// Returns true if the event was consumed.
    func handleMouseDown(event: CGEvent) -> Bool {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        guard buttonNumber == 2 else { return false }
        // A release that never arrived (mouse unplugged mid-press) must not
        // leak into the next middle click and eat its release.
        awaitingMiddleUp = false

        let (onDock, appURL) = dockAppInfo(at: event.location)
        if onDock {
            if let appURL { openNewWindow(of: appURL, generation: Self.generation) }
            awaitingMiddleUp = true
            return true
        }

        // Read the selection before anything clears it — the click that
        // follows moves focus. It stands in for X11's primary selection.
        let selection = Self.readSelection()
        let generation = Self.generation

        if let targetPid = textFieldPid(at: event.location) {
            // Taking the click over only makes sense where a normal window
            // can receive the replacement: over Mission Control's shield, an
            // open menu, or SuperOpt's own windows there is none.
            guard let target = Self.clickTarget(at: event.location) else { return false }

            var copyLatch: CopyLatch?
            if selection.chromiumSource {
                // The source's selection is invisible to AX (a Chromium
                // focus-only shell), so copy it now, while the source still
                // has focus; the ⌘V fallback then pastes the fresh copy.
                // Event order — copy, caret click, paste — is the queue's.
                copyLatch = Self.startCopyLatch(generation: generation)
            }
            // AppKit text views ignore middle clicks — the caret never moves —
            // so replace the click with a synthetic left one that places the
            // caret at the click point, the way X11 places it before inserting
            // the primary selection. The click waits for the target window to
            // be in front, raised first if needed, because a left click on an
            // inactive window is swallowed as a bare activation.
            let clickPoint = event.location
            DispatchQueue.main.async {
                let proceed = {
                    Self.clickWhenWindowIsFront(
                        at: clickPoint, expected: target, generation: generation
                    ) { clicked in
                        guard clicked else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            Self.insert(selection.text, into: targetPid, generation: generation)
                        }
                    }
                }
                if let copyLatch {
                    // The ⌘C races the target window's activation — losing
                    // delivers the copy keystroke to the wrong app — so the
                    // paste waits for the copy's latched outcome first.
                    copyLatch.awaitConcluded {
                        guard copyLatch.outcome != .landedElsewhere else { return }
                        proceed()
                    }
                } else {
                    proceed()
                }
            }
            awaitingMiddleUp = true
            return true
        }

        // A backgrounded Chromium app answers no focused-element query and
        // its editors hit-test as plain groups, so the click cannot be
        // classified yet. Let the real click through — it activates the
        // window, as stock macOS would — and re-check once the app under the
        // point has come forward.
        Self.scheduleDeferredPaste(at: event.location, selection: selection, generation: generation)
        return false
    }

    /// The unclassifiable-target branch of a middle click: the real click is
    /// let through to do the activating, and a deferred re-check runs once
    /// the app under the point has come forward.
    private static func scheduleDeferredPaste(
        at point: CGPoint, selection: (text: String?, chromiumSource: Bool), generation: Int
    ) {
        var copyLatch: CopyLatch?
        if selection.chromiumSource,
           // Only for a background window of the same app — the VS Code
           // window A → window B case. A cross-app target's activation races
           // the copy in a way the wait cannot attribute, and copy attempts
           // aimed at other apps' windows would clobber the clipboard on
           // clicks that never paste; those fall back to the clipboard.
           let source = NSWorkspace.shared.frontmostApplication,
           clickTarget(at: point)?.pid == source.processIdentifier {
            copyLatch = startCopyLatch(generation: generation)
        }
        deferredPaste(
            at: point,
            selection: selection.text,
            copyLatch: copyLatch,
            generation: generation)
    }

    /// Posts the ⌘C that fetches a Chromium source's invisible selection,
    /// snapshotting the pasteboard and the focus state the copy is
    /// attributed by, and starts the latch that watches for it to land.
    /// Must run while the source still has focus.
    private static func startCopyLatch(generation: Int) -> CopyLatch? {
        guard let source = NSWorkspace.shared.frontmostApplication else { return nil }
        let copySource = CopySource(
            pid: source.processIdentifier,
            windowID: KeyboardUtils.focusedWindowID(pid: source.processIdentifier))
        let pending = PendingCopy(
            before: NSPasteboard.general.changeCount, source: copySource)
        KeyboardUtils.postKey(keyC, flags: .maskCommand) // ⌘C
        return CopyLatch(pending: pending, generation: generation)
    }

    /// Returns true if the event was consumed.
    func handleMouseUp(event: CGEvent) -> Bool {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        guard buttonNumber == 2, awaitingMiddleUp else { return false }
        awaitingMiddleUp = false
        return true
    }

    /// Abandons any in-flight paste chain, e.g. when the feature is switched
    /// off. Unlike the click-through replay, a pending paste is new synthetic
    /// input rather than the user's own click restored, so it is dropped
    /// instead of completed. A middle press whose release is still pending
    /// lets that release through — one phantom up, the lesser evil next to a
    /// stale flag eating a release that belongs to a later click.
    func reset() {
        Self.generation += 1
        awaitingMiddleUp = false
    }

    // MARK: - Selection

    /// The X11 primary selection stand-in: the focused element's selected
    /// text, read before the click moves focus and clears it. Chromium
    /// editors expose a focus-only shell that reports no selected text even
    /// with a live selection, so `chromiumSource` flags that the selection —
    /// if any — can only be had by copying it.
    private static func readSelection() -> (text: String?, chromiumSource: Bool) {
        var element: AXUIElement?
        var ref: AnyObject?
        if AXUIElementCopyAttributeValue(
            KeyboardUtils.systemWide, kAXFocusedUIElementAttribute as CFString, &ref
        ) == .success, let focusedRef = ref,
            let focusedElement = KeyboardUtils.toAXElement(focusedRef) {
            element = focusedElement
        } else if let front = NSWorkspace.shared.frontmostApplication {
            // The system-wide query flakes on Chromium frontmost apps; ask
            // the frontmost app directly.
            element = focusedElement(of: front.processIdentifier)
        }
        guard let element else { return (nil, false) }
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &value) == .success,
            let text = value as? String, !text.isEmpty {
            return (text, false)
        }
        return (nil, isChromiumElement(element))
    }

    // MARK: - Hit testing

    private func textFieldPid(at pos: CGPoint) -> pid_t? {
        var axElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            KeyboardUtils.systemWide, Float(pos.x), Float(pos.y), &axElement
        ) == .success, let element = axElement else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != 0 else { return nil }

        // The AppKit shape: the text area sits in the AX tree under the
        // pointer. Chromium shape: the hit lands on plain groups and only
        // the app's focused editor can be asked for — gated on the engine
        // attribute at both the hit and the focused element, because AppKit
        // and Gecko expose real structure under the pointer, and a native
        // focused element's ancestors can span unrelated UI (a tab bar
        // sharing a container with the text view) that the bounds walk
        // would cover and classify as a paste target. WebKit answers the
        // attribute too, so Safari page content passes both gates — an
        // accepted residual.
        if Self.hasTextRole(element) { return pid }
        guard Self.isChromiumElement(element),
              let focused = Self.focusedTextElement(of: pid),
              Self.isChromiumElement(focused),
              Self.textElementCovers(focused, pos) else { return nil }
        return pid
    }

    /// Walks up from the hit-tested element looking for a text role — the
    /// AppKit shape, where the text area is in the AX tree under the pointer.
    private static func hasTextRole(_ element: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<5 {
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue)
            if let role = roleValue as? String, KeyboardUtils.textRoles.contains(role),
               !Self.isSecureTextField(current) { return true }
            var parentValue: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue)
            guard let parent = parentValue,
                  let parentElement = KeyboardUtils.toAXElement(parent)
            else { break }
            current = parentElement
        }
        return false
    }
}

// MARK: - Dock detection

extension MiddleClickPasteHandler {
    fileprivate func dockAppInfo(at pos: CGPoint) -> (onDock: Bool, appURL: URL?) {
        var axElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            KeyboardUtils.systemWide, Float(pos.x), Float(pos.y), &axElement
        ) == .success, let element = axElement else {
            return (false, nil)
        }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        guard let dockApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first, pid == dockApp.processIdentifier else {
            return (false, nil)
        }

        // Traverse up to find the dock item (click may land on a child element)
        var current = element
        for _ in 0..<5 {
            var subroleValue: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXSubroleAttribute as CFString, &subroleValue)
            if let subrole = subroleValue as? String, subrole == kAXApplicationDockItemSubrole {
                var urlValue: AnyObject?
                AXUIElementCopyAttributeValue(current, kAXURLAttribute as CFString, &urlValue)
                if let url = urlValue as? URL { return (true, url) }
                if let str = urlValue as? String { return (true, URL(string: str)) }
                return (true, nil)
            }
            var parentValue: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue)
            guard let parent = parentValue,
                  let parentElement = KeyboardUtils.toAXElement(parent)
            else { break }
            current = parentElement
        }
        return (true, nil)
    }
}

// MARK: - New window

extension MiddleClickPasteHandler {
    /// How long to keep waiting for a Dock-launched app to come forward before
    /// ⌘N is aimed at it. Named distinctly from the deferred paste's
    /// `activationTimeout` in MiddleClickPasteWindow.swift — extensions of
    /// this class move between the two files, and a bare reference would
    /// silently rebind to the other value.
    private static let dockActivationTimeout: TimeInterval = 1.0
    /// How long a reopened app is given to put up a window of its own.
    private static let reopenGrace: TimeInterval = 0.6

    func openNewWindow(of appURL: URL, generation: Int) {
        let bundleID = Bundle(url: appURL)?.bundleIdentifier
        let pid = bundleID.flatMap { id in
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == id }?.processIdentifier
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        guard let pid else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            return
        }

        // Activating an app with no windows left makes AppKit's reopen handling
        // open one, so a ⌘N on top of that is a second window.
        let hadWindows = Self.windowCount(pid: pid) > 0
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if hadWindows {
                    guard generation == MiddleClickPasteHandler.generation else { return }
                    AppActivation.wait(for: pid, timeout: Self.dockActivationTimeout) {
                        Self.postNewWindowIfFrontmost(pid: pid, generation: generation)
                    }
                } else {
                    Self.waitForReopenedWindow(pid: pid, generation: generation)
                }
            }
        }
    }

    private static func waitForReopenedWindow(pid: pid_t, generation: Int) {
        guard generation == MiddleClickPasteHandler.generation, windowCount(pid: pid) == 0 else { return }
        let observing = DockReopenObserver.start(pid: pid, wait: reopenGrace) {
            guard generation == MiddleClickPasteHandler.generation, windowCount(pid: pid) == 0 else { return }
            postNewWindowIfFrontmost(pid: pid, generation: generation)
        }
        if !observing {
            postNewWindowIfReopenDidNot(pid: pid, deadline: Date() + reopenGrace, generation: generation)
        }
    }

    /// An app that answers a reopen with a window of its own needs nothing
    /// further; one that ignores it still gets its ⌘N, just late.
    private static func postNewWindowIfReopenDidNot(
        pid: pid_t, deadline: Date, generation: Int
    ) {
        guard generation == MiddleClickPasteHandler.generation else { return }
        guard windowCount(pid: pid) == 0 else { return }
        guard Date() < deadline else {
            // The reopen path's last chance: a single look, not a wait.
            // Polling here would fire the ⌘N the moment a slow activation
            // lands — right before the reopen's own window appears — and
            // open a second one.
            return postNewWindowIfFrontmost(pid: pid, generation: generation)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            postNewWindowIfReopenDidNot(pid: pid, deadline: deadline, generation: generation)
        }
    }

    private static func postNewWindowIfFrontmost(pid: pid_t, generation: Int) {
        guard generation == MiddleClickPasteHandler.generation else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        KeyboardUtils.postKey(keyN, flags: .maskCommand) // ⌘N
    }

    /// The windows the app has, minimized and hidden ones included. Read through
    /// the accessibility API rather than `CGWindowListCopyWindowInfo`, which only
    /// lists what is on screen and would call a minimized window no window at all.
    /// The role check drops Finder's desktop, which is in the list as an
    /// `AXScrollArea`.
    private static func windowCount(pid: pid_t) -> Int {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value
        ) == .success, let windows = value as? [AXUIElement] else { return 0 }
        return windows.filter { window in
            var role: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role)
            return role as? String == kAXWindowRole
        }.count
    }
}
