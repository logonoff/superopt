import Cocoa

private let skylight = dlopen(nil, RTLD_LAZY)
private let appServices = dlopen(
    "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
    RTLD_LAZY
)

@MainActor
class MissionControlCloseHandler {
    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias ScreenRectFn = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> Int32
    private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
    private let cid: Int32
    private let getScreenRect: ScreenRectFn
    private let axGetWindow: AXGetWindowFn?

    private var enabled = false
    private(set) var mcActive = false
    private var lastCheckTime: TimeInterval = 0
    private let checkInterval: TimeInterval = 0.25
    private var cachedRefreshRate: Double = 60.0
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
    private var ghostRects: [WindowEntry] = []
    private var unclosableWIDs: Set<UInt32> = []
    private var closableWIDs: Set<UInt32> = []
    private var recentlyClosedWIDs: Set<UInt32> = []

    private static let buttonSize: CGFloat = 26
    private static let hitPadding: CGFloat = 9

    init?() {
        // Private: CGSGetScreenRectForWindow returns the on-screen compositor bounds
        // of a window (the scaled thumbnail position during Mission Control).
        // CGWindowListCopyWindowInfo only reports logical frames, which don't update
        // during MC's scaling transform — no public API exposes compositor geometry.
        guard let cidPtr = dlsym(skylight, "CGSMainConnectionID"),
              let srPtr = dlsym(skylight, "CGSGetScreenRectForWindow")
        else { return nil }
        cid = unsafeBitCast(cidPtr, to: MainConnFn.self)()
        getScreenRect = unsafeBitCast(srPtr, to: ScreenRectFn.self)
        // Private: _AXUIElementGetWindow maps an AXUIElement to its CGWindowID.
        // No public API bridges AX elements to CGWindowIDs — without this, matching
        // AX windows to compositor thumbnails requires fragile title-based heuristics.
        axGetWindow = dlsym(appServices, "_AXUIElementGetWindow")
            .map { unsafeBitCast($0, to: AXGetWindowFn.self) }
    }

    private var screenObserver: NSObjectProtocol?

