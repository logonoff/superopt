import Cocoa

struct SnapWindowItem {
    let pid: pid_t
    let windowID: UInt32
    let title: String
    let appName: String
    let icon: NSImage
}

@MainActor
class SnapAssistPanel {
    enum TileDirection { case left, right }

    private let panel: NSPanel
    private let backdrop: NSView
    private let glassView: NSGlassEffectView
    private let container: NSView
    let direction: TileDirection
    private(set) var items: [SnapWindowItem] = []
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?
    private var dismissTimer: Timer?
    private var windowCheckTimer: Timer?
    private var tiledWindowFrame: CGRect = .zero
    private var tiledPID: pid_t = -1
    private var onDismiss: (() -> Void)?
    var onWillTile: (() -> Void)?

    private static let itemHeight: CGFloat = 52
    private static let iconSize: CGFloat = 36
    private static let cellPadding: CGFloat = 8
    private static let containerPadding: CGFloat = 8

    init?(direction: TileDirection, screen: NSScreen, onDismiss: @escaping () -> Void) {
        self.direction = direction
        self.onDismiss = onDismiss

        tiledPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let tiledWID = Self.frontWindowID(pid: tiledPID)
        let candidates = Self.collectWindows(screen: screen, excludeWID: tiledWID)
        guard !candidates.isEmpty else { return nil }
        items = candidates
        tiledWindowFrame = Self.frontWindowFrame(pid: tiledPID)

        let freeFrame = Self.freeArea(
            direction: direction, screen: screen, tiledFrame: tiledWindowFrame)
        panel = Self.makePanel(frame: freeFrame)

        backdrop = NSView(frame: NSRect(origin: .zero, size: freeFrame.size))
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        panel.contentView = backdrop

        let cFrame = Self.containerFrame(itemCount: items.count, panelSize: freeFrame.size)
        let contentWrapper = NSView(frame: NSRect(origin: .zero, size: cFrame.size))
        glassView = NSGlassEffectView(frame: cFrame)
        glassView.style = .regular
        glassView.cornerRadius = 12
        glassView.contentView = contentWrapper
        container = contentWrapper
        backdrop.addSubview(glassView)

        addButtons(containerWidth: cFrame.width, containerHeight: cFrame.height)
        showAnimated()
        installMonitors()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        windowCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTiledWindow() }
        }
    }

    deinit {
        dismissTimer?.invalidate()
        windowCheckTimer?.invalidate()
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }
        if let obs = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    private func checkTiledWindow() {
        let currentFrame = Self.frontWindowFrame(pid: tiledPID)
        if currentFrame == .zero || currentFrame != tiledWindowFrame { dismiss() }
    }
    // MARK: - Panel setup
    private static func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        return panel
    }

    private func addButtons(containerWidth: CGFloat, containerHeight: CGFloat) {
        let btnWidth = containerWidth - Self.containerPadding * 2
        let startY = containerHeight - Self.containerPadding - Self.itemHeight
        for (index, item) in items.enumerated() {
            let originY = startY - CGFloat(index) * Self.itemHeight
            let btn = Self.makeButton(
                item: item, originY: originY, width: btnWidth)
            btn.target = self
            btn.action = #selector(itemClicked(_:))
            btn.tag = index
            container.addSubview(btn)
        }
    }

    private func showAnimated() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }
}
// MARK: - Window enumeration
extension SnapAssistPanel {
    private static func collectWindows(screen: NSScreen, excludeWID: UInt32) -> [SnapWindowItem] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let screenFrame = screen.frame
        let primaryHeight = KeyboardUtils.primaryScreenHeight()
        var result: [SnapWindowItem] = []
        var seenWIDs: Set<UInt32> = []

        for info in windowList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != myPID, wid != excludeWID, !seenWIDs.contains(wid),
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let originX = bounds["X"], let originY = bounds["Y"],
                  let winWidth = bounds["Width"], let winHeight = bounds["Height"],
                  winWidth > 100, winHeight > 100
            else { continue }

            let center = NSPoint(
                x: originX + winWidth / 2, y: primaryHeight - (originY + winHeight / 2))
            guard screenFrame.contains(center) else { continue }

            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            let appName = app.localizedName ?? ""
            let windowTitle = axWindowTitle(pid: pid, windowID: wid)
                ?? info[kCGWindowName as String] as? String ?? ""
            guard !appName.isEmpty || !windowTitle.isEmpty else { continue }

            seenWIDs.insert(wid)
            let icon = app.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
            result.append(SnapWindowItem(
                pid: pid, windowID: wid, title: windowTitle, appName: appName, icon: icon))
        }
        return result
    }

    private static func axWindowTitle(pid: pid_t, windowID: UInt32) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref)
        guard let windows = ref as? [AXUIElement],
              let getWindow = KeyboardUtils.axGetWindow else { return nil }
        for win in windows {
            var axWID: UInt32 = 0
            guard getWindow(win, &axWID) == 0, axWID == windowID else { continue }
            var titleRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
            return titleRef as? String
        }
        return nil
    }
}

