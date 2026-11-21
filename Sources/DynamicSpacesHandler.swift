import Cocoa

/// Reconciles each visible Mission Control strip one desktop at a time.
@MainActor
final class DynamicSpacesHandler {
    enum Action: Equatable {
        case add
        case remove(UInt64)
    }

    private struct Proposal: Equatable {
        let order: [UInt64]
        let current: UInt64
        let action: Action
    }

    private var previous: [String: Proposal] = [:]
    /// Some display arrangements keep full-screen apps at the end. If Add places
    /// an empty desktop immediately before that same app, keep it as the spare.
    private var lastAddAnchor: [String: UInt64] = [:]
    private var submittedOrder: [String: [UInt64]] = [:]
    private var queued: DispatchWorkItem?
    private var nextCheck: TimeInterval = 0

    func reset() {
        queued?.cancel()
        queued = nil
        nextCheck = 0
        previous.removeAll()
        submittedOrder.removeAll()
        lastAddAnchor.removeAll()
    }

    /// The monitor can discover Mission Control inside the event tap and can tick
    /// at display refresh rate. Keep AX requests out of the tap and pace snapshots.
    func scheduleCheck() {
        let now = ProcessInfo.processInfo.systemUptime
        guard queued == nil, now >= nextCheck else { return }
        nextCheck = now + 0.24
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            queued = nil
            reconcile()
        }
        queued = work
        DispatchQueue.main.async(execute: work)
    }

    /// Only type 0 is a desktop. A full-screen or Split View Space (type 4)
    /// can occupy the last position but must never be selected for removal.
    /// A missing occupancy reading is unknown, so it cannot justify an action.
    static func action(for display: ManagedDisplay, occupied: [UInt64: Bool], lastAddAnchor: UInt64? = nil) -> Action? {
        guard let last = display.spaceIDs.last, display.spaceTypes.count == display.spaceIDs.count,
              display.spaceTypes.allSatisfy({ $0 == 0 || $0 == 4 }),
              display.spaceIDs.indices.contains(display.currentIndex) else { return nil }
        let desktops = zip(display.spaceIDs, display.spaceTypes).filter { $0.1 == 0 }.map(\.0)
        let current = display.spaceIDs[display.currentIndex]
        let currentIsEmpty = display.spaceTypes[display.currentIndex] == 0 && occupied[current] == false
        let spare = currentIsEmpty ? current : desktops.last
        if let extra = desktops.last(where: { $0 != spare && occupied[$0] == false }) {
            return .remove(extra)
        }
        if currentIsEmpty { return nil }
        if display.spaceTypes.last == 4 {
            if lastAddAnchor == last, let spare = desktops.last, occupied[spare] != true { return nil }
            return .add
        }
        return occupied[last] == true ? .add : nil
    }

    private func reconcile() {
        guard NSEvent.pressedMouseButtons == 0, let pid = MissionControlStrip.windowManagerPID,
              let windows = DesktopWindows(windowManagerPID: pid) else {
            previous.removeAll()
            return
        }
        let displays = SpaceSwitcher.displays()
        var strips: [MissionControlStrip]?
        var proposals: [String: Proposal] = [:]
        for display in displays {
            let key = display.identifier
            guard submittedOrder[key] != display.spaceIDs else { continue }
            submittedOrder.removeValue(forKey: key)
            guard let action = Self.action(for: display, occupied: windows.occupancy(of: display),
                                           lastAddAnchor: lastAddAnchor[key]) else { continue }
            let proposal = Proposal(order: display.spaceIDs, current: display.spaceIDs[display.currentIndex],
                                    action: action)
            proposals[key] = proposal
            // Require two consecutive readings. After submitting, wait for the strip
            // to change before issuing another press, even if AX times out replying.
            guard previous[key] == proposal else { continue }
            if strips == nil { strips = MissionControlStrip.visible(pid: pid) }
            if let strip = MissionControlStrip.match(for: display, in: strips ?? [], displays: displays),
               strip.perform(action, on: display) {
                submittedOrder[key] = proposal.order
                if action == .add { lastAddAnchor[key] = proposal.order.last }
            }
        }
        previous = proposals
    }
}

@MainActor
private struct DesktopWindows {
    let known: Set<CGWindowID>
    let appWindows: Set<CGWindowID>

    init?(windowManagerPID: pid_t) {
        guard let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
            as? [[String: Any]], !all.isEmpty else { return nil }
        var known: Set<CGWindowID> = []
        var appWindows: Set<CGWindowID> = []
        let appLayers = 0...Int(CGWindowLevelForKey(.modalPanelWindow))
        for window in all {
            guard let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            known.insert(id)
            // Mission Control creates its own layer-zero window on an empty
            // inactive desktop. Counting it would continually create new desktops.
            if pid != windowManagerPID && appLayers.contains(layer) { appWindows.insert(id) }
        }
        self.known = known
        self.appWindows = appWindows
    }

