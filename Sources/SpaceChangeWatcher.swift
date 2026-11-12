import Cocoa

/// Notices when a display changes space, however it was done — the keyboard shortcut,
/// Mission Control, a swipe, clicking an app that lives on another space.
///
/// `NSWorkspace.activeSpaceDidChangeNotification` is the signal. It says nothing about
/// which display moved, so each display's current space is read and compared with the
/// last reading. The notification arrives when the switch animation finishes, about a
/// second after the keystroke that started it, and the space list is up to date by
/// then — which is also the first moment a panel can be put on screen without the
/// animation dragging it away.
@MainActor
final class SpaceChangeWatcher {
    /// The display that changed, and the screens showing that change.
    var onChange: ((ManagedDisplay, [NSScreen]) -> Void)?

    private var lastCurrent: [String: UInt64] = [:]
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        lastCurrent = currentSpaces()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        lastCurrent = [:]
    }

    private func report() {
        for display in SpaceSwitcher.displays() {
            guard display.currentIndex < display.spaceIDs.count else { continue }
            let current = display.spaceIDs[display.currentIndex]
            guard lastCurrent[display.identifier] != current else { continue }
            lastCurrent[display.identifier] = current
            onChange?(display, SpaceSwitcher.screens(showing: display))
        }
    }

    private func currentSpaces() -> [String: UInt64] {
        var spaces: [String: UInt64] = [:]
        for display in SpaceSwitcher.displays() where display.currentIndex < display.spaceIDs.count {
            spaces[display.identifier] = display.spaceIDs[display.currentIndex]
        }
        return spaces
    }
}
