#!/bin/zsh
set -euo pipefail

# Compiles and runs the configuration parser checks without a test framework or
# fixtures. These checks catch bindings that parse without producing an action.

ROOT="${0:A:h:h}"
OUT="$(mktemp -d)/configcheck"
SDKROOT="$(xcrun --show-sdk-path)"

clang \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -I"$ROOT/third_party/tomlc17" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  -framework ApplicationServices \
  -framework Carbon \
  "$ROOT/src/Config.m" \
  "$ROOT/src/ConfigCheck.m" \
  "$ROOT/src/SystemGestureClaims.m" \
  "$ROOT/third_party/tomlc17/tomlc17.c" \
  -o "$OUT" 2>/dev/null

"$OUT" \
  "$ROOT/config.default.toml" \
  "$ROOT/config-notes.default.md" \
  "$ROOT/GESTURES.md" \
  "$ROOT/src/jitouch/Jitouch/Gesture.m"

KEY_OUT="$(mktemp -d)/keyeventcheck"
clang \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework ApplicationServices \
  "$ROOT/src/KeyEventSequence.m" \
  "$ROOT/src/KeyEventSequenceCheck.m" \
  -o "$KEY_OUT" 2>/dev/null
"$KEY_OUT"

DEFER_OUT="$(mktemp -d)/defercheck"
clang \
  -fblocks \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/DeferredGestureDispatcher.m" \
  "$ROOT/src/DeferredGestureDispatcherCheck.m" \
  -o "$DEFER_OUT" 2>/dev/null
"$DEFER_OUT"

CONTACT_TAP_OUT="$(mktemp -d)/contacttapcheck"
clang \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/ContactTapRecognizer.m" \
  "$ROOT/src/ContactTapRecognizerCheck.m" \
  -o "$CONTACT_TAP_OUT" 2>/dev/null
"$CONTACT_TAP_OUT"

APPLICATION_SCOPE_OUT="$(mktemp -d)/applicationscopecachecheck"
clang \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Cocoa \
  "$ROOT/src/ApplicationScopeCache.m" \
  "$ROOT/src/ApplicationScopeCacheCheck.m" \
  -o "$APPLICATION_SCOPE_OUT" 2>/dev/null
"$APPLICATION_SCOPE_OUT"

GESTURE_SEQUENCE_OUT="$(mktemp -d)/gesturesequencecheck"
clang \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/GestureSequence.m" \
  "$ROOT/src/GestureSequenceCheck.m" \
  -o "$GESTURE_SEQUENCE_OUT" 2>/dev/null
"$GESTURE_SEQUENCE_OUT"

SINGLE_INSTANCE_OUT="$(mktemp -d)/singleinstancecheck"
clang \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  -framework AppKit \
  "$ROOT/src/SingleInstance.m" \
  "$ROOT/src/SingleInstanceCheck.m" \
  -o "$SINGLE_INSTANCE_OUT" 2>/dev/null
"$SINGLE_INSTANCE_OUT"

MOUSE_CONTACT_FILTER_OUT="$(mktemp -d)/mousecontactfiltercheck"
clang \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/MouseContactFilter.m" \
  "$ROOT/src/MouseContactFilterCheck.m" \
  -o "$MOUSE_CONTACT_FILTER_OUT" 2>/dev/null
"$MOUSE_CONTACT_FILTER_OUT"

CONTACT_ONSET_TRACKER_OUT="$(mktemp -d)/contactonsettrackercheck"
clang \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/ContactOnsetTracker.m" \
  "$ROOT/src/ContactOnsetTrackerCheck.m" \
  -o "$CONTACT_ONSET_TRACKER_OUT" 2>/dev/null
"$CONTACT_ONSET_TRACKER_OUT"

MOUSE_CLICK_INTERACTION_OUT="$(mktemp -d)/mouseclickinteractioncheck"
clang \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/MouseClickInteraction.m" \
  "$ROOT/src/MouseClickInteractionCheck.m" \
  -o "$MOUSE_CLICK_INTERACTION_OUT" 2>/dev/null
"$MOUSE_CLICK_INTERACTION_OUT"

TRACE_RECORDER_OUT="$(mktemp -d)/tracerecordercheck"
clang \
  -fblocks \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/TraceRecorder.m" \
  "$ROOT/src/TraceRecorderCheck.m" \
  -o "$TRACE_RECORDER_OUT" 2>/dev/null
"$TRACE_RECORDER_OUT"

TRACE_SESSION_OUT="$(mktemp -d)/tracesessioncheck"
clang \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/TraceSessionModel.m" \
  "$ROOT/src/TraceSessionModelCheck.m" \
  -o "$TRACE_SESSION_OUT" 2>/dev/null
