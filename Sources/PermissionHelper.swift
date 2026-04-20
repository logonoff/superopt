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
        if !isInputMonitoringGranted() {
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
        if AXIsProcessTrusted() && isInputMonitoringGranted() && hasEventTap() {
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
        alert.addButton(withTitle: PermissionHelper.openAccessibilityTitle)
        alert.addButton(withTitle: PermissionHelper.openInputMonitoringTitle)
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: openAccessibilityPrompt()
        case .alertSecondButtonReturn: openInputMonitoring()
        default: break
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func showPermissionLoop() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString(
            "Continue", comment: "Button to retry after granting permissions"))
            .keyEquivalent = "\r"
        alert.addButton(withTitle: PermissionHelper.openAccessibilityTitle)
        alert.addButton(withTitle: PermissionHelper.openInputMonitoringTitle)
        alert.addButton(withTitle: NSLocalizedString("Quit", comment: "Button to quit the app"))

        let permissionTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if AXIsProcessTrusted() && self.isInputMonitoringGranted() && self.trySetupEventTap() {
                timer.invalidate()
                alert.window.orderOut(nil)
                NSApplication.shared.abortModal()
            }
        }
        RunLoop.main.add(permissionTimer, forMode: .modalPanel)

        while true {
            let missing = buildMissingPermissions()
            if missing.isEmpty && trySetupEventTap() { alert.window.orderOut(nil); break }

            alert.messageText = PermissionHelper.permissionsRequiredTitle
            alert.informativeText = formatPermissionsMessage(missing)

            // Reposition after runModal centers the alert, to avoid overlapping the system prompt
            DispatchQueue.main.async {
                if let screen = NSScreen.main {
                    let originX = screen.frame.maxX - alert.window.frame.width - 40
                    let originY = screen.frame.maxY - alert.window.frame.height - 80
                    alert.window.setFrameOrigin(NSPoint(x: originX, y: originY))
                }
            }

            let response = alert.runModal()
            if response == .abort {
                break // auto-dismissed by timer — permissions granted
            }
            switch response {
            case .alertFirstButtonReturn:
                if trySetupEventTap() { alert.window.orderOut(nil); break }
            case .alertSecondButtonReturn:
                alert.window.orderOut(nil)
                openAccessibilityPrompt()
            case .alertThirdButtonReturn:
                alert.window.orderOut(nil)
                openInputMonitoring()
            default:
                permissionTimer.invalidate()
                NSApplication.shared.terminate(nil); return
            }
        }
        permissionTimer.invalidate()
    }
}
