import Cocoa

@MainActor
enum AppActivation {
    /// Calls completion when the requested app comes forward or the deadline expires.
    static func wait(for pid: pid_t, timeout: TimeInterval, completion: @escaping () -> Void) {
        let workspace = NSWorkspace.shared
        if workspace.frontmostApplication?.processIdentifier == pid {
            completion()
            return
        }

        let center = workspace.notificationCenter
        var observer: NSObjectProtocol?
        var deadline: Timer?
        func finish() {
            guard let token = observer else { return }
            observer = nil
            center.removeObserver(token)
            deadline?.invalidate()
            deadline = nil
            completion()
        }

        observer = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  activated.processIdentifier == pid else { return }
            // Inside the notification, frontmostApplication can still be the outgoing app.
            DispatchQueue.main.async {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { finish() }
            }
        }
        deadline = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            MainActor.assumeIsolated { finish() }
        }
    }
}