"$TRACE_SESSION_OUT"

TRACE_REPLAY_OUT="$(mktemp -d)/tracereplaycheck"
clang \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/GestureSequence.m" \
  "$ROOT/src/MouseClickInteraction.m" \
  "$ROOT/src/MouseContactFilter.m" \
  "$ROOT/src/TraceReplayCheck.m" \
  -o "$TRACE_REPLAY_OUT" 2>/dev/null
"$TRACE_REPLAY_OUT" "$ROOT/fixtures/trace/interaction-replay.synthetic.json"

TRACE_ANALYZER_OUT="$(mktemp -d)/traceanalyzer"
clang \
  -fblocks \
  -fobjc-exceptions \
  -fno-objc-arc \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/TraceAnalyzer.m" \
  -o "$TRACE_ANALYZER_OUT" 2>/dev/null
TRACE_ANALYZER_FIXTURE="$(mktemp -d)/analyzer-bundle"
cp -R "$ROOT/fixtures/trace/analyzer-bundle/." "$TRACE_ANALYZER_FIXTURE"
"$TRACE_ANALYZER_OUT" "$TRACE_ANALYZER_FIXTURE" >/dev/null
grep -q '"true_positive" : 1' "$TRACE_ANALYZER_FIXTURE/analysis.json" ||
  { echo "trace analyzer changed the synthetic positive classification" >&2; exit 1; }
grep -q '"true_negative" : 1' "$TRACE_ANALYZER_FIXTURE/analysis.json" ||
  { echo "trace analyzer changed the synthetic negative classification" >&2; exit 1; }
grep -q '"under" : 1' "$TRACE_ANALYZER_FIXTURE/analysis.json" ||
  { echo "trace analyzer stopped detecting an under-dispatched rapid pair" >&2; exit 1; }
grep -q '"observed_dispatch_count" : 2' "$TRACE_ANALYZER_FIXTURE/analysis.json" ||
  { echo "trace analyzer stopped counting all ambient gesture dispatches" >&2; exit 1; }
grep -q '"Three-Finger Tap" : 1' "$TRACE_ANALYZER_FIXTURE/analysis.json" ||
  { echo "trace analyzer stopped counting catalog shadow recognitions" >&2; exit 1; }
grep -q '"available" : 1' "$TRACE_ANALYZER_FIXTURE/analysis.json" ||
  { echo "trace analyzer stopped reporting mouse-down eligibility" >&2; exit 1; }
CANDIDATE_TRACE_FIXTURE="$(mktemp -d)/candidate-bundle"
cp -R "$ROOT/fixtures/trace/candidate-bundle/." "$CANDIDATE_TRACE_FIXTURE"
"$TRACE_ANALYZER_OUT" "$CANDIDATE_TRACE_FIXTURE" >/dev/null
grep -q '"capture" : "candidate-gesture-guided"' "$CANDIDATE_TRACE_FIXTURE/analysis.json" ||
  { echo "trace analyzer stopped reporting the candidate capture kind" >&2; exit 1; }
grep -q '"candidate" : "corner-pull"' "$CANDIDATE_TRACE_FIXTURE/analysis.json" ||
  { echo "trace analyzer stopped reporting the recorded candidate name" >&2; exit 1; }
grep -q '"peak_contact_count" : 2' "$CANDIDATE_TRACE_FIXTURE/analysis.json" ||
  { echo "trace analyzer stopped summarizing the per-repetition contact profile" >&2; exit 1; }
grep -q '"frames" : 3' "$CANDIDATE_TRACE_FIXTURE/analysis.json" ||
  { echo "trace analyzer stopped counting per-repetition frames" >&2; exit 1; }

MALFORMED_TRACE="$(mktemp -d)/malformed-bundle"
if "$TRACE_ANALYZER_OUT" "$MALFORMED_TRACE" >/dev/null 2>&1; then
  echo "trace analyzer accepted a malformed bundle" >&2
  exit 1
fi

TRACKPAD_INTERACTION_OUT="$(mktemp -d)/trackpadinteractioncheck"
clang \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/ContactOnsetTracker.m" \
  "$ROOT/src/GestureSequence.m" \
  "$ROOT/src/TrackpadInteraction.m" \
  "$ROOT/src/TrackpadInteractionCheck.m" \
  -o "$TRACKPAD_INTERACTION_OUT" 2>/dev/null
"$TRACKPAD_INTERACTION_OUT"

