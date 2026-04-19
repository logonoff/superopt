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

    private let optionKeyHandler = OptionKeyHandler()
    private let hotCorner = HotCorner()
    private let rippleAnimation = RippleAnimation()
    private let dockLauncher = DockLauncher()
    private let lockKeyOSD = LockKeyOSD()
    private let homeEndHandler = HomeEndHandler()
    private let menuBarBackground = MenuBarBackground()
    private var lastCapsLockState = false

    // MARK: - Feature Toggles

    private static let features: [(title: String, key: String, defaultOn: Bool)] = [
        ("Opt → Mission Control",    "optSingleEnabled",     true),
        ("Opt Opt → Apps",           "optDoubleEnabled",     true),
        ("Hot Corner",               "hotCornersEnabled",    true),
        ("Opt+N → Dock App",         "dockShortcutsEnabled", true),
        ("Caps Lock OSD",            "lockKeyOSDEnabled",    true),
        ("Home/End → Line Start/End","homeEndRemapEnabled",  true),
        ("Dark Menu Bar",            "menuBarBgEnabled",     false),
    ]

    private var featureMenuItems: [String: NSMenuItem] = [:]
    private var dockFinderPositionMenuItem: NSMenuItem!

    private func isEnabled(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    private func setEnabled(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
        featureMenuItems[key]?.state = value ? .on : .off

        switch key {
        case "hotCornersEnabled":
            hotCorner.enabled = value
        case "dockShortcutsEnabled":
            dockFinderPositionMenuItem.isEnabled = value
        case "menuBarBgEnabled":
            if value { menuBarBackground.start() } else { menuBarBackground.stop() }
        default:
            break
        }
    }

    private var dockFinderPosition: Int {
        get { UserDefaults.standard.integer(forKey: "dockFinderPosition") }
        set {
            UserDefaults.standard.set(newValue, forKey: "dockFinderPosition")
            dockFinderPositionMenuItem.title = "  Finder Position: \(newValue)"
        }
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        var defaults: [String: Any] = ["dockFinderPosition": 1]
        for f in AppDelegate.features { defaults[f.key] = f.defaultOn }
        UserDefaults.standard.register(defaults: defaults)

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

        for (i, f) in AppDelegate.features.enumerated() {
            let item = NSMenuItem(title: f.title, action: #selector(toggleFeature(_:)), keyEquivalent: "")
            item.tag = i
            item.state = isEnabled(f.key) ? .on : .off
            featureMenuItems[f.key] = item
            menu.addItem(item)

            if f.key == "dockShortcutsEnabled" {
                dockFinderPositionMenuItem = NSMenuItem(title: "  Finder Position: \(dockFinderPosition)", action: nil, keyEquivalent: "")
                let positionSubmenu = NSMenu()
                for pos in 1...9 {
                    let posItem = NSMenuItem(title: "\(pos)", action: #selector(setFinderPosition(_:)), keyEquivalent: "")
                    posItem.tag = pos
                    posItem.state = (pos == dockFinderPosition) ? .on : .off
                    positionSubmenu.addItem(posItem)
                }
                dockFinderPositionMenuItem.submenu = positionSubmenu
                dockFinderPositionMenuItem.isEnabled = isEnabled("dockShortcutsEnabled")
                menu.addItem(dockFinderPositionMenuItem)
            }
        }

        let systemMenuBarBgOn = UserDefaults.standard.bool(forKey: "SLSMenuBarUseBlurredAppearance")
        if systemMenuBarBgOn {
            featureMenuItems["menuBarBgEnabled"]?.isEnabled = false
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Request Permissions...", action: #selector(requestPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About OptWin", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit OptWin", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleFeature(_ sender: NSMenuItem) {
        let f = AppDelegate.features[sender.tag]
        setEnabled(f.key, !isEnabled(f.key))
    }

    @objc private func setFinderPosition(_ sender: NSMenuItem) {
        dockFinderPosition = sender.tag
        for item in sender.menu!.items {
            item.state = (item.tag == sender.tag) ? .on : .off
        }
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
            if isEnabled("lockKeyOSDEnabled") {
                let capsLockOn = event.flags.contains(.maskAlphaShift)
                if capsLockOn != lastCapsLockState {
                    lastCapsLockState = capsLockOn
                    lockKeyOSD.show(text: capsLockOn ? "⇪ Caps Lock On" : "⇪ Caps Lock Off", active: capsLockOn)
                }
            }
        case .keyDown:
            if isEnabled("dockShortcutsEnabled") && event.flags.contains(.maskAlternate) {
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
            if isEnabled("homeEndRemapEnabled") && homeEndHandler.handleKeyDown(event: event) {
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
