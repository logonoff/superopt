import Cocoa

/// One display's spaces, as the window server lists them.
struct ManagedDisplay {
    /// The window server's name for the display: its UUID when displays have separate
    /// spaces, or a single shared name when they change space together.
    let identifier: String
    let spaceIDs: [UInt64]
    let currentIndex: Int
    let spaceTypes: [Int?]
}

/// Reads which space each display is showing.
///
/// Spaces have no public API at all: AppKit lets a window say which spaces it joins
/// (`NSWindow.CollectionBehavior`) and stops there, so a process cannot ask how many
/// spaces exist or which one is current. `SLSMainConnectionID` returns this process's
/// connection to the window server and `SLSCopyManagedDisplaySpaces` returns, per
/// display, the ordered list of spaces and which is current — in strip order, left to
/// right, as `SpaceShortcut` moves through them.
///
/// Reading only. Changing the space goes through `SpaceShortcut`, because the matching
/// setter here leaves the menu bar drawing two apps at once.
@MainActor
enum SpaceSwitcher {
    private typealias MainConnectionFn = @convention(c) () -> UInt32
    // Typed as Unmanaged because the hand-written signature carries no
    // audit annotation: a plain CFArray? return is treated by ARC as a
    // borrowed reference, so the Copy rule's +1 would never be released
    // (measured with CFGetRetainCount against an audited call — one extra
    // retain). takeRetainedValue consumes it.
    private typealias CopyDisplaySpacesFn = @convention(c) (UInt32) -> Unmanaged<CFArray>?

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

    // SLSCopyWindowsWithOptionsAndTags includes windows on inactive desktops and,
    // with options 0x7, minimized windows. Core Graphics lists windows but does
    // not expose their Space membership. Bit 11 excludes all-Spaces windows.
    private typealias CopyWindowsFn = @convention(c) (
        UInt32, UInt32, CFArray, UInt32, UnsafePointer<UInt64>, UnsafePointer<UInt64>
    ) -> Unmanaged<CFArray>?
    private static let copyWindows: CopyWindowsFn? = skyLight.flatMap {
        dlsym($0, "SLSCopyWindowsWithOptionsAndTags").map { unsafeBitCast($0, to: CopyWindowsFn.self) }
    }

    static func windows(on space: UInt64) -> [CGWindowID]? {
        guard let connection, let copyWindows else { return nil }
        var required: UInt64 = 0
        var excluded: UInt64 = 1 << 11
        return copyWindows(connection, 0, [space] as CFArray, 0x7, &required, &excluded)?
            .takeRetainedValue() as? [CGWindowID]
    }

    static func displays() -> [ManagedDisplay] {
        guard let connection, let copyDisplaySpaces,
              let raw = copyDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        return raw.compactMap { entry in
            // The identifier alone makes a row worth keeping: a display whose
            // other fields did not decode is present but unreadable — a
            // mid-transition read — and dropping it would make a
            // list-pruning consumer mistake the misread for a disconnect. A
            // row with no identifier at all names nothing; that is what a
            // real disconnect looks like.
            guard let identifier = entry["Display Identifier"] as? String else { return nil }
            let spaces = (entry["Spaces"] as? [[String: Any]]) ?? []
            let current = (entry["Current Space"] as? [String: Any])?["id64"] as? UInt64
            let ids = spaces.compactMap { $0["id64"] as? UInt64 }
            // The current space can fail to appear among the display's
            // spaces, and a space list can fail to fully decode, in a
            // mid-transition read. The row is kept with an out-of-range
            // index rather than dropped, so the space-change watcher does
            // not mistake the misread for a disconnect and erase the
            // display's baseline; the other consumers treat the index as
            // unreadable or bail on it. A hole in the list would shift every
            // position after it, so a partial list resolves no index at
            // all — not one against the entries that did decode.
            let index = ids.count == spaces.count
                ? current.flatMap { ids.firstIndex(of: $0) } ?? ids.count
                : ids.count
            return ManagedDisplay(identifier: identifier, spaceIDs: ids, currentIndex: index,
                                  spaceTypes: spaces.map { $0["type"] as? Int })
        }
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
        // The shared-spaces configuration collapses the list to a single entry
        // under a name that matches no screen, and they all move together.
        // Reaching this point any other way — a UUID that will not resolve, a
        // display the window server has not listed yet — has no known answer,
        // and another display's row would be the wrong one to switch by.
        let identifiers = Set(all.map(\.identifier))
        let anyScreenListed = NSScreen.screens.contains {
            identifier(for: $0).map(identifiers.contains) ?? false
        }
        // One entry that names no screen is the shared configuration itself;
        // anything else reaching this point is a resolution failure with no
        // known answer.
        guard all.count == 1, !anyScreenListed else { return nil }
        return (shared, NSScreen.screens)
    }

    /// The screens that show a given entry's spaces: the one display it names, or every
    /// screen when the displays share a single set of spaces between them.
    static func screens(showing display: ManagedDisplay) -> [NSScreen] {
        if let match = NSScreen.screens.first(where: { identifier(for: $0) == display.identifier }) {
            return [match]
        }
        return NSScreen.screens
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