SYSTEM_GESTURE_OUT="$(mktemp -d)/systemgestureclaimscheck"
clang \
  -fblocks \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/SystemGestureClaims.m" \
  "$ROOT/src/SystemGestureClaimsCheck.m" \
  -o "$SYSTEM_GESTURE_OUT" 2>/dev/null
"$SYSTEM_GESTURE_OUT"

SCRIPT_RUNNER_OUT="$(mktemp -d)/scriptrunnercheck"
clang \
  -fblocks \
  -fobjc-exceptions \
  -fno-objc-arc \
  -I"$ROOT/src" \
  -isysroot "$SDKROOT" \
  -framework Foundation \
  "$ROOT/src/ScriptRunner.m" \
  "$ROOT/src/ScriptRunnerCheck.m" \
  -o "$SCRIPT_RUNNER_OUT" 2>/dev/null
"$SCRIPT_RUNNER_OUT"

# The login item plist is written by two independent pieces of code: the app's
# Open at Login menu item (JitouchAppDelegate.m) and scripts/install-login-agent.sh.
# They may differ in how they launch the app, but the job label and the keys
# that govern its behavior must stay identical, or a login item written by one
# side stops being recognized or managed by the other.
APP_SRC="$ROOT/src/jitouch/Jitouch/JitouchAppDelegate.m"
INSTALL_SH="$ROOT/scripts/install-login-agent.sh"
LABEL="fyi.thirdwind.trickpad.agent"

fail() {
  echo "login item drift: $1" >&2
  echo "  The app (src/jitouch/Jitouch/JitouchAppDelegate.m, loginAgentPlistContents)" >&2
  echo "  and scripts/install-login-agent.sh both write the launchd plist and must" >&2
  echo "  agree on the label and behavior keys. Edit whichever side changed so both" >&2
  echo "  match, then rerun scripts/check.sh." >&2
  exit 1
}

managed_fail() {
  echo "managed installation files drift: $1" >&2
  echo "  config.toml is create-only, AGENTS.md is atomically refreshed, and" >&2
  echo "  AGENTS.local.md remains user-owned across every installation path." >&2
  exit 1
}

wake_fail() {
  echo "wake recovery drift: $1" >&2
  echo "  Waking must rebuild the multitouch device list and re-register callbacks." >&2
  exit 1
}

gesture_fail() {
  echo "gesture conflict regression: $1" >&2
  exit 1
}

for f in "$APP_SRC" "$INSTALL_SH" "$ROOT/scripts/uninstall-login-agent.sh" "$ROOT/scripts/uninstall.sh"; do
  grep -q "$LABEL" "$f" || fail "$f does not contain the label $LABEL"
done

for key in RunAtLoad KeepAlive ProcessType; do
  grep -q "<key>$key</key>" "$APP_SRC"    || fail "the app's plist is missing <key>$key</key>"
  grep -q "<key>$key</key>" "$INSTALL_SH" || fail "install-login-agent.sh's plist is missing <key>$key</key>"
done
grep -q "<string>Interactive</string>" "$APP_SRC"    || fail "the app's plist does not set ProcessType to Interactive"
grep -q "<string>Interactive</string>" "$INSTALL_SH" || fail "install-login-agent.sh's plist does not set ProcessType to Interactive"

# The application owns AGENTS.md while config.toml and AGENTS.local.md remain
# user-owned. Every installation path must preserve that boundary.
grep -q 'mv -f "$AGENT_TMP" "$CONFIG_DIR/AGENTS.md"' "$ROOT/scripts/start.sh" || managed_fail "start.sh does not atomically refresh AGENTS.md"
grep -q 'mv -f "$AGENT_TMP" "$CONFIG_DIR/AGENTS.md"' "$INSTALL_SH" || managed_fail "install-login-agent.sh does not atomically refresh AGENTS.md"
grep -q 'NSDataWritingAtomic' "$APP_SRC" || managed_fail "the app does not atomically refresh AGENTS.md"
grep -q 'AGENTS.local.md' "$ROOT/config-notes.default.md" || managed_fail "installed agent instructions do not route to AGENTS.local.md"

for item in 'Diagnostics' 'Copy Debug Info' 'Open Recent Logs' 'Verbose Logging This Session'; do
  grep -q "$item" "$APP_SRC" || fail "the menu is missing $item"
done
grep -q 'BindingCount' "$APP_SRC" || fail "the menu does not report the active binding count"
grep -q 'reverseObjectEnumerator' "$APP_SRC" || fail "Current Gestures shows the first repeated declaration instead of the last"
grep -q 'Reload failed' "$APP_SRC" || fail "a rejected watched reload is not visible in the menu"
grep -q 'No gestures were loaded' "$APP_SRC" || fail "startup claims defaults after rejecting the configuration"
! sed -n '/NSArray \*labels = @\[@\[@"Success/,/traceLabelButtons =/p' "$APP_SRC" | grep -q 'setRepresentedObject' ||
  fail "trace label buttons use NSMenuItem-only representedObject storage"
