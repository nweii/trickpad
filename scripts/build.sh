#!/bin/zsh
set -euo pipefail

APP_NAME="Trickpad"
BUNDLE_ID="fyi.thirdwind.trickpad"

# --dev builds a development bundle that installs beside the released copy:
# its own name, bundle identifier, and icon, everything else shared. The
# separate identifier keys separate user defaults, a separate Accessibility
# grant, and separate updater state, so repeated test installs leave no state
# behind for the released copy. Both builds read the same config.toml, and
# SingleInstance.m keeps one copy running: a development build takes the
# shared instance lock over a running release copy.
if [[ "${1:-}" == "--dev" ]]; then
  APP_NAME="Trickpad DEV"
  BUNDLE_ID="fyi.thirdwind.trickpad.dev"
fi

APP_VERSION="0.10.1-dev"
APP_BUILD_NUMBER="19"
MIN_MACOS_VERSION="11.0"
ARCHITECTURES=(x86_64 arm64)
ROOT="${0:A:h:h}"
SRC_ROOT="$ROOT/src/jitouch/Jitouch"
BUILD_ROOT="$ROOT/build"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RES_DIR="$APP_BUNDLE/Contents/Resources"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
SPARKLE_FRAMEWORK="$ROOT/third_party/sparkle/Sparkle.framework"

# The appcast Sparkle asks for, and the public half of the EdDSA key pair that
# signs every update. Every copy in the wild asks for this URL forever, so it
# must not change once a release carries it.
#
# The key is empty until `generate_keys` has been run and its private half is
# in the Keychain with a recovery copy in 1Password. An empty key builds an app
# with no updater rather than one that cannot verify what it downloads.
SPARKLE_FEED_URL="https://updates.thirdwind.fyi/trickpad/9zvff4/appcast.xml"
SPARKLE_PUBLIC_KEY="PRUR58SW8YdEJmAFlzV+LxGjQR1xS8txBGJdU8ZOeyw="
ICON_SOURCE="$ROOT/icons/$APP_NAME.icon"
ICON_BUILD_SOURCE="$BUILD_ROOT/$APP_NAME.icon"
ICON_INFO="$BUILD_ROOT/TrickpadIconInfo.plist"

mkdir -p "$MACOS_DIR" "$RES_DIR"

# Icon Composer 2.0 writes a top-level feature declaration that its renderer
# understands but Xcode 26.6's asset compiler rejects. Compile a compatible
# generated copy while retaining the authored document unchanged.
ditto "$ICON_SOURCE" "$ICON_BUILD_SOURCE"
plutil -remove features "$ICON_BUILD_SOURCE/icon.json" 2>/dev/null || true

# Compile the Icon Composer document into the layered asset catalog macOS 26
# uses, plus the flattened ICNS fallback for earlier supported releases.
xcrun actool "$ICON_BUILD_SOURCE" \
  --compile "$RES_DIR" \
  --platform macosx \
  --minimum-deployment-target "$MIN_MACOS_VERSION" \
  --app-icon "$APP_NAME" \
  --output-partial-info-plist "$ICON_INFO" \
  --warnings \
  --notices \
  --errors >/dev/null

# An unreleased build reports the last shipped version number, so it carries
# the commit it was built from. A build made exactly at the version's clean
# tag carries no stamp, keeping releases pristine. A trailing + marks
# uncommitted changes.
BUILD_STAMP=""
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  head_commit="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
  tag_commit="$(git -C "$ROOT" rev-parse "v$APP_VERSION^{commit}" 2>/dev/null || true)"
  if [[ -n "$head_commit" ]]; then
    if [[ "$tag_commit" != "$head_commit" ]] || ! git -C "$ROOT" diff --quiet HEAD 2>/dev/null; then
      BUILD_STAMP="$(git -C "$ROOT" rev-parse --short HEAD)"
      git -C "$ROOT" diff --quiet HEAD 2>/dev/null || BUILD_STAMP="$BUILD_STAMP+"
    fi
  fi
