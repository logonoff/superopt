<h1>
    <img align="top" src="./docs/favicon.png" alt width="36" />
    SuperOpt
</h1>

[![GitHub Release](https://img.shields.io/github/v/release/logonoff/superopt?color=%23FBB040)](https://github.com/logonoff/superopt/releases/latest)
[![WTFPL](http://www.wtfpl.net/wp-content/uploads/2012/12/wtfpl-badge-4.png)](http://www.wtfpl.net/)

> [!WARNING]
> This is AI slop and I have not thoroughly vetted the code. Use at your own risk.

A macOS menu bar app that brings GNOME desktop muscle memory to the Mac. Requires **macOS 27 Golden Gate** or later.

## Install

```
brew install logonoff/bucket/superopt
```

Or build from source:

```
./build.sh && ./install.sh
```

### Gatekeeper

This app is self-signed but not notarized, so macOS may block it the first time you try to open it. If it does, open System Settings, click Privacy & Security, scroll down, and then click Open Anyway, or remove the quarantine attribute before opening it:

```
xattr -d com.apple.quarantine /Applications/SuperOpt.app
```

### Verification

Releases are signed with a self-signed certificate (RSA-2048, CN=SuperOpt). The app is not notarized (I refuse to pay for the Apple Developer Program). To compensate:

- **[Build attestations](https://github.com/logonoff/superopt/attestations)**: every release zip has a GitHub build provenance attestation linking the artifact to the exact source commit and workflow run, so you can confirm the binary was built from the published source code and not tampered with after the fact. Verify with `gh attestation verify SuperOpt.zip --repo logonoff/superopt`.
- **[Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)**: tags with releases are never moved, and release assets are never replaced. The Homebrew cask pins a SHA-256 hash.
- **Signed commits**: all commits to `main` are GPG-signed.

Code-signing public key ([`codesign.pem`](https://logonoff.github.io/superopt/codesign.pem), RSA-2048; SHA-256 of the file: `4fbb60bb36dee64f110fba20aa10b6e8092ef844390b5151228487bdbebbc86d`).

## Features

### Option Key Shortcuts

| Shortcut | Action |
|---|---|
| ⌥ | Open Mission Control |
| ⌥ twice | Open Spotlight Apps |
| ⌥A | Open Spotlight Apps |
| ⌥1–9 | Open apps from the Dock by number |

### Desktop

| Feature | Description |
|---|---|
| Hot Corner | Quickly moving the pointer into the top-left corner of any screen opens Mission Control (with a GNOME ripple animation) |
| Window Tiling | The Option-arrow keys tile, fill, or restore windows (off by default) |
| Green Button Fills Screen | The green button fills the screen instead of entering full screen (off by default) |
| Close Windows in Mission Control | Holding the pointer over a window in Mission Control shows a close button |
| Type to Search in Mission Control | Typing in Mission Control closes it and passes what you typed to Spotlight search or Spotlight Apps (off by default) |
| Tile Assist | After tiling a window, SuperOpt suggests other windows to fill the remaining space (off by default) |
| Dark Menu Bar | Shows an opaque bar behind the transparent menu bar when a window fills the screen (off by default) |
| Scroll to Switch Spaces | Scrolling over the Apple menu switches that display to the next or previous space (off by default) |
| Space Indicator | Shows an onscreen row of dots when a display switches spaces (off by default) |

### Keyboard

| Feature | Description |
|---|---|
| Caps Lock Indicator | Shows an onscreen indicator when you turn Caps Lock on or off |
| Home and End | Home and End move the insertion point to the beginning or end of the line in text fields; Control-Home and Control-End move it to the beginning or end of the document |
| Shortcut Remapping | Maps Linux shortcuts to Mac equivalents—Control-X, Control-C, and Control-V; Alt-F4; F2 to rename in the Finder; browser, terminal, and code editor shortcuts; and more (off by default) |

### Input

| Feature | Description |
|---|---|
| Menu Key → Shortcut Menu | The Menu key on PC keyboards opens a shortcut menu (off by default) |
| Scroll Zoom in Browsers | Control-scroll zooms in and out in web browsers, with a Natural or Traditional scroll direction setting (off by default) |
| Click-Through Focus | Clicking an inactive window activates it and passes the click through, as on Windows or Linux (off by default) |
| Cut and Paste Files in the Finder | Cut, then paste in the Finder to move files—press Command-X, then Command-V, or Control-X, then Control-V, whichever pair you choose in SuperOpt’s settings (off by default) |
| Middle-Click Paste | Paste in text fields (X11-style), open a new window from the Dock, or use the native behavior elsewhere (off by default) |

All features can be individually turned on or off in SuperOpt’s settings, available from the menu bar icon. The Option key is detected when it’s released, so existing shortcuts are unaffected.

While you’re using an app on the Excluded Apps list, SuperOpt turns off every feature and dims its menu bar icon, so the app behaves as it would without SuperOpt (off by default).

## Build

```
./build.sh
```

Requires Command Line Tools for Xcode (`xcode-select --install`).

## Permissions

SuperOpt requires two permissions in System Settings, under Privacy & Security:

1. **Accessibility**—synthetic key events and window management
2. **Input Monitoring**—global keyboard and mouse event detection

Use the Request Permissions menu item to open the relevant panes.

## Privacy

SuperOpt runs entirely offline. It does not collect telemetry, make network requests, or transmit any data. All processing happens locally on your Mac. The source code is available for review in this repository.

## License

[WTFPL v2](http://www.wtfpl.net/)

This program is free software. It comes without any warranty, to the extent permitted by applicable law.