grep -q 'doCommand(gesture, device, binding, matchedApplication)' \
  "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
  gesture_fail "deferred gestures resolve their application scope twice"

# Hold-taps end in a tap, so they must pass through the shared tap eligibility
# path that rejects broad contacts and physical clicks.
for gesture in 'One-Fix Left-Tap' 'One-Fix Right-Tap'; do
  grep -q "dispatchExclusiveTapCommand(@\"$gesture\", TRACKPAD" "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
    gesture_fail "$gesture bypasses shared trackpad tap eligibility"
done
grep -q 'BOOL anchorRemained = nFingers == 1 && data\[0\]\.identifier == fixId;' \
  "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
  gesture_fail "trackpad hold-tap treats full lift as a held anchor"

# A two-finger tap lands its contacts together and lifts them a frame later, so
# without a held anchor the Magic Mouse hold-tap recognizes it first and takes
# the sequence. Both recognizers must keep measuring against the same interval.
grep -q 'MGContactOnsetTrackerContactArrivedAfter(&magicMouseContactOnsets,' \
  "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
  gesture_fail "Magic Mouse hold-tap accepts an anchor that never rested, which steals two-finger taps"
[[ "$(grep -c 'kMagicMouseTwoFingerTapMaximumOnsetSpread)' "$ROOT/src/jitouch/Jitouch/Gesture.m")" -ge 3 ]] ||
  gesture_fail "Magic Mouse hold-tap and taps no longer share one contact onset interval"
grep -q 'major=%f minor=%f size=%f' "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
  gesture_fail "verbose logging cannot capture trackpad contact geometry"
for gesture in 'Two-Finger Click' 'Three-Finger Click'; do
  grep -q "bindingForGesture(@\"$gesture\", MAGICMOUSE) != nil" \
    "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
    gesture_fail "an unbound $gesture can claim the Magic Mouse sequence"
done
for gesture in \
  'One-Fix-Press Two-Slide-Up' 'One-Fix-Press Two-Slide-Down' \
  'One-Fix Two-Slide-Up' 'One-Fix Two-Slide-Down' \
  'Three-Finger Pinch-Out' 'Three-Finger Pinch-In' \
  'Two-Fix Index-Double-Tap' 'Two-Fix Middle-Double-Tap' 'Two-Fix Ring-Double-Tap' \
  'Pinch Out' 'Pinch In' 'Thumb'; do
  ! grep -q "dispatchCommand(@\"$gesture\"" "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
    gesture_fail "$gesture bypasses gesture sequence ownership"
done
for gesture in 'Two-Fix One-Slide-Right' 'Two-Fix One-Slide-Left' \
  'Two-Fix One-Slide-Up' 'Two-Fix One-Slide-Down'; do
  grep -q "dispatchExclusiveCommand(@\"$gesture\", MAGICMOUSE, kGestureOwnerTwoFixedOneSlide)" \
    "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
    gesture_fail "$gesture shares the Magic Mouse hold-slide owner"
done