fi
# An updater that cannot verify a signature is worse than no updater, so a
# missing key builds an app without one rather than one that trusts whatever it
# downloads. An empty BUILD_STAMP means this build sits on the clean release
# tag, and a release must never take that path.
SPARKLE_ENABLED=0
if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
  SPARKLE_ENABLED=1
elif [[ -z "$BUILD_STAMP" ]]; then
  echo "Refusing to build release $APP_VERSION with no SPARKLE_PUBLIC_KEY." >&2
  echo "Run generate_keys, store the private half, and set the public half in this script." >&2
  exit 1
fi

STAMP_KEYS=""
if [[ -n "$BUILD_STAMP" ]]; then
  STAMP_KEYS="  <key>TrickpadBuildStamp</key>
  <string>$BUILD_STAMP</string>"
fi

# Sparkle asks once, on second launch, whether to check for updates on its own,
# and offers automatic downloading as an option inside that same request. The
# question is asked before anything is fetched, so a fresh install still makes
# no network request until someone answers.
#
# SUEnableAutomaticChecks is deliberately absent. Setting it removes that
# request entirely, which also removes the only place the automatic-download
# option is ever offered.
#
# SUAutomaticallyUpdate sets that option's starting state. Off, so agreeing to
# automatic checks does not quietly agree to unattended installs as well.
SPARKLE_KEYS=""
if [[ "$SPARKLE_ENABLED" == "1" ]]; then
  SPARKLE_KEYS="  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUAutomaticallyUpdate</key>
  <false/>"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD_NUMBER</string>
$STAMP_KEYS
$SPARKLE_KEYS
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS_VERSION</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST


SDKROOT="$(xcrun --show-sdk-path)"

# The framework ships inside the bundle, so the executable finds it through an
# rpath rather than an absolute path. Copied with ditto to preserve the version
# symlinks; its nested code is re-signed innermost first further down.
SPARKLE_BUILD_FLAGS=()
if [[ "$SPARKLE_ENABLED" == "1" ]]; then
  mkdir -p "$FRAMEWORKS_DIR"
  rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
  ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"
  SPARKLE_BUILD_FLAGS=(
    -F"$ROOT/third_party/sparkle"
    -framework Sparkle
    -rpath @executable_path/../Frameworks
    -DTRICKPAD_SPARKLE=1
  )
else
  rm -rf "$FRAMEWORKS_DIR"
fi

clang \
  "${SPARKLE_BUILD_FLAGS[@]}" \
  -arch x86_64 \
  -arch arm64 \
  -mmacosx-version-min="$MIN_MACOS_VERSION" \
  -Werror=unguarded-availability-new \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$SRC_ROOT" \
  -I"$ROOT/src" \
  -I"$ROOT/third_party/tomlc17" \
  -isysroot "$SDKROOT" \
  -F"$SDKROOT/System/Library/PrivateFrameworks" \
  -framework Cocoa \
  -framework Carbon \
  -framework ApplicationServices \
  -framework AudioToolbox \
  -framework AVFAudio \
  -framework IOKit \
  -framework ScriptingBridge \
  -framework MultitouchSupport \
  "$ROOT/src/main.m" \
  "$ROOT/src/ApplicationScopeCache.m" \
  "$ROOT/src/Config.m" \
  "$ROOT/src/ContactTapRecognizer.m" \
  "$ROOT/src/DeferredGestureDispatcher.m" \
  "$ROOT/src/GestureSequence.m" \
  "$ROOT/src/KeyEventSequence.m" \
  "$ROOT/src/MiddleButtonLifecycle.m" \
  "$ROOT/src/MouseContactFilter.m" \
  "$ROOT/src/MouseClickInteraction.m" \
  "$SRC_ROOT/MultitouchDeviceLifecycle.m" \
  "$ROOT/src/ContactOnsetTracker.m" \
  "$ROOT/src/ScriptRunner.m" \
  "$ROOT/src/SequenceDispatcher.m" \
  "$ROOT/src/SystemGestureClaims.m" \
  "$ROOT/src/TraceRecorder.m" \
  "$ROOT/src/TraceSessionModel.m" \
  "$ROOT/src/SingleInstance.m" \
  "$ROOT/src/TrackpadInteraction.m" \
  "$ROOT/src/UpdaterController.m" \
  "$ROOT/third_party/tomlc17/tomlc17.c" \
  "$SRC_ROOT/JitouchAppDelegate.m" \
  "$SRC_ROOT/Settings.m" \
  "$SRC_ROOT/Gesture.m" \
  "$SRC_ROOT/KeyUtility.m" \
  "$SRC_ROOT/CursorWindow.m" \
  "$SRC_ROOT/CursorView.m" \
  "$SRC_ROOT/GestureWindow.m" \
  "$SRC_ROOT/GestureView.m" \
  "$SRC_ROOT/SizeHistory.m" \
  -o "$MACOS_DIR/$APP_NAME"

