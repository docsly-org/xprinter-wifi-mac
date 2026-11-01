#!/bin/bash
# Builds "Xprinter Setup.app" (universal, ad-hoc signed) into ./dist
set -euo pipefail
cd "$(dirname "$0")"

# Build in a fixed neutral folder: the compiler embeds the build path in the binary,
# and a path under /Users/<name>/ would publish the builder's user name.
WORK=/tmp/xprinter-setup-build
rm -rf "$WORK" && mkdir -p "$WORK"
rsync -a --exclude .build --exclude dist --exclude .git ./ "$WORK/"
(cd "$WORK" && swift build -c release --arch arm64 --arch x86_64)
BIN=$(cd "$WORK" && swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

APP="dist/Xprinter Setup.app"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/XprinterSetup" "$APP/Contents/MacOS/"
strip -S -x "$APP/Contents/MacOS/XprinterSetup"  # drop debug paths to object files
cp -R "$BIN"/*.bundle "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/"
cp Assets/AppIcon.icns "$APP/Contents/Resources/"
[ -d AppResources ] && cp -R AppResources/*.lproj "$APP/Contents/Resources/"  # localized permission texts
codesign --force --deep -s - "$APP"

(cd dist && ditto -c -k --keepParent "Xprinter Setup.app" "Xprinter-Setup.zip")
echo "Built: $APP and dist/Xprinter-Setup.zip"
