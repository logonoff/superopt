import Cocoa

class HotCorner {
    var onTrigger: ((NSScreen) -> Void)?
    var enabled: Bool = true

    private var triggered = false
    private var lastTriggerTime: TimeInterval = 0
    private let zone: CGFloat = 2
    private let cooldown: TimeInterval = 0.5 // seconds before re-trigger is allowed

    // Pressure-based triggering (inspired by GNOME's PressureBarrier)
    // Instead of pointer barriers, we measure cursor velocity approaching the corner.
    // GNOME uses 100px of cumulative pressure in a 1000ms window.
    // We approximate this by requiring sufficient speed when entering the corner zone.
    private var lastMousePos: CGPoint = .zero
    private var lastMouseTime: TimeInterval = 0
    private let velocityThreshold: CGFloat = 500 // points/sec — filters out slow drifts

    func handleMouseMoved(event: CGEvent) {
        guard enabled else { return }

        let pos = event.location
        let now = ProcessInfo.processInfo.systemUptime

        if let screen = screenAtTopLeftCorner(pos) {
            if !triggered && (now - lastTriggerTime) >= cooldown {
                let elapsed = now - lastMouseTime
                if elapsed > 0 && elapsed < 0.5 {
                    let deltaX = pos.x - lastMousePos.x
                    let deltaY = pos.y - lastMousePos.y
                    let speed = sqrt(deltaX * deltaX + deltaY * deltaY) / CGFloat(elapsed)

                    if speed >= velocityThreshold {
                        triggered = true
                        lastTriggerTime = now
                        onTrigger?(screen)
                    }
                }
            }
        } else {
            triggered = false
        }

        lastMousePos = pos
        lastMouseTime = now
    }

    private func screenAtTopLeftCorner(_ point: CGPoint) -> NSScreen? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }

        for screen in NSScreen.screens {
            let frame = screen.frame
            let cornerX = frame.origin.x
            let cornerY = primaryHeight - frame.origin.y - frame.height

            if point.x >= cornerX && point.x < cornerX + zone
                && point.y >= cornerY && point.y < cornerY + zone {
                return screen
            }
        }
        return nil
    }
}
