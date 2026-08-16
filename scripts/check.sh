#!/bin/zsh
set -euo pipefail

# Compiles and runs the configuration parser checks without a test framework or
# fixtures. These checks catch bindings that parse without producing an action.

ROOT="${0:A:h:h}"
SDKROOT="$(xcrun --show-sdk-path)"
CHECK_FILTER="${CHECK_FILTER:-}"
CHECK_COUNT=0
SYSTEM_GESTURE_OUT=""
OBJC_FLAGS=(-fobjc-exceptions -fno-objc-arc -I"$ROOT/src" -isysroot "$SDKROOT")

run_compiled_check() {
  local name="$1"
  local runner="$2"
  local output compiler_output
  shift 2

  [[ -z "$CHECK_FILTER" || "$CHECK_FILTER" == "$name" ]] || return 0
  output="$(mktemp -d)/${name//-/}"
  compiler_output="$(mktemp)"
  if ! clang "$@" -o "$output" >"$compiler_output" 2>&1; then
    echo "$name: compile failed" >&2
    cat "$compiler_output" >&2
    exit 1
  fi
  "$runner" "$output"
  (( CHECK_COUNT += 1 ))
}

run_shell_check() {
  local name="$1"
  local runner="$2"

  [[ -z "$CHECK_FILTER" || "$CHECK_FILTER" == "$name" ]] || return 0
  "$runner"
  (( CHECK_COUNT += 1 ))
}

run_without_arguments() {
  "$1"
}

run_config_check() {
  "$1" "$ROOT/config.default.toml" "$ROOT/config-notes.default.md" "$ROOT/GESTURES.md" "$ROOT/src/jitouch/Jitouch/Gesture.m"
}

run_trace_replay_check() {
  "$1" "$ROOT/fixtures/trace/interaction-replay.synthetic.json"
}

run_trace_analyzer_check() {
  local executable="$1"
  local fixture candidate_fixture malformed_trace

  fixture="$(mktemp -d)/analyzer-bundle"
  cp -R "$ROOT/fixtures/trace/analyzer-bundle/." "$fixture"
  "$executable" "$fixture" >/dev/null
  grep -q '"true_positive" : 1' "$fixture/analysis.json" ||
    { echo "trace analyzer changed the synthetic positive classification" >&2; exit 1; }
  grep -q '"true_negative" : 1' "$fixture/analysis.json" ||
    { echo "trace analyzer changed the synthetic negative classification" >&2; exit 1; }
  grep -q '"under" : 1' "$fixture/analysis.json" ||
    { echo "trace analyzer stopped detecting an under-dispatched rapid pair" >&2; exit 1; }
  grep -q '"observed_dispatch_count" : 2' "$fixture/analysis.json" ||
    { echo "trace analyzer stopped counting all ambient gesture dispatches" >&2; exit 1; }
  grep -q '"Three-Finger Tap" : 1' "$fixture/analysis.json" ||
    { echo "trace analyzer stopped counting catalog shadow recognitions" >&2; exit 1; }
  grep -q '"available" : 1' "$fixture/analysis.json" ||
    { echo "trace analyzer stopped reporting mouse-down eligibility" >&2; exit 1; }

  candidate_fixture="$(mktemp -d)/candidate-bundle"
  cp -R "$ROOT/fixtures/trace/candidate-bundle/." "$candidate_fixture"
  "$executable" "$candidate_fixture" >/dev/null
  grep -q '"capture" : "candidate-gesture-guided"' "$candidate_fixture/analysis.json" ||
    { echo "trace analyzer stopped reporting the candidate capture kind" >&2; exit 1; }
  grep -q '"candidate" : "corner-pull"' "$candidate_fixture/analysis.json" ||
    { echo "trace analyzer stopped reporting the recorded candidate name" >&2; exit 1; }
  grep -q '"peak_contact_count" : 2' "$candidate_fixture/analysis.json" ||
    { echo "trace analyzer stopped summarizing the per-repetition contact profile" >&2; exit 1; }
  grep -q '"frames" : 3' "$candidate_fixture/analysis.json" ||
    { echo "trace analyzer stopped counting per-repetition frames" >&2; exit 1; }

  malformed_trace="$(mktemp -d)/malformed-bundle"
  if "$executable" "$malformed_trace" >/dev/null 2>&1; then
    echo "trace analyzer accepted a malformed bundle" >&2
    exit 1
  fi
}

