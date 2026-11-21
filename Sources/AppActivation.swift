import Cocoa

@MainActor
enum AppActivation {
    /// How often `frontmostApplication` is re-read while waiting. The property
    /// can still name the outgoing app well after the activation notification
    /// fires, and the notification itself can fire before this wait even
    /// registers (the Dock path arrives 0.15 s after openApplication) — both
    /// measured, see AGENTS.md — so the real state has to be polled for, as
    /// each caller did before this helper existed.
    private static let pollInterval: TimeInterval = 0.05

    /// Calls completion when the requested app comes forward or the timeout
    /// expires — frontmost or not, leaving the caller to decide what an app
    /// that never came forward deserves.
    static func wait(for pid: pid_t, timeout: TimeInterval, completion: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func check() {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                completion()
            } else if Date() < deadline {
                let timer = Timer(timeInterval: pollInterval, repeats: false) { _ in
                    MainActor.assumeIsolated { check() }
                }
                RunLoop.main.add(timer, forMode: .common)
            } else {
                completion()
            }
        }
        check()
    }
}
