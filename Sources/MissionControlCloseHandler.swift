import Cocoa

private let skylight = dlopen(nil, RTLD_LAZY)
@MainActor
class MissionControlCloseHandler {
    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias ScreenRectFn = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> Int32
    private let cid: Int32
    private let getScreenRect: ScreenRectFn

    private let monitor: MissionControlMonitor
    private var enabled = false
    private var overlay: CloseOverlay?
    private var hoveredWID: UInt32 = 0
    private var buttonHovered = false
    private var positionTimer: Timer?
    private var lastOverlayOrigin = NSPoint.zero
    private var lastThumbnailMotion: TimeInterval = 0

    private struct WindowEntry {
        let wid: UInt32
        let pid: pid_t
        let rect: CGRect
    }

    private var windowRects: [WindowEntry] = []
    private var unclosableWIDs: Set<UInt32> = []
    private var closableWIDs: Set<UInt32> = []
    /// Consecutive unanswered AX reads per window — the window match or the
    /// close-button read — bounding the retry of a transient failure: a
    /// window with no AX counterpart at all would otherwise re-pay the
    /// lookup (including its window-list fallback) every tick for the whole
    /// Mission Control session.
    private var axFailureCounts: [UInt32: Int] = [:]

    private static let buttonSize: CGFloat = 26
    private static let hitPadding: CGFloat = 9
    /// After this many consecutive unanswered reads a window is treated as
    /// unclosable: enough ticks for a busy app to recover, few enough that
    /// a structural miss costs a fixed number of probes.
    private static let axRetryLimit = 3
    /// How far from a cached thumbnail rect the pointer may sit before the
    /// live read is skipped: the cache lags a moving thumbnail by whatever
    /// it travelled since the last 4 Hz refresh, so this is deliberately
    /// much wider than the button's hit padding.
    private static let hoverPrefilter: CGFloat = 150

    init?(monitor: MissionControlMonitor) {
        self.monitor = monitor
        // Private: CGSGetScreenRectForWindow returns the on-screen compositor bounds
        // of a window (the scaled thumbnail position during Mission Control).
        // CGWindowListCopyWindowInfo only reports logical frames, which don't update
        // during MC's scaling transform — no public API exposes compositor geometry.
        guard let cidPtr = dlsym(skylight, "CGSMainConnectionID"),
              let srPtr = dlsym(skylight, "CGSGetScreenRectForWindow")
        else { return nil }
        cid = unsafeBitCast(cidPtr, to: MainConnFn.self)()
        getScreenRect = unsafeBitCast(srPtr, to: ScreenRectFn.self)
    }

    func start() {
        enabled = true
        DisplayRefreshRate.startTracking()
    }

    func stop() {
        enabled = false; deactivateMC()
    }

    /// Share the monitor's ticks for stationary-pointer hover and stable thumbnails.
    func missionControlDidTick(_ windowList: [[String: Any]]) {
        guard enabled else { return }
        refreshWindowRects(from: windowList)
        if positionTimer == nil { updatePosition() }
    }