run_system_gesture_check() {
  SYSTEM_GESTURE_OUT="$1"
  "$SYSTEM_GESTURE_OUT"
}

run_compiled_check config run_config_check "${OBJC_FLAGS[@]}" -I"$ROOT/third_party/tomlc17" -framework Foundation -framework ApplicationServices -framework Carbon "$ROOT/src/Config.m" "$ROOT/src/ConfigCheck.m" "$ROOT/src/SystemGestureClaims.m" "$ROOT/third_party/tomlc17/tomlc17.c"
run_compiled_check key-event run_without_arguments "${OBJC_FLAGS[@]}" -framework ApplicationServices "$ROOT/src/KeyEventSequence.m" "$ROOT/src/KeyEventSequenceCheck.m"
run_compiled_check deferred-gesture run_without_arguments -fblocks "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/DeferredGestureDispatcher.m" "$ROOT/src/DeferredGestureDispatcherCheck.m"
run_compiled_check sequence-dispatcher run_without_arguments -fblocks "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/SequenceDispatcher.m" "$ROOT/src/SequenceDispatcherCheck.m"
run_compiled_check contact-tap run_without_arguments "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/ContactTapRecognizer.m" "$ROOT/src/ContactTapRecognizerCheck.m"
run_compiled_check application-scope run_without_arguments "${OBJC_FLAGS[@]}" -framework Cocoa "$ROOT/src/ApplicationScopeCache.m" "$ROOT/src/ApplicationScopeCacheCheck.m"
run_compiled_check multitouch-lifecycle run_without_arguments "${OBJC_FLAGS[@]}" -I"$ROOT/src/jitouch/Jitouch" -framework Foundation -framework IOKit -F"$SDKROOT/System/Library/PrivateFrameworks" -framework MultitouchSupport "$ROOT/src/jitouch/Jitouch/MultitouchDeviceLifecycle.m" "$ROOT/src/MultitouchDeviceLifecycleCheck.m"
run_compiled_check gesture-sequence run_without_arguments "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/GestureSequence.m" "$ROOT/src/GestureSequenceCheck.m"
run_compiled_check single-instance run_without_arguments "${OBJC_FLAGS[@]}" -framework Foundation -framework AppKit "$ROOT/src/SingleInstance.m" "$ROOT/src/SingleInstanceCheck.m"
run_compiled_check mouse-contact-filter run_without_arguments "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/MouseContactFilter.m" "$ROOT/src/MouseContactFilterCheck.m"
run_compiled_check contact-onset-tracker run_without_arguments "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/ContactOnsetTracker.m" "$ROOT/src/ContactOnsetTrackerCheck.m"
run_compiled_check middle-button-lifecycle run_without_arguments "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/MiddleButtonLifecycle.m" "$ROOT/src/MiddleButtonLifecycleCheck.m"
run_compiled_check mouse-click-interaction run_without_arguments "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/MouseClickInteraction.m" "$ROOT/src/MouseClickInteractionCheck.m"
run_compiled_check trace-recorder run_without_arguments -fblocks "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/TraceRecorder.m" "$ROOT/src/TraceRecorderCheck.m"
run_compiled_check trace-session run_without_arguments "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/TraceSessionModel.m" "$ROOT/src/TraceSessionModelCheck.m"
run_compiled_check trace-replay run_trace_replay_check "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/GestureSequence.m" "$ROOT/src/MouseClickInteraction.m" "$ROOT/src/MouseContactFilter.m" "$ROOT/src/TraceReplayCheck.m"
run_compiled_check trace-analyzer run_trace_analyzer_check -fblocks -fobjc-exceptions -fno-objc-arc -isysroot "$SDKROOT" -framework Foundation "$ROOT/src/TraceAnalyzer.m"
run_compiled_check trackpad-interaction run_without_arguments "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/ContactOnsetTracker.m" "$ROOT/src/GestureSequence.m" "$ROOT/src/TrackpadInteraction.m" "$ROOT/src/TrackpadInteractionCheck.m"
run_compiled_check system-gesture run_system_gesture_check -fblocks "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/SystemGestureClaims.m" "$ROOT/src/SystemGestureClaimsCheck.m"
run_compiled_check script-runner run_without_arguments -fblocks "${OBJC_FLAGS[@]}" -framework Foundation "$ROOT/src/ScriptRunner.m" "$ROOT/src/ScriptRunnerCheck.m"
run_shell_check publish "$ROOT/scripts/publish-check.sh"

