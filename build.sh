#!/bin/bash
set -e

APP_NAME="SuperOpt"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Must match LSMinimumSystemVersion in Info.plist and actool's
# --minimum-deployment-target below.
DEPLOYMENT_TARGET="27.0"

# Load signing identity from .env if present (CODESIGN_IDENTITY="Your Certificate Name")
if [ -f .env ]; then
    source .env
fi
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

VERSION=$(git describe --tags --dirty --always 2>/dev/null || echo "unknown")

echo "Building $APP_NAME ($VERSION)..."

# Pin the toolchain. macOS gates behaviour changes on the SDK a binary was linked
# against, not on its deployment target, so building against an SDK older than
# DEPLOYMENT_TARGET makes a local build behave differently from the CI release —
# on macOS 27 that includes NSMenu hiding menu item images. Honour an explicit
# DEVELOPER_DIR, otherwise pick the newest installed Xcode that has a matching
# SDK, otherwise leave the selected toolchain alone and warn.
sdk_major() { echo "${1%%.*}"; }
TARGET_MAJOR=$(sdk_major "$DEPLOYMENT_TARGET")

current_sdk() { xcrun --sdk macosx --show-sdk-version 2>/dev/null | tail -1; }

# xcrun fails while Xcode is mid-upgrade or its licence is unaccepted, and returns
# an empty version. Comparing that numerically errors out, which would make the
# check below silently pass — the one failure mode it exists to catch.
is_number() { [ -n "$1" ] && [ "$1" -eq "$1" ] 2>/dev/null; }
sdk_too_old() {
    local major
    major=$(sdk_major "$1")
    is_number "$major" && [ "$major" -lt "$TARGET_MAJOR" ]
}

# Only full Xcode installs are candidates. The Command Line Tools can ship a newer
# SDK than the selected Xcode, but they provide neither the sourcekitd SwiftLint
# loads nor actool, so selecting them trades one broken build step for another.
if [ -z "$DEVELOPER_DIR" ] && sdk_too_old "$(current_sdk)"; then
    BEST_DIR=""
    BEST_SDK=""
    for CANDIDATE in /Applications/Xcode*.app/Contents/Developer; do
        [ -d "$CANDIDATE" ] || continue
        CANDIDATE_SDK=$(DEVELOPER_DIR="$CANDIDATE" xcrun --sdk macosx --show-sdk-version 2>/dev/null | tail -1)
        [ -n "$CANDIDATE_SDK" ] || continue
        if [ -z "$BEST_SDK" ] || [ "$(printf '%s\n%s\n' "$BEST_SDK" "$CANDIDATE_SDK" | sort -V | tail -1)" = "$CANDIDATE_SDK" ]; then
            BEST_DIR="$CANDIDATE"
            BEST_SDK="$CANDIDATE_SDK"
        fi
    done
    if [ -n "$BEST_DIR" ] && ! sdk_too_old "$BEST_SDK"; then
        export DEVELOPER_DIR="$BEST_DIR"
        echo "Selected Xcode with the macOS $BEST_SDK SDK: $BEST_DIR"
    fi
fi

SDK_VERSION=$(current_sdk)
if ! is_number "$(sdk_major "$SDK_VERSION")"; then
    echo "Warning: could not determine the macOS SDK version."
    echo "  'xcrun --sdk macosx --show-sdk-version' returned nothing, which usually means Xcode is"
    echo "  mid-upgrade or its licence has not been accepted (sudo xcodebuild -license)."
    if [ -n "$STRICT_SDK" ]; then
        echo "Error: STRICT_SDK is set and the SDK version could not be verified"
        exit 1
    fi
elif sdk_too_old "$SDK_VERSION"; then
    echo "Warning: building against the macOS $SDK_VERSION SDK but targeting $DEPLOYMENT_TARGET."
    echo "  macOS applies behaviour changes based on the linked SDK, so this build will not"
    echo "  match a release built against the macOS $TARGET_MAJOR SDK. Install Xcode $TARGET_MAJOR,"
    echo "  or set DEVELOPER_DIR to a toolchain that ships the macOS $TARGET_MAJOR SDK."
    # CI sets STRICT_SDK=1 so a release is never cut against the wrong SDK.
    if [ -n "$STRICT_SDK" ]; then
        echo "Error: STRICT_SDK is set and the SDK is older than the deployment target"
        exit 1
    fi
fi

# Lint sources if SwiftLint is available, but don't fail the build if it's not installed (e.g., in CI)
if command -v swiftlint &>/dev/null; then
    swiftlint lint --strict --quiet Sources/
else
    echo "Warning: SwiftLint not found, skipping linting"
    echo "Run 'brew install swiftlint' to install SwiftLint"
fi

# Compile the app bundle
mkdir -p "$BUILD_DIR"

