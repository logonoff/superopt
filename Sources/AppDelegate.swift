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
            // Both branches route through accessibilityChanged: it re-enables
            // or tears down the tap, verifies the result, and arms the safety
            // timer when the tap cannot be brought back. The callback itself
            // must not leave a state that nothing else will retry.
            delegate.accessibilityChanged()
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

/// The Caps Lock OSD's status strings, localized once.
private enum CapsLockOSDText {
    static let turnedOn = NSLocalizedString("Caps Lock On", comment: "OSD text when Caps Lock is turned on")
    static let turnedOff = NSLocalizedString("Caps Lock Off", comment: "OSD text when Caps Lock is turned off")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
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
    private let spaceScrollHandler = SpaceScrollHandler()
    private let spaceIndicator = SpaceSwitcherOSD()
    private let spaceChangeWatcher = SpaceChangeWatcher()
    private let menuKeyHandler = MenuKeyHandler()
    private let menuBarBackground = MenuBarBackground()
    private let dynamicSpaces = DynamicSpacesHandler()
    private let mcMonitor = MissionControlMonitor()
    private lazy var mcCloseHandler = MissionControlCloseHandler(monitor: mcMonitor)
    private lazy var mcSearchHandler = MissionControlSearchHandler(monitor: mcMonitor)
    private var snapAssistPanel: SnapAssistPanel?
    private let tileAssistWatcher = TileAssistWatcher()
    /// Held for the process lifetime: a released source is cancelled, and
    /// `signal(SIGTERM, SIG_IGN)` would then be the only disposition left.
    private var sigtermSource: DispatchSourceSignal?
    private let settingsWindow = SettingsWindowController()
    private let permissionHelper = PermissionHelper()
    private let excludedApps = ExcludedApps()
    private var lastCapsLockState = false
    /// Kept so menuNeedsUpdate can refresh the checkmark.
    private var launchMenuItem: NSMenuItem?
    /// Whether the last left press was consumed as a Mission Control
    /// close-button hit — its release must not re-stamp the search
    /// suppression, so closing a window in Mission Control stays searchable.
    private var closeButtonPress = false

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
        "spaceScrollEnabled": false,
        "spaceIndicatorEnabled": false,
        "dynamicSpacesEnabled": false,
        "excludedAppsEnabled": false,
        "dockFinderPosition": 1
    ]

    /// A feature is on when the user turned it on and the active app is not one of the
    /// apps they excluded.
    private func isEnabled(_ key: String) -> Bool {
        !excludedApps.isSuspended && UserDefaults.standard.bool(forKey: key)
    }

    @objc private func defaultsChanged() { defaultsChanged(activatedApp: nil) }

    /// `activatedApp` is the app named by the activation notification when
    /// this runs from inside one (the exclusion transition), nil otherwise.
    /// `frontmostApplication` still answers with the outgoing app there, so
    /// anything seeded from it — the Tile Assist watcher's initial
    /// observation — must be handed the real app or it watches the app the
    /// user just left until the next switch.
    private func defaultsChanged(activatedApp: NSRunningApplication?) {
        excludedApps.reload()
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
            tileAssistWatcher.start(with: activatedApp)
        } else {
            tileAssistWatcher.stop()
            // Dismiss it with its feature: left up, it keeps its timers to
            // the 5 s timeout. The exclusion path relies on this branch too.
            snapAssistPanel?.dismiss()
            // An arrange press still waiting on its app to activate is
            // synthetic input in flight — abandoned rather than delivered
            // while the feature is off, the middle-click paste's rule.
            SnapAssistPanel.cancelPendingTileActions()
        }
        if isEnabled("spaceIndicatorEnabled") {
            spaceChangeWatcher.start()
        } else { spaceChangeWatcher.stop() }
        // The setting itself, not `isEnabled`: a press withheld on the way into an
        // excluded app has to be replayed even though arriving there suspends the
        // feature, or the click that brought the app forward is swallowed.
        if !UserDefaults.standard.bool(forKey: "clickThroughFocusEnabled") {
            clickThroughFocusHandler.dropWithheldPress()
        }
        // Unlike the click-through replay, a pending middle-click paste is new
        // synthetic input rather than the user's own click restored, so
        // switching the feature off (or into an excluded app) abandons it.
        if !isEnabled("middleClickPasteEnabled") {
            middleClickPasteHandler.reset()
        }
    }

    // swiftlint:disable block_based_kvo
    // Arbitrary UserDefaults keys have no KeyPath representation, so the
    // block-based KVO API cannot observe them and the selector-based
    // override is the only route.
    nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "SLSMenuBarUseBlurredAppearance" else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.defaultsChanged() }
        }
    }
    // swiftlint:enable block_based_kvo

    /// Switching into or out of an excluded app. The menu bar icon dims, anything
    /// already on screen goes away, and the timers and observers behind the features
    /// are stopped or started by `defaultsChanged`, which reads `isEnabled`.
    private func applyExclusion(_ activatedApp: NSRunningApplication? = nil) {
        statusItem?.button?.alphaValue = excludedApps.isSuspended ? 0.5 : 1
        if excludedApps.isSuspended { snapAssistPanel?.dismiss() }
        // A pending type-to-search session keeps posting synthetic input and
        // intercepting keystrokes from its own timers — the handleEvent
        // suspension guard only blocks new events — so it is abandoned on
        // the way into an excluded app, like the middle-click paste is.
        if excludedApps.isSuspended { mcSearchHandler.reset() }
        defaultsChanged(activatedApp: activatedApp)
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
        // The handler runs on a private queue so it fires no matter what the main thread is blocked in.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(
            signal: SIGTERM, queue: DispatchQueue(label: "co.logonoff.superopt.sigterm"))
        source.setEventHandler { exit(0) }
        source.resume()
        sigtermSource = source

        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleQuitAppleEvent(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication)
        )
        UserDefaults.standard.register(defaults: AppDelegate.defaultPreferences)

        // Before the menu bar background starts: it reads the status item's appearance
        // to find out what colour the menu bar is drawing its text.
        setupStatusItem()

        let systemMenuBarBg = UserDefaults.standard.bool(forKey: "SLSMenuBarUseBlurredAppearance")
        if isEnabled("menuBarBgEnabled") && !systemMenuBarBg { menuBarBackground.start() }

        lastCapsLockState = NSEvent.modifierFlags.contains(.capsLock)

        // Before the event tap exists: the OSD measures its labels by rasterizing
        // them, which draws — slow work for the tap callback, where a slow
        // callback gets the tap disabled by timeout.
        lockKeyOSD.prepare(texts: [CapsLockOSDText.turnedOn, CapsLockOSDText.turnedOff])

        if isEnabled("mcCloseEnabled") { mcCloseHandler?.start() }
        updateMissionControlMonitor()
        setupCallbacks()
        hotCorner.enabled = isEnabled("hotCornersEnabled")

        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged as () -> Void),
            name: UserDefaults.didChangeNotification, object: nil
        )

        // "Show menu bar background" is written by System Settings, not by
        // this process, and didChangeNotification covers only this
        // process's own writes — KVO on the key is the route that sees the
        // external one, the same way the excluded-apps list and the
        // shortcut tree observe their keys (measured). The app delegate
        // lives for the process lifetime, so the observation is never
        // removed.
        UserDefaults.standard.addObserver(
            self, forKeyPath: "SLSMenuBarUseBlurredAppearance", options: [], context: nil)

        excludedApps.onChange = { [weak self] app in self?.applyExclusion(app) }
        excludedApps.start()

        permissionHelper.hasEventTap = { [weak self] in self?.eventTap != nil }
        permissionHelper.trySetupEventTap = { [weak self] in self?.setupEventTap() ?? false }

        if !setupEventTap() {
            // The startup alert observes grants in its modal run loop.
            // Start the safety heartbeat once the event tap is up.
            permissionHelper.showPermissionLoop()
        }

        // React to Accessibility permission changes
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(accessibilityChanged),
            name: NSNotification.Name("com.apple.accessibility.api"), object: nil
        )

        // Settle the permission safety timer into its steady-state heartbeat.
        // Nothing else runs on a healthy launch — no notification has fired
        // and the tap was never disabled — so without this the backstop the
        // heartbeat exists for would never be armed.
        accessibilityChanged()
    }

    func applicationWillTerminate(_: Notification) {
        safetyTimer?.invalidate(); tearDownEventTap(); mcCloseHandler?.stop(); mcMonitor.stop()
        DistributedNotificationCenter.default().removeObserver(self)
    }
    // MARK: - Event Tap
    private func setupEventTap() -> Bool {
        // A second tap would orphan the first one's run loop source.
        guard eventTap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
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
        eventTapSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        // Caps Lock toggles that happened while no tap was listening left the
        // OSD's latch stale; resync so the next real toggle still shows.
        resyncCapsLockLatch()
        // The Option latch goes stale the same way, and a missed release
        // would read as a clean press on the next modifier-less flagsChanged.
        optionKeyHandler.resync()
        return true
    }

    @objc func accessibilityChanged() {
        guard AXIsProcessTrusted() else {
            tearDownEventTap()
            setSafetyInterval(Self.recoveryInterval)
            return
        }
        if eventTap == nil {
            _ = setupEventTap()
        }
        // An assigned tap can still be disabled — a revocation notice that
        // arrived by notification only, or secure input having taken it down —
        // so the assignment alone is not proof the tap is working.
        if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            resyncCapsLockLatch()
            optionKeyHandler.resync()
            if !CGEvent.tapIsEnabled(tap: tap) {
                // A tap that will not come back is not helped by re-enabling
                // it every few seconds; drop it so the next tick builds a
                // fresh one.
                tearDownEventTap()
            }
        }
        if eventTap.map({ CGEvent.tapIsEnabled(tap: $0) }) ?? false {
            // Steady state. A slow heartbeat keeps the documented backstop
            // alive for a revocation that neither the distributed
            // notification nor the tap-disabled callback reports.
            setSafetyInterval(Self.heartbeatInterval)
        } else {
            setSafetyInterval(Self.recoveryInterval)
        }
    }

    /// Safety net: re-checks permissions in case neither the distributed
    /// notification nor the tap-disabled callback arrives. Fast while
    /// something is wrong, settling to a slow heartbeat once the tap is
    /// verified.
    private static let recoveryInterval: TimeInterval = 3.0
    private static let heartbeatInterval: TimeInterval = 30.0

    private func setSafetyInterval(_ interval: TimeInterval) {
        if let timer = safetyTimer, abs(timer.timeInterval - interval) < 0.001 { return }
        safetyTimer?.invalidate()
        safetyTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibilityChanged() }
        }
    }

    /// Caps Lock toggles that happened while no tap was listening leave the
    /// OSD's latch stale; resync so the next real toggle still shows.
    private func resyncCapsLockLatch() {
        lastCapsLockState = NSEvent.modifierFlags.contains(.capsLock)
    }

    func tearDownEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        // Core Foundation objects are ARC-managed from Swift, but a source
        // left registered in .commonModes is retained by the run loop and
        // would accumulate across permission flaps, so it has to be removed
        // for the ARC release to take effect.
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            eventTapSource = nil
        }
        eventTap = nil
    }
}