if [[ -n "$CHECK_FILTER" ]]; then
  (( CHECK_COUNT > 0 )) || { echo "unknown CHECK_FILTER: $CHECK_FILTER" >&2; exit 1; }
  echo "checks: $CHECK_COUNT unit passed"
  exit 0
fi

typeset -A STRIPPED_SOURCES

strip_source_comments() {
  local source="$1"
  local stripped

  if [[ -z "${STRIPPED_SOURCES[$source]-}" ]]; then
    stripped="$(mktemp)"
    case "$source" in
      *.[chm]) perl -0777 -pe 's{("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/}{defined $1 ? $1 : ""}gse' "$source" >"$stripped" ;;
      *.sh) perl -0777 -pe 's{("(?:\\.|[^"\\])*")|#[^\n]*}{defined $1 ? $1 : ""}gse' "$source" >"$stripped" ;;
      *) perl -pe '' "$source" >"$stripped" ;;
    esac
    STRIPPED_SOURCES[$source]="$stripped"
  fi
  REPLY="${STRIPPED_SOURCES[$source]}"
}

source_has() {
  local pattern="$1"
  strip_source_comments "$2"
  grep -q -- "$pattern" "$REPLY"
}

source_count() {
  local pattern="$1"
  strip_source_comments "$2"
  grep -c -- "$pattern" "$REPLY" || true
}

source_section_has() {
  local pattern="$1"
  local source="$2"
  local range="$3"
  local section
  strip_source_comments "$source"
  section="$(mktemp)"
  sed -n "$range p" "$REPLY" >"$section"
  grep -q -- "$pattern" "$section"
}

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
  source_has "$LABEL" "$f" || fail "$f does not contain the label $LABEL"
done

for key in RunAtLoad KeepAlive ProcessType; do
  source_has "<key>$key</key>" "$APP_SRC"    || fail "the app's plist is missing <key>$key</key>"
  source_has "<key>$key</key>" "$INSTALL_SH" || fail "install-login-agent.sh's plist is missing <key>$key</key>"
done
source_has "<string>Interactive</string>" "$APP_SRC"    || fail "the app's plist does not set ProcessType to Interactive"
source_has "<string>Interactive</string>" "$INSTALL_SH" || fail "install-login-agent.sh's plist does not set ProcessType to Interactive"

# The application owns AGENTS.md while config.toml and AGENTS.local.md remain
# user-owned. Every installation path must preserve that boundary.
source_has 'mv -f "$AGENT_TMP" "$CONFIG_DIR/AGENTS.md"' "$ROOT/scripts/start.sh" || managed_fail "start.sh does not atomically refresh AGENTS.md"
source_has 'mv -f "$AGENT_TMP" "$CONFIG_DIR/AGENTS.md"' "$INSTALL_SH" || managed_fail "install-login-agent.sh does not atomically refresh AGENTS.md"
source_has 'NSDataWritingAtomic' "$APP_SRC" || managed_fail "the app does not atomically refresh AGENTS.md"
source_has 'AGENTS.local.md' "$ROOT/config-notes.default.md" || managed_fail "installed agent instructions do not route to AGENTS.local.md"

for item in 'Diagnostics' 'Copy Debug Info' 'Open Recent Logs' 'Verbose Logging This Session'; do
  source_has "$item" "$APP_SRC" || fail "the menu is missing $item"
done
source_has 'BindingCount' "$APP_SRC" || fail "the menu does not report the active binding count"
source_has 'reverseObjectEnumerator' "$APP_SRC" || fail "Current Gestures shows the first repeated declaration instead of the last"
source_has 'Reload failed' "$APP_SRC" || fail "a rejected watched reload is not visible in the menu"
source_has 'No gestures were loaded' "$APP_SRC" || fail "startup claims defaults after rejecting the configuration"
! source_section_has 'setRepresentedObject' "$APP_SRC" '/NSArray \*labels = @\[@\[@"Success/,/traceLabelButtons =/' ||
  fail "trace label buttons use NSMenuItem-only representedObject storage"