    private func followThumbnail() {
        lastThumbnailMotion = ProcessInfo.processInfo.systemUptime
        guard positionTimer == nil else { return }
        positionTimer = Timer.scheduledTimer(
            withTimeInterval: DisplayRefreshRate.frameInterval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updatePosition()
                if ProcessInfo.processInfo.systemUptime - self.lastThumbnailMotion >= 2 {
                    self.stopTimer()
                }
            }
        }
    }

    private func updatePosition() {
        guard monitor.isActive else { return }
        _ = updateHover(at: CGEvent(source: nil)?.location ?? .zero)
        updateOverlay()
    }

    private func stopTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func closeButtonCGRect(for windowRect: CGRect) -> CGRect {
        let half = Self.buttonSize / 2
        return CGRect(
            x: windowRect.maxX - half, y: windowRect.origin.y - half,
            width: Self.buttonSize, height: Self.buttonSize)
    }

    private func hitTestCGRect(for windowRect: CGRect) -> CGRect {
        closeButtonCGRect(for: windowRect).insetBy(
            dx: -Self.hitPadding, dy: -Self.hitPadding)
    }

    // MARK: - Event tap hooks

    func handleClick(event: CGEvent) -> Bool {
        // `hoveredWID` is only ever set while Mission Control was up, so with
        // nothing hovered there is nothing to do — and this runs for every
        // click in every app, so the walk below is not paid there.
        let wid = hoveredWID
        guard wid != 0 else { return false }
        // A fresh walk rather than the `isActive` flag: it stays true through
        // the close animation, and a click in that window would otherwise
        // close a very real window from where a thumbnail used to be.
        guard monitor.check() else { return false }
        let loc = event.location
        guard let entry = windowRects.first(where: { $0.wid == wid })
        else { return false }
        // The visible button tracks the live compositor rect at the display's
        // refresh rate while `windowRects` refreshes at the monitor's 4 Hz,
        // so the hit test runs against where the button is drawn. The same
        // size floor as the overlay: no button is drawn below it, so no
        // click is consumed there either.
        var live = CGRect.zero
        guard getScreenRect(cid, entry.wid, &live) == 0,
              live.width > 60, live.height > 60,
              hitTestCGRect(for: live).contains(loc)
        else { return false }
        closeWindow(pid: entry.pid, windowID: entry.wid)
        return true
    }

    @discardableResult
    func handleMouseMoved(event: CGEvent) -> Bool {
        guard enabled, !KeyboardUtils.isSynthetic(event) else { return false }
        let loc = event.location

        // A mouse move is how Mission Control opened by a trackpad swipe — which
        // fires no trigger — gets noticed.
        monitor.checkIfDue()
        guard monitor.isActive else { return false }
        if updateHover(at: loc) { updateOverlay() }
        return false
    }

    private func updateHover(at loc: CGPoint) -> Bool {
        // Live compositor rects, not the 4 Hz-cached ones: the click path
        // tests the live rect, so the drawn affordance has to agree with it
        // while thumbnails move. The cached rect pre-filters, generously —
        // the cache lags a moving thumbnail by whatever it travelled since
        // the last 4 Hz refresh, so a tight margin would drop hover exactly
        // during animations — and the live read is still only paid for
        // entries the pointer is plausibly on.
        let hitWID = windowRects.first(where: { entry in
            entry.rect.insetBy(dx: -Self.hoverPrefilter, dy: -Self.hoverPrefilter).contains(loc)
                && hoverRect(for: entry).contains(loc)
        })?.wid ?? 0
        var overButton = false
        if hitWID != 0, let entry = windowRects.first(where: { $0.wid == hitWID }) {
            overButton = hitTestCGRect(for: hoverRect(for: entry)).contains(loc)
        }
        let changed = hitWID != hoveredWID || overButton != buttonHovered
        if hitWID == 0 {
            stopTimer()
        } else if hitWID != hoveredWID {
            followThumbnail()
        }
        hoveredWID = hitWID
        buttonHovered = overButton
        return changed
    }

    /// Where a window's thumbnail is right now: the live compositor rect
    /// under the same size floor as everything that draws or consumes the
    /// button, falling back to the cached one only when the live read fails.
    /// Zero when neither qualifies — no button is drawn there, so nothing is
    /// hovered either.
    private func hoverRect(for entry: WindowEntry) -> CGRect {
        var live = CGRect.zero
        if getScreenRect(cid, entry.wid, &live) == 0,
           live.width > 60, live.height > 60 {
            return live
        }
        return (entry.rect.width > 60 && entry.rect.height > 60) ? entry.rect : .zero
    }

    func deactivateMC() {
        hoveredWID = 0; buttonHovered = false
        hideOverlay()
        windowRects.removeAll()
        unclosableWIDs.removeAll(); closableWIDs.removeAll()
        axFailureCounts.removeAll()
        stopTimer()
    }

    /// Records an unanswered classification read; after enough consecutive
    /// ones the window is given up on for the session, so a structural miss
    /// costs a fixed number of probes.
    private func noteAXFailure(_ wid: UInt32) {
        let failures = (axFailureCounts[wid] ?? 0) + 1
        axFailureCounts[wid] = failures
        if failures >= Self.axRetryLimit {
            unclosableWIDs.insert(wid)
            axFailureCounts.removeValue(forKey: wid)
        }
    }

    private func refreshWindowRects(from windowList: [[String: Any]]) {
        let myPID = ProcessInfo.processInfo.processIdentifier
        var rects: [WindowEntry] = []
        for info in windowList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != myPID, !unclosableWIDs.contains(wid)
            else { continue }
            var screenRect = CGRect.zero
            guard getScreenRect(cid, wid, &screenRect) == 0,
                  screenRect.width > 60, screenRect.height > 60 else { continue }
            if !closableWIDs.contains(wid) {
                // A read that did not answer — the app busy, an AX timeout
                // at the tick — is retried on later ticks rather than cached
                // as a structural answer, and bounded so a window with no AX
                // counterpart at all costs a fixed number of probes.
                guard let axWin = KeyboardUtils.findAXWindow(pid: pid, windowID: wid) else {
                    noteAXFailure(wid)
                    continue
                }
                let (btn, answered) = axCloseButtonRead(of: axWin)
                guard answered else {
                    noteAXFailure(wid)
                    continue
                }
                axFailureCounts.removeValue(forKey: wid)
                if let btn, axIsEnabled(btn) {
                    closableWIDs.insert(wid)
                } else {
                    unclosableWIDs.insert(wid)
                    continue
                }
            }
            rects.append(WindowEntry(wid: wid, pid: pid, rect: screenRect))
        }
        windowRects = rects
    }

    // MARK: - Overlay

    private func updateOverlay() {
        guard hoveredWID != 0 else { hideOverlay(); return }
        var liveRect = CGRect.zero
        guard getScreenRect(cid, hoveredWID, &liveRect) == 0,
              liveRect.width > 60, liveRect.height > 60
        else { stopTimer(); hideOverlay(); return }
        let cgBtn = closeButtonCGRect(for: liveRect)
        let origin = KeyboardUtils.cgRectToNS(cgBtn).origin
        let moved = abs(origin.x - lastOverlayOrigin.x) > 0.5
            || abs(origin.y - lastOverlayOrigin.y) > 0.5
        lastOverlayOrigin = origin

        if let existing = overlay {
            if moved { followThumbnail() }
            existing.reposition(origin: origin)
            existing.setState(hovered: buttonHovered)
        } else {
            overlay = CloseOverlay(
                origin: origin, size: Self.buttonSize, hovered: buttonHovered)
            followThumbnail()
        }
    }

    private func hideOverlay() { overlay?.close(); overlay = nil }
}

