#!/bin/bash
set -e

APP_NAME="OptWin"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

VERSION=$(git describe --tags --dirty --always 2>/dev/null || echo "unknown")

echo "Building $APP_NAME ($VERSION)..."

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

codesign --force --sign - "$APP_BUNDLE"

echo "Build complete: $APP_BUNDLE"
echo ""
echo "To run:    open $APP_BUNDLE"
echo "To install: cp -r $APP_BUNDLE /Applications/"
echo ""
echo "NOTE: Grant Accessibility permissions in"
echo "  System Settings -> Privacy & Security -> Accessibility"
