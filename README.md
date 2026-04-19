# OptWin

> [!WARNING]
> This is AI slop and I have not vetted the code. Use at your own risk!

A tiny macOS menu bar app that repurposes the Option key. Requires **macOS 26 (Tahoe)** or later.

- **Single press `⌥`** → Mission Control
- **Double press `⌥`** → Spotlight Apps
- **Hot corner** → Slam mouse to top-left corner of any screen → Mission Control (with GNOME-style ripple animation)
- **`⌥`+`1-9`** → Launch the Nth app in your Dock (Finder position configurable)
- **Caps Lock OSD** → On-screen notification when Caps Lock is toggled
- **Home/End** → Moves cursor to line start/end in text fields (Linux behavior)
- **Dark Menu Bar** → Shows a black bar behind the transparent menu bar when a window fills the screen (off by default, requires "Show menu bar background" to be disabled in System Settings → Menu Bar as this replaces it)

All features can be individually toggled on/off from the menu bar. Detection happens on key-up, so existing keyboard shortcuts using Option are unaffected.

## Install

```
brew tap logonoff/opt-win https://github.com/logonoff/opt-win
brew install --cask optwin
```

Or build from source:

```
./build.sh && ./install.sh
```

### Gatekeeper

The app is not notarized, so macOS will warn about it on first launch. To bypass this, right-click the app and select "Open". You only need to do this once. Alternatively, you can run the following command in Terminal:

```
xattr -d com.apple.quarantine /Applications/OptWin.app
```

## Build

```
./build.sh
```

Requires Xcode command line tools (`xcode-select --install`).

## Permissions

OptWin requires two permissions:

1. **Accessibility** — needed to post synthetic key events (Spotlight trigger, Mission Control)
2. **Input Monitoring** — needed to detect key presses and mouse movement via the global event tap

Grant both in System Settings → Privacy & Security. Use the "Request Permissions..." menu item to open the relevant panes.

## License

[WTFPL](http://www.wtfpl.net/)