source_has 'doCommand(gesture, device, binding, matchedApplication)' \
  "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
  gesture_fail "deferred gestures resolve their application scope twice"

# Hold-taps end in a tap, so they must pass through the shared tap eligibility
# path that rejects broad contacts and physical clicks.
for gesture in 'One-Fix Left-Tap' 'One-Fix Right-Tap' \
  'Two-Fix Left-Tap' 'Two-Fix Right-Tap' 'Two-Fix Between-Tap' \
  'Three-Fix Left-Tap' 'Three-Fix Right-Tap'; do
  source_has "dispatchExclusiveTapCommand(@\"$gesture\", TRACKPAD" "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
    gesture_fail "$gesture bypasses shared trackpad tap eligibility"
done
source_has 'BOOL anchorRemained = nFingers == 1 && data\[0\]\.identifier == fixId;' \
  "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
  gesture_fail "trackpad hold-tap treats full lift as a held anchor"
source_has 'if (enHanded && result == kTrackpadFixedHoldTapLeft)' \
  "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
  gesture_fail "trackpad fixed hold-taps do not mirror left and right for a left dominant hand"

# A two-finger tap lands its contacts together and lifts them a frame later, so
# without a held anchor the Magic Mouse hold-tap recognizes it first and takes
# the sequence. Both recognizers must keep measuring against the same interval.
source_has 'MGContactOnsetTrackerContactArrivedAfter(&magicMouseContactOnsets,' \
  "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
  gesture_fail "Magic Mouse hold-tap accepts an anchor that never rested, which steals two-finger taps"
[[ "$(source_count 'kMagicMouseTwoFingerTapMaximumOnsetSpread)' "$ROOT/src/jitouch/Jitouch/Gesture.m")" -ge 3 ]] ||
  gesture_fail "Magic Mouse hold-tap and taps no longer share one contact onset interval"
source_has 'major=%f minor=%f size=%f' "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
  gesture_fail "verbose logging cannot capture trackpad contact geometry"
for gesture in 'Two-Finger Click' 'Three-Finger Click'; do
  source_has "bindingForGesture(@\"$gesture\", MAGICMOUSE) != nil" \
    "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
    gesture_fail "an unbound $gesture can claim the Magic Mouse sequence"
done
for gesture in \
  'One-Fix-Press Two-Slide-Up' 'One-Fix-Press Two-Slide-Down' \
  'One-Fix Two-Slide-Up' 'One-Fix Two-Slide-Down' \
  'Three-Finger Pinch-Out' 'Three-Finger Pinch-In' \
  'Two-Fix Index-Double-Tap' 'Two-Fix Middle-Double-Tap' 'Two-Fix Ring-Double-Tap' \
  'Pinch Out' 'Pinch In' 'Thumb'; do
  ! source_has "dispatchCommand(@\"$gesture\"" "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
    gesture_fail "$gesture bypasses gesture sequence ownership"
done
for gesture in 'Two-Fix One-Slide-Right' 'Two-Fix One-Slide-Left' \
  'Two-Fix One-Slide-Up' 'Two-Fix One-Slide-Down'; do
  source_has "dispatchExclusiveCommand(@\"$gesture\", MAGICMOUSE, kGestureOwnerTwoFixedOneSlide)" \
    "$ROOT/src/jitouch/Jitouch/Gesture.m" ||
    gesture_fail "$gesture shares the Magic Mouse hold-slide owner"
done

