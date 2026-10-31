#!/bin/bash
# Builds "Xprinter Setup.app" (universal, ad-hoc signed) into ./dist
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

APP="dist/Xprinter Setup.app"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/XprinterSetup" "$APP/Contents/MacOS/"
cp -R "$BIN/XprinterSetup_XprinterSetup.bundle" "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/"
cp Assets/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --deep -s - "$APP"

(cd dist && ditto -c -k --keepParent "Xprinter Setup.app" "Xprinter-Setup.zip")
echo "Built: $APP and dist/Xprinter-Setup.zip"