    func start() {
        enabled = true
        updateCachedRefreshRate()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateCachedRefreshRate() }
            }
        }
    }

    func stop() {
        enabled = false; deactivateMC()
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
    }

    private func updateCachedRefreshRate() {
        var maxRate = 60.0
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        for display in displays {
            if let mode = CGDisplayCopyDisplayMode(display) {
                maxRate = max(maxRate, mode.refreshRate)
            }
        }
        cachedRefreshRate = maxRate
    }

    private func setTimerRate(fast: Bool) {
        let interval: TimeInterval = fast ? 1.0 / cachedRefreshRate : 0.25
        if let existing = positionTimer, abs(existing.timeInterval - interval) < 0.01 {
            return
        }
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(
            withTimeInterval: interval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateOverlay() }
        }
    }

    private func stopPositionTimer() {
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
        guard mcActive else { return false }
        let loc = event.location
        if ghostRects.contains(where: { $0.rect.contains(loc) }) { return true }
        guard hoveredWID != 0,
              let entry = windowRects.first(where: { $0.wid == hoveredWID }),
              hitTestCGRect(for: entry.rect).contains(loc)
        else { return false }
        closeWindow(pid: entry.pid, windowID: entry.wid, cursorLocation: loc)
        return true
    }

    @discardableResult
    func handleMouseMoved(event: CGEvent) -> Bool {
        guard enabled, !KeyboardUtils.isSynthetic(event) else { return false }
        let loc = event.location

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastCheckTime >= checkInterval {
            lastCheckTime = now
            if checkMCState() { return false }
        }
        guard mcActive else { return false }

        if ghostRects.contains(where: { $0.rect.contains(loc) }) { return true }

        let hitWID = windowRects.first(where: { $0.rect.contains(loc) })?.wid ?? 0
        let overButton: Bool
        if hitWID != 0, let entry = windowRects.first(where: { $0.wid == hitWID }) {
            overButton = hitTestCGRect(for: entry.rect).contains(loc)
        } else {
            overButton = false
        }

        let changed = hitWID != hoveredWID || overButton != buttonHovered
        hoveredWID = hitWID
        buttonHovered = overButton
        if changed {
            updateOverlay()
            if hoveredWID != 0 {
                stableFrames = 0; setTimerRate(fast: true)
            } else {
                stopPositionTimer()
            }
        }
        return false
    }

    private func checkMCState() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]]
        else { return false }
        if KeyboardUtils.isMissionControlActive(windowList) {
            mcActive = true
            refreshWindowRects(from: windowList)
            return false
        } else if mcActive {
            deactivateMC()
            return true
        }
        return false
    }

    private func deactivateMC() {
        mcActive = false; hoveredWID = 0; buttonHovered = false
        stopPositionTimer(); hideOverlay()
        windowRects.removeAll(); ghostRects.removeAll()
        unclosableWIDs.removeAll(); closableWIDs.removeAll()
        recentlyClosedWIDs.removeAll()
    }

    private func refreshWindowRects(from windowList: [[String: Any]]) {
        let myPID = ProcessInfo.processInfo.processIdentifier
        var rects: [WindowEntry] = []
        for info in windowList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != myPID, !unclosableWIDs.contains(wid),
                  !recentlyClosedWIDs.contains(wid)
            else { continue }
            var screenRect = CGRect.zero
            guard getScreenRect(cid, wid, &screenRect) == 0,
                  screenRect.width > 60, screenRect.height > 60 else { continue }
            if !closableWIDs.contains(wid) {
                guard let axWin = findAXWindow(pid: pid, windowID: wid),
                      hasCloseButton(axWindow: axWin)
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
        let primaryHeight = KeyboardUtils.primaryScreenHeight()
        guard primaryHeight > 0 else { return }
        let cgBtn = closeButtonCGRect(for: liveRect)
        let origin = NSPoint(x: cgBtn.origin.x,
                             y: primaryHeight - cgBtn.origin.y - cgBtn.height)
        let moved = abs(origin.x - lastOverlayOrigin.x) > 0.5
            || abs(origin.y - lastOverlayOrigin.y) > 0.5
        lastOverlayOrigin = origin

        if moved {
            stableFrames = 0
            setTimerRate(fast: true)
        } else {
            stableFrames += 1
            if stableFrames > Int(cachedRefreshRate * 2) { setTimerRate(fast: false) }
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
    fileprivate func findAXWindow(pid: pid_t, windowID: UInt32) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref)
        guard let windows = ref as? [AXUIElement] else { return nil }
        if let axGetWindow {
            for win in windows {
                var axWID: UInt32 = 0
                if axGetWindow(win, &axWID) == 0, axWID == windowID { return win }
            }
        }
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]],
              let title = list.first(where: {
                  $0[kCGWindowNumber as String] as? UInt32 == windowID
              })?[kCGWindowName as String] as? String
        else { return nil }
        for win in windows {
            var titleRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
            if (titleRef as? String) == title { return win }
        }
        return nil
    }

    fileprivate func axCloseButton(of window: AXUIElement) -> AXUIElement? {
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(
            window, kAXCloseButtonAttribute as CFString, &ref)
        return ref.flatMap(KeyboardUtils.toAXElement)
    }

    fileprivate func closeWindow(pid: pid_t, windowID: UInt32, cursorLocation: CGPoint = .zero) {
        guard let win = findAXWindow(pid: pid, windowID: windowID),
              let btn = axCloseButton(of: win) else { return }
        var screenRect = CGRect.zero
        _ = getScreenRect(cid, windowID, &screenRect)
        AXUIElementPerformAction(btn, kAXPressAction as CFString)
        hoveredWID = 0; hideOverlay()
        closableWIDs.remove(windowID)
        recentlyClosedWIDs.insert(windowID)
        windowRects.removeAll(where: { $0.wid == windowID })
        if screenRect.width > 0 {
            ghostRects.append(WindowEntry(wid: windowID, pid: pid, rect: screenRect))
            nudgeMouseOff(screenRect, from: cursorLocation)
        }
    }

    private func nudgeMouseOff(_ rect: CGRect, from point: CGPoint) {
        var nudged = point
        nudged.x = point.x < rect.midX ? rect.minX - 2 : rect.maxX + 2
        for pos in [nudged, point] {
            guard let evt = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                    mouseCursorPosition: pos, mouseButton: .left)
            else { continue }
            evt.setIntegerValueField(.eventSourceUserData, value: KeyboardUtils.syntheticTag)
            evt.post(tap: .cghidEventTap)
        }
    }

    fileprivate func hasCloseButton(axWindow: AXUIElement) -> Bool {
        guard let btn = axCloseButton(of: axWindow) else { return false }
        var enabled: AnyObject?
        AXUIElementCopyAttributeValue(btn, kAXEnabledAttribute as CFString, &enabled)
        return (enabled as? Bool) != false
    }

}

// MARK: - Close button overlay

private class CloseOverlay {
    let window: NSWindow
    private let buttonView: CloseButtonView

    @MainActor
    init(origin: NSPoint, size: CGFloat, hovered: Bool) {
        let frame = NSRect(x: origin.x, y: origin.y, width: size, height: size)
        window = NSWindow(contentRect: frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        buttonView = CloseButtonView(
            frame: NSRect(x: 0, y: 0, width: size, height: size))
        buttonView.isHovered = hovered
        window.contentView = buttonView
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15; window.animator().alphaValue = 1
        }
    }

    @MainActor func reposition(origin: NSPoint) { window.setFrameOrigin(origin) }

    @MainActor func setState(hovered: Bool) {
        guard buttonView.isHovered != hovered else { return }
        buttonView.isHovered = hovered; buttonView.needsDisplay = true
    }

    @MainActor func close() { window.close() }
}

private class CloseButtonView: NSView {
    var isHovered = false

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3,
                       color: NSColor(white: 0, alpha: 0.5).cgColor)
        ctx.addPath(CGPath(ellipseIn: rect, transform: nil))
        ctx.setFillColor(isHovered ? NSColor.systemRed.cgColor
                                   : CGColor(gray: 0.18, alpha: 0.9))
        ctx.fillPath()
        ctx.restoreGState()
        let xInset = rect.width * 0.3
        let xRect = rect.insetBy(dx: xInset, dy: xInset)
        let xPath = NSBezierPath()
        xPath.move(to: NSPoint(x: xRect.minX, y: xRect.minY))
        xPath.line(to: NSPoint(x: xRect.maxX, y: xRect.maxY))
        xPath.move(to: NSPoint(x: xRect.maxX, y: xRect.minY))
        xPath.line(to: NSPoint(x: xRect.minX, y: xRect.maxY))
        xPath.lineWidth = 1.5; xPath.lineCapStyle = .round
        NSColor.white.setStroke(); xPath.stroke()
    }
}
