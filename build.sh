#!/bin/bash
set -e

APP_NAME="OptWin"
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
cp -R Locales/*.lproj "$APP_BUNDLE/Contents/Resources/"

# Compile Liquid Glass icon if actool is available (requires Xcode, not just CLT)
if [ -d "Icon.icon" ] && actool --version &>/dev/null; then
    actool Icon.icon \
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
        --platform macosx
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string Icon" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconName Icon" "$APP_BUNDLE/Contents/Info.plist"
else
    echo "Skipping icon (actool not available or Icon.icon not found)"
fi

# Codesign the app bundle with an ad-hoc signature to allow it to run without Gatekeeper blocking it
codesign --force --sign - "$APP_BUNDLE"

echo "Build complete: $APP_BUNDLE"
echo ""
echo "To run:     open $APP_BUNDLE"
echo "To install: ./install.sh"
