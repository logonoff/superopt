<h1>
    <img align="top" src="./docs/favicon.png" alt width="36" />
    SuperOpt
</h1>

[![GitHub Release](https://img.shields.io/github/v/release/logonoff/superopt?color=%23FBB040)](https://github.com/logonoff/superopt/releases/latest)
[![WTFPL](http://www.wtfpl.net/wp-content/uploads/2012/12/wtfpl-badge-4.png)](http://www.wtfpl.net/)

> [!WARNING]
> This is AI slop and I have not vetted the code. Use at your own risk!

A macOS menu bar app that brings GNOME desktop muscle memory to macOS. Requires **macOS Tahoe 26** or later.

## Install

```
brew install logonoff/bucket/superopt
```

Or build from source:

```
./build.sh && ./install.sh
```

### Gatekeeper

The app is not notarized. Control-click and choose "Open" the first time you open the app, or run:

```
xattr -d com.apple.quarantine /Applications/SuperOpt.app
```

## Features

### Option Key Shortcuts

| Shortcut | Action |
|---|---|
| Press `⌥` | Open Mission Control |
| Press `⌥` Twice | Open Spotlight Apps |
| `⌥`+`A` | Open Spotlight Apps |
| `⌥`+`1-9` | Open apps from the Dock by number |

### Desktop

| Feature | Description |
|---|---|
| Hot Corner | Move the pointer to the top-left corner → Mission Control (with GNOME ripple animation) |
| Window Tiling | `⌥`+arrow keys to tile, maximize, or restore windows (off by default) |
| Green Button Fills | The maximize button expands the window to fill the screen instead of entering full screen (off by default) |
| Close in Mission Control | Hold the pointer over a window in Mission Control to show a close button |
| Tile Assist | After tiling a window, a panel suggests other windows to fill the remaining space (off by default) |
| Dark Menu Bar | Opaque bar behind transparent menu bar when a window fills the screen (off by default) |

### Keyboard

| Feature | Description |
|---|---|
| Caps Lock Indicator | Onscreen notification when Caps Lock is turned on or off |
| Home/End | Line start/end in text fields. Ctrl+Home/End for document start/end |
| Shortcut Remapping | Maps Linux shortcuts to Mac equivalents — Ctrl+C/V/X, Alt+F4, F2 rename, browser/terminal/code editor shortcuts, and more. Each can be individually turned on or off. (off by default) |

### Input

| Feature | Description |
|---|---|
| Menu Key | The Menu key on PC keyboards opens a shortcut menu (off by default) |
| Scroll Zoom | Ctrl+scroll zooms in browsers, with natural or traditional direction (off by default) |
| Cut and Paste Files | Ctrl+X then Ctrl+V in the Finder moves files instead of duplicating (off by default) |
| Middle-Click Paste | Paste on text fields (X11-style), new window from the Dock, native behavior elsewhere (off by default) |

All features can be individually turned on or off. Option key detection happens on key-up, so existing shortcuts are unaffected.

## Build

```
./build.sh
```

Requires Xcode command line tools (`xcode-select --install`).

## Permissions

SuperOpt requires two permissions in System Settings > Privacy & Security:

1. **Accessibility** — synthetic key events and window management
2. **Input Monitoring** — global keyboard and mouse event detection

Use the "Request Permissions" menu item to open the relevant panes.

## Privacy

SuperOpt runs entirely offline. It does not collect telemetry, make network requests, or transmit any data. All processing happens locally on your Mac. The source code is available for review in this repository.

## License

[WTFPL v2](http://www.wtfpl.net/)

This program is free software. It comes without any warranty, to the extent permitted by applicable law.
