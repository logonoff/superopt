import Cocoa

/// One display's spaces, as the window server lists them.
struct ManagedDisplay {
    /// The window server's name for the display: its UUID when displays have separate
    /// spaces, or a single shared name when they change space together.
    let identifier: String
    let spaceIDs: [UInt64]
    let currentIndex: Int
}

/// Reads which space each display is showing, and changes it.
///
/// Spaces have no public API at all. AppKit lets a window say which spaces it joins
/// (`NSWindow.CollectionBehavior`) and stops there: a process cannot ask how many
/// spaces exist, which one is current, or move to another. These three SkyLight
/// symbols are what the window server itself uses. `SLSMainConnectionID` returns this
/// process's connection to it. `SLSCopyManagedDisplaySpaces` returns, per display, the
/// ordered list of spaces and which is current. `SLSManagedDisplaySetCurrentSpace`
/// moves one named display to one of its spaces, animating as a Control-arrow switch
/// does — and, unlike posting that shortcut, it picks the display rather than leaving
/// the choice to wherever the keyboard focus happens to be.
@MainActor
enum SpaceSwitcher {
    private typealias MainConnectionFn = @convention(c) () -> UInt32
    private typealias CopyDisplaySpacesFn = @convention(c) (UInt32) -> CFArray?
    private typealias SetCurrentSpaceFn = @convention(c) (UInt32, CFString, UInt64) -> Void

    private static let skyLight = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static let connection: UInt32? = {
        guard let skyLight, let symbol = dlsym(skyLight, "SLSMainConnectionID") else { return nil }
        return unsafeBitCast(symbol, to: MainConnectionFn.self)()
    }()

    private static let copyDisplaySpaces: CopyDisplaySpacesFn? = {
        guard let skyLight,
              let symbol = dlsym(skyLight, "SLSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: CopyDisplaySpacesFn.self)
    }()

    private static let setSpace: SetCurrentSpaceFn? = {
        guard let skyLight,
              let symbol = dlsym(skyLight, "SLSManagedDisplaySetCurrentSpace") else { return nil }
        return unsafeBitCast(symbol, to: SetCurrentSpaceFn.self)
    }()

    static func displays() -> [ManagedDisplay] {
        guard let connection, let copyDisplaySpaces,
              let raw = copyDisplaySpaces(connection) as? [[String: Any]]
        else { return [] }

        return raw.compactMap { entry in
            guard let identifier = entry["Display Identifier"] as? String,
                  let spaces = entry["Spaces"] as? [[String: Any]],
                  let current = (entry["Current Space"] as? [String: Any])?["id64"] as? UInt64
            else { return nil }
            let ids = spaces.compactMap { $0["id64"] as? UInt64 }
            guard let index = ids.firstIndex(of: current) else { return nil }
            return ManagedDisplay(identifier: identifier, spaceIDs: ids, currentIndex: index)
        }
    }

    static func setCurrentSpace(_ spaceID: UInt64, on display: String) {
        guard let connection, let setSpace else { return }
        setSpace(connection, display as CFString, spaceID)
    }

    /// The spaces a given screen's menu bar controls, and every screen that moves with
    /// them. With "Displays have separate Spaces" on, each display is listed under its
    /// own UUID and only that one moves. With it off, the displays share a single entry
    /// under a name that matches no screen, and they all move together.
    static func target(for screen: NSScreen) -> (display: ManagedDisplay, screens: [NSScreen])? {
        let all = displays()
        guard let shared = all.first else { return nil }
        if let uuid = identifier(for: screen),
           let match = all.first(where: { $0.identifier == uuid }) {
            return (match, [screen])
        }
        return (shared, NSScreen.screens)
    }

    /// The window server names displays by UUID, which is what `CGDisplayCreateUUID`
    /// produces from the display ID `NSScreen` carries.
    static func identifier(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
