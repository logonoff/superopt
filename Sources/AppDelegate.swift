// This getting long is mostly due to the features needing to be handled in one file
// swiftlint:disable file_length
import Cocoa
import ServiceManagement

func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }

    return MainActor.assumeIsolated {
        let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if AXIsProcessTrusted(), let tap = delegate.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                delegate.tearDownEventTap()
            }
            return Unmanaged.passUnretained(event)
        }

        if delegate.handleEvent(type: type, event: event) {
            if KeyboardUtils.isSynthetic(event) {
                return Unmanaged.passUnretained(event) // rewritten in-place
            }
            return nil // consume the event
        }
        return Unmanaged.passUnretained(event)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var eventTap: CFMachPort?
    private var statusItem: NSStatusItem!
    private var safetyTimer: Timer?

    private let optionKeyHandler = OptionKeyHandler()
    private let hotCorner = HotCorner()
    private let rippleAnimation = RippleAnimation()
    private let dockLauncher = DockLauncher()
    private let lockKeyOSD = LockKeyOSD()
    private let homeEndHandler = HomeEndHandler()
    private let gnomeShortcutHandler = GnomeShortcutHandler()
    private let finderCutHandler = FinderCutHandler()
    private let middleClickPasteHandler = MiddleClickPasteHandler()
    private let clickThroughFocusHandler = ClickThroughFocusHandler()
    private let zoomButtonHandler = ZoomButtonHandler()
    private let windowTilingHandler = WindowTilingHandler()
    private let scrollZoomHandler = ScrollZoomHandler()
    private let menuKeyHandler = MenuKeyHandler()
    private let menuBarBackground = MenuBarBackground()
    private let mcMonitor = MissionControlMonitor()
    private lazy var mcCloseHandler = MissionControlCloseHandler(monitor: mcMonitor)
    private lazy var mcSearchHandler = MissionControlSearchHandler(monitor: mcMonitor)
    private var snapAssistPanel: SnapAssistPanel?
    private let tileAssistWatcher = TileAssistWatcher()
    private let settingsWindow = SettingsWindowController()
    private let permissionHelper = PermissionHelper()
    private var lastCapsLockState = false

    // MARK: - Preferences

    private static let defaultPreferences: [String: Any] = [
        "optSingleEnabled": true,
        "optDoubleEnabled": true,
        "hotCornersEnabled": true,
        "dockShortcutsEnabled": true,
        "lockKeyOSDEnabled": true,
        "homeEndRemapEnabled": true,
        "menuBarBgEnabled": false,
        "appGridEnabled": true,
        "windowTilingEnabled": false,
        "snapAssistEnabled": false,
        "gnomeShortcutsEnabled": false,
        "vscodeTerminalEnabled": false,
        "finderCutMode": FinderCutMode.off.rawValue,
        "middleClickPasteEnabled": false,
        "clickThroughFocusEnabled": false,
        "zoomButtonEnabled": false,
        "menuKeyRightClickEnabled": false,
        "mcCloseEnabled": true,
        "mcTypeToSearchMode": MissionControlSearchMode.off.rawValue,
        "scrollZoomMode": ScrollZoomMode.off.rawValue,
        "dockFinderPosition": 1
    ]

    private func isEnabled(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    @objc private func defaultsChanged() {
        hotCorner.enabled = isEnabled("hotCornersEnabled")
        let wantsBg = isEnabled("menuBarBgEnabled")
            && !UserDefaults.standard.bool(forKey: "SLSMenuBarUseBlurredAppearance")
        if wantsBg { menuBarBackground.start() } else { menuBarBackground.stop() }
        gnomeShortcutHandler.reloadSettings()
        scrollZoomHandler.reloadSettings()
        finderCutHandler.reloadSettings()
        mcSearchHandler.reloadSettings()
        if isEnabled("mcCloseEnabled") {
            mcCloseHandler?.start()
        } else { mcCloseHandler?.stop() }
        updateMissionControlMonitor()
        if isEnabled("snapAssistEnabled") {
            tileAssistWatcher.start()
        } else { tileAssistWatcher.stop() }
        if !isEnabled("clickThroughFocusEnabled") { clickThroughFocusHandler.reset() }
    }

    /// The monitor is shared, so it runs whenever any feature that needs to know
    /// about Mission Control is on, and not at all otherwise.
    private func updateMissionControlMonitor() {
        if isEnabled("mcCloseEnabled") || mcSearchHandler.isEnabled {
            mcMonitor.start()
        } else { mcMonitor.stop() }
    }

    private var dockFinderPosition: Int { UserDefaults.standard.integer(forKey: "dockFinderPosition") }

    // MARK: - App Lifecycle
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NSApplication.shared.abortModal(); return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    @objc func handleQuitAppleEvent(_: NSAppleEventDescriptor, withReply _: NSAppleEventDescriptor) {
        NSApplication.shared.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app can quit even when a modal dialog is blocking the run loop
        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource.setEventHandler { exit(0) }
        termSource.resume()
        signal(SIGTERM, SIG_IGN)

        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleQuitAppleEvent(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication)
        )
        UserDefaults.standard.register(defaults: AppDelegate.defaultPreferences)

        let systemMenuBarBg = UserDefaults.standard.bool(forKey: "SLSMenuBarUseBlurredAppearance")
        if isEnabled("menuBarBgEnabled") && !systemMenuBarBg { menuBarBackground.start() }

        lastCapsLockState = NSEvent.modifierFlags.contains(.capsLock)

        if isEnabled("mcCloseEnabled") { mcCloseHandler?.start() }
        updateMissionControlMonitor()
        setupCallbacks()
        hotCorner.enabled = isEnabled("hotCornersEnabled")

        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification, object: nil
        )

        setupStatusItem()

        permissionHelper.hasEventTap = { [weak self] in self?.eventTap != nil }
        permissionHelper.trySetupEventTap = { [weak self] in self?.setupEventTap() ?? false }

        if !setupEventTap() {
            permissionHelper.showPermissionLoop()
        }

        // React to Accessibility permission changes
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(accessibilityChanged),
            name: NSNotification.Name("com.apple.accessibility.api"), object: nil
        )

        // Safety net: periodically verify permissions in case the notification doesn't fire
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibilityChanged() }
        }
    }

    func applicationWillTerminate(_: Notification) {
        safetyTimer?.invalidate(); tearDownEventTap(); mcCloseHandler?.stop(); mcMonitor.stop()
        DistributedNotificationCenter.default().removeObserver(self)
    }
    // MARK: - Event Tap
    private func setupEventTap() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            return false
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    @objc private func accessibilityChanged() {
        if AXIsProcessTrusted() {
            if eventTap == nil && setupEventTap() {
                safetyTimer?.invalidate()
                safetyTimer = nil
            }
        } else {
            tearDownEventTap()
            if safetyTimer == nil {
                safetyTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.accessibilityChanged() }
                }
            }
        }
    }

    func tearDownEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        eventTap = nil
    }
    // MARK: - Actions

    /// Virtual key code emitted by the Mission Control key — a dedicated feature key,
    /// not the F3 function key, which is code 99. Which F-position it shares varies by
    /// keyboard model, so the code is the only stable way to name it.
    private static let missionControlKeyCode: Int64 = 160

    fileprivate func triggerMissionControl() {
        // Emulate the Mission Control key rather than spawning `open -a "Mission Control"`:
        // no subprocess, and it does exactly what the hardware key does. Key code
        // 160 needs the Fn flag set — without it the key does nothing. Like the
        // real key, this toggles.
        KeyboardUtils.postKey(Self.missionControlKeyCode, flags: .maskSecondaryFn)
        // The synthetic key is skipped by handleKeyDown, so flag it from here.
        mcMonitor.noteTrigger()
    }
    private func setupCallbacks() {
        tileAssistWatcher.onTile = { [weak self] dir, screen in
            self?.showSnapAssist(direction: dir, screen: screen)
        }
        tileAssistWatcher.isPanelVisible = { [weak self] in
            self?.snapAssistPanel != nil
        }
        if isEnabled("snapAssistEnabled") { tileAssistWatcher.start() }
        optionKeyHandler.onSinglePress = { [weak self] in
            guard let self, isEnabled("optSingleEnabled") else { return }
            triggerMissionControl()
        }
        optionKeyHandler.onDoublePress = { [weak self] in
            guard let self, isEnabled("optDoubleEnabled") else { return }
            triggerSpotlight()
        }
        hotCorner.onTrigger = { [weak self] screen in
            self?.rippleAnimation.play(onScreen: screen)
            self?.triggerMissionControl()
        }
        // The Mission Control key toggles, so the same key that opens Mission Control closes it.
        // The close-button handler is already polling and notices on its next tick.
        mcSearchHandler.dismissMissionControl = {
            KeyboardUtils.postKey(Self.missionControlKeyCode, flags: .maskSecondaryFn)
        }
    }

    /// Virtual key code emitted by the Apps key (formerly Launchpad) on Apple keyboards.
    /// macOS routes it to the Spotlight Apps view now that Launchpad is gone. A
    /// dedicated feature key, not the F4 function key, which is code 118.
    private static let launchPanelKeyCode: Int64 = 131

    fileprivate func triggerSpotlight() {
        // Emulate the Apps key rather than opening spotlight://apps: on macOS 27 the
        // Spotlight UI moved into Siri AI, whose spotlight: LaunchServices claim is
        // flagged apple-internal, so NSWorkspace.open(_:) fails with
        // kLSApplicationNotFoundErr. The Apps key emits key code 131 with the Fn flag set —
        // without Fn the key does nothing. Like the real key, this toggles.
        KeyboardUtils.postKey(Self.launchPanelKeyCode, flags: .maskSecondaryFn)
    }
    fileprivate func showSnapAssist(
        direction: SnapAssistPanel.TileDirection, screen: NSScreen
    ) {
        snapAssistPanel?.dismiss()
        let panel = SnapAssistPanel(
            direction: direction, screen: screen) { [weak self] in
                self?.snapAssistPanel = nil
            }
        panel?.onWillTile = { [weak self] in self?.tileAssistWatcher.suppress() }
        snapAssistPanel = panel
    }
}