    func occupancy(of display: ManagedDisplay) -> [UInt64: Bool] {
        var result: [UInt64: Bool] = [:]
        var members: [UInt64: Set<CGWindowID>] = [:]
        for (id, kind) in zip(display.spaceIDs, display.spaceTypes) where kind == 0 {
            if let windows = SpaceSwitcher.windows(on: id) { members[id] = Set(windows) }
        }
        // Some apps are assigned to All Desktops through the Dock. Only windows
        // common to every desktop are safe to disregard, and only after reading
        // every membership list. A missing list cannot establish that a window is shared.
        var shared: Set<CGWindowID> = []
        if members.count > 1, members.count == display.spaceTypes.filter({ $0 == 0 }).count,
           let first = members.values.first {
            shared = members.values.reduce(first) { $0.intersection($1) }
        }
        for (id, windows) in members {
            let local = windows.subtracting(shared)
            if !appWindows.isDisjoint(with: local) {
                result[id] = true
            } else if known.isSuperset(of: local) {
                result[id] = false
            }
        }
        return result
    }
}

/// WindowManager publishes mc.display directly under its AX application on macOS 27.
/// The AX buttons have no Space IDs. Match their display, count and current SkyLight
/// order immediately before performing an action on one.
@MainActor
private struct MissionControlStrip {
    let pid: pid_t
    let displayID: CGDirectDisplayID
    let group: AXUIElement

    private static func value(_ key: String, of element: AXUIElement) -> AnyObject? {
        var result: AnyObject?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        value(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }

    private static func child(_ identifier: String, of element: AXUIElement) -> AXUIElement? {
        children(of: element).last { value(kAXIdentifierAttribute, of: $0) as? String == identifier }
    }

    static var windowManagerPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager")
            .first?.processIdentifier
    }

    static func visible(pid: pid_t) -> [Self] {
        let app = AXUIElementCreateApplication(pid)
        return children(of: app).compactMap { item in
            guard value(kAXIdentifierAttribute, of: item) as? String == "mc.display",
                  let id = value("AXDisplayID", of: item) as? CGDirectDisplayID,
                  let spaces = child("mc.spaces", of: item) else { return nil }
            return Self(pid: pid, displayID: id, group: spaces)
        }
    }

    static func match(for display: ManagedDisplay, in strips: [Self], displays: [ManagedDisplay]) -> Self? {
        let screens = NSScreen.screens
        let shared = displays.count == 1 && !NSScreen.screensHaveSeparateSpaces
        let mainOnly = displays.count == 1 && screens.count == 1 && display.identifier == "Main"
        for screen in screens where shared || mainOnly || SpaceSwitcher.identifier(for: screen) == display.identifier {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if let strip = strips.first(where: { $0.displayID == id }) { return strip }
        }
        return nil
    }

    func perform(_ action: DynamicSpacesHandler.Action, on display: ManagedDisplay) -> Bool {
        guard let list = Self.child("mc.spaces.list", of: group) else { return false }
        let buttons = Self.children(of: list)
        guard buttons.count == display.spaceIDs.count else { return false }
        let target: AXUIElement
        let command: String
        switch action {
        case .add:
            guard let add = Self.child("mc.spaces.add", of: group) else { return false }
            target = add
            command = kAXPressAction
        case .remove(let id):
            guard let index = display.spaceIDs.firstIndex(of: id),
                  let windows = DesktopWindows(windowManagerPID: pid),
                  DynamicSpacesHandler.action(for: display, occupied: windows.occupancy(of: display)) == action
            else { return false }
            target = buttons[index]
            command = "AXRemoveDesktop"
        }
        var actions: CFArray?
        guard AXUIElementCopyActionNames(target, &actions) == .success,
              (actions as? [String])?.contains(command) == true,
              Self.value(kAXEnabledAttribute, of: target) as? Bool != false,
              let fresh = SpaceSwitcher.displays().first(where: { $0.identifier == display.identifier }),
              fresh.spaceIDs == display.spaceIDs, fresh.currentIndex == display.currentIndex,
              NSEvent.pressedMouseButtons == 0,
              let visible = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]], KeyboardUtils.isMissionControlActive(visible) else { return false }
        // A timeout can arrive after the action took effect. Treat an attempted
        // press as submitted until the next topology or Mission Control session.
        let status = AXUIElementPerformAction(target, command as CFString)
        return status == .success || status == .cannotComplete
    }
}
