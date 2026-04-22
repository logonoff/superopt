# SuperOpt

A macOS menu bar app that repurposes the Option key and adds GNOME-style hot corners.

**Keep this file up to date.** When adding features, changing architecture, or learning new project conventions, update the relevant sections below so future sessions have full context.

**Privacy: This app must never make network requests, collect telemetry, phone home, or transmit any data.** All processing is local. Do not add dependencies, analytics, crash reporting, or any code that communicates over the network.

## Features

- **Single press `⌥`** → Opens Mission Control
- **Double press `⌥`** → Opens Spotlight Applications section (via `spotlight://apps` URL)
- **Hot corner** → Slamming mouse to top-left corner of any screen opens Mission Control with a GNOME-style ripple animation
- **Opt+1–9** → Launches the Nth app in the Dock (position 1 = Finder, then persistent-apps from `com.apple.dock.plist`). Consumes the keypress so no special character is typed. "Finder Position" submenu lets you place Finder at any slot 1–9 (default 1), shifting other apps to fill the gap. Disabled when parent feature is off.
- **Caps Lock OSD** → Shows a centered on-screen notification ("⇪ Caps Lock On/Off") when Caps Lock is toggled, inspired by gnome-shell-extension-lockkeys
- **Home/End remap** → When a text field is focused, Home/End keys move the cursor to the start/end of the line (like Windows/Linux) instead of scrolling. Ctrl+Home/End jumps to the document start/end (Cmd+Up/Down). Uses the Accessibility API to detect focused text fields. Preserves Shift for text selection.
- **⌥A → Apps** → Option+A opens Spotlight Apps (same as double-press Option). Own UserDefaults key (`appGridEnabled`). Enabled by default.
- **Shortcut Remapping** → Maps Linux keyboard shortcuts to their Mac equivalents. Organized into categories (General, File, View, Text Editing, Finder, Tabs & Windows, Browsers, Terminal, Code Editor) with per-shortcut toggles in disclosure groups. Includes: Ctrl+C/X/V/Z/A/S/N/F/P/R/T/W/L etc. → ⌘ equivalents, Ctrl+Y → ⌘⇧Z (Redo), Ctrl+Q → ⌘Q (Quit), Ctrl+Delete → ⌥Delete (delete word), Ctrl+⌦ → ⌥⌦ (forward delete word), Ctrl+Left/Right → ⌥Left/Right (word navigation), Alt+F4 → ⌘W (close), Alt+L → ⌃⌘Q (lock screen), Alt+Enter → ⌘I (Properties). Finder-specific: F2 → Rename, ⌦ → Move to Trash. Browser shortcuts: Ctrl+R (reload), Ctrl+Shift+I/F12 (DevTools → ⌘⌥I), Ctrl+H (history → ⌘Y), Ctrl+Shift+P (private window, Firefox). Terminal shortcuts: Ctrl+Shift+C/V/W/Q/T → ⌘C/V/W/Q/T (only in terminal apps). Terminal apps pass through plain Ctrl+C/D/E/L/U/W/Z unchanged. Code Editor shortcuts: Ctrl+H → ⌘⌥F (Find and Replace), Ctrl+/ (comment), Ctrl+] / Ctrl+[ (indent/outdent), Ctrl+Shift+Up/Down → ⌥Up/Down (move line), etc. — only active in VS Code, Cursor, JetBrains, Zed, Sublime Text, Nova. Finder, Browsers, Terminal, and Code Editor categories are app-gated — shortcuts only fire in the matching app. Disabled shortcuts stored in `gnomeDisabledShortcuts` UserDefaults array. Master toggle and all shortcuts disabled by default.
- **Cut & Paste Files in Finder** → Emulates GNOME-style file cut & paste. Ctrl+X copies files and marks for move, Ctrl+V moves instead of duplicating (posts ⌘⌥V). Ctrl+C cancels pending cut. Only active in Finder when no text field is focused. Own handler class (`FinderCutHandler`), own UserDefaults key (`finderCutEnabled`). Disabled by default.
- **Middle-click Paste** → Context-aware middle mouse button matching GNOME/X11 behavior. The click always passes through first (positioning the cursor), then pastes if the click target is a text field — checked via `AXUIElementCopyElementAtPosition` before the click and `isFocusedOnTextField` after a 50ms delay. On Dock app icons, opens a new window (activates the app and posts ⌘N, or just launches if not running). On other Dock elements, consumed with no action. Non-text-field clicks pass through unchanged (browsers get native open-in-new-tab, other apps get default middle-click). Own handler class (`MiddleClickPasteHandler`), own UserDefaults key (`middleClickPasteEnabled`). Disabled by default.
- **Scroll Zoom** → Ctrl+scroll zooms in and out in browsers. Supports natural (scroll up = zoom in) and traditional (scroll down = zoom in) scroll directions via a picker (Off/Natural/Traditional). Own handler class (`ScrollZoomHandler`), own UserDefaults key (`scrollZoomMode`). Disabled by default.
- **Window Tiling** → Option+Arrow keys tile, maximize, or restore windows by triggering native macOS tiling via Accessibility menu item pressing. Option+Up → Fill, Option+Down → Return to Previous Size, Option+Left/Right → Left/Right half. Own handler class (`WindowTilingHandler`), own UserDefaults key (`windowTilingEnabled`). Disabled by default.
- **Green Button Fills Window** → Clicking the green traffic light fills the window to the visible screen area instead of entering full screen. Clicking again restores the previous window size. Uses Accessibility API to detect the green button (`AXFullScreenButton`/`AXZoomButton` subrole), find the parent window, and set `AXPosition`/`AXSize` directly. Saves pre-zoom frames keyed by PID + window title. Own handler class (`ZoomButtonHandler`), own UserDefaults key (`zoomButtonEnabled`). Disabled by default.
- **Dark Menu Bar** → When a window fills the screen, shows a black bar behind the transparent menu bar to make it opaque. Disabled by default. Auto-disabled if macOS "Show menu bar background" system setting is on (`SLSMenuBarUseBlurredAppearance`). Repositions on screen parameter changes.
- All features can be individually toggled on/off via the status bar menu (persisted via UserDefaults, all enabled by default)
- **Every new feature must have a toggle** in the status bar menu, persisted via UserDefaults, enabled by default
- **Request Permissions** menu item — checks Accessibility (`AXIsProcessTrusted`) and Input Monitoring (event tap exists), offers buttons to open each settings pane directly
- Option key detection happens on key-up so existing keyboard shortcuts are unaffected

## Architecture

Single-target Swift app compiled with `swiftc` (no Xcode project, no SPM). All sources are in `Sources/`.

| File | Purpose |
|---|---|
| `main.swift` | Entry point — creates NSApplication, sets `.accessory` policy, runs the app |
| `AppDelegate.swift` | Status bar menu, CGEventTap setup, event routing, action triggers (Mission Control / Spotlight). Contains the free `eventTapCallback` function (required for C interop). Menu contains Settings/Permissions/About/Quit — feature toggles are in the settings window. |
| `SettingsWindow.swift` | SwiftUI `Form` with `.grouped` style embedded in an NSWindow via `NSHostingView`. Uses `@AppStorage` for live UserDefaults binding. Opened via Cmd+Comma or the menu. |
| `PermissionHelper.swift` | Handles first-launch and menu-triggered permission dialogs. Loops with Continue/Open Accessibility/Open Input Monitoring/Quit. Auto-dismisses via 1s timer when permissions are granted. Repositions to top-right to avoid overlapping the system accessibility prompt. |
| `OptionKeyHandler.swift` | Tracks Option key state via `flagsChanged` events. Detects clean single/double presses using a timer. Exposes `onSinglePress` / `onDoublePress` closures. |
| `HotCorner.swift` | Monitors `mouseMoved` events and detects when cursor hits the top-left corner (2px zone) of any screen. Exposes `onTrigger(NSScreen)` closure. Handles CGEvent↔NSScreen coordinate conversion. |
| `RippleAnimation.swift` | Ported from GNOME Shell `js/ui/ripples.js`. Three concentric quarter-circle CAShapeLayer ripples with staggered scale/opacity animations. Displays in a borderless transparent window. |
| `DockLauncher.swift` | Reads persistent dock apps from `com.apple.dock.plist`. Finder is hardcoded at position 1. Launches apps via `NSWorkspace`. |
| `LockKeyOSD.swift` | Caps Lock on-screen display. Shows a dark rounded overlay centered on screen with fade in/out animations. Reuses the window if already visible. |
| `HomeEndHandler.swift` | Remaps Home/End to Cmd+Left/Right (line start/end) and Ctrl+Home/End to Cmd+Up/Down (document start/end) in text fields. Uses Accessibility API to detect focused text inputs. Preserves Shift for selection. |
| `GnomeShortcutHandler.swift` | Strictly 1:1 keyboard shortcut remappings — one input key combo maps to one output key combo. Data-driven: contains `GnomeShortcutDef` struct and static shortcut definitions (9 categories, 40+ shortcuts) used by both handler and settings UI. Handles Ctrl→Cmd swaps, special remaps (Redo, word nav, DevTools), Alt shortcuts, Finder-specific actions (rename, trash), terminal Ctrl+Shift shortcuts, and no-modifier F-key remaps. Per-shortcut enablement via `disabledShortcuts` set. Features involving state, different event types, AX manipulation, or non-keyboard input belong in their own handler class. |
| `ScrollZoomHandler.swift` | Ctrl+scroll zoom for browsers. Intercepts scroll wheel events with Ctrl held and posts ⌘+/⌘- key events. Supports natural and traditional scroll directions via `ScrollZoomMode` enum. Own UserDefaults key (`scrollZoomMode`). |
| `FinderCutHandler.swift` | Emulates GNOME-style file cut & paste in Finder. Ctrl+X copies and sets `cutPending` flag, Ctrl+V posts ⌘⌥V (move) when flag is set, Ctrl+C clears the flag. Skips text fields via Accessibility API. Own UserDefaults key (`finderCutEnabled`). |
| `MiddleClickPasteHandler.swift` | Context-aware middle mouse button. On Dock app icons, opens a new window via AX traversal + ⌘N. In browsers, passes through for native open-in-new-tab. Elsewhere, X11-style paste (⌘V). Uses `AXUIElementCopyElementAtPosition` and PID comparison to detect Dock clicks, traverses parent chain to find `AXApplicationDockItem` subrole, reads `kAXURLAttribute` for the app path. Own UserDefaults key (`middleClickPasteEnabled`). |
| `WindowTilingHandler.swift` | GNOME-style window tiling via Option+Arrow keys. Searches the frontmost app's menu bar via AX for Window → Move & Resize items and presses them via `AXUIElementPerformAction(kAXPressAction)`. Matches by `AXMenuItemCmdVirtualKey` (arrow keys for Left/Right) or `AXMenuItemCmdChar` (F/R for Fill/Return) with modifier value 28 (fn+Ctrl). Synthetic events are tagged via `KeyboardUtils.syntheticTag` and skipped in `handleKeyDown` to prevent re-entrant handling. Own UserDefaults key (`windowTilingEnabled`). |
| `ZoomButtonHandler.swift` | Green button fill-window. Detects clicks on `AXFullScreenButton`/`AXZoomButton` via `AXUIElementCopyElementAtPosition`, traverses to parent `AXWindow`, and toggles between filling the visible screen and restoring the saved frame via `AXPosition`/`AXSize`. Stores pre-zoom frames keyed by PID + title. Own UserDefaults key (`zoomButtonEnabled`). |
| `GnomeShortcutSettings.swift` | `ObservableObject` managing per-shortcut enabled/disabled state. Stores disabled shortcut IDs in `gnomeDisabledShortcuts` UserDefaults array. Provides `Binding<Bool>` per shortcut for SwiftUI toggles. |
| `KeyboardUtils.swift` | Shared utilities: `postKey` (CGEvent key synthesis), `isTerminalApp`/`isFinderApp` (bundle ID checks), `isFocusedOnTextField` (Accessibility API role check), `terminalBundleIDs` set. Used by HomeEndHandler, GnomeShortcutHandler, and FinderCutHandler. |
| `MenuBarBackground.swift` | Shows a black bar behind the menu bar when a window fills the screen. Uses `CGWindowListCopyWindowInfo` to detect filled screens. `UnconstrainedWindow` subclass bypasses menu bar frame constraints. |

## Build & Install

```bash
./build.sh        # compiles Sources/*.swift → build/SuperOpt.app
./install.sh      # moves to /Applications (builds first if needed)
./install.sh --run # install and launch
```

No Xcode project — just `swiftc` with `-framework Cocoa`. Build script at `build.sh`. A `Package.swift` exists for IDE support (symbol resolution across files) but is not used for production builds. Version is stamped into `Info.plist` at build time via `git describe --tags --dirty --always`. If `actool` is available (requires full Xcode, not just CLT), the Liquid Glass icon from `Icon.icon` is compiled into `Assets.car` and bundled; otherwise the icon step is skipped. SwiftLint runs before compilation if installed (`brew install swiftlint`); build fails on any violation. **Every `// swiftlint:disable` comment must have a justification comment explaining why the rule can't be satisfied.** Fix the underlying issue instead of disabling the rule when possible. For `force_cast` on Core Foundation types (`AXUIElement`, `AXValue`), use the `KeyboardUtils.toAXElement`/`toAXValue` helpers instead of inline disables.

## Localization

All user-visible strings are localizable. Non-SwiftUI strings (menu items, alerts, OSD text) use `NSLocalizedString()`. SwiftUI `Text("literal")` strings auto-resolve via `LocalizedStringKey`.

- **Languages**: English (en), Arabic (ar), Chinese Simplified (zh-Hans), French (fr), Russian (ru), Spanish (es)
- **Source strings**: `Locales/en.lproj/Localizable.strings` (UTF-8, checked into repo)
- **Regenerating**: Delete `Locales/en.lproj/` and run `./build.sh` — it runs `genstrings` and converts from UTF-16 to UTF-8. SwiftUI `Text()` literals are covered by dummy `NSLocalizedString` calls at the top of `SettingsWindow.swift`.
- **Adding a language**: Create `Locales/XX.lproj/Localizable.strings` (copy from `Locales/en.lproj/`, translate the right-hand values). The build script copies all `Locales/*.lproj` directories automatically.
- **Adding new strings**: For AppKit code, wrap in `NSLocalizedString("key", comment: "description")`. For SwiftUI `Text()` literals, also add a dummy `NSLocalizedString` call in the `_settingsStrings` block at the top of `SettingsWindow.swift` so `genstrings` extracts it. **When adding or removing strings, update all locale files** (`ar`, `zh-Hans`, `fr`, `ru`, `es`) — the build script warns on missing or extra keys.

## Key Implementation Details

- **Event tap**: Active tap (`CGEventTapOptions.defaultTap`) on `cgSessionEventTap`. Monitors: `flagsChanged`, `keyDown`, mouse down events, `mouseMoved`. Re-enables itself on `tapDisabledByTimeout`. Only Opt+N keyDown events are consumed; all other events pass through unchanged.
- **Dock shortcuts**: Reads `~/Library/Preferences/com.apple.dock.plist` → `persistent-apps` array. Finder is always position 1. Virtual key codes 0x12–0x19 map to number keys 1–9.
- **Option key "clean press"**: A press is dirty (ignored) if any other key, mouse button, or modifier is used while Option is held. This prevents triggering on Opt+Tab, Cmd+Opt, Opt+Click, etc.
- **Double press timing**: 300ms threshold between two clean Option releases.
- **Spotlight trigger**: Opens `spotlight://apps` URL which opens the Spotlight Applications section on macOS 26.
- **Mission Control trigger**: Runs `/usr/bin/open -a "Mission Control"`.
- **Hot corner detection**: Uses velocity-based triggering inspired by GNOME's `PressureBarrier`. GNOME accumulates cursor pressure (100px threshold in a 1000ms window) against pointer barriers. Since macOS pointer barriers are private API, we approximate by measuring cursor speed — only triggers when the cursor enters the 2px corner zone at ≥500 pts/sec, filtering out slow drifts. Resets when cursor leaves the zone.
- **Hot corner coordinate math**: CGEvent uses flipped coordinates (0,0 = top-left of primary display). NSScreen uses bottom-left origin. Conversion: `cgY = primaryScreenHeight - nsY - screenHeight`.
- **Ripple animation**: Uses GNOME's exact parameters — three ripples with delays 0/50/350ms, durations 830/1000/1000ms, scale easeOut, opacity easeIn. Quarter-circle shape via CGPath arc.
- **Permissions**: Requires both **Accessibility** and **Input Monitoring** in System Settings → Privacy & Security. Running from terminal inherits the terminal's permissions; running as a standalone app (via `open`) requires its own grants. Accessibility is checked via `AXIsProcessTrusted()`. Input Monitoring is checked via `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` (not a public Swift symbol — accessed via `dlsym`). The event tap (`CGEvent.tapCreate`) requires both permissions, so it can't distinguish which is missing on its own. Accessibility changes take effect immediately; Input Monitoring requires an app restart. A `DistributedNotificationCenter` observer on `com.apple.accessibility.api` detects Accessibility changes and tears down or re-creates the event tap. A 3s safety timer backs this up in case the notification doesn't fire.
- **Code signing**: Ad-hoc signed (`codesign --force --sign -`) so permissions persist across rebuilds (tied to bundle ID, not binary hash).
- **App hides from Dock**: Both `LSUIElement=true` in Info.plist and `.accessory` activation policy.
- **Menu bar background positioning**: macOS constrains normal windows below the menu bar area. `UnconstrainedWindow` overrides `constrainFrameRect(_:to:)` to bypass this. Windows must be created once and never destroyed to avoid position resets. Uses `NSApplication.didChangeScreenParametersNotification` to reposition when screen layout changes. Hides during Mission Control by checking for Dock-owned windows at layer > 0 in `CGWindowListCopyWindowInfo`.
- **Liquid Glass**: `NSGlassEffectView` is available on macOS 26. Style `1` (`NSGlassEffectView.Style(rawValue: 1)`) gives the "clear glass" variant. Use `contentView` property to embed content, not `addSubview`. `actool` compiles `Icon.icon` bundles from Icon Composer into `Assets.car`; requires full Xcode, not just CLT.
- **GNOME shortcuts app-aware gating**: Finder, Browsers, Terminal, and Code Editor category shortcuts only fire in matching apps. Browser apps: Safari, Firefox, Chrome, Edge, Brave, Opera, Vivaldi, Arc. Code editors: VS Code, Cursor, JetBrains, Zed, Sublime Text, Nova. The gated shortcut IDs are derived from the `allShortcuts` array filtered by category — adding a shortcut to any gated category automatically restricts it. `isEnabled()` checks both the disabled set and the app context. Ctrl+H contextually maps to Find and Replace (⌘⌥F) in code editors and View History (⌘Y) in browsers.
- **GNOME shortcuts terminal detection**: Reuses the same terminal bundle ID set as HomeEndHandler. In terminal apps, plain Ctrl+C/D/E/L/U/W/Z pass through unchanged since those are native terminal control sequences. Ctrl+Shift+C/V/W/Q are remapped to Cmd equivalents (copy/paste/close in terminals). All other Ctrl remaps still apply in terminals.
- **Finder cut & paste**: Handled by `FinderCutHandler`, separate from `GnomeShortcutHandler`. Ctrl+X posts Cmd+C and sets `cutPending` flag. Next Ctrl+V posts Cmd+Opt+V (move) instead of Cmd+V (duplicate). Ctrl+C clears the flag. Only active in Finder when no text field is focused (renaming). Own UserDefaults key (`finderCutEnabled`, default false). Checked before GNOME shortcuts in event routing so Ctrl+X/V in Finder is intercepted first.
- **GNOME shortcuts per-shortcut toggles**: Disabled shortcut IDs stored in `gnomeDisabledShortcuts` UserDefaults array. `GnomeShortcutHandler.reloadSettings()` rebuilds the disabled set from UserDefaults. Settings UI uses `GnomeShortcutSettings` ObservableObject with per-ID bindings. Shortcuts organized into 9 categories displayed as DisclosureGroups with checkbox-style toggles (per HIG: checkboxes for hierarchical settings).
- **⌥A → Apps**: Handled in AppDelegate's `handleKeyDown` as its own feature toggle (`appGridEnabled`), separate from GNOME shortcut remapping. Calls `triggerSpotlight()` (same as double-press Option). Checked before the GNOME shortcut handler in event routing.
- **Home/End in terminals**: CGEvents can't inject into a terminal's PTY. Terminal apps are skipped; users must configure Home/End in their terminal's keyboard settings and shell (`bindkey` in zsh).
- **Synthetic event tagging**: `KeyboardUtils.postKey` tags all synthetic events with `eventSourceUserData = 0x4F5054`. `AppDelegate.handleKeyDown` skips synthetic events (`KeyboardUtils.isSynthetic`) so remapped keys (e.g. Ctrl+Left → ⌥Left) don't trigger other handlers (e.g. window tiling) when they re-enter the event tap.
- **Event tap threading**: The CGEventTap callback runs on the main run loop because `CFRunLoopAddSource` is called with `CFRunLoopGetCurrent()` from `applicationDidFinishLaunching` (main thread). UI calls in the callback are safe without dispatching to main.
- **Privacy keys**: Info.plist must include `NSAccessibilityUsageDescription` and `NSListenEventUsageDescription` for Accessibility and Input Monitoring permissions.
- **Ripple window level**: Must use `.screenSaver` (not `.floating`) so the ripple renders above the menu bar. `.floating` renders below it.

## CI

GitHub Actions workflow at `.github/workflows/build.yml` — triggers on `x.y.z` tags, builds on `macos-26`, creates a GitHub release with `SuperOpt.zip` attached. Release notes are generated from `git log` since the previous tag. After the release, the workflow auto-updates the Homebrew cask (`Casks/superopt.rb`) with the new version and SHA, and commits to `main`.

A `Makefile` is also available with targets: `build`, `install`, `run` (kill → clean → install --run), `kill`, `clean`.

## Homebrew

A cask is hosted in this repo at `Casks/superopt.rb`. Install via:

```bash
brew tap logonoff/superopt https://github.com/logonoff/superopt
brew install --cask superopt
```

## Apple Documentation

To access Apple developer documentation as markdown, replace `developer.apple.com` with `sosumi.ai` in any URL:

- **APIs**: `https://sosumi.ai/documentation/{framework}/{symbol}` (e.g. `https://sosumi.ai/documentation/appkit/nswindow`)
- **HIG**: `https://sosumi.ai/design/human-interface-guidelines/{topic}`
- **WWDC transcripts**: `https://sosumi.ai/videos/play/{collection}/{id}`
- **External Swift-DocC**: `https://sosumi.ai/external/{full-https-url}`

Search before fetching when the path is uncertain. Target specific symbol pages for implementation questions. **All UI changes must consult the HIG** at `https://sosumi.ai/design/human-interface-guidelines` before implementation.

## Website

The project website is at `docs/index.html`, served via GitHub Pages from the `main` branch `/docs` folder. Keep it updated when adding or changing features.

## Git

Do not add a `Co-Authored-By` trailer to commit messages.

## License

WTFPL v2.
