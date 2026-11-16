#!/bin/zsh
# Builds Trickpad Dev from this checkout, installs it over the copy in
# /Applications, and opens it. Opening it takes over from the released copy;
# quitting it from the menu hands back.
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="Trickpad Dev"
BUNDLE_ID="fyi.thirdwind.trickpad.dev"
BUILT="$ROOT/build/$APP_NAME.app"
INSTALL_DIR="${TRICKPAD_DEV_INSTALL_DIR:-/Applications}"
INSTALLED="$INSTALL_DIR/$APP_NAME.app"
# Earlier builds were named "Trickpad DEV". On a case-sensitive volume that is a
# separate folder, and leaving it would keep two Dev copies in Spotlight.
LEGACY="$INSTALL_DIR/Trickpad DEV.app"

"$ROOT/scripts/build.sh" --dev >/dev/null

# Quit through the application rather than its menu, so the running Dev copy
# does not hand back to the released copy only to take over again below.
# Case-insensitive, so it also finds a copy still running under the old name.
running_dev() {
  pgrep -if "/Trickpad Dev\.app/Contents/MacOS/" >/dev/null 2>&1
}
if running_dev; then
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    running_dev || break
    sleep 0.25
  done
  if running_dev; then
    echo "$APP_NAME did not quit; quit it and run this again." >&2
    exit 1
  fi
fi

rm -rf "$INSTALLED" "$LEGACY"
ditto "$BUILT" "$INSTALLED"
open "$INSTALLED"

stamp="$(/usr/libexec/PlistBuddy -c 'Print :TrickpadBuildStamp' "$INSTALLED/Contents/Info.plist" 2>/dev/null || true)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED/Contents/Info.plist")"
echo "Opened $INSTALLED ($version${stamp:+ $stamp})"
