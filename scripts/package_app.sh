#!/bin/sh
set -eu

swift build -c release --product DontSwitchMics
swift build -c release --product dontswitchmicsctl
BIN_DIR="$(swift build --show-bin-path -c release)"

APP_DIR="dist/DontSwitchMics.app"
rm -rf "$APP_DIR" "dist/DontSwitchMics.zip"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/DontSwitchMics" "$APP_DIR/Contents/MacOS/DontSwitchMics"
cp "Bundle/Info.plist" "$APP_DIR/Contents/Info.plist"

xattr -cr "$APP_DIR"
codesign --force --sign - "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "dist/DontSwitchMics.zip"
