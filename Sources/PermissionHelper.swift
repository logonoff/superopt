import Cocoa

class PermissionHelper {
    var hasEventTap: () -> Bool = { false }
    var trySetupEventTap: () -> Bool = { false }

    private static let ioHIDCheck: ((UInt32) -> UInt32)? = {
        guard let ptr = dlsym(dlopen(nil, RTLD_LAZY), "IOHIDCheckAccess") else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (UInt32) -> UInt32).self)
    }()

    private func isInputMonitoringGranted() -> Bool {
        // IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) — 0 = granted
        guard let check = PermissionHelper.ioHIDCheck else { return hasEventTap() }
        return check(1) == 0
    }

    private static let inputMonitoringURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    private static var openAccessibilityTitle: String {
        NSLocalizedString("Open Accessibility", comment: "Button to open Accessibility preferences")
    }
    private static var openInputMonitoringTitle: String {
        NSLocalizedString("Open Input Monitoring", comment: "Button to open Input Monitoring preferences")
    }
    private static var permissionsRequiredTitle: String {
        NSLocalizedString("Permissions Required", comment: "Alert title for missing permissions")
    }

    private func buildMissingPermissions() -> [String] {
        if !hasEventTap() { _ = trySetupEventTap() }

        var missing: [String] = []
        if !AXIsProcessTrusted() { missing.append(NSLocalizedString("Accessibility", comment: "Permission name")) }
        // IOHIDCheckAccess may report granted when inheriting terminal permissions,
        // so also check if the event tap actually works
        if !isInputMonitoringGranted() || (!hasEventTap() && AXIsProcessTrusted()) {
            missing.append(NSLocalizedString("Input Monitoring", comment: "Permission name"))
        }
        return missing
    }

    private func formatPermissionsMessage(_ missing: [String]) -> String {
        // swiftlint:disable:next line_length
        let format = NSLocalizedString("OptWin needs the following permissions:\n\n%@\n\nGrant access in System Settings → Privacy & Security, then click Continue.\n\nIf you recently updated OptWin, you may need to remove and re-add it in each permission list.", comment: "Alert body for missing permissions — %@ is the list of missing permissions")
        return String(format: format, missing.joined(separator: ", "))
    }

    private func openAccessibilityPrompt() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    private func openInputMonitoring() {
        if let url = URL(string: PermissionHelper.inputMonitoringURL) { NSWorkspace.shared.open(url) }
    }

    func requestPermissions() {
        let needsAccessibility = !AXIsProcessTrusted()
        let needsInputMonitoring = !isInputMonitoringGranted()

        if !needsAccessibility && !needsInputMonitoring && hasEventTap() {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "Permissions Granted", comment: "Alert title when all permissions are granted")
            alert.informativeText = NSLocalizedString(
                "OptWin already has all required permissions.", comment: "Alert body when all permissions are granted")
            alert.alertStyle = .informational; alert.runModal(); return
        }

        let alert = NSAlert()
        alert.messageText = PermissionHelper.permissionsRequiredTitle
        alert.informativeText = formatPermissionsMessage(buildMissingPermissions())
        alert.alertStyle = .warning
        if needsAccessibility {
            alert.addButton(withTitle: PermissionHelper.openAccessibilityTitle)
        }
        if needsInputMonitoring {
            alert.addButton(withTitle: PermissionHelper.openInputMonitoringTitle)
        }
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))

        let response = alert.runModal()
        var buttonIndex = 0
        if needsAccessibility {
            if response == NSApplication.ModalResponse(rawValue: 1000 + buttonIndex) {
                openAccessibilityPrompt(); return
            }
            buttonIndex += 1
        }
        if needsInputMonitoring {
            if response == NSApplication.ModalResponse(rawValue: 1000 + buttonIndex) {
                openInputMonitoring(); return
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func showPermissionLoop() {
        let permissionTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if AXIsProcessTrusted() && self.isInputMonitoringGranted() && self.trySetupEventTap() {
                timer.invalidate()
                NSApplication.shared.abortModal()
            }
        }
        RunLoop.main.add(permissionTimer, forMode: .modalPanel)

        while true {
            let missing = buildMissingPermissions()
            if missing.isEmpty && trySetupEventTap() { break }

            let needsAccessibility = !AXIsProcessTrusted()
            let needsInputMonitoring = !isInputMonitoringGranted()

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = PermissionHelper.permissionsRequiredTitle
            alert.informativeText = formatPermissionsMessage(missing)

            alert.addButton(withTitle: NSLocalizedString(
                "Continue", comment: "Button to retry after granting permissions"))
                .keyEquivalent = "\r"
            if needsAccessibility {
                alert.addButton(withTitle: PermissionHelper.openAccessibilityTitle)
            }
            if needsInputMonitoring {
                alert.addButton(withTitle: PermissionHelper.openInputMonitoringTitle)
            }
            alert.addButton(withTitle: NSLocalizedString("Quit", comment: "Button to quit the app"))

            DispatchQueue.main.async {
                if let screen = NSScreen.main {
                    let originX = screen.frame.maxX - alert.window.frame.width - 40
                    let originY = screen.frame.maxY - alert.window.frame.height - 80
                    alert.window.setFrameOrigin(NSPoint(x: originX, y: originY))
                }
            }

            let response = alert.runModal()
            alert.window.orderOut(nil)

            if response == .abort { break }

            // Button indices shift depending on which permissions are missing
            var buttonIndex = 1
            if needsAccessibility {
                if response == NSApplication.ModalResponse(rawValue: 1000 + buttonIndex) {
                    openAccessibilityPrompt(); continue
                }
                buttonIndex += 1
            }
            if needsInputMonitoring {
                if response == NSApplication.ModalResponse(rawValue: 1000 + buttonIndex) {
                    openInputMonitoring(); continue
                }
                buttonIndex += 1
            }
            // Last button is always Quit
            if response == NSApplication.ModalResponse(rawValue: 1000 + buttonIndex) {
                permissionTimer.invalidate()
                NSApplication.shared.terminate(nil); return
            }
            // Continue button (alertFirstButtonReturn = 1000)
            if trySetupEventTap() { break }
        }
        permissionTimer.invalidate()
    }
}