# The app warns about conflicts from SystemGestureClaims.m while an agent reads
# scripts/system-gestures.sh. Both describe the same macOS preference keys, so
# they must name the same key and slug pairs, and every slug must still exist.
SYSTEM_GESTURES="$ROOT/scripts/system-gestures.sh"
script_table() {
  local line fields domains slug
  for line in ${(f)"$(sed -n '/^ENTRIES=(/,/^)/p' "$SYSTEM_GESTURES" | grep -o '"[^"]*"')"}; do
    fields=(${(s.:.)${line//\"/}})
    domains="$fields[2]"
    case "$domains" in
      '$MOUSE_DOMAINS') domains="com.apple.AppleMultitouchMouse" ;;
      '$TRACKPAD_DOMAINS') domains="com.apple.driver.AppleBluetoothMultitouch.trackpad,com.apple.AppleMultitouchTrackpad" ;;
    esac
    for slug in ${(s.,.)fields[4]}; do
      echo "$fields[1] $domains $fields[3] $slug ${fields[5]:--} ${fields[6]:--}"
    done
  done | sort
}
diff <(script_table) <("$SYSTEM_GESTURE_OUT" --table) >/dev/null ||
  gesture_fail "scripts/system-gestures.sh and src/SystemGestureClaims.m describe different macOS gesture conflicts"

while read -r device domains key slug prerequisite disqualifier; do
  if [[ "$device" == "trackpad" ]]; then method="trackpadGestureSlugs"; else method="mouseGestureSlugs"; fi
  sed -n "/+ (NSDictionary \*)$method {/,/^}/p" "$ROOT/src/Config.m" | grep -q "@\"$slug\":" ||
    gesture_fail "a macOS gesture conflict names $device slug $slug, which Config.m does not define"
done < <(script_table)

# Fingers rest on a Magic Mouse after the button releases, so a click's contacts
# outlast any fixed window and go on to read as a tap. Suppression holds until
# the contacts a tap recognizer can see are gone: raw-lift release stalled for
# seconds behind resting fingers the filter had already excluded from taps.
GESTURE_SRC="$ROOT/src/jitouch/Jitouch/Gesture.m"
grep -q 'magicMouseTapsSuppressedUntilLift = YES;' "$GESTURE_SRC" ||
  gesture_fail "a Magic Mouse physical click no longer suppresses taps"
grep -q 'if (eligibleTapContactCount == 0 &&' "$GESTURE_SRC" ||
  gesture_fail "Magic Mouse tap suppression is not released by the tap-eligible contacts lifting"
grep -q 'eligibleTapContactCount = tapContactCount;' "$GESTURE_SRC" ||
  gesture_fail "Magic Mouse tap suppression release ignores contact filtering"
[[ "$(grep -c 'if (magicMouseTapsSuppressedUntilLift ||' "$GESTURE_SRC")" -eq 4 ]] ||
  gesture_fail "a Magic Mouse tap recognizer ignores post-click suppression"

# Binding lookups run several times per touch frame, so they must read the
# cached application candidates rather than Accessibility, and both events that
# can change the answer must still drop the cache.
grep -q 'return MGApplicationScopeCacheCandidates();' "$GESTURE_SRC" ||
  gesture_fail "binding lookups no longer read the cached application candidates"
grep -q 'MGApplicationScopeCacheInvalidate();' "$ROOT/src/jitouch/Jitouch/Settings.m" ||
  gesture_fail "a configuration reload no longer drops the cached application candidates"
grep -q 'MGApplicationScopeCacheObserveApplicationActivation();' "$APP_SRC" ||
  gesture_fail "the app no longer drops the cached application candidates when another application activates"

grep -q 'NSWorkspaceDidWakeNotification' "$APP_SRC" || wake_fail "the app does not observe wake notifications"
grep -q '\[self reload\]' "$APP_SRC" || wake_fail "the wake handler does not reload gesture devices"
for token in turnOffMagicMouse turnOffTrackpad MTUnregisterContactFrameCallback \
  MTDeviceStop MTDeviceCreateList MTRegisterContactFrameCallback MTDeviceStart; do
  sed -n '/^- (void)reload {/,/^}/p' "$ROOT/src/jitouch/Jitouch/Gesture.m" | grep -q "$token" ||
    wake_fail "Gesture reload is missing $token"
done

grep -q 'config-version' "$ROOT/config.default.toml" || managed_fail "the default config has no format version"
grep -q 'config-version' "$ROOT/GESTURES.md" || managed_fail "GESTURES.md does not document the format version"
for f in "$ROOT/config.default.toml" "$ROOT/config-notes.default.md"; do
  grep -q 'thirdwind.fyi/trickpad' "$f" || managed_fail "$f does not point setup help to the product guide"
done
grep -q 'https://thirdwind.fyi/trickpad/docs.md' "$APP_SRC" ||
  managed_fail "Copy Prompt does not point agents to the website documentation"
grep -q 'https://thirdwind.fyi/trickpad/download' "$APP_SRC" ||
  managed_fail "Get Latest Version does not point to the stable retrieval page"
for f in "$ROOT/config.default.toml" "$ROOT/GESTURES.md"; do
  grep -q 'defer = true' "$f" || managed_fail "$f does not document deferred tap bindings"
  grep -q 'script:' "$f" || managed_fail "$f does not document script bindings"
  grep -q 'haptic-feedback' "$f" || managed_fail "$f does not document haptic feedback"
done

BUILD_LOG="$(mktemp)"
if ! "$ROOT/scripts/build.sh" >"$BUILD_LOG" 2>&1; then
  cat "$BUILD_LOG" >&2
  exit 1
fi
if grep -q 'warning:' "$BUILD_LOG"; then
  grep 'warning:' "$BUILD_LOG" >&2
  echo "build emitted compiler warnings" >&2
  exit 1
fi

echo "login item plist writers agree"
