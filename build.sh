#!/bin/bash
# Builds Blinders and wraps the binary in a Dock app bundle.
#   ./build.sh            build Blinders.app here
#   ./build.sh --install  also copy it to ~/Applications and relaunch it
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0
[ "${1:-}" = "--install" ] && INSTALL=1

VERSION="$(cat VERSION)"
APP="Blinders.app"

echo "==> swift build -c release"
swift build -c release
BIN=".build/release/Blinders"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Blinders"
# Regenerate with ./tools/make-icon.sh after editing tools/MakeIcon.swift.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Blinders</string>
  <key>CFBundleDisplayName</key><string>Blinders</string>
  <key>CFBundleExecutable</key><string>Blinders</string>
  <key>CFBundleIdentifier</key><string>com.tannergrandstaff.blinders</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHumanReadableCopyright</key><string>Tanner Grandstaff</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>Blinders control</string>
      <key>CFBundleURLSchemes</key><array><string>blinders</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Blinders asks for no TCC permissions (Carbon hotkey + mouse-move monitor),
# so ad-hoc signing is fine here: there are no grants for a rebuild to break.
codesign --force --sign - "$APP" >/dev/null 2>&1

DEST="$APP"
if [ "$INSTALL" = "1" ]; then
  DEST="$HOME/Applications/$APP"
  mkdir -p "$HOME/Applications"
  pkill -x Blinders 2>/dev/null && sleep 1 || true
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
fi

LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f "$DEST" || true

if [ "$INSTALL" = "1" ]; then
  open "$DEST"
  echo "==> installed and launched: $DEST"
else
  echo "==> done: $(pwd)/$APP"
fi
