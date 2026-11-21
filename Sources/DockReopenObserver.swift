import Cocoa

/// Detects whether an app answered a Dock reopen by creating its own window.
@MainActor
final class DockReopenObserver {
    private var observer: AXObserver?
    private var deadline: Timer?

    static func start(pid: pid_t, wait: TimeInterval, onDeadline: @escaping () -> Void) -> Bool {
        DockReopenObserver().observe(pid: pid, wait: wait, onDeadline: onDeadline)
    }

    private func observe(pid: pid_t, wait: TimeInterval, onDeadline: @escaping () -> Void) -> Bool {
        var observer: AXObserver?
        let result = AXObserverCreate(pid, { _, element, _, context in
            guard let context else { return }
            let watcher = Unmanaged<DockReopenObserver>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.windowCreated(element) }
        }, &observer)
        guard result == .success, let observer else { return false }
        let app = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, context)
                == .success else { return false }
        self.observer = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        // Retain the observer until it sees a window or reaches the deadline.
        deadline = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { _ in
            MainActor.assumeIsolated {
                self.stop()
                onDeadline()
            }
        }
        return true
    }

    private func windowCreated(_ element: AXUIElement) {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
              value as? String == kAXWindowRole else { return }
        stop()
    }

    private func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            self.observer = nil
        }
        deadline?.invalidate()
        deadline = nil
    }
}
