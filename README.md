<h1>
    <img align="top" src="./docs/favicon.png" alt width="36" />
    SuperOpt
</h1>

[![GitHub Release](https://img.shields.io/github/v/release/logonoff/superopt?color=%23FBB040)](https://github.com/logonoff/superopt/releases/latest)
[![WTFPL](http://www.wtfpl.net/wp-content/uploads/2012/12/wtfpl-badge-4.png)](http://www.wtfpl.net/)

> [!WARNING]
> This is AI slop and I have not vetted the code. Use at your own risk!

A macOS menu bar app that brings GNOME desktop muscle memory to macOS. Requires **macOS 26 (Tahoe)** or later.

<video src="https://github.com/user-attachments/assets/8d14ad15-434d-4318-a1ab-e16173e018d5" controls muted style="max-width: 100%; border-radius: 8px;"></video>

## Install

```
brew tap logonoff/bucket
brew install --cask superopt
```

Or build from source:

```
./build.sh && ./install.sh
```

### Gatekeeper

The app is not notarized. Right-click and select "Open" on first launch, or run:

```
xattr -d com.apple.quarantine /Applications/SuperOpt.app
```

## Features

### Option Key Shortcuts

| Shortcut | Action |
|---|---|
| Single press `⌥` | Open Mission Control |
| Double press `⌥` | Open Spotlight Apps |
| `⌥`+`A` | Open Spotlight Apps |
| `⌥`+`1-9` | Launch the Nth app in the Dock |

### Desktop

| Feature | Description |
|---|---|
| Hot Corner | Move mouse to top-left corner → Mission Control (with GNOME ripple animation) |
| Window Tiling | `⌥`+Arrow keys to tile, maximize, or restore windows (off by default) |
| Green Button Fills | Green button fills window instead of full screen (off by default) |
| Close in Mission Control | Hover over a window in Mission Control to show a close button |
| Dark Menu Bar | Opaque bar behind transparent menu bar when a window fills the screen (off by default) |

### Keyboard

| Feature | Description |
|---|---|
| Caps Lock OSD | On-screen notification when Caps Lock is toggled |
| Home/End | Line start/end in text fields. Ctrl+Home/End for document start/end |
| Shortcut Remapping | Maps Linux shortcuts to Mac equivalents — Ctrl+C/V/X, Alt+F4, F2 rename, browser/terminal/code editor shortcuts, and more. Each can be individually toggled. (off by default) |

### Input

| Feature | Description |
|---|---|
| Menu Key | The Menu key on PC keyboards opens a shortcut menu (off by default) |
| Scroll Zoom | Ctrl+scroll zooms in browsers, with natural or traditional direction (off by default) |
| Cut & Paste Files | Ctrl+X then Ctrl+V in Finder moves files instead of duplicating (off by default) |
| Middle-click Paste | Paste on text fields (X11-style), new window from Dock, native behavior elsewhere (off by default) |

All features can be individually toggled on/off. Option key detection happens on key-up, so existing shortcuts are unaffected.

## Build

```
./build.sh
```

Requires Xcode command line tools (`xcode-select --install`).

## Permissions

SuperOpt requires two permissions in System Settings → Privacy & Security:

1. **Accessibility** — synthetic key events and window management
2. **Input Monitoring** — global keyboard and mouse event detection

Use the "Request Permissions..." menu item to open the relevant panes.

## Privacy

SuperOpt runs entirely offline. It does not collect telemetry, phone home, make network requests, or transmit any data. All processing happens locally on your Mac. The source code is available for review in this repository.

## License

[WTFPL v2](http://www.wtfpl.net/)

This program is free software. It comes without any warranty, to the extent permitted by applicable law.