// MARK: - Actions
extension AppDelegate {
    /// Virtual key code emitted by the Mission Control key — a dedicated feature key,
    /// not the F3 function key, which is code 99. Which F-position it shares varies by
    /// keyboard model, so the code is the only stable way to name it.
    private static let missionControlKeyCode: Int64 = 160
    /// Virtual key code of Escape.
    private static let keyEscape: Int64 = 0x35

    fileprivate func triggerMissionControl() {
        // The key toggles: when Mission Control is up, this closes it, and
        // the search handler has to treat that activation as consumed — its
        // phantom-search guard never sees the synthetic key posted below.
        // It syncs the monitor itself, so a Mission Control it has not seen
        // open is still marked before this key closes it.
        mcSearchHandler.noteDismissal()
        // Emulate the Mission Control key rather than spawning `open -a "Mission Control"`:
        // no subprocess, and it does exactly what the hardware key does. Key code
        // 160 needs the Fn flag set — without it the key does nothing. Like the
        // real key, this toggles.
        KeyboardUtils.postKey(Self.missionControlKeyCode, flags: .maskSecondaryFn)
        // The synthetic key is skipped by handleKeyDown, so flag it from here.
        mcMonitor.noteTrigger()
    }
    private func setupCallbacks() {
        mcMonitor.onActive = { [weak self] list in
            guard let self else { return }
            mcCloseHandler?.missionControlDidTick(list)
            if isEnabled("dynamicSpacesEnabled") { dynamicSpaces.scheduleCheck() }
        }
        mcMonitor.onInactive = { [weak self] in
            self?.mcCloseHandler?.deactivateMC()
            self?.dynamicSpaces.reset()
        }
        tileAssistWatcher.onTile = { [weak self] dir, screen, tiled in
            self?.showSnapAssist(direction: dir, screen: screen, tiled: tiled)
        }
        tileAssistWatcher.onWindowChange = { [weak self] pid, frame in
            self?.snapAssistPanel?.tiledWindowDidChange(pid: pid, frame: frame)
        }
        if isEnabled("snapAssistEnabled") { tileAssistWatcher.start() }
        spaceChangeWatcher.onChange = { [weak self] display, screens in
            guard let self, isEnabled("spaceIndicatorEnabled") else { return }
            spaceIndicator.show(spaceCount: display.spaceIDs.count,
                                activeIndex: display.currentIndex, on: screens)
        }
        // Scrolling past either end of the row changes nothing, so it produces no
        // space change for the watcher to report, and the popup has to come from here.
        spaceScrollHandler.onEdge = { [weak self] count, index, screens in
            guard let self, isEnabled("spaceIndicatorEnabled") else { return }
            spaceIndicator.show(spaceCount: count, activeIndex: index, on: screens)
        }
        if isEnabled("spaceIndicatorEnabled") { spaceChangeWatcher.start() }
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
        // The close-button handler is already polling and notices on its next tick;
        // the trigger is noted so the monitor learns of the close at frame rate.
        mcSearchHandler.dismissMissionControl = { [weak self] in
            KeyboardUtils.postKey(Self.missionControlKeyCode, flags: .maskSecondaryFn)
            self?.mcMonitor.noteTrigger()
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
        direction: SnapAssistPanel.TileDirection, screen: NSScreen,
        tiled: TiledWindowInfo
    ) {
        snapAssistPanel?.dismiss()
        var panel: SnapAssistPanel?
        panel = SnapAssistPanel(
            direction: direction, screen: screen, tiled: tiled) { [weak self] in
            // The dismissed panel may no longer be the current one — a new
            // tile during its dismiss animation replaces it, and nil-ing
            // unconditionally here would orphan the new panel's window.
            guard let self, let panel, self.snapAssistPanel === panel else { return }
            self.snapAssistPanel = nil
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
        // A status item takes the appearance of the menu bar it sits in, which is how
        // the menu bar background finds out whether the text there is dark or light.
        menuBarBackground.menuBarAppearance = { [weak self] in
            self?.statusItem?.button?.effectiveAppearance
        }

        let menu = NSMenu()
        let settingsTitle = NSLocalizedString("Settings…", comment: "Menu item to open settings window")
        menu.addItem(NSMenuItem(title: settingsTitle, action: #selector(openSettings), keyEquivalent: ","))

        let permTitle = NSLocalizedString(
            "Request Permissions…", comment: "Menu item to check and request permissions")
        menu.addItem(NSMenuItem(
            title: permTitle, action: #selector(requestPermissions), keyEquivalent: ""))

        let launchTitle = NSLocalizedString("Open at Login", comment: "Menu item for starting the app at login")
        let item = NSMenuItem(title: launchTitle, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        launchMenuItem = item
        menu.addItem(item)

        let aboutTitle = NSLocalizedString("About SuperOpt", comment: "Menu item to show about panel")
        menu.addItem(NSMenuItem(title: aboutTitle, action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let quitTitle = NSLocalizedString("Quit SuperOpt", comment: "Menu item to quit the app")
        menu.addItem(NSMenuItem(title: quitTitle, action: #selector(quit), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    /// The checkmark is a launch-time snapshot otherwise: the registration
    /// can change outside this menu (System Settings → Login Items), and
    /// nothing would correct the stale state until relaunch.
    @objc func menuNeedsUpdate(_ menu: NSMenu) {
        launchMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func requestPermissions() {
        permissionHelper.requestPermissions()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func showAbout() {
        // Same as SettingsWindowController.activateAndFront: the cooperative
        // activate() never activates this accessory app, leaving the panel not key.
        NSApplication.shared.activate(ignoringOtherApps: true)
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
                "Can’t Update Login Item", comment: "Alert title when login item registration fails")
            alert.informativeText = NSLocalizedString(
                "You can manage login items in Login Items & Extensions settings.",
                comment: "Alert body directing user to login items settings")
            alert.alertStyle = .warning
            let openTitle = NSLocalizedString(
                "Open Login Items & Extensions Settings", comment: "Button to open login items settings")
            alert.addButton(withTitle: openTitle)
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
            if alert.runModal() == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

// MARK: - Event Routing
extension AppDelegate {
    /// Key and mouse input that dirties a held Option press, mirrored into
    /// the suspended path so a release inside an excluded app cannot read as
    /// clean.
    private static let optionDirtyingEvents: Set<CGEventType> = [
        .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown
    ]

    /// Key or mouse input while the active app is excluded. It still dirties
    /// a held Option press — the same events mark it on the unsuspended
    /// path, or a release inside the excluded app would read as clean. A
    /// left press also supersedes any in-flight click-through press the way
    /// a new press does on the unsuspended path: the handler never sees
    /// this one (the feature is off here), so its release has to pass
    /// through untouched rather than be consumed by state left over from a
    /// press that is over. Synthetic events are exempt — the click-through
    /// replay posts its own press while suspended, and it must neither
    /// reset the state waiting for the real release nor dirty a held
    /// Option press as though the user had acted.
    private func handleSuspendedInput(type: CGEventType, event: CGEvent) {
        guard !KeyboardUtils.isSynthetic(event) else { return }
        if Self.optionDirtyingEvents.contains(type) {
            optionKeyHandler.markOtherInput()
        }
        if type == .leftMouseDown {
            clickThroughFocusHandler.reset()
        }
    }

    /// Returns true if the event should be consumed.
    @discardableResult
    func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        // Caps Lock transitions are tracked even while the active app is
        // excluded or the OSD is off: a skipped toggle would leave the latch
        // stale and silently eat the next real toggle's notification. Option
        // press state is tracked there for the same reason — the suspension
        // guard below would otherwise swallow the release of a chord held
        // into an excluded app, and the stale flags misjudge the next press
        // after leaving (a chord held straight through reads as clean when a
        // companion modifier releases). Only the actions are suppressed
        // while suspended.
        if type == .flagsChanged {
            trackCapsLock(event: event)
            optionKeyHandler.handleFlagsChanged(
                event: event, actionsEnabled: !excludedApps.isSuspended)
        }
        // Every handler below is off in an excluded app, including the ones that read
        // their own setting rather than going through `isEnabled`. Their key
        // and mouse input still dirties a held Option press — the same events
        // mark it on the unsuspended path — or a release inside the excluded
        // app would read as clean.
        //
        // A click-through press whose target is an excluded app suspends
        // SuperOpt from its own activation, and its release still has to be
        // recorded (or consumed after the replay) or the window is left with
        // the button down — so that one release is routed to the handler
        // ahead of the guard, and a new press while suspended supersedes the
        // in-flight one so its own release passes through untouched.
        if type == .leftMouseUp, clickThroughFocusHandler.hasPendingPress {
            return clickThroughFocusHandler.handleMouseUp(event: event)
        }
        guard !excludedApps.isSuspended else {
            handleSuspendedInput(type: type, event: event)
            return false
        }
        switch type {
        case .keyDown: return handleKeyDown(event: event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return handleMouseDown(type: type, event: event)
        case .leftMouseUp: return handleMouseUp(event: event)
        case .otherMouseUp:
            return middleClickPasteHandler.handleMouseUp(event: event)
        case .mouseMoved: return handleMouseMoved(event: event)
        case .scrollWheel: return handleScroll(event: event)
        default: break
        }
        return false
    }

    private func handleMouseUp(event: CGEvent) -> Bool {
        // Mission Control closes a thumbnail click on the release, so a
        // press held while dragging one out keeps the close-animation window
        // open past the press-time stamp — re-stamp from the release. A
        // close-button hit's release is excluded, keeping it searchable.
        if !KeyboardUtils.isSynthetic(event) {
            if closeButtonPress {
                closeButtonPress = false
            } else {
                mcSearchHandler.noteClickInMissionControl()
            }
        }
        return isEnabled("clickThroughFocusEnabled") && clickThroughFocusHandler.handleMouseUp(event: event)
    }

    /// The monitor is shared, so it runs whenever any feature that needs to know
    /// about Mission Control is on, and not at all otherwise.
    func updateMissionControlMonitor() {
        let dynamic = isEnabled("dynamicSpacesEnabled")
        if !dynamic { dynamicSpaces.reset() }
        if !excludedApps.isSuspended && (dynamic || isEnabled("mcCloseEnabled") || mcSearchHandler.isEnabled) {
            mcMonitor.start(detectUnsignalledOpen: dynamic)
        } else {
            mcMonitor.stop()
        }
    }

    private func handleScroll(event: CGEvent) -> Bool {
        if isEnabled("spaceScrollEnabled") && spaceScrollHandler.handleScroll(event: event) {
            return true
        }
        return scrollZoomHandler.handleScroll(event: event)
    }

    private func handleMouseMoved(event: CGEvent) -> Bool {
        hotCorner.handleMouseMoved(event: event)
        return isEnabled("mcCloseEnabled") && mcCloseHandler?.handleMouseMoved(event: event) == true
    }

    private func handleMouseDown(type: CGEventType, event: CGEvent) -> Bool {
        if type == .leftMouseDown {
            if !KeyboardUtils.isSynthetic(event) {
                // A new press retires any stale click-through release
                // obligation even with the feature off: the handler's own
                // clear sits behind the isEnabled gates below, and a stale
                // `.dropped` would otherwise consume this press's release.
                clickThroughFocusHandler.noteExternalPress()
            }
            // A click while Mission Control is up usually closes it — a
            // thumbnail, the desktop — so the monitor looks for that at
            // frame rate rather than learning of the close up to 250 ms
            // late. A click that leaves it open (the spaces bar) expires
            // the trigger by its grace window.
            closeButtonPress = false
            if mcMonitor.isActive {
                mcMonitor.noteTrigger()
                if isEnabled("mcCloseEnabled") && mcCloseHandler?.handleClick(event: event) == true {
                    closeButtonPress = true
                    optionKeyHandler.markOtherInput(); return true
                }
            }
            // The search suppression is stamped for every real press, not
            // only while the monitor reports Mission Control up: one opened
            // by a trackpad swipe it never saw is closed by the same click,
            // and the stamp is inert when nothing is up — no session can
            // start. Synthetic presses are skipped, like their releases.
            if !KeyboardUtils.isSynthetic(event) {
                mcSearchHandler.noteClickInMissionControl()
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

    /// Shows the Caps Lock OSD on a toggle. State tracking lives in
    /// `trackCapsLock`, which runs even when this does not.
    private func trackCapsLock(event: CGEvent) {
        let capsLockOn = event.flags.contains(.maskAlphaShift)
        guard capsLockOn != lastCapsLockState else { return }
        lastCapsLockState = capsLockOn
        guard isEnabled("lockKeyOSDEnabled") else { return }
        lockKeyOSD.show(text: capsLockOn ? CapsLockOSDText.turnedOn : CapsLockOSDText.turnedOff, active: capsLockOn)
    }

    /// Whether the key at `keyCode` is the apps-grid key: the one typing "a",
    /// or on a layout typing no ASCII letters the one that is A on a US
    /// keyboard.
    private static func appGridKeyIsA(_ keyCode: Int64) -> Bool {
        guard let char = KeyboardLayout.character(forKeyCode: keyCode) else {
            return keyCode == 0x00
        }
        return char == "a" || (!KeyboardLayout.isLetter(char) && keyCode == 0x00)
    }

    /// ⌥A → Spotlight Apps. Its own feature toggle, separate from shortcut remapping.
    private func handleAppGridKey(event: CGEvent) -> Bool {
        guard isEnabled("appGridEnabled"),
              event.flags.contains(.maskAlternate),
              !event.flags.contains(.maskCommand),
              !event.flags.contains(.maskControl),
              // ⌥⇧A is a different chord, and on a US layout it types Å.
              !event.flags.contains(.maskShift),
              // The key that types "a" — on AZERTY the A lives where US
              // keyboards keep their Q, so a key-code match would fire on ⌥Q.
              // On layouts that type no ASCII letters at all (Cyrillic,
              // Greek), it is the key that is A on a US keyboard, where the
              // old key-code match worked and a character match never fires.
              Self.appGridKeyIsA(event.getIntegerValueField(.keyboardEventKeycode))
        else { return false }
        // Held keys autorepeat, and the Apps key toggles — repeats would
        // strobe the panel open and closed. The chord is already handled, so
        // the repeats are consumed rather than typed into whatever has focus.
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }
        triggerSpotlight()
        return true
    }

    private func handleKeyDown(event: CGEvent) -> Bool {
        if KeyboardUtils.isSynthetic(event) { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // Not consumed — just tells the monitor to start looking for Mission
        // Control, since opening it from the keyboard moves no mouse. Escape
        // closes an open Mission Control, so it counts as a trigger too:
        // without it the monitor learns of the close up to 250 ms late.
        // Bare keys only — a modified Escape (⌥⌘Esc is Force Quit) closes
        // nothing, and the same rule gates the search handler's guard.
        let bareKey = !event.flags.contains(.maskCommand)
            && !event.flags.contains(.maskControl)
            && !event.flags.contains(.maskAlternate)
            && !event.flags.contains(.maskShift)
        if keyCode == Self.missionControlKeyCode
            || (bareKey && keyCode == Self.keyEscape && mcMonitor.isActive) {
            mcMonitor.noteTrigger()
        }
        if mcSearchHandler.handleKeyDown(event: event) {
            optionKeyHandler.markOtherInput(); return true
        }
        if isEnabled("dockShortcutsEnabled")
            && dockLauncher.handleKeyDown(event: event, finderPosition: dockFinderPosition) {
            optionKeyHandler.markOtherInput(); return true
        }
        if isEnabled("menuKeyRightClickEnabled") && menuKeyHandler.handleKeyDown(event: event) {
            optionKeyHandler.markOtherInput(); return true
        }
        if isEnabled("homeEndRemapEnabled") && homeEndHandler.handleKeyDown(event: event) {
            optionKeyHandler.markOtherInput(); return true
        }
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