// MARK: - Layout

extension SnapAssistPanel {
    fileprivate static func containerFrame(itemCount: Int, panelSize: NSSize) -> NSRect {
        let width: CGFloat = min(340, panelSize.width - 80)
        let contentHeight = CGFloat(itemCount) * itemHeight + containerPadding * 2
        let height = min(contentHeight, panelSize.height - 80)
        return NSRect(
            x: (panelSize.width - width) / 2,
            y: (panelSize.height - height) / 2,
            width: width, height: height)
    }

    fileprivate static func makeButton(
        item: SnapWindowItem, originY: CGFloat, width: CGFloat
    ) -> NSButton {
        let frame = NSRect(x: containerPadding, y: originY, width: width, height: itemHeight)
        let btn = HoverButton(frame: frame)
        btn.isBordered = false
        btn.bezelStyle = .inline
        btn.title = ""

        let imageView = NSImageView(frame: NSRect(
            x: cellPadding, y: (itemHeight - iconSize) / 2, width: iconSize, height: iconSize))
        imageView.image = item.icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        btn.addSubview(imageView)

        let labelX = cellPadding + iconSize + cellPadding
        let labelWidth = frame.width - iconSize - cellPadding * 3

        if item.title.isEmpty {
            let nameField = NSTextField(labelWithString: item.appName)
            nameField.font = .systemFont(ofSize: 13)
            nameField.textColor = .labelColor
            nameField.lineBreakMode = .byTruncatingTail
            nameField.frame = NSRect(
                x: labelX, y: (itemHeight - 18) / 2, width: labelWidth, height: 18)
            btn.addSubview(nameField)
        } else {
            let titleField = NSTextField(labelWithString: item.title)
            titleField.font = .systemFont(ofSize: 13)
            titleField.textColor = .labelColor
            titleField.lineBreakMode = .byTruncatingTail
            titleField.frame = NSRect(x: labelX, y: itemHeight / 2, width: labelWidth, height: 18)
            btn.addSubview(titleField)

            let appField = NSTextField(labelWithString: item.appName)
            appField.font = .systemFont(ofSize: 11)
            appField.textColor = .secondaryLabelColor
            appField.lineBreakMode = .byTruncatingTail
            appField.frame = NSRect(
                x: labelX, y: itemHeight / 2 - 18, width: labelWidth, height: 16)
            btn.addSubview(appField)
        }

        return btn
    }
}
// MARK: - Event monitors & dismiss
extension SnapAssistPanel {
    fileprivate func installMonitors() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { self?.dismiss() } }
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            let loc = event.locationInWindow
            let containerInPanel = self.backdrop.convert(self.glassView.frame, to: nil)
            if !containerInPanel.contains(loc) {
                self.dismiss()
                return nil
            }
            return event
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.dismiss() } }
    }

    func dismiss() {
        guard panel.isVisible else { return }
        dismissTimer?.invalidate(); dismissTimer = nil
        windowCheckTimer?.invalidate(); windowCheckTimer = nil
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
        if let obs = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appActivationObserver = nil
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel.orderOut(nil)
                self?.onDismiss?()
                self?.onDismiss = nil
            }
        })
    }
}
// MARK: - Geometry
extension SnapAssistPanel {
    fileprivate static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref)
        return ref.flatMap(KeyboardUtils.toAXElement)
    }

    fileprivate static func frontWindowID(pid: pid_t) -> UInt32 {
        guard let win = focusedWindow(pid: pid),
              let getWindow = KeyboardUtils.axGetWindow else { return 0 }
        var wid: UInt32 = 0
        return getWindow(win, &wid) == 0 ? wid : 0
    }

    fileprivate static func frontWindowFrame(pid: pid_t) -> CGRect {
        guard let win = focusedWindow(pid: pid) else { return .zero }
        var posRef: AnyObject?
        var sizeRef: AnyObject?
        AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef)
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let val = posRef.flatMap(KeyboardUtils.toAXValue) { AXValueGetValue(val, .cgPoint, &pos) }
        if let val = sizeRef.flatMap(KeyboardUtils.toAXValue) { AXValueGetValue(val, .cgSize, &size) }
        return CGRect(origin: pos, size: size)
    }

    fileprivate static func freeArea(
        direction: TileDirection, screen: NSScreen, tiledFrame: CGRect
    ) -> NSRect {
        let visible = screen.visibleFrame
        let tiledWidth = tiledFrame.width > 0 ? tiledFrame.width : visible.width / 2
        let freeWidth = visible.width - tiledWidth
        switch direction {
        case .left:
            return NSRect(x: visible.origin.x + tiledWidth, y: visible.origin.y,
                          width: freeWidth, height: visible.height)
        case .right:
            return NSRect(x: visible.origin.x, y: visible.origin.y,
                          width: freeWidth, height: visible.height)
        }
    }
}
