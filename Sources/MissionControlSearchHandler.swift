import Cocoa

/// Where a keystroke typed in Mission Control ends up.
enum MissionControlSearchMode: Int {
    case off = 0
    case search = 1  // Spotlight search
    case apps = 2    // Spotlight Apps
}

/// GNOME's Activities overview starts searching as soon as you type in it. This
/// does the same for Mission Control: the first printable keystroke closes Mission
/// Control, opens Spotlight, and types everything buffered along the way into it.
///
/// Spotlight can't be opened while Mission Control is on screen — the key is simply
/// swallowed — so the two have to be posted in that order, and the buffered text can
/// only go out once Spotlight's field is actually focused. Keys pressed during that
/// gap are consumed rather than passed through, since Mission Control has already
/// started closing and they would otherwise land in whatever it uncovers.
@MainActor
class MissionControlSearchHandler {
    /// Virtual key code emitted by the Spotlight key (F4 on current Apple keyboards).
    private static let spotlightKeyCode: Int64 = 177
    /// Virtual key code emitted by the Apps key, which opens the Spotlight Apps view.
    private static let appsKeyCode: Int64 = 131
    /// On macOS 27 the Spotlight UI lives in Siri AI.app.
    private static let spotlightBundleID = "com.apple.campo"

    private static let keyEscape: Int64 = 0x35
    private static let keyDelete: Int64 = 0x33

    /// Mission Control swallows the Spotlight key until it has begun closing, so the
    /// two posts need a gap. Measured success rate by gap: 0 ms 0/8, 1–5 ms 0/8,
    /// 8 ms 3/8, 12 ms 6/8, 20 ms 23/23, 25/30/40 ms 15/15 each. 25 ms sits at twice
    /// the last gap that ever failed. There is no need to wait out the close
    /// animation — the Mission Control window itself lingers for ~320 ms.
    private static let dismissDelay: TimeInterval = 0.025
    /// Spotlight is normally ready ~140 ms after its key. Give up well after that
    /// rather than holding the user's keystrokes indefinitely.
    private static let readyTimeout: TimeInterval = 1.5
    /// Only look for Mission Control on the first keystroke of a typing burst.
    private static let burstGap: TimeInterval = 0.3

    private var mode: MissionControlSearchMode = .off
    private var buffer = ""
    private var pending = false
    private var injected = false
    private var lastTypedAt: TimeInterval = 0
    private var handledActivation: Int?
    private var deadline: TimeInterval = 0
    private var timer: Timer?

    /// Closes Mission Control. Supplied by `AppDelegate`, which owns the F3 trigger.
    var dismissMissionControl: (() -> Void)?

    var isEnabled: Bool { mode != .off }

    private let monitor: MissionControlMonitor

    init(monitor: MissionControlMonitor) {
        self.monitor = monitor
        reloadSettings()
    }

    func reloadSettings() {
        mode = MissionControlSearchMode(
            rawValue: UserDefaults.standard.integer(forKey: "mcTypeToSearchMode")
        ) ?? .off
        if mode == .off { finish() }
    }

    /// Returns true if the event was consumed.
    func handleKeyDown(event: CGEvent) -> Bool {
        guard mode != .off else { return false }
        if pending { return handleWhilePending(event: event) }

        guard let text = Self.typedText(event),
              text.rangeOfCharacter(from: CharacterSet.whitespaces.inverted) != nil
        else { return false }

        let now = ProcessInfo.processInfo.systemUptime
        let startsBurst = now - lastTypedAt > Self.burstGap
        lastTypedAt = now
        guard missionControlIsUp(startsBurst: startsBurst),
              // One search per appearance of Mission Control. Without this, a key
              // pressed just after a session ends but before Mission Control has
              // finished animating away starts a second search, which toggles
              // Mission Control back open.
              handledActivation != monitor.activationID
        else { return false }

        handledActivation = monitor.activationID
        start(with: text)
        return true
    }

    /// The monitor already knows whenever Mission Control was opened a way SuperOpt
    /// can see — F3, the Option press, the hot corner — which makes the common case
    /// free and exact, with no throttle to miss keystrokes behind.
    ///
    /// The window list walk is the fallback, and costs about 1.2 ms when it has gone
    /// cold, so it is not something to do on every keystroke. It is worth it when a
    /// trigger is outstanding and Mission Control is mid-animation, and once per
    /// typing burst otherwise, which is what catches a Mission Control opened by a
    /// trackpad swipe — the one route that fires no trigger.
    private func missionControlIsUp(startsBurst: Bool) -> Bool {
        if monitor.isActive { return true }
        guard startsBurst || monitor.isOpening else { return false }
        return monitor.check()
    }

