import Cocoa

struct SnapWindowItem {
    let pid: pid_t
    let windowID: UInt32
    let title: String
    let appName: String
    let icon: NSImage
}

/// The window that just tiled, as the watcher knows it. The panel would
/// otherwise re-identify it from the frontmost app at popup time — half a
/// second after the tile, by which point focus may have moved elsewhere and
/// the wrong window measured, excluded, and dismissed against.
struct TiledWindowInfo {
    let pid: pid_t
    let windowID: UInt32
    let frame: CGRect
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
    private var globalClickMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?
    private var dismissTimer: Timer?
    private var windowCheckTimer: Timer?
    private var tiledWindowFrame: CGRect = .zero
    private var tiledWindowID: UInt32 = 0
    private var tiledPID: pid_t = -1
    private var onDismiss: (() -> Void)?
    var onWillTile: (() -> Void)?

    private static let itemHeight: CGFloat = 52
    private static let iconSize: CGFloat = 36
    private static let cellPadding: CGFloat = 8
    private static let containerPadding: CGFloat = 8
    /// The margin containerFrame and capacity leave around the container.
    private static let panelMargin: CGFloat = 80
    /// The smallest free area the popup is offered for. Width: the panel
    /// margin plus a container wide enough for the icon, its cell paddings,
    /// and a truncated label — the sliver a near-full-width window leaves
    /// when the watcher mistakes it for half-tiled has nothing worth
    /// offering anyway. Height: one row with its padding plus the panel
    /// margin; freeArea always hands the panel the screen's full visible
    /// height, so that floor is defensive.
    private static let minFreeWidth: CGFloat = 180 + panelMargin
    private static let minFreeHeight: CGFloat = itemHeight + containerPadding * 2 + panelMargin

    init?(direction: TileDirection, screen: NSScreen, tiled: TiledWindowInfo,
          onDismiss: @escaping () -> Void) {
        self.direction = direction
        self.onDismiss = onDismiss

        tiledPID = tiled.pid
        tiledWindowFrame = tiled.frame
        tiledWindowID = tiled.windowID
        let freeFrame = Self.freeArea(
            direction: direction, screen: screen, tiledFrame: tiledWindowFrame)
        // Below the minimums containerFrame's min(_, size − margin) goes
        // negative (a narrow sliver's width) or, defensively, leaves no
        // room for even one row (height — freeArea always returns the
        // screen's full visible height).
        guard freeFrame.width >= Self.minFreeWidth,
              freeFrame.height >= Self.minFreeHeight
        else { return nil }
        let candidates = Self.collectWindows(
            screen: screen, excludeWID: tiled.windowID,
            excludePID: tiled.pid, excludeFrame: tiled.frame)
        // More windows than the container has height for would lay out
        // buttons below the glass, outside the panel frame entirely.
        let maxItems = Self.capacity(panelHeight: freeFrame.height)
        items = Array(candidates.prefix(maxItems))
        guard !items.isEmpty else { return nil }
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
        // Registration success is not delivery — the Dock has accepted AX
        // notifications that never arrived (measured, see AGENTS.md) — and a
        // failed focused-window read inside the watcher deafens it until the
        // next focus change. The poll stays as a backstop at its original
        // rate: the panel lives at most five seconds, so there is no
        // steady-state cost for a slower cadence to save.
        windowCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTiledWindow() }
        }
    }

    deinit {
        dismissTimer?.invalidate()
        windowCheckTimer?.invalidate()
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor) }
        if let obs = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    private func checkTiledWindow() {
        // A failed AX read reports .zero — not evidence the window moved or
        // closed — and a tiled frame of .zero (the identity never resolved)
        // cannot be compared. Dismissing on either would kill the popup
        // whenever the app is briefly unresponsive; the 5-second timeout
        // covers a window that really is gone.
        let currentFrame = Self.frontWindowFrame(pid: tiledPID)
        // Identity, not just geometry: two windows of the tiled app can share
        // a frame, and a focus change between them is invisible to the frame
        // check below. The event path dismisses on the same identity change.
        if tiledWindowID != 0,
           let focused = KeyboardUtils.focusedWindowID(pid: tiledPID),
           focused != tiledWindowID {
            dismiss()
            return
        }
        guard currentFrame != .zero, tiledWindowFrame != .zero,
              currentFrame != tiledWindowFrame
        else { return }
        dismiss()
    }

    /// A nil frame denotes a change of focused window within the tiled app.
    func tiledWindowDidChange(pid: pid_t, frame: CGRect?) {
        guard pid == tiledPID, frame != tiledWindowFrame else { return }
        dismiss()
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

    /// Bumped by dismiss, so a pending fade-in fallback cannot land after a
    /// dismissal has started (the panel stays "visible" through its own
    /// fade-out).
    private var fadeGeneration = 0

    private func showAnimated() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let generation = fadeGeneration
        var landed = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }, completionHandler: {
            MainActor.assumeIsolated { landed = true }
        })
        // The completion of a group whose animation never starts is never
        // delivered (measured in this app — see OSDPanel, which carries the
        // same fallback), and an invisible window still eats clicks through
        // its backdrop for the 5 s timeout, so land the fade directly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible, !landed,
                      self.fadeGeneration == generation else { return }
                self.panel.alphaValue = 1
            }
        }
    }
}
// MARK: - Layout

extension SnapAssistPanel {
    fileprivate static func containerFrame(itemCount: Int, panelSize: NSSize) -> NSRect {
        let width: CGFloat = min(340, panelSize.width - panelMargin)
        let contentHeight = CGFloat(itemCount) * itemHeight + containerPadding * 2
        let height = min(contentHeight, panelSize.height - panelMargin)
        return NSRect(
            x: (panelSize.width - width) / 2,
            y: (panelSize.height - height) / 2,
            width: width, height: height)
    }

    /// How many item rows fit in a panel of this height — the container caps
    /// at `panelSize.height - panelMargin`, and buttons laid out past that
    /// would draw outside the glass entirely.
    fileprivate static func capacity(panelHeight: CGFloat) -> Int {
        max(1, Int((panelHeight - panelMargin - containerPadding * 2) / itemHeight))
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
            // A click in another of this app's windows (settings, the
            // permission dialog) goes through rather than being consumed as
            // an outside click — it still dismisses the popup.
            if event.window !== self.panel {
                self.dismiss()
                return event
            }
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
        // Clicks in other apps' windows never reach the local monitor, and a
        // click on the tiled window changes neither the frontmost app nor the
        // window's frame — the documented "clicking outside" dismissal needs
        // a global monitor to see them.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func dismiss() {
        guard dismissTimer != nil else { return }
        fadeGeneration += 1
        dismissTimer?.invalidate(); dismissTimer = nil
        windowCheckTimer?.invalidate(); windowCheckTimer = nil
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor); globalClickMonitor = nil }
        if let obs = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appActivationObserver = nil
        }
        let panelWindow = panel
        // No completion handler: one handed to a group whose animation never
        // starts is retained forever, holding the window with it (measured —
        // the OSDPanel finding). The delayed block below is the sole
        // deliverer, which is OSDPanel's own workaround for exactly this.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panelWindow.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                panelWindow.alphaValue = 0
                panelWindow.orderOut(nil)
                self?.onDismiss?()
                self?.onDismiss = nil
            }
        }
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

    fileprivate static func frontWindowFrame(pid: pid_t) -> CGRect {
        guard let win = focusedWindow(pid: pid) else { return .zero }
        return KeyboardUtils.axWindowFrame(win)
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
