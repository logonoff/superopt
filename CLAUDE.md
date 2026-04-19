# OptWin

A macOS menu bar app that repurposes the Option key and adds GNOME-style hot corners.

**Keep this file up to date.** When adding features, changing architecture, or learning new project conventions, update the relevant sections below so future sessions have full context.

## Features

- **Single press `⌥`** → Opens Mission Control
- **Double press `⌥`** → Opens Spotlight Applications section (via `spotlight://apps` URL)
- **Hot corner** → Slamming mouse to top-left corner of any screen opens Mission Control with a GNOME-style ripple animation
- **Opt+1–9** → Launches the Nth app in the Dock (position 1 = Finder, then persistent-apps from `com.apple.dock.plist`). Consumes the keypress so no special character is typed. "Finder Position" submenu lets you place Finder at any slot 1–9 (default 1), shifting other apps to fill the gap. Disabled when parent feature is off.
- **Caps Lock OSD** → Shows a centered on-screen notification ("⇪ Caps Lock On/Off") when Caps Lock is toggled, inspired by gnome-shell-extension-lockkeys
- **Home/End remap** → When a text field is focused, Home/End keys move the cursor to the start/end of the line (like Windows/Linux) instead of scrolling. Uses the Accessibility API to detect focused text fields. Preserves Shift for text selection.
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
| `AppDelegate.swift` | Status bar menu, CGEventTap setup, event routing, action triggers (Mission Control / Spotlight). Contains the free `eventTapCallback` function (required for C interop). |
| `OptionKeyHandler.swift` | Tracks Option key state via `flagsChanged` events. Detects clean single/double presses using a timer. Exposes `onSinglePress` / `onDoublePress` closures. |
| `HotCorner.swift` | Monitors `mouseMoved` events and detects when cursor hits the top-left corner (2px zone) of any screen. Exposes `onTrigger(NSScreen)` closure. Handles CGEvent↔NSScreen coordinate conversion. |
| `RippleAnimation.swift` | Ported from GNOME Shell `js/ui/ripples.js`. Three concentric quarter-circle CAShapeLayer ripples with staggered scale/opacity animations. Displays in a borderless transparent window. |
| `DockLauncher.swift` | Reads persistent dock apps from `com.apple.dock.plist`. Finder is hardcoded at position 1. Launches apps via `NSWorkspace`. |
| `LockKeyOSD.swift` | Caps Lock on-screen display. Shows a dark rounded overlay centered on screen with fade in/out animations. Reuses the window if already visible. |
| `HomeEndHandler.swift` | Remaps Home/End to Cmd+Left/Right in text fields. Uses Accessibility API to detect focused text inputs. Preserves Shift for selection. |
| `MenuBarBackground.swift` | Shows a black bar behind the menu bar when a window fills the screen. Uses `CGWindowListCopyWindowInfo` to detect filled screens. `UnconstrainedWindow` subclass bypasses menu bar frame constraints. |

## Build & Install

```bash
./build.sh        # compiles Sources/*.swift → build/OptWin.app
./install.sh      # moves to /Applications (builds first if needed)
./install.sh --run # install and launch
```

No Xcode project — just `swiftc` with `-framework Cocoa`. Build script at `build.sh`. Version is stamped into `Info.plist` at build time via `git describe --tags --dirty --always`. If `actool` is available (requires full Xcode, not just CLT), the Liquid Glass icon from `icon.icon` is compiled into `Assets.car` and bundled; otherwise the icon step is skipped.

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
- **Permissions**: Requires both **Accessibility** and **Input Monitoring** in System Settings → Privacy & Security. Running from terminal inherits the terminal's permissions; running as a standalone app (via `open`) requires its own grants.
- **Code signing**: Ad-hoc signed (`codesign --force --sign -`) so permissions persist across rebuilds (tied to bundle ID, not binary hash).
- **App hides from Dock**: Both `LSUIElement=true` in Info.plist and `.accessory` activation policy.

## CI

GitHub Actions workflow at `.github/workflows/build.yml` — triggers on `x.y.z` tags, builds on `macos-26`, creates a GitHub release with `OptWin.zip` attached. Release notes are generated from `git log` since the previous tag. After the release, the workflow auto-updates the Homebrew cask (`Casks/optwin.rb`) with the new version and SHA, and commits to `main`.

A `Makefile` is also available with targets: `build`, `install`, `run` (kill → clean → install --run), `kill`, `clean`.

## Homebrew

A cask is hosted in this repo at `Casks/optwin.rb`. Install via:

```bash
brew tap logonoff/opt-win https://github.com/logonoff/opt-win
brew install --cask optwin
```

## License

WTFPL v2.