    // MARK: - Session

    private func start(with text: String) {
        buffer = text
        pending = true
        deadline = ProcessInfo.processInfo.systemUptime + Self.readyTimeout
        DisplayRefreshRate.startTracking()
        dismissMissionControl?()
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.dismissDelay, repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.openSpotlight() }
        }
    }

    private func openSpotlight() {
        guard pending else { return }
        KeyboardUtils.postKey(
            mode == .apps ? Self.appsKeyCode : Self.spotlightKeyCode,
            flags: .maskSecondaryFn)
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: DisplayRefreshRate.frameInterval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollForSpotlight() }
        }
    }

    /// Drives the handoff. Keystrokes stay intercepted until Spotlight has visibly
    /// taken the text and nothing new is queued, because a key released too early
    /// can reach Spotlight ahead of the injected text and scramble the query —
    /// typing "hi there" lands as "ehi ther" when the last key overtakes the rest.
    private func pollForSpotlight() {
        if !injected {
            guard isSpotlightReady() else { return giveUpIfLate() }
            injected = true
            flushBuffer()
        } else if !spotlightFieldIsPopulated() {
            giveUpIfLate()
        } else if !buffer.isEmpty {
            flushBuffer()
        } else {
            finish()
        }
    }

    private func flushBuffer() {
        let text = buffer
        buffer = ""
        KeyboardUtils.postText(text)
    }

    private func giveUpIfLate() {
        if ProcessInfo.processInfo.systemUptime > deadline { finish() }
    }

    /// Ends the session, whether the text went out or not. Invalidating the timer
    /// before it has fired also calls off the Spotlight key, so cancelling within
    /// `dismissDelay` leaves Mission Control merely closed.
    private func finish() {
        pending = false
        injected = false
        buffer = ""
        timer?.invalidate()
        timer = nil
    }

    private func handleWhilePending(event: CGEvent) -> Bool {
        let flags = event.flags
        // Leave ⌘Tab and friends alone — they are not part of the search.
        guard !flags.contains(.maskCommand), !flags.contains(.maskControl),
              !flags.contains(.maskAlternate)
        else { return false }

        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case Self.keyEscape:
            finish()
        case Self.keyDelete:
            if !buffer.isEmpty { buffer.removeLast() }
        default:
            if let text = Self.typedText(event) { buffer += text }
        }
        // Swallow the key either way. Mission Control has already started closing and
        // Spotlight is not up yet, so anything let through would land in whatever
        // window Mission Control uncovers.
        return true
    }

    // MARK: - Spotlight readiness

    /// True once Spotlight is both on screen and focused on its search field.
    ///
    /// The window alone is not enough: Siri AI keeps its panel window around after
    /// Spotlight is dismissed, hidden by dropping its alpha to 0 rather than by
    /// ordering it out, so a plain on-screen check matches a closed Spotlight too.
    /// The focused field alone is not enough either, because that field stays focused
    /// after dismissal.
    private func isSpotlightReady() -> Bool { spotlightField() != nil }

    /// True once the injected text has shown up in Spotlight's field. Only emptiness
    /// is checked, not the exact contents: Spotlight is empty when it opens, so
    /// anything at all means the text landed, and matching exactly would be brittle
    /// if Spotlight ever completed or reformatted the query.
    private func spotlightFieldIsPopulated() -> Bool {
        guard let field = spotlightField() else { return false }
        var value: AnyObject?
        AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value)
        return (value as? String).map { !$0.isEmpty } ?? false
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

    // MARK: - Key decoding

    /// The text a keystroke would insert, or nil if it would not insert any.
    private static func typedText(_ event: CGEvent) -> String? {
        let flags = event.flags
        guard !flags.contains(.maskCommand), !flags.contains(.maskControl),
              !flags.contains(.maskAlternate)
        else { return nil }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
            maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }

        let text = String(utf16CodeUnits: chars, count: length)
        guard text.unicodeScalars.allSatisfy(isTypable) else { return nil }
        return text
    }

    /// Control characters (Escape, Return, Tab, Delete) and the private-use range
    /// AppKit maps the arrow and function keys into are keystrokes, not text.
    private static func isTypable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x20 && scalar.value != 0x7F
            && !(0xF700...0xF8FF).contains(scalar.value)
    }
}
