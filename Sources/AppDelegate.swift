import Cocoa

func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = delegate.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
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
    private var hotCornerMenuItem: NSMenuItem!
    private var optSingleMenuItem: NSMenuItem!
    private var optDoubleMenuItem: NSMenuItem!
    private var dockShortcutsMenuItem: NSMenuItem!
    private var dockFinderPositionMenuItem: NSMenuItem!
    private var lockKeyOSDMenuItem: NSMenuItem!
    private var homeEndRemapMenuItem: NSMenuItem!
    private var menuBarBgMenuItem: NSMenuItem!

    private let optionKeyHandler = OptionKeyHandler()
    private let hotCorner = HotCorner()
    private let rippleAnimation = RippleAnimation()
    private let dockLauncher = DockLauncher()
    private let lockKeyOSD = LockKeyOSD()
    private let homeEndHandler = HomeEndHandler()
    private let menuBarBackground = MenuBarBackground()
    private var lastCapsLockState = false

    private var hotCornersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "hotCornersEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "hotCornersEnabled")
            hotCornerMenuItem.state = newValue ? .on : .off
            hotCorner.enabled = newValue
        }
    }

    private var optSingleEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "optSingleEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "optSingleEnabled")
            optSingleMenuItem.state = newValue ? .on : .off
        }
    }

    private var optDoubleEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "optDoubleEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "optDoubleEnabled")
            optDoubleMenuItem.state = newValue ? .on : .off
        }
    }

    private var dockShortcutsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "dockShortcutsEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "dockShortcutsEnabled")
            dockShortcutsMenuItem.state = newValue ? .on : .off
            dockFinderPositionMenuItem.isEnabled = newValue
        }
    }

    private var dockFinderPosition: Int {
        get { UserDefaults.standard.integer(forKey: "dockFinderPosition") }
        set {
            UserDefaults.standard.set(newValue, forKey: "dockFinderPosition")
            dockFinderPositionMenuItem.title = "  Finder Position: \(newValue)"
        }
    }

    private var lockKeyOSDEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "lockKeyOSDEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "lockKeyOSDEnabled")
            lockKeyOSDMenuItem.state = newValue ? .on : .off
        }
    }

    private var homeEndRemapEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "homeEndRemapEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "homeEndRemapEnabled")
            homeEndRemapMenuItem.state = newValue ? .on : .off
        }
    }

    private var menuBarBgEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "menuBarBgEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "menuBarBgEnabled")
            menuBarBgMenuItem.state = newValue ? .on : .off
            if newValue { menuBarBackground.start() } else { menuBarBackground.stop() }
        }
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "hotCornersEnabled": true,
            "optSingleEnabled": true,
            "optDoubleEnabled": true,
            "dockShortcutsEnabled": true,
            "dockFinderPosition": 1,
            "lockKeyOSDEnabled": true,
            "homeEndRemapEnabled": true,
            "menuBarBgEnabled": false,
        ])

        let systemMenuBarBg = UserDefaults.standard.bool(forKey: "SLSMenuBarUseBlurredAppearance")
        if menuBarBgEnabled && !systemMenuBarBg { menuBarBackground.start() }

        lastCapsLockState = NSEvent.modifierFlags.contains(.capsLock)

        optionKeyHandler.onSinglePress = { [weak self] in
            guard let self = self, self.optSingleEnabled else { return }
            self.triggerMissionControl()
        }
        optionKeyHandler.onDoublePress = { [weak self] in
            guard let self = self, self.optDoubleEnabled else { return }
            self.triggerSpotlight()
        }

        hotCorner.onTrigger = { [weak self] screen in
            self?.rippleAnimation.play(onScreen: screen)
            self?.triggerMissionControl()
        }
        hotCorner.enabled = hotCornersEnabled

        setupStatusItem()

        if !setupEventTap() {
            showAccessibilityAlert()
        }
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "⌥"
        }

        let menu = NSMenu()

        optSingleMenuItem = NSMenuItem(title: "Opt → Mission Control", action: #selector(toggleOptSingle), keyEquivalent: "")
        optSingleMenuItem.state = optSingleEnabled ? .on : .off
        menu.addItem(optSingleMenuItem)

        optDoubleMenuItem = NSMenuItem(title: "Opt Opt → Apps", action: #selector(toggleOptDouble), keyEquivalent: "")
        optDoubleMenuItem.state = optDoubleEnabled ? .on : .off
        menu.addItem(optDoubleMenuItem)

        hotCornerMenuItem = NSMenuItem(title: "Hot Corner", action: #selector(toggleHotCorners), keyEquivalent: "")
        hotCornerMenuItem.state = hotCornersEnabled ? .on : .off
        menu.addItem(hotCornerMenuItem)

        dockShortcutsMenuItem = NSMenuItem(title: "Opt+N → Dock App", action: #selector(toggleDockShortcuts), keyEquivalent: "")
        dockShortcutsMenuItem.state = dockShortcutsEnabled ? .on : .off
        menu.addItem(dockShortcutsMenuItem)

        dockFinderPositionMenuItem = NSMenuItem(title: "  Finder Position: \(dockFinderPosition)", action: nil, keyEquivalent: "")
        let positionSubmenu = NSMenu()
        for i in 1...9 {
            let item = NSMenuItem(title: "\(i)", action: #selector(setFinderPosition(_:)), keyEquivalent: "")
            item.tag = i
            item.state = (i == dockFinderPosition) ? .on : .off
            positionSubmenu.addItem(item)
        }
        dockFinderPositionMenuItem.submenu = positionSubmenu
        menu.addItem(dockFinderPositionMenuItem)

        lockKeyOSDMenuItem = NSMenuItem(title: "Caps Lock OSD", action: #selector(toggleLockKeyOSD), keyEquivalent: "")
        lockKeyOSDMenuItem.state = lockKeyOSDEnabled ? .on : .off
        menu.addItem(lockKeyOSDMenuItem)

        homeEndRemapMenuItem = NSMenuItem(title: "Home/End → Line Start/End", action: #selector(toggleHomeEndRemap), keyEquivalent: "")
        homeEndRemapMenuItem.state = homeEndRemapEnabled ? .on : .off
        menu.addItem(homeEndRemapMenuItem)

        let systemMenuBarBgOn = UserDefaults.standard.bool(forKey: "SLSMenuBarUseBlurredAppearance")
        menuBarBgMenuItem = NSMenuItem(title: "Dark Menu Bar", action: #selector(toggleMenuBarBg), keyEquivalent: "")
        menuBarBgMenuItem.state = menuBarBgEnabled ? .on : .off
        menuBarBgMenuItem.isEnabled = !systemMenuBarBgOn
        menu.addItem(menuBarBgMenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Request Permissions...", action: #selector(requestPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About OptWin", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit OptWin", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleOptSingle() {
        optSingleEnabled = !optSingleEnabled
    }

    @objc private func toggleOptDouble() {
        optDoubleEnabled = !optDoubleEnabled
    }

    @objc private func toggleHotCorners() {
        hotCornersEnabled = !hotCornersEnabled
    }

    @objc private func toggleDockShortcuts() {
        dockShortcutsEnabled = !dockShortcutsEnabled
    }

    @objc private func setFinderPosition(_ sender: NSMenuItem) {
        dockFinderPosition = sender.tag
        for item in sender.menu!.items {
            item.state = (item.tag == sender.tag) ? .on : .off
        }
    }

    @objc private func toggleLockKeyOSD() {
        lockKeyOSDEnabled = !lockKeyOSDEnabled
    }

    @objc private func toggleHomeEndRemap() {
        homeEndRemapEnabled = !homeEndRemapEnabled
    }

    @objc private func toggleMenuBarBg() {
        menuBarBgEnabled = !menuBarBgEnabled
    }

    @objc private func requestPermissions() {
        let trusted = AXIsProcessTrusted()
        let hasEventTap = eventTap != nil

        if trusted && hasEventTap {
            let alert = NSAlert()
            alert.messageText = "Permissions Granted"
            alert.informativeText = "OptWin already has all required permissions."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        var missing: [String] = []
        if !trusted { missing.append("Accessibility") }
        if !hasEventTap { missing.append("Input Monitoring") }

        let alert = NSAlert()
        alert.messageText = "Permissions Required"
        alert.informativeText = """
            OptWin needs the following permissions:

            \(missing.joined(separator: ", "))

            After granting, restart OptWin for changes to take effect.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Accessibility")
        alert.addButton(withTitle: "Open Input Monitoring")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        } else if response == .alertSecondButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .version: "",
            .credits: {
                let credits = NSMutableAttributedString()
                let font = NSFont.systemFont(ofSize: 11)
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.paragraphSpacing = 8
                paragraphStyle.alignment = .center

                credits.append(NSAttributedString(string: "GitHub\n", attributes: [
                    .font: font,
                    .link: URL(string: "https://github.com/logonoff/opt-win")!,
                    .paragraphStyle: paragraphStyle,
                ]))
                credits.append(NSAttributedString(string: "License: WTFPL v2", attributes: [
                    .font: font,
                    .paragraphStyle: paragraphStyle,
                ]))
                return credits
            }(),
        ])
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
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

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue").keyEquivalent = "\r"
        alert.addButton(withTitle: "Open Accessibility")
        alert.addButton(withTitle: "Open Input Monitoring")
        alert.addButton(withTitle: "Quit")

        while true {
            let trusted = AXIsProcessTrusted()

            var missing: [String] = []
            if !trusted { missing.append("Accessibility") }
            if eventTap == nil { missing.append("Input Monitoring") }

            if missing.isEmpty && setupEventTap() {
                alert.window.orderOut(nil)
                break
            }

            alert.messageText = "Permissions Required"
            alert.informativeText = """
                OptWin needs the following permissions:

                \(missing.joined(separator: ", "))

                Grant access in System Settings → Privacy & Security, then click Continue.
                """

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if setupEventTap() {
                    alert.window.orderOut(nil)
                    break
                }
            } else if response == .alertSecondButtonReturn {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                AXIsProcessTrustedWithOptions(options)
            } else if response == .alertThirdButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            } else {
                NSApplication.shared.terminate(nil)
                return
            }
        }
    }

    // MARK: - Event Routing

    // Virtual key codes for number keys 1–9
    private static let numberKeyCodes: [Int64: Int] = [
        0x12: 1, 0x13: 2, 0x14: 3, 0x15: 4, 0x17: 5,
        0x16: 6, 0x1A: 7, 0x1C: 8, 0x19: 9,
    ]

    /// Returns true if the event should be consumed (not passed through).
    @discardableResult
    func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .flagsChanged:
            optionKeyHandler.handleFlagsChanged(event: event)
            if lockKeyOSDEnabled {
                let capsLockOn = event.flags.contains(.maskAlphaShift)
                if capsLockOn != lastCapsLockState {
                    lastCapsLockState = capsLockOn
                    lockKeyOSD.show(text: capsLockOn ? "⇪ Caps Lock On" : "⇪ Caps Lock Off", active: capsLockOn)
                }
            }
        case .keyDown:
            if dockShortcutsEnabled && event.flags.contains(.maskAlternate) {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if let number = AppDelegate.numberKeyCodes[keyCode] {
                    let finderPos = dockFinderPosition
                    let position: Int
                    if number == finderPos {
                        position = 1 // this slot is Finder
                    } else if number < finderPos {
                        position = number + 1 // shift up to make room
                    } else {
                        position = number // unchanged
                    }
                    optionKeyHandler.markOtherInput()
                    dockLauncher.launch(position: position)
                    return true
                }
            }
            if homeEndRemapEnabled && homeEndHandler.handleKeyDown(event: event) {
                return true
            }
            optionKeyHandler.markOtherInput()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            optionKeyHandler.markOtherInput()
        case .mouseMoved:
            hotCorner.handleMouseMoved(event: event)
        default:
            break
        }
        return false
    }

    // MARK: - Actions

    private func triggerMissionControl() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Mission Control"]
        try? task.run()
    }

    private func triggerSpotlight() {
        NSWorkspace.shared.open(URL(string: "spotlight://apps")!)
    }
}