# swiftc defaults the deployment target to a version newer than the running OS
# (minos 28.0 on macOS 27), which makes LaunchServices refuse to launch the app
# with kLSIncompatibleSystemVersionErr (-10825). MACOSX_DEPLOYMENT_TARGET is
# ignored here, so the target has to be passed explicitly.
swiftc Sources/*.swift \
    -o "$BUILD_DIR/$APP_NAME" \
    -target "$(uname -m)-apple-macos$DEPLOYMENT_TARGET" \
    -framework Cocoa \
    -O

mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp Info.plist "$APP_BUNDLE/Contents/"

# Stamp version into Info.plist so the about panel doesn't show a stale build number
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_BUNDLE/Contents/Info.plist"

# Generate and bundle localization strings
mkdir -p "$APP_BUNDLE/Contents/Resources"
LPROJ_SRC="Locales/en.lproj"
rm -rf "$LPROJ_SRC"
mkdir -p "$LPROJ_SRC"
genstrings -SwiftUI -o "$LPROJ_SRC" Sources/*.swift 2>/dev/null
iconv -f UTF-16 -t UTF-8 "$LPROJ_SRC/Localizable.strings" > "$LPROJ_SRC/Localizable.strings.tmp"
mv "$LPROJ_SRC/Localizable.strings.tmp" "$LPROJ_SRC/Localizable.strings"

# Validate and check translations against the English source
KEYS_TMP="/tmp/_superopt_keys.json"
KEYS_JS='
  var path = $.NSProcessInfo.processInfo.environment.objectForKey("_KEYS_FILE").js;
  var data = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  Object.keys(JSON.parse(data.js)).sort().map(JSON.stringify).join("\n");
'

extract_keys() {
    plutil -convert json -o "$KEYS_TMP" "$1"
    _KEYS_FILE="$KEYS_TMP" osascript -l JavaScript -e "$KEYS_JS"
}

EN_KEYS=$(extract_keys "$LPROJ_SRC/Localizable.strings")

for LPROJ in Locales/*.lproj; do
    [ "$LPROJ" = "$LPROJ_SRC" ] && continue
    LANG=$(basename "$LPROJ" .lproj)
    STRINGS="$LPROJ/Localizable.strings"

    if ! plutil -lint "$STRINGS" >/dev/null 2>&1; then
        echo "Error: $LANG.lproj/Localizable.strings is malformed"
        plutil -lint "$STRINGS"
        exit 1
    fi

    LANG_KEYS=$(extract_keys "$STRINGS")
    MISSING=$(comm -23 <(echo "$EN_KEYS") <(echo "$LANG_KEYS"))
    EXTRA=$(comm -13 <(echo "$EN_KEYS") <(echo "$LANG_KEYS"))

    if [ -n "$MISSING" ]; then
        echo "Warning: $LANG — added $(echo "$MISSING" | wc -l | tr -d ' ') key(s) with English placeholder text (translate these):"
        echo "$MISSING" | sed "s/^/  /"
    fi
    if [ -n "$EXTRA" ]; then
        echo "Warning: $LANG — removed $(echo "$EXTRA" | wc -l | tr -d ' ') stale key(s):"
        echo "$EXTRA" | sed "s/^/  /"
    fi

    # Reorder locale entries to match English key order.
    # Reads the locale file first to build a key→line map, then walks the
    # English file and outputs each line with the translated value substituted.
    awk '
    NR == FNR {
        if (/^"/) {
            key = $0; sub(/^"/, "", key); sub(/".*/, "", key)
            trans[key] = $0
        }
        next
    }
    {
        if (/^"/) {
            key = $0; sub(/^"/, "", key); sub(/".*/, "", key)
            if (key in trans) print trans[key]; else print
        } else {
            print
        }
    }
    ' "$STRINGS" "$LPROJ_SRC/Localizable.strings" > "${STRINGS}.tmp"
    mv "${STRINGS}.tmp" "$STRINGS"

    # Fail if any translation value equals the English source (untranslated).
    # Excludes: single-word keys, and shortcut labels (starting with ⌥/⌃/⇧/⌘).
    UNTRANSLATED=$(awk '
    NR == FNR {
        if (/^"/) en[NR] = $0
        next
    }
    /^"/ {
        key = $0; sub(/^"/, "", key); sub(/".*/, "", key)
        if (key !~ / /) next
        if (key ~ /^[⌥⌃⇧⌘⇪]/) next
        for (i in en) {
            if (en[i] == $0) { print key; break }
        }
    }
    ' "$LPROJ_SRC/Localizable.strings" "$STRINGS")
    if [ -n "$UNTRANSLATED" ]; then
        echo "Error: $LANG has untranslated strings (value = English source):"
        echo "$UNTRANSLATED" | sed "s/^/  /"
        exit 1
    fi
done

cp -R Locales/*.lproj "$APP_BUNDLE/Contents/Resources/"

# Compile Liquid Glass icon if actool is available (requires Xcode, not just CLT)
if [ -d "Icon.icon" ] && actool --version &>/dev/null; then
    ACTOOL_OUT=$(actool Icon.icon \
        --compile "$APP_BUNDLE/Contents/Resources" \
        --output-format human-readable-text \
        --notices --warnings --errors \
        --output-partial-info-plist /dev/null \
        --app-icon Icon \
        --include-all-app-icons \
        --enable-on-demand-resources NO \
        --development-region en \
        --target-device mac \
        --minimum-deployment-target "$DEPLOYMENT_TARGET" \
        --platform macosx 2>&1) || { echo "$ACTOOL_OUT"; exit 1; }
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string Icon" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconName Icon" "$APP_BUNDLE/Contents/Info.plist"
    # Extract 256x256 favicon from the compiled icns for the website
    ICNS="$APP_BUNDLE/Contents/Resources/Icon.icns"
    if [ -f "$ICNS" ]; then
        sips -s format png -z 256 256 "$ICNS" --out docs/favicon.png &>/dev/null
    fi
    # actool spawns ibtoold as a background daemon that outlives the build
    pkill -9 ibtoold 2>/dev/null || true
else
    echo "Skipping icon (actool not available or Icon.icon not found)"
fi

# Codesign the app bundle to allow it to run without Gatekeeper blocking it
# Uses CODESIGN_IDENTITY from .env if set, otherwise falls back to ad-hoc signing
codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --entitlements SuperOpt.entitlements "$APP_BUNDLE"

echo "Build complete: $APP_BUNDLE"
