import Cocoa

@MainActor
class PermissionHelper {
    var hasEventTap: () -> Bool = { false }
    var trySetupEventTap: () -> Bool = { false }

    // Private: IOHIDCheckAccess queries Input Monitoring permission status directly.
    // No public API checks Input Monitoring — a CGEvent tap succeeds with only
    // Accessibility granted, so it can't distinguish the two permissions.
    private static let ioHIDCheck: ((UInt32) -> UInt32)? = {
        guard let ptr = dlsym(dlopen(nil, RTLD_LAZY), "IOHIDCheckAccess") else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (UInt32) -> UInt32).self)
    }()

    private func isInputMonitoringGranted() -> Bool {
        // IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) — 0 = granted
        guard let check = PermissionHelper.ioHIDCheck else { return hasEventTap() }
        return check(1) == 0 // kIOHIDRequestTypeListenEvent = 1, 0 = granted
    }

    private static let inputMonitoringURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    private static var openAccessibilityTitle: String {
        NSLocalizedString("Open Device Control and Data Access Settings",
                          comment: "Button to open Accessibility settings")
    }
    private static var openInputMonitoringTitle: String {
        NSLocalizedString("Open Input Monitoring Settings", comment: "Button to open Input Monitoring settings")
    }
    private static var permissionsRequiredTitle: String {
        NSLocalizedString("Permissions Required", comment: "Alert title for missing permissions")
    }

    private struct MissingPermissions {
        var accessibility = false
        var inputMonitoring = false
        var isEmpty: Bool { !accessibility && !inputMonitoring }

        var names: [String] {
            var names: [String] = []
            if accessibility {
                names.append(NSLocalizedString("Device Control and Data Access", comment: "Permission name"))
            }
            if inputMonitoring {
                names.append(NSLocalizedString("Input Monitoring", comment: "Permission name"))
            }
            return names
        }
    }

    /// Which permissions are missing, under the same predicate for the
    /// message body and the buttons — IOHIDCheckAccess may report granted
    /// when inheriting terminal permissions, so the event tap's actual
    /// existence is checked too.
    private func checkMissingPermissions() -> MissingPermissions {
        var missing = MissingPermissions()
        if !hasEventTap() { _ = trySetupEventTap() }
        missing.accessibility = !AXIsProcessTrusted()
        missing.inputMonitoring = !isInputMonitoringGranted()
            || (!hasEventTap() && AXIsProcessTrusted())
        return missing
    }

    private func formatPermissionsMessage(_ missing: [String]) -> String {
        let format = NSLocalizedString(
            "SuperOpt needs the following:\n\n%@\n\n"
            + "Grant access in Privacy & Security settings.",
            comment: "Alert body for missing permissions — %@ is the list of missing permissions; "
                + "shared by both permission alerts, so it can't name a specific button")
        return String(format: format, missing.joined(separator: ", "))
    }

    private func openAccessibilityPrompt() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    private func openInputMonitoring() {
        if let url = URL(string: PermissionHelper.inputMonitoringURL) { NSWorkspace.shared.open(url) }
    }

    func requestPermissions() {
        let missing = checkMissingPermissions()

        if missing.isEmpty, hasEventTap() {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "Permissions Granted", comment: "Alert title when all permissions are granted")
            alert.informativeText = NSLocalizedString(
                "SuperOpt already has the permissions it needs.",
                comment: "Alert body when all permissions are granted")
            alert.alertStyle = .informational; alert.runModal(); return
        }

        let alert = NSAlert()
        alert.messageText = PermissionHelper.permissionsRequiredTitle
        alert.informativeText = formatPermissionsMessage(missing.names)
        alert.alertStyle = .warning
        if missing.accessibility {
            alert.addButton(withTitle: PermissionHelper.openAccessibilityTitle)
        }
        if missing.inputMonitoring {
            alert.addButton(withTitle: PermissionHelper.openInputMonitoringTitle)
        }
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))

        let response = alert.runModal()
        var buttonIndex = 0
        if missing.accessibility {
            if response == NSApplication.ModalResponse(rawValue: 1000 + buttonIndex) {
                openAccessibilityPrompt(); return
            }
            buttonIndex += 1
        }
        if missing.inputMonitoring {
            if response == NSApplication.ModalResponse(rawValue: 1000 + buttonIndex) {
                openInputMonitoring(); return
            }
        }
    }

    private weak var permissionWindow: NSWindow?
    private var permissionRetry: Timer?

    @objc private func permissionDidChange() {
        guard let permissionWindow, NSApplication.shared.modalWindow === permissionWindow else { return }
        if finishIfTrusted() { return }

        // A grant can be announced before the new trust state is readable.
        guard permissionRetry == nil else { return }
        let retry = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.permissionRetry = nil
                _ = self?.finishIfTrusted()
            }
        }
        permissionRetry = retry
        RunLoop.main.add(retry, forMode: .modalPanel)
    }

    private func finishIfTrusted() -> Bool {
        guard let permissionWindow, NSApplication.shared.modalWindow === permissionWindow,
              AXIsProcessTrusted(), trySetupEventTap()
        else { return false }
        NSApplication.shared.abortModal()
        return true
    }

    // Modal loop with dynamic button layout depending on which permissions are missing.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func showPermissionLoop() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self, selector: #selector(permissionDidChange),
            name: NSNotification.Name("com.apple.accessibility.api"), object: nil,
            suspensionBehavior: .deliverImmediately
        )
        defer { center.removeObserver(self, name: NSNotification.Name("com.apple.accessibility.api"), object: nil) }

        while true {
            let missing = checkMissingPermissions()
            if missing.isEmpty, trySetupEventTap() { break }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = PermissionHelper.permissionsRequiredTitle
            alert.informativeText = formatPermissionsMessage(missing.names)

            alert.addButton(withTitle: NSLocalizedString(
                "Continue", comment: "Button to retry after granting permissions"))
                .keyEquivalent = "\r"
            if missing.accessibility {
                alert.addButton(withTitle: PermissionHelper.openAccessibilityTitle)
            }
            if missing.inputMonitoring {
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

            // Launch calls this loop from an AppKit callback so distributed
            // notifications can be delivered in modal mode.
            permissionWindow = alert.window
            let response = alert.runModal()
            permissionWindow = nil
            permissionRetry?.invalidate()
            permissionRetry = nil
            alert.window.orderOut(nil)

            if response == .abort { break }

            // Button indices shift depending on which permissions are missing
            var buttonIndex = 1
            if missing.accessibility {
                if response == NSApplication.ModalResponse(rawValue: 1000 + buttonIndex) {
                    openAccessibilityPrompt(); continue
                }
                buttonIndex += 1
            }
            if missing.inputMonitoring {
                if response == NSApplication.ModalResponse(rawValue: 1000 + buttonIndex) {
                    openInputMonitoring(); continue
                }
                buttonIndex += 1
            }
            // Last button is always Quit
            if response == NSApplication.ModalResponse(rawValue: 1000 + buttonIndex) {
                NSApplication.shared.terminate(nil); return
            }
            // Continue button (alertFirstButtonReturn = 1000)
            if trySetupEventTap() { break }
        }
    }
}
