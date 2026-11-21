import Cocoa

// MARK: - Window focus and paste delivery
// Split out of MiddleClickPasteHandler.swift to stay under the SwiftLint
// file-length limit, the way KeyboardUtilsMenus.swift extends KeyboardUtils.

extension MiddleClickPasteHandler {
    /// Types the selection at the caret, or falls back to a clipboard paste.
    /// Posted keys and text deliver to whichever app is frontmost, so the
    /// target has to still be it — and its focused element is re-checked
    /// through the app-level query, because the system-wide one flakes on
    /// Chromium — before anything is typed.
    static func insert(_ selection: String?, into pid: pid_t, generation: Int) {
        guard generation == MiddleClickPasteHandler.generation else { return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        let focusedEl = focusedTextElement(of: pid)
        guard front, focusedEl != nil else { return }
        if let selection, !selection.isEmpty {
            KeyboardUtils.postText(selection)
        } else {
            KeyboardUtils.postKey(keyV, flags: .maskCommand) // ⌘V
        }
    }

    /// Re-checks the paste condition once the window under the point has come
    /// forward, then pastes. The real middle click that was let through does
    /// the activating; only a frontmost Chromium app can be asked for its
    /// focused editor. If the app has not come forward on its own within a
    /// short grace, it is raised the way any click on an inactive window
    /// would raise it, so the feature does not depend on the middle button
    /// itself counting as an activating click. `copyLatch` watches a
    /// Chromium source's click-time ⌘C; the paste waits for its outcome
    /// before falling back to the clipboard.
    static func deferredPaste(
        at point: CGPoint, selection: String?, copyLatch: CopyLatch?, generation: Int
    ) {
        guard let target = frontWindow(at: point) else { return }
        pollUntilTargetReady(DeferredPaste(
            target: target,
            point: point,
            selection: selection,
            copyLatch: copyLatch,
            generation: generation,
            sourcePid: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            deadline: Date().addingTimeInterval(activationTimeout),
            raiseDeadline: Date().addingTimeInterval(raiseGrace)
        ))
    }

    private struct DeferredPaste {
        let target: TargetWindow
        let point: CGPoint
        let selection: String?
        /// The watch over a click-time ⌘C, when the source's selection had
        /// to be copied; nil when there was none.
        let copyLatch: CopyLatch?
        let generation: Int
        /// The app that was frontmost when the click was let through. The
        /// grace-period raise happens only while focus has not moved on.
        let sourcePid: pid_t?
        let deadline: Date
        let raiseDeadline: Date
        var raised = false
        /// Ready polls that found a non-Chromium focused element — the
        /// deferred re-check abandons on the second; intervening polls do
        /// not reset the count.
        var nonChromiumStreak = 0
    }

    /// Waits until the app under the point is frontmost with that window
    /// focused — the state the real click's activation produces — then
    /// re-checks whether the point sits in the app's focused text editor.
    /// Chromium's accessibility tree may still be building the first time,
    /// so the check is retried each poll until the deadline, or until two
    /// ready polls have found a non-Chromium focused element.
    private static func pollUntilTargetReady(_ state: DeferredPaste) {
        guard state.generation == MiddleClickPasteHandler.generation else { return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focused = KeyboardUtils.focusedWindowID(pid: state.target.pid)
        let ready = front == state.target.pid && focused == state.target.windowID
        let element = focusedTextElement(of: state.target.pid)
        // The focused-editor classification is the Chromium shape only — an
        // AppKit or Gecko focused element's ancestors can span unrelated UI
        // (a tab bar) that the bounds walk would cover. WebKit answers the
        // same attribute, so Safari page content passes the gate too — an
        // accepted residual: only a click inside the focused field's own
        // ancestor groups can misfire there, and no attribute separates
        // WebKit from Chromium.
        let engineElement = element.map(isChromiumElement) ?? false
        let covers = engineElement
            && element.map { textElementCovers($0, state.point) } == true
        if ready && covers {
            let paste = {
                clickWhenWindowIsFront(
                    at: state.point, expected: state.target, generation: state.generation
                ) { clicked in
                    guard clicked else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        insert(state.selection, into: state.target.pid, generation: state.generation)
                    }
                }
            }
            if let copyLatch = state.copyLatch {
                // A click-time ⌘C is in flight; let its latched outcome
                // decide before the ⌘V fallback reads the clipboard.
                copyLatch.awaitConcluded {
                    guard copyLatch.outcome != .landedElsewhere else { return }
                    paste()
                }
            } else {
                paste()
            }
            return
        }

        var next = state
        if ready, element != nil, !engineElement {
            // The target's focused element is known and not Chromium-shaped,
            // so this click can never classify as a paste target — stop
            // rather than poll out the deadline. Two observations first
            // (intervening polls do not reset the count): a window mixing
            // native and web content can answer with its native field on
            // one poll before DOM focus lands.
            next.nonChromiumStreak += 1
            if next.nonChromiumStreak >= 2 { return }
        }
        guard Date() < state.deadline else { return }
        if !ready && !next.raised && Date() >= next.raiseDeadline {
            // Raising is only ours to do while the user has not moved on:
            // focus on a third app means the click's activation was
            // undone or never came, and yanking the window back over the
            // user's choice would override it.
            guard front == state.target.pid || front == state.sourcePid else { return }
            DisplayRefreshRate.startTracking()
            KeyboardUtils.raiseWindow(pid: state.target.pid, windowID: state.target.windowID)
            NSRunningApplication(processIdentifier: state.target.pid)?.activate()
            next.raised = true
        }
        let timer = Timer(timeInterval: DisplayRefreshRate.frameInterval, repeats: false) { _ in
            MainActor.assumeIsolated {
                pollUntilTargetReady(next)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// A click-time ⌘C in flight: what the pasteboard counted before it, and
    /// where focus was when it was posted — what the copy is attributed by.
    struct PendingCopy {
        let before: Int
        let source: CopySource
    }

    /// The app — and, within it, the window — holding focus when the ⌘C was
    /// posted. A copy that lands after focus moved off these copied some
    /// other app's or window's selection.
    struct CopySource {
        let pid: pid_t
        let windowID: UInt32?
    }

    /// The normal window a replacement click at the point would land on, or
    /// nil when there is none — Mission Control's shield, open menus and
    /// SuperOpt's own windows are not click targets, and a click replaced
    /// there would be dropped.
    static func clickTarget(at point: CGPoint) -> TargetWindow? {
        frontWindow(at: point)
    }

    /// Posts the caret-positioning click once the window under the point is
    /// genuinely in front. A left click on an inactive window — another app's,
    /// or another window of the frontmost app — is swallowed by macOS as a
    /// bare activation and reaches no view, so the window is raised first and
    /// the click waits. `expected`, when given, is the window the click was
    /// aimed at; a different window having moved over the point aborts, so
    /// the click never lands somewhere the user did not click. `then`
    /// reports whether the click was posted.
    static func clickWhenWindowIsFront(
        at point: CGPoint, expected: TargetWindow?, generation: Int, then: @escaping (Bool) -> Void
    ) {
        guard generation == MiddleClickPasteHandler.generation else { then(false); return }
        guard let target = frontWindow(at: point) else { then(false); return }
        if let expected, expected.windowID != target.windowID {
            then(false)
            return
        }
        if !needsFocus(target) {
            postClick(at: point)
            then(true)
            return
        }
        DisplayRefreshRate.startTracking()
        KeyboardUtils.raiseWindow(pid: target.pid, windowID: target.windowID)
        NSRunningApplication(processIdentifier: target.pid)?.activate()
        pollUntilFront(
            target, at: point, deadline: Date().addingTimeInterval(focusTimeout),
            generation: generation, then: then)
    }

    /// A plain left click at the given point, tagged synthetic so SuperOpt's
    /// own mouse handlers leave it alone. Clears any selection and positions
    /// the caret where the middle click landed.
    private static func postClick(at point: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(
                mouseEventSource: src, mouseType: type,
                mouseCursorPosition: point, mouseButton: .left
            ) else { continue }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: KeyboardUtils.syntheticTag)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// Polls at the display refresh rate, like `ClickThroughFocusHandler`:
    /// the window coming forward is what the user is about to see.
    private static func pollUntilFront(
        _ target: TargetWindow, at point: CGPoint, deadline: Date,
        generation: Int, then: @escaping (Bool) -> Void
    ) {
        guard generation == MiddleClickPasteHandler.generation else { then(false); return }
        let onTop = frontWindow(at: point)?.windowID == target.windowID
        let active = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
        if onTop && active {
            postClick(at: point)
            then(true)
        } else if Date() < deadline {
            let timer = Timer(timeInterval: DisplayRefreshRate.frameInterval, repeats: false) { _ in
                MainActor.assumeIsolated {
                    pollUntilFront(target, at: point, deadline: deadline,
                                   generation: generation, then: then)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        } else {
            then(false)
        }
    }

    struct TargetWindow {
        let pid: pid_t
        let windowID: UInt32
    }

    /// Time to give the target window to come forward before the paste is
    /// dropped, leaving stock macOS behavior.
    private static let focusTimeout: TimeInterval = 0.25
    /// Time for the real middle click's activation to bring the target app
    /// forward before a deferred paste gives up.
    private static let activationTimeout: TimeInterval = 0.6
    /// Grace before the deferred paste raises the target window itself,
    /// rather than waiting for the click's activation.
    private static let raiseGrace: TimeInterval = 0.25

    /// The frontmost normal window containing `point`, the one a click there
    /// lands on. `CGWindowListCopyWindowInfo` runs front to back, so the first
    /// window containing the point is it.
    private static func frontWindow(at point: CGPoint) -> TargetWindow? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for info in list {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds)
            else { continue }
            let layer = info[kCGWindowLayer as String] as? Int
            guard frame.contains(point) else { continue }
            // The cursor window follows the pointer and always contains the
            // point — it is the pointer, not a click target.
            if layer == Int(CGWindowLevelForKey(.cursorWindow)) { continue }
            // Above layer 0 sit the menu bar, the Dock and open menus — a
            // click there is not ours to replace. Below it is the desktop.
            guard layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? UInt32,
                  pid != ProcessInfo.processInfo.processIdentifier
            else { return nil }
            return TargetWindow(pid: pid, windowID: windowID)
        }
        return nil
    }

    private static func needsFocus(_ target: TargetWindow) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if front.processIdentifier != target.pid { return true }
        // Same app, different window: macOS swallows that press as a bare
        // activation too — the two-browser-windows case.
        guard let focused = KeyboardUtils.focusedWindowID(pid: target.pid) else { return false }
        return focused != target.windowID
    }
}

/// Watches a click-time ⌘C and latches its outcome as the pasteboard moves:
/// whether the copy landed, and — at that moment — whether focus was still
/// on the source app and window that posted it. Attribution has to be
/// latched when the count moves because the deferred path's paste waits
/// until after focus has already shifted to the target window; sampling
/// focus then would reject every correctly-landed copy. An unmoved count at
/// the timeout means nothing was selected, so the clipboard still holds what
/// it held before the click — including a deliberate user ⌘C — and the
/// ordinary clipboard fallback proceeds, exactly as for an AppKit source
/// with no selection. A count that moved after focus left the source copied
/// the wrong selection, and the paste is abandoned rather than pasting it.
@MainActor
final class CopyLatch {
    enum Outcome {
        case pending
        /// Copied while focus was still on the source.
        case landed
        /// The count moved after focus left the source — the keystroke
        /// copied some other window's selection.
        case landedElsewhere
        /// Nothing was copied within the timeout.
        case nothingCopied
    }

    /// Time given the source app to process the copy keystroke before the
    /// latch concludes that nothing was copied.
    private static let settleTimeout: TimeInterval = 0.3

    private(set) var outcome: Outcome = .pending
    private var completions: [() -> Void] = []
    private let pending: MiddleClickPasteHandler.PendingCopy
    private let generation: Int
    private let deadline: Date

    init(pending: MiddleClickPasteHandler.PendingCopy, generation: Int) {
        self.pending = pending
        self.generation = generation
        deadline = Date().addingTimeInterval(Self.settleTimeout)
        poll()
    }

    /// Whether focus is still on the app — and, within it, the window —
    /// that posted the copy. The pasteboard cannot say which app wrote it,
    /// so the copy is attributed by the state around it.
    private func copyIsFromSource() -> Bool {
        let source = pending.source
        guard source.pid != 0,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == source.pid
        else { return false }
        guard let sourceWindow = source.windowID else { return true }
        return KeyboardUtils.focusedWindowID(pid: source.pid) == sourceWindow
    }

    private func poll() {
        guard outcome == .pending else { return }
        guard generation == MiddleClickPasteHandler.generation else {
            conclude(.nothingCopied)
            return
        }
        if NSPasteboard.general.changeCount != pending.before {
            conclude(copyIsFromSource() ? .landed : .landedElsewhere)
        } else if Date() >= deadline {
            conclude(.nothingCopied)
        } else {
            let timer = Timer(timeInterval: DisplayRefreshRate.frameInterval, repeats: false) { _ in
                MainActor.assumeIsolated { self.poll() }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Runs `then` once the outcome is known.
    func awaitConcluded(then: @escaping () -> Void) {
        if outcome == .pending {
            completions.append(then)
        } else {
            then()
        }
    }

    private func conclude(_ outcome: Outcome) {
        self.outcome = outcome
        let callbacks = completions
        completions.removeAll()
        for callback in callbacks { callback() }
    }
}