// MARK: - Status Bar
extension AppDelegate {
    fileprivate func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "⌥"
            button.setAccessibilityLabel("SuperOpt")
        }

        let menu = NSMenu()
        let settingsTitle = NSLocalizedString("Settings\u{2026}", comment: "Menu item to open settings window")
        menu.addItem(NSMenuItem(title: settingsTitle, action: #selector(openSettings), keyEquivalent: ","))

        let permTitle = NSLocalizedString(
            "Request Permissions\u{2026}", comment: "Menu item to check and request permissions")
        menu.addItem(NSMenuItem(
            title: permTitle, action: #selector(requestPermissions), keyEquivalent: ""))

        let launchTitle = NSLocalizedString("Open at Login", comment: "Menu item for starting the app at login")
        let launchItem = NSMenuItem(title: launchTitle, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        let aboutTitle = NSLocalizedString("About SuperOpt", comment: "Menu item to show about panel")
        menu.addItem(NSMenuItem(title: aboutTitle, action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let quitTitle = NSLocalizedString("Quit SuperOpt", comment: "Menu item to quit the app")
        menu.addItem(NSMenuItem(title: quitTitle, action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func requestPermissions() {
        permissionHelper.requestPermissions()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func showAbout() {
        NSApplication.shared.activate()
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 8; style.alignment = .center
        let font = NSFont.systemFont(ofSize: 11)
        let credits = NSMutableAttributedString()
        let githubText = NSLocalizedString("GitHub", comment: "About panel link text")
        guard let githubURL = URL(string: "https://github.com/logonoff/superopt") else { return }
        credits.append(NSAttributedString(string: githubText, attributes: [
            .font: font, .link: githubURL, .paragraphStyle: style
        ]))
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.version: "", .credits: credits])
        NSApp.keyWindow?.orderFrontRegardless()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister(); sender.state = .off
            } else {
                try SMAppService.mainApp.register(); sender.state = .on
            }
        } catch {
            NSLog("SuperOpt: failed to update login item: %@", error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "Unable to Update Login Item", comment: "Alert title when login item registration fails")
            alert.informativeText = NSLocalizedString(
                "You can manage login items in System Settings > General > Login Items.",
                comment: "Alert body directing user to login items settings")
            alert.alertStyle = .warning
            let openTitle = NSLocalizedString("Open Login Items", comment: "Button to open login items settings")
            alert.addButton(withTitle: openTitle)
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
            if alert.runModal() == .alertFirstButtonReturn {
                let url = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
                if let url = URL(string: url) { NSWorkspace.shared.open(url) }
            }
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

// MARK: - Event Routing
extension AppDelegate {
    /// Returns true if the event should be consumed.
    @discardableResult
    func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .flagsChanged: handleFlagsChanged(event: event)
        case .keyDown: return handleKeyDown(event: event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return handleMouseDown(type: type, event: event)
        case .leftMouseUp: return handleMouseUp(event: event)
        case .mouseMoved: return handleMouseMoved(event: event)
        case .scrollWheel: return handleScroll(event: event)
        default: break
        }
        return false
    }

    private func handleMouseUp(event: CGEvent) -> Bool {
        isEnabled("clickThroughFocusEnabled") && clickThroughFocusHandler.handleMouseUp(event: event)
    }

    private func handleScroll(event: CGEvent) -> Bool {
        KeyboardUtils.isBrowserApp() && scrollZoomHandler.handleScroll(event: event)
    }

    private func handleMouseMoved(event: CGEvent) -> Bool {
        hotCorner.handleMouseMoved(event: event)
        return isEnabled("mcCloseEnabled") && mcCloseHandler?.handleMouseMoved(event: event) == true
    }

    private func handleMouseDown(type: CGEventType, event: CGEvent) -> Bool {
        if type == .leftMouseDown {
            if isEnabled("mcCloseEnabled") && mcCloseHandler?.handleClick(event: event) == true {
                optionKeyHandler.markOtherInput(); return true
            }
            if isEnabled("zoomButtonEnabled") && zoomButtonHandler.handleClick(event: event) {
                optionKeyHandler.markOtherInput(); return true
            }
            if isEnabled("clickThroughFocusEnabled")
                && clickThroughFocusHandler.handleMouseDown(event: event) {
                optionKeyHandler.markOtherInput(); return true
            }
        }
        if type == .otherMouseDown && isEnabled("middleClickPasteEnabled")
            && middleClickPasteHandler.handleMouseDown(event: event) {
            optionKeyHandler.markOtherInput(); return true
        }
        optionKeyHandler.markOtherInput()
        return false
    }

    private func handleFlagsChanged(event: CGEvent) {
        optionKeyHandler.handleFlagsChanged(event: event)
        guard isEnabled("lockKeyOSDEnabled") else { return }
        let capsLockOn = event.flags.contains(.maskAlphaShift)
        guard capsLockOn != lastCapsLockState else { return }
        lastCapsLockState = capsLockOn
        let onText = NSLocalizedString("⇪ Caps Lock On", comment: "OSD text when Caps Lock is turned on")
        let offText = NSLocalizedString("⇪ Caps Lock Off", comment: "OSD text when Caps Lock is turned off")
        lockKeyOSD.show(text: capsLockOn ? onText : offText, active: capsLockOn)
    }

    /// ⌥A → Spotlight Apps. Its own feature toggle, separate from shortcut remapping.
    private func handleAppGridKey(event: CGEvent) -> Bool {
        guard isEnabled("appGridEnabled"),
              event.flags.contains(.maskAlternate),
              !event.flags.contains(.maskCommand),
              !event.flags.contains(.maskControl),
              event.getIntegerValueField(.keyboardEventKeycode) == 0x00
        else { return false }
        triggerSpotlight()
        return true
    }

    private func handleKeyDown(event: CGEvent) -> Bool {
        if KeyboardUtils.isSynthetic(event) { return false }
        // Not consumed — just tells the close-button handler to start looking for
        // Mission Control, since opening it from the keyboard moves no mouse.
        if event.getIntegerValueField(.keyboardEventKeycode) == Self.missionControlKeyCode {
            mcMonitor.noteTrigger()
        }
        if mcSearchHandler.handleKeyDown(event: event) {
            optionKeyHandler.markOtherInput(); return true
        }
        if isEnabled("dockShortcutsEnabled")
            && dockLauncher.handleKeyDown(event: event, finderPosition: dockFinderPosition) {
            optionKeyHandler.markOtherInput(); return true
        }
        if isEnabled("menuKeyRightClickEnabled") && menuKeyHandler.handleKeyDown(event: event) { return true }
        if isEnabled("homeEndRemapEnabled") && homeEndHandler.handleKeyDown(event: event) { return true }
        if finderCutHandler.handleKeyDown(event: event) {
            optionKeyHandler.markOtherInput(); return true
        }
        if handleAppGridKey(event: event) {
            optionKeyHandler.markOtherInput(); return true
        }
        if isEnabled("windowTilingEnabled") && windowTilingHandler.handleKeyDown(event: event) {
            optionKeyHandler.markOtherInput(); return true
        }
        if isEnabled("gnomeShortcutsEnabled") && gnomeShortcutHandler.handleKeyDown(event: event) {
            optionKeyHandler.markOtherInput(); return true
        }
        optionKeyHandler.markOtherInput()
        return false
    }
}
