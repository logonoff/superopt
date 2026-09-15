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
    private var stableFrames = 0

    private struct WindowEntry {
        let wid: UInt32
        let pid: pid_t
        let rect: CGRect
    }

    private var windowRects: [WindowEntry] = []
    private var unclosableWIDs: Set<UInt32> = []
    private var closableWIDs: Set<UInt32> = []

    private static let buttonSize: CGFloat = 26
    private static let hitPadding: CGFloat = 9
    private static let slowInterval: TimeInterval = 0.25

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
        // The monitor owns Mission Control detection and is shared, so the callbacks
        // check `enabled` rather than being torn down when this feature is off.
        monitor.onActive = { [weak self] list in self?.missionControlDidTick(list) }
        monitor.onInactive = { [weak self] in self?.deactivateMC() }
    }

    func stop() {
        enabled = false; deactivateMC()
    }

    private enum TickRate {
        case slow // Mission Control up, nothing animating
        case fast // thumbnails animating, follow them at the display's rate
    }

    /// Runs on each of the monitor's polls while Mission Control is up, off the window
    /// list it already fetched. Starting the position timer here is what gets the
    /// close button on screen when Mission Control was opened with the pointer held
    /// still, which produces no mouse-moved event of its own.
    private func missionControlDidTick(_ windowList: [[String: Any]]) {
        guard enabled else { return }
        refreshWindowRects(from: windowList)
        if positionTimer == nil { setTickRate(.slow) }
    }

    private func setTickRate(_ rate: TickRate) {
        let interval: TimeInterval
        switch rate {
        case .slow: interval = Self.slowInterval
        case .fast: interval = DisplayRefreshRate.frameInterval
        }
        if let existing = positionTimer, abs(existing.timeInterval - interval) < 0.01 {
            return
        }
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(
            withTimeInterval: interval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
    }

    private func onTick() {
        guard monitor.isActive else { return }
        // Derive hover from where the pointer is now rather than from a move event.
        updateHover(at: CGEvent(source: nil)?.location ?? .zero)
        if hoveredWID != 0 { updateOverlay() }
    }

    private func stopTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
        stableFrames = 0
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
        guard monitor.isActive else { return false }
        let loc = event.location
        guard hoveredWID != 0,
              let entry = windowRects.first(where: { $0.wid == hoveredWID }),
              hitTestCGRect(for: entry.rect).contains(loc)
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
        updateHover(at: loc)
        return false
    }

    private func updateHover(at loc: CGPoint) {
        let hitWID = windowRects.first(where: { $0.rect.contains(loc) })?.wid ?? 0
        var overButton = false
        if hitWID != 0, let entry = windowRects.first(where: { $0.wid == hitWID }) {
            overButton = hitTestCGRect(for: entry.rect).contains(loc)
        }
        guard hitWID != hoveredWID || overButton != buttonHovered else { return }
        hoveredWID = hitWID
        buttonHovered = overButton
        if hoveredWID != 0 {
            stableFrames = 0; setTickRate(.fast)
        } else {
            setTickRate(.slow)
        }
        updateOverlay()
    }

    private func deactivateMC() {
        hoveredWID = 0; buttonHovered = false
        hideOverlay()
        windowRects.removeAll()
        unclosableWIDs.removeAll(); closableWIDs.removeAll()
        stopTimer()
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
                guard let axWin = KeyboardUtils.findAXWindow(pid: pid, windowID: wid),
                      let btn = axCloseButton(of: axWin),
                      axIsEnabled(btn)
                else { unclosableWIDs.insert(wid); continue }
                closableWIDs.insert(wid)
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
        else { hideOverlay(); return }
        let cgBtn = closeButtonCGRect(for: liveRect)
        let origin = KeyboardUtils.cgRectToNS(cgBtn).origin
        let moved = abs(origin.x - lastOverlayOrigin.x) > 0.5
            || abs(origin.y - lastOverlayOrigin.y) > 0.5
        lastOverlayOrigin = origin

        if moved {
            stableFrames = 0
            setTickRate(.fast)
        } else {
            stableFrames += 1
            if stableFrames > Int(DisplayRefreshRate.current * 2) { setTickRate(.slow) }
        }

        if let existing = overlay {
            existing.reposition(origin: origin)
            existing.setState(hovered: buttonHovered)
        } else {
            overlay = CloseOverlay(
                origin: origin, size: Self.buttonSize, hovered: buttonHovered)
        }
    }

    private func hideOverlay() { overlay?.close(); overlay = nil }
}

// MARK: - AX helpers

extension MissionControlCloseHandler {
    fileprivate func axCloseButton(of window: AXUIElement) -> AXUIElement? {
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(
            window, kAXCloseButtonAttribute as CFString, &ref)
        return ref.flatMap(KeyboardUtils.toAXElement)
    }

    fileprivate func closeWindow(pid: pid_t, windowID: UInt32) {
        guard let win = KeyboardUtils.findAXWindow(pid: pid, windowID: windowID),
              let btn = axCloseButton(of: win) else { return }
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
