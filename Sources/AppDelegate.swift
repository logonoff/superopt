import Cocoa
import ServiceManagement

func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
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
        return nil // consume the event
    }
    return Unmanaged.passUnretained(event)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var eventTap: CFMachPort?
    private var statusItem: NSStatusItem!

    private let optionKeyHandler = OptionKeyHandler()
    private let hotCorner = HotCorner()
    private let rippleAnimation = RippleAnimation()
    private let dockLauncher = DockLauncher()
    private let lockKeyOSD = LockKeyOSD()
    private let homeEndHandler = HomeEndHandler()
    private let gnomeShortcutHandler = GnomeShortcutHandler()
    private let finderCutHandler = FinderCutHandler()
    private let middleClickPasteHandler = MiddleClickPasteHandler()
    private let zoomButtonHandler = ZoomButtonHandler()
    private let windowTilingHandler = WindowTilingHandler()
    private let scrollZoomHandler = ScrollZoomHandler()
    private let menuBarBackground = MenuBarBackground()
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
        "gnomeShortcutsEnabled": false,
        "finderCutEnabled": false,
        "middleClickPasteEnabled": false,
        "zoomButtonEnabled": false,
        "scrollZoomMode": ScrollZoomMode.off.rawValue,
        "dockFinderPosition": 1
    ]

    private func isEnabled(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    private func handleSettingChanged(_ key: String, _ value: Any) {
        switch key {
        case "hotCornersEnabled":
            hotCorner.enabled = value as? Bool ?? true
        case "menuBarBgEnabled":
            if value as? Bool == true { menuBarBackground.start() } else { menuBarBackground.stop() }
        case "gnomeDisabledShortcuts":
            gnomeShortcutHandler.reloadSettings()
        default:
            break
        }
    }

    private var dockFinderPosition: Int {
        UserDefaults.standard.integer(forKey: "dockFinderPosition")
    }

    // MARK: - App Lifecycle

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NSApplication.shared.abortModal()
        return .terminateNow
    }

    @objc func handleQuitAppleEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        exit(0)
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

        optionKeyHandler.onSinglePress = { [weak self] in
            guard let self = self, self.isEnabled("optSingleEnabled") else { return }
            self.triggerMissionControl()
        }
        optionKeyHandler.onDoublePress = { [weak self] in
            guard let self = self, self.isEnabled("optDoubleEnabled") else { return }
            self.triggerSpotlight()
        }

        hotCorner.onTrigger = { [weak self] screen in
            self?.rippleAnimation.play(onScreen: screen)
            self?.triggerMissionControl()
        }
        hotCorner.enabled = isEnabled("hotCornersEnabled")

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
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.accessibilityChanged()
        }
    }
    // MARK: - Event Tap

    private func setupEventTap() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
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
            if eventTap == nil { _ = setupEventTap() }
        } else {
            tearDownEventTap()
        }
    }

    func tearDownEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }
    // MARK: - Actions

    fileprivate func triggerMissionControl() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Mission Control"]
        try? task.run()
    }
    fileprivate func triggerSpotlight() {
        NSWorkspace.shared.open(URL(string: "spotlight://apps")!)
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

        let launchTitle = NSLocalizedString("Launch at Login", comment: "Menu item to toggle start at login")
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
        settingsWindow.show { [weak self] key, value in self?.handleSettingChanged(key, value) }
    }

    @objc private func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 8; style.alignment = .center
        let font = NSFont.systemFont(ofSize: 11)
        let credits = NSMutableAttributedString()
        let githubText = NSLocalizedString("GitHub", comment: "About panel link text")
        let githubURL = URL(string: "https://github.com/logonoff/superopt")!
        credits.append(NSAttributedString(string: githubText, attributes: [
            .font: font, .link: githubURL, .paragraphStyle: style
        ]))
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.version: "", .credits: credits])
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister(); sender.state = .off
            } else {
                try SMAppService.mainApp.register(); sender.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "Unable to Update Login Item", comment: "Alert title when login item registration fails")
            alert.informativeText = NSLocalizedString(
                "You can manage login items in System Settings → General → Login Items.",
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
    private static var numberKeyCodes: [Int64: Int] { // Virtual key codes 1–9
        [0x12: 1, 0x13: 2, 0x14: 3, 0x15: 4, 0x17: 5, 0x16: 6, 0x1A: 7, 0x1C: 8, 0x19: 9]
    }

    /// Returns true if the event should be consumed.
    @discardableResult
    func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .flagsChanged: handleFlagsChanged(event: event)
        case .keyDown: if handleKeyDown(event: event) { return true }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if handleMouseDown(type: type, event: event) { return true }
        case .mouseMoved: hotCorner.handleMouseMoved(event: event)
        case .scrollWheel:
            if KeyboardUtils.isBrowserApp()
                && scrollZoomHandler.handleScroll(event: event) { return true }
        default: break
        }
        return false
    }

    private func handleMouseDown(type: CGEventType, event: CGEvent) -> Bool {
        if type == .leftMouseDown && isEnabled("zoomButtonEnabled") && zoomButtonHandler.handleClick(event: event) {
            return true
        }
        if type == .otherMouseDown && isEnabled("middleClickPasteEnabled")
            && middleClickPasteHandler.handleMouseDown(event: event) {
            return true
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
        let onText = NSLocalizedString("⇪ Caps Lock On", comment: "OSD text when Caps Lock is enabled")
        let offText = NSLocalizedString("⇪ Caps Lock Off", comment: "OSD text when Caps Lock is disabled")
        lockKeyOSD.show(text: capsLockOn ? onText : offText, active: capsLockOn)
    }

    private func handleKeyDown(event: CGEvent) -> Bool {
        if KeyboardUtils.isSynthetic(event) { return false }
        if isEnabled("dockShortcutsEnabled") && event.flags.contains(.maskAlternate) {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if let number = AppDelegate.numberKeyCodes[keyCode] {
                let finderPos = dockFinderPosition
                let position = number == finderPos ? 1 : (number < finderPos ? number + 1 : number)
                optionKeyHandler.markOtherInput()
                dockLauncher.launch(position: position)
                return true
            }
        }
        if isEnabled("homeEndRemapEnabled") && homeEndHandler.handleKeyDown(event: event) { return true }
        if isEnabled("finderCutEnabled") && finderCutHandler.handleKeyDown(event: event) {
            optionKeyHandler.markOtherInput(); return true
        }
        if isEnabled("appGridEnabled") && event.flags.contains(.maskAlternate)
            && !event.flags.contains(.maskCommand) && !event.flags.contains(.maskControl) {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 0x00 { // Option+A → Spotlight Apps
                optionKeyHandler.markOtherInput()
                triggerSpotlight()
                return true
            }
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
