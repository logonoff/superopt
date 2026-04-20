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
    private let gnomeShortcutHandler = GnomeShortcutHandler()
    private let finderCutHandler = FinderCutHandler()
    private let middleClickPasteHandler = MiddleClickPasteHandler()
    private let zoomButtonHandler = ZoomButtonHandler()
    private let menuBarBackground = MenuBarBackground()
    private let settingsWindow = SettingsWindowController()
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
        "gnomeShortcutsEnabled": false,
        "finderCutEnabled": false,
        "middleClickPasteEnabled": false,
        "zoomButtonEnabled": false,
        "dockFinderPosition": 1,
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

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        if !setupEventTap() {
            showAccessibilityAlert()
        }
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "⌥"
            button.setAccessibilityLabel("OptWin")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: NSLocalizedString("Settings...", comment: "Menu item to open settings window"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Request Permissions...", comment: "Menu item to check and request permissions"), action: #selector(requestPermissions), keyEquivalent: ""))
        let launchItem = NSMenuItem(title: NSLocalizedString("Launch at Login", comment: "Menu item to toggle start at login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)
        menu.addItem(NSMenuItem(title: NSLocalizedString("About OptWin", comment: "Menu item to show about panel"), action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("Quit OptWin", comment: "Menu item to quit the app"), action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        settingsWindow.show { [weak self] key, value in
            self?.handleSettingChanged(key, value)
        }
    }

    @objc private func requestPermissions() {
        let trusted = AXIsProcessTrusted()
        let hasEventTap = eventTap != nil

        if trusted && hasEventTap {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Permissions Granted", comment: "Alert title when all permissions are granted")
            alert.informativeText = NSLocalizedString("OptWin already has all required permissions.", comment: "Alert body when all permissions are granted")
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        var missing: [String] = []
        if !trusted { missing.append(NSLocalizedString("Accessibility", comment: "Permission name")) }
        if !hasEventTap { missing.append(NSLocalizedString("Input Monitoring", comment: "Permission name")) }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Permissions Required", comment: "Alert title for missing permissions")
        alert.informativeText = String(
            format: NSLocalizedString(
                "OptWin needs the following permissions:\n\n%@\n\nGrant access in System Settings → Privacy & Security, then click Continue. If you recently updated OptWin, you may need to remove and re-add it in each permission list.",
                comment: "Alert body for missing permissions — %@ is the list of missing permissions"),
            missing.joined(separator: ", "))
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Open Accessibility", comment: "Button to open Accessibility preferences"))
        alert.addButton(withTitle: NSLocalizedString("Open Input Monitoring", comment: "Button to open Input Monitoring preferences"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))

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

                credits.append(NSAttributedString(string: NSLocalizedString("GitHub", comment: "About panel link text") + "\n", attributes: [
                    .font: font,
                    .link: URL(string: "https://github.com/logonoff/opt-win")!,
                    .paragraphStyle: paragraphStyle,
                ]))
                credits.append(NSAttributedString(string: NSLocalizedString("License: WTFPL v2", comment: "About panel license text"), attributes: [
                    .font: font,
                    .paragraphStyle: paragraphStyle,
                ]))
                return credits
            }(),
        ])
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Unable to update login item", comment: "Alert title when login item registration fails")
            alert.informativeText = NSLocalizedString("You can manage login items in System Settings → General → Login Items.", comment: "Alert body directing user to login items settings")
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("Open Login Items", comment: "Button to open login items settings"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
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
        alert.addButton(withTitle: NSLocalizedString("Continue", comment: "Button to retry after granting permissions")).keyEquivalent = "\r"
        alert.addButton(withTitle: NSLocalizedString("Open Accessibility", comment: "Button to open Accessibility preferences"))
        alert.addButton(withTitle: NSLocalizedString("Open Input Monitoring", comment: "Button to open Input Monitoring preferences"))
        alert.addButton(withTitle: NSLocalizedString("Quit", comment: "Button to quit the app"))

        while true {
            let trusted = AXIsProcessTrusted()

            var missing: [String] = []
            if !trusted { missing.append(NSLocalizedString("Accessibility", comment: "Permission name")) }
            if eventTap == nil { missing.append(NSLocalizedString("Input Monitoring", comment: "Permission name")) }

            if missing.isEmpty && setupEventTap() {
                alert.window.orderOut(nil)
                break
            }

            alert.messageText = NSLocalizedString("Permissions Required", comment: "Alert title for missing permissions")
            alert.informativeText = String(
                format: NSLocalizedString(
                    "OptWin needs the following permissions:\n\n%@\n\nGrant access in System Settings → Privacy & Security, then click Continue. If you recently updated OptWin, you may need to remove and re-add it in each permission list.",
                    comment: "Alert body for missing permissions — %@ is the list of missing permissions"),
                missing.joined(separator: ", "))

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
                    lockKeyOSD.show(text: capsLockOn
                        ? NSLocalizedString("⇪ Caps Lock On", comment: "OSD text when Caps Lock is enabled")
                        : NSLocalizedString("⇪ Caps Lock Off", comment: "OSD text when Caps Lock is disabled"),
                        active: capsLockOn)
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
            if isEnabled("finderCutEnabled") && finderCutHandler.handleKeyDown(event: event) {
                optionKeyHandler.markOtherInput()
                return true
            }
            if isEnabled("gnomeShortcutsEnabled") && gnomeShortcutHandler.handleKeyDown(event: event) {
                optionKeyHandler.markOtherInput()
                return true
            }
            optionKeyHandler.markOtherInput()
        case .leftMouseDown:
            if isEnabled("zoomButtonEnabled") && zoomButtonHandler.handleClick(event: event) {
                return true
            }
            optionKeyHandler.markOtherInput()
        case .rightMouseDown:
            optionKeyHandler.markOtherInput()
        case .otherMouseDown:
            if isEnabled("middleClickPasteEnabled") && middleClickPasteHandler.handleMouseDown(event: event) {
                return true
            }
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