# The app warns about conflicts from SystemGestureClaims.m while an agent reads
# scripts/system-gestures.sh. Both describe the same macOS preference keys, so
# they must name the same key and slug pairs, and every slug must still exist.
SYSTEM_GESTURES="$ROOT/scripts/system-gestures.sh"
script_table() {
  local line fields domains slug
  strip_source_comments "$SYSTEM_GESTURES"
  for line in ${(f)"$(sed -n '/^ENTRIES=(/,/^)/p' "$REPLY" | grep -o '"[^"]*"')"}; do
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
  source_section_has "@\"$slug\":" "$ROOT/src/Config.m" "/+ (NSDictionary \*)$method {/,/^}/" ||
    gesture_fail "a macOS gesture conflict names $device slug $slug, which Config.m does not define"
done < <(script_table)

# Fingers rest on a Magic Mouse after the button releases, so a click's contacts
# outlast any fixed window and go on to read as a tap. Suppression holds until
# the contacts a tap recognizer can see are gone: raw-lift release stalled for
# seconds behind resting fingers the filter had already excluded from taps.
GESTURE_SRC="$ROOT/src/jitouch/Jitouch/Gesture.m"
source_has 'magicMouseTapsSuppressedUntilLift = YES;' "$GESTURE_SRC" ||
  gesture_fail "a Magic Mouse physical click no longer suppresses taps"
source_has 'if (eligibleTapContactCount == 0 &&' "$GESTURE_SRC" ||
  gesture_fail "Magic Mouse tap suppression is not released by the tap-eligible contacts lifting"
source_has 'eligibleTapContactCount = tapContactCount;' "$GESTURE_SRC" ||
  gesture_fail "Magic Mouse tap suppression release ignores contact filtering"
[[ "$(source_count 'if (magicMouseTapsSuppressedUntilLift ||' "$GESTURE_SRC")" -eq 4 ]] ||
  gesture_fail "a Magic Mouse tap recognizer ignores post-click suppression"

# Binding lookups run several times per touch frame, so they must read the
# cached application candidates rather than Accessibility, and both events that
# can change the answer must still drop the cache.
source_has 'return MGApplicationScopeCacheCandidates();' "$GESTURE_SRC" ||
  gesture_fail "binding lookups no longer read the cached application candidates"
source_has 'MGApplicationScopeCacheInvalidate();' "$ROOT/src/jitouch/Jitouch/Settings.m" ||
  gesture_fail "a configuration reload no longer drops the cached application candidates"
source_has 'MGApplicationScopeCacheObserveApplicationActivation();' "$APP_SRC" ||
  gesture_fail "the app no longer drops the cached application candidates when another application activates"

source_has 'dispatchSequence:sequence' "$GESTURE_SRC" ||
  gesture_fail "sequence bindings do not dispatch through SequenceDispatcher"
source_has 'Run sequence (%lu action%@)' "$APP_SRC" ||
  gesture_fail "Current Gestures does not summarize sequence bindings"
source_section_has 'cancelPendingGestureSequences();' "$ROOT/src/jitouch/Jitouch/Settings.m" '/+ (void)loadSettings2:/,/^}/' ||
  gesture_fail "a configuration reload does not cancel pending sequence steps"
source_section_has 'cancelPendingGestureSequences();' "$GESTURE_SRC" '/^void turnOffGestures()/,/^}/' ||
  gesture_fail "turning gestures off does not cancel pending sequence steps"

source_has 'NSWorkspaceDidWakeNotification' "$APP_SRC" || wake_fail "the app does not observe wake notifications"
source_has '\[self reload\]' "$APP_SRC" || wake_fail "the wake handler does not reload gesture devices"
for token in turnOffMagicMouse turnOffTrackpad '\[multitouchDevices rebuild\]'; do
  source_section_has "$token" "$ROOT/src/jitouch/Jitouch/Gesture.m" '/^- (void)reload {/,/^}/' ||
    wake_fail "Gesture reload is missing $token"
done

source_has 'config-version' "$ROOT/config.default.toml" || managed_fail "the default config has no format version"
source_has 'config-version' "$ROOT/GESTURES.md" || managed_fail "GESTURES.md does not document the format version"
for f in "$ROOT/config.default.toml" "$ROOT/config-notes.default.md"; do
  source_has 'thirdwind.fyi/trickpad' "$f" || managed_fail "$f does not point setup help to the product guide"
done
source_has 'https://thirdwind.fyi/trickpad/docs.md' "$APP_SRC" ||
  managed_fail "Copy Prompt does not point agents to the website documentation"
source_has 'https://thirdwind.fyi/trickpad/download' "$APP_SRC" ||
  managed_fail "Get Latest Version does not point to the stable retrieval page"
for f in "$ROOT/config.default.toml" "$ROOT/GESTURES.md"; do
  source_has 'defer = true' "$f" || managed_fail "$f does not document deferred tap bindings"
  source_has 'script:' "$f" || managed_fail "$f does not document script bindings"
  source_has 'haptic-feedback' "$f" || managed_fail "$f does not document haptic feedback"
done

(( CHECK_COUNT += 1 ))
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

(( CHECK_COUNT += 1 ))
echo "checks: $CHECK_COUNT units passed"
