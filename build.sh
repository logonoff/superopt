#!/bin/bash
set -e

APP_NAME="SuperOpt"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

VERSION=$(git describe --tags --dirty --always 2>/dev/null || echo "unknown")

echo "Building $APP_NAME ($VERSION)..."

# Lint sources if SwiftLint is available, but don't fail the build if it's not installed (e.g., in CI)
if command -v swiftlint &>/dev/null; then
    swiftlint lint --strict --quiet Sources/
else
    echo "Warning: SwiftLint not found, skipping linting"
    echo "Run 'brew install swiftlint' to install SwiftLint"
fi

# Compile the app bundle
mkdir -p "$BUILD_DIR"

swiftc Sources/*.swift \
    -o "$BUILD_DIR/$APP_NAME" \
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
        --minimum-deployment-target 26.0 \
        --platform macosx 2>&1) || { echo "$ACTOOL_OUT"; exit 1; }
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string Icon" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconName Icon" "$APP_BUNDLE/Contents/Info.plist"
    # Extract 256x256 favicon from the compiled icns for the website
    ICNS="$APP_BUNDLE/Contents/Resources/Icon.icns"
    if [ -f "$ICNS" ]; then
        sips -s format png -z 256 256 "$ICNS" --out docs/favicon.png &>/dev/null
    fi
else
    echo "Skipping icon (actool not available or Icon.icon not found)"
fi

# Codesign the app bundle with an ad-hoc signature to allow it to run without Gatekeeper blocking it
codesign --force --sign - --options runtime --entitlements OptWin.entitlements "$APP_BUNDLE"

echo "Build complete: $APP_BUNDLE"