# The bundle carries its own seed files so a copied app can create the
# configuration folder without the source tree beside it.
cp "$ROOT/config.default.toml" "$RES_DIR/config.default.toml"
cp "$ROOT/config-notes.default.md" "$RES_DIR/config-notes.default.md"
cp "$ROOT/Trickpad-menu-bar-icon.svg" "$RES_DIR/Trickpad-menu-bar-icon.svg"
# An agent managing the configuration folder has no source tree, and needs to
# read the macOS gesture assignments a binding can collide with.
cp "$ROOT/scripts/system-gestures.sh" "$RES_DIR/system-gestures.sh"
chmod +x "$RES_DIR/system-gestures.sh"

# The installed app analyzes its redacted export without depending on source files.
clang \
  -arch x86_64 \
  -arch arm64 \
  -mmacosx-version-min="$MIN_MACOS_VERSION" \
  -Werror=unguarded-availability-new \
  -fblocks \
  -fobjc-exceptions \
  -fno-objc-arc \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/TraceAnalyzer.m" \
  -o "$RES_DIR/analyze-trace"

# Keep the public compatibility claim tied to the binaries users receive.
for binary in "$MACOS_DIR/$APP_NAME" "$RES_DIR/analyze-trace"; do
  xcrun vtool -show-build "$binary" | grep -q "minos $MIN_MACOS_VERSION" || {
    echo "Unexpected deployment target in $binary" >&2
    exit 1
  }
  built_architectures="$(lipo -archs "$binary")"
  for architecture in "${ARCHITECTURES[@]}"; do
    [[ " $built_architectures " == *" $architecture "* ]] || {
      echo "Missing $architecture architecture in $binary" >&2
      exit 1
    }
  done
done

# Nested code is signed innermost first, so every signature covers contents that
# are already final, and the bundle itself is signed last without --deep.
# --deep re-signs nested code in its own order and leaves Sparkle's framework
# reported as modified, which fails verification.
if [[ "$SPARKLE_ENABLED" == "1" ]]; then
  sparkle_version_dir="$FRAMEWORKS_DIR/Sparkle.framework/Versions/B"
  for nested in \
    "$sparkle_version_dir/XPCServices/Downloader.xpc" \
    "$sparkle_version_dir/XPCServices/Installer.xpc" \
    "$sparkle_version_dir/Updater.app" \
    "$sparkle_version_dir/Autoupdate" \
    "$sparkle_version_dir"; do
    [[ -e "$nested" ]] || {
      echo "Sparkle layout changed, missing $nested" >&2
      exit 1
    }
    codesign --force --sign - "$nested" >/dev/null
  done
fi
codesign --force --sign - "$RES_DIR/analyze-trace" >/dev/null

# A stable designated requirement lets macOS TCC associate Accessibility
# permission with this bundle identifier across rebuilds.
codesign --force --sign - \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP_BUNDLE" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null

# The Accessibility grant survives rebuilds only while this requirement holds.
codesign -d -r- "$APP_BUNDLE" 2>&1 | grep -q "designated => identifier \"$BUNDLE_ID\"" || {
  echo "Designated requirement missing from the signed bundle" >&2
  exit 1
}

echo "$APP_BUNDLE"