// MARK: - AX helpers

extension MissionControlCloseHandler {
    /// The window's close button, and whether the read that produced it
    /// answered at all. A read error is distinct from "no close button":
    /// an app that is merely busy must not be cached as a structural
    /// answer for the whole session.
    fileprivate func axCloseButtonRead(of window: AXUIElement) -> (
        button: AXUIElement?, answered: Bool
    ) {
        var ref: AnyObject?
        let error = AXUIElementCopyAttributeValue(
            window, kAXCloseButtonAttribute as CFString, &ref)
        if error == .success { return (ref.flatMap(KeyboardUtils.toAXElement), true) }
        if error == .noValue || error == .attributeUnsupported { return (nil, true) }
        return (nil, false)
    }

    fileprivate func closeWindow(pid: pid_t, windowID: UInt32) {
        guard let win = KeyboardUtils.findAXWindow(pid: pid, windowID: windowID),
              let btn = axCloseButtonRead(of: win).button else { return }
        AXUIElementPerformAction(btn, kAXPressAction as CFString)
        hoveredWID = 0; hideOverlay()
        closableWIDs.remove(windowID)
        windowRects.removeAll(where: { $0.wid == windowID })
    }

    fileprivate func axIsEnabled(_ element: AXUIElement) -> Bool {
        var val: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &val)
        return (val as? Bool) != false
    }
}
