# trickpad

Maps Magic Mouse and Magic Trackpad multi-touch gestures to keystrokes, built-in actions, custom URLs, or executable scripts on macOS. Runs as a background agent with a menu bar item and no window.

`CLAUDE.md` is a symlink to this file. Edit this one.

Shell scripts live in `scripts/` and resolve paths from the project root, two levels up from themselves.

## Where things live

- `src/` — the app, including the vendored engine under `src/jitouch/`.
- `scripts/` — build, check, package, and install scripts, plus `scripts/debug/` for hand-run diagnostic programs nothing else depends on.
- `docs/` — reference material for people and agents working on the project rather than for the people using it, including `docs/agents/` for the practices an agent is expected to follow.
- `packaging/` — the disk image background and its source.
- `fixtures/` — synthetic inputs the checks replay.
- `third_party/` — vendored dependencies kept at a pinned version.
- `assets/` — material that ships to people rather than to the build: `assets/design/` for design working files, `assets/marketing/` for generated icon exports used by the website and the storefront. No script reads either, so moving something here means it is not part of the build.
- `build/`, `run/`, and `.scratch/` are ignored by git and safe to delete. `build/` holds compiled output and packaged images, `run/` holds runtime logs and generated commands, and `.scratch/` is working space for anything that does not belong in the repository. Keep nothing in them that exists nowhere else.

The repository root holds the licence files, the reference documents, the starter configuration, and the two icon sources `build.sh` reads: `Trickpad.icon` for the app icon and `Trickpad-menu-bar-icon.svg` for the menu bar mark. A file at the root is either read by the build or read by a person arriving at the repository; anything else belongs in a directory above.

## Agent skills

### Issue tracker

Issues live as GitHub issues in `nweii/trickpad`, managed with the `gh` CLI. The tracker is public; commercial and strategic work does not belong in it. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repository root. See `docs/agents/domain.md`.

## Vendored engine, local config layer

Recognition is [Jitouch](https://github.com/JitouchApp/Jitouch), vendored under `src/jitouch/` by way of a fork. The `upstream` remote points at that fork.

Jitouch is a gesture app with a catalog of built-in actions and a preference pane for choosing among them. This project keeps its recognizers and drops the rest, so a gesture sends whatever keyboard shortcut the configuration names. Prefer that shape when adding anything: the built-in actions still work and are worth using where they fit, but the catalog is not the point.

`src/main.m` is 26 lines. `Gesture.m` is roughly 4,800 lines of recognizers. Changes belong in `src/Config.m` unless the engine is demonstrably wrong.

Jitouch reads the private `MultitouchSupport.framework`, which is undocumented and free to change across macOS releases. Upstream has had no code commits since January 2023, so breakage is ours to fix.

## Build and run

```bash
./scripts/build.sh             # single clang call, no Xcode project
./scripts/check.sh             # configuration parser checks
./scripts/stop.sh && ./scripts/start.sh
./scripts/update.sh            # preview and install a source update
```

`start.sh` builds when the bundle is missing, seeds the configuration folder, and launches the app.

Configuration changes skip the build. Apply them from the menu bar item's Reload Settings, or restart with `scripts/start.sh`. SIGHUP re-registers the multi-touch devices without rereading the file, so it does not apply a binding change on its own.

The app observes `NSWorkspaceDidWakeNotification` and fully rebuilds its device list and callback registrations after wake. `scripts/check.sh` protects this recovery path from drifting out of the vendored engine.

`update.sh` requires a clean checkout, fetches public `origin/main`, previews the incoming commits, and asks before a fast-forward update. After approval it runs the checks, rebuilds, and restarts. `--yes` skips only the prompt and is for an agent to use after the user has approved the displayed update.

The Accessibility grant binds to the bundle path plus the designated requirement that `scripts/build.sh` pins. Keep both stable and the grant survives every rebuild.

## Menu bar item

About opens a submenu carrying the version, read from the running bundle, plus a link to the product website.

`showIcon` in `JitouchAppDelegate.m` builds it. Top to bottom:

- Turn Trickpad Off, which suspends recognition without quitting.
- The Accessibility status, which opens the Privacy pane when access is missing.
- The configuration row, titled by its binding count ("11 bindings loaded"), whose title also reports skipped lines or a rejected reload. Its submenu lists the live bindings by device, each phrased through `humanNameForGesture:`, with a binding's own line comment beside it in dim parentheses. Application-specific rows name their scope, exclusions appear as Off, and when lines were skipped the submenu opens with a clickable details row.
- Manage with Agent, a submenu of the coding agents found through the user's login shell. Candidates are probed in one background shell when the menu opens, and the submenu serves the cached result, so hovering it costs no shell spawns. Picking one writes `~/.config/trickpad/manage-with-agent.command` and opens it, starting that agent in the configuration folder with the running app path and a prompt pointing at the installed instructions. The submenu also carries Copy Prompt (⌘C), which keeps the configuration private and tells the agent to ask for lines, and Copy Prompt + Settings (⌥⌘C), which attaches the whole `config.toml` as the user's explicit choice.
- Edit Settings (⌘,), which opens `config.toml` in the user's editor.
- Reload Settings (⌘R), which rereads the file into the running engine. Key equivalents, including ⌘Q on Quit, fire while the menu is open. Rows carry no icons, which would sit unevenly beside the Open at Login checkmark.
- Open at Login, a checkbox running `install-login-agent.sh` or `uninstall-login-agent.sh` with `PLIST_ONLY` set, so the file changes without launchd terminating the running process. It sits after the separator with the app-lifecycle rows, not among the configuration actions.
- Diagnostics, which can copy a state summary, open the last 15 minutes of logs, or enable verbose logging for the current session. An internal preference can also reveal the guided Magic Mouse trace session described below.
- About Trickpad, whose submenu shows the running version and opens the stable product-owned website and latest-version retrieval page, then Quit Trickpad.

## Releasing

The version lives in one place: `CFBundleShortVersionString` in `scripts/build.sh`. The menu bar header reads it from the running bundle, so it cannot drift from what is installed.

Semantic versioning, read against the configuration file rather than the code, because the config is the only interface anyone depends on. Before 1.0, a minor release may intentionally change that alpha interface and must carry a migration note. After 1.0:

- **Patch** — a fix that leaves every existing `config.toml` working.
- **Minor** — new gestures, keys, actions, or settings. An existing config keeps working, since unknown names are reported and skipped rather than failing.
- **Major** — a rename or removal that makes an existing `config.toml` behave differently. The positional gesture rename would have been one.

To cut a release:

```bash
# bump CFBundleShortVersionString and CFBundleVersion in scripts/build.sh
./scripts/build.sh && ./scripts/check.sh
./scripts/package.sh
git commit -am "Release X.Y.Z"
git tag -a vX.Y.Z -m "X.Y.Z"
git push origin main --tags
gh release create vX.Y.Z --title "X.Y.Z" --notes "..."
```

GitHub releases carry the tag, changelog, and automatic source archives without a packaged binary. The DMG that `scripts/package.sh` produces is delivered through Gumroad and must not be attached to GitHub. Packaging refuses to reuse a version whose source tag already points at another commit and verifies the styled drag-to-Applications layout, app signature, license, notices, trademark notice, and exact-source link.

The release title is the bare version. The repository name sits above it on every page that shows a release, so repeating it adds nothing.

### What a release commits this repository to

Two of these fail quietly, and one is already guarded.

**The corresponding-source link is generated, not written.** GPLv3 requires the buyer of a binary to be able to obtain its exact source, and `scripts/package.sh` satisfies that without anyone typing a URL: it derives the link from the app version, refuses to package when that version's tag already points at a different commit, and greps the mounted image to confirm the link before finishing. Leave it generated. A hand-maintained copy of that link anywhere else would have no such guard, so proposing one is a decision to take deliberately rather than a gap to fill.

**`CHANGELOG.md` is an interface, not only prose.** A downstream surface parses it to render a customer-facing changelog and the version it advertises. The shape it relies on: `## X.Y.Z` per release, a `Released YYYY-MM-DD.` line, a `### Section` heading per group, `- ` bullets that may wrap, and any trailing paragraph as closing notes. Entries are written in the imperative, so the section heading supplies the tense. Changing that structure degrades a page outside this repository, which no check here will catch.

Write the entries in ASD-STE100 Simplified Technical English: one idea per sentence, sentences under 25 words, no semicolons, and none of "should", "may", "might", or "could". The `simple-english` skill carries the full rules. Customers decide from this file whether an update affects them, and many of them do not read English as a first language, so an entry that needs a second reading has failed. Describing a fix in the vocabulary of the code that caused it is the way these go wrong.

**Publishing the tag does not publish the release.** Surfaces that read this repository do so when they build, not when it changes, so each needs a rebuild of its own before a customer sees the new version. Treat a release as delivered only once every surface below has been refreshed.

### After a release

1. The product website's reference pages, which carry their own copy of the configuration syntax and are updated by hand, so a change to `GESTURES.md` reaches them only when someone ports it.
2. Any surface that derives from `CHANGELOG.md`, which needs a rebuild to pick up the new entry.
3. The storefront listing, where any copy naming a feature the release changed is maintained by hand.

## Cross-surface product facts

Buyer-facing facts appear in this repository, in the packaged disk image, on the product website, and in the storefront listing. Keep one owner for each fact:

- `scripts/build.sh` owns the version, build number, minimum macOS version, and supported architectures.
- `GESTURES.md` owns configuration syntax, gesture names, actions, and settings.
- `scripts/package.sh` owns the paid artifact's contents and exact-source link.
- `packaging/dmg-background.svg` owns the short install and Gatekeeper guidance shown beside the app.
- `CHANGELOG.md` owns what each release changed, in the structure above.

README, `config.default.toml`, `config-notes.default.md`, the website, and the storefront description mirror the facts their readers need. When an owned fact changes, search every mirror before completing the work. Completion requires every relevant mirror to agree in substance, the repository checks to pass, and a fresh package verification when delivery contents or DMG guidance changed. Preserve each surface's level of detail instead of forcing identical prose everywhere.

`gh release create` has been seen to report a missing `workflow` scope that the token already holds. Creating it through `gh api repos/OWNER/REPO/releases` works. Pass `--repo` to any `gh release` or `gh repo` command here, or it resolves to the `upstream` remote and reports the fork's releases instead.

Moving a published tag turns its GitHub release back into a draft. Republishing it is a separate step, and a release left drafted is invisible.

The app is ad-hoc signed rather than notarized, so anyone installing the official packaged build clears Gatekeeper by hand. That warning returns for every new download, because approving one copy does not teach macOS to trust later ones. The Accessibility grant does persist across builds, since `scripts/build.sh` pins a designated requirement naming the bundle identifier without a code hash. Notarizing would need a paid Apple Developer account. Building from source stays supported and skips the Gatekeeper step.

A rename or removal of a configuration name is the one change that needs a migration note in the release, because an existing file will silently stop matching. `scripts/check.sh` catches a name that exists in code but not the docs; it cannot catch a name that used to exist.

## Configuration model

`src/Config.m` reads `~/.config/trickpad/config.toml` and returns the settings dictionary the engine consumed when it was a plist, so nothing downstream knows the format changed. `TRICKPAD_CONFIG` overrides the path. `resolvedPath` returns nil when no file exists.

The folder is seeded from two files at the project root: `config.default.toml` becomes the user-owned `config.toml`, and `config-notes.default.md` becomes the app-managed `AGENTS.md`. `start.sh`, `install-login-agent.sh`, and the app create `config.toml` only when missing and atomically refresh `AGENTS.md` from the running version. An optional user-owned `AGENTS.local.md` survives updates.

The file is TOML, parsed by the vendored `tomlc17` parser pinned under `third_party/tomlc17`. Strings are quoted and comments begin with `#` outside a string. `[MOUSE]` and `[TRACKPAD]` group bindings; general settings belong in `[GENERAL]`. TOML tables and keys cannot repeat. Device prefixes are not part of the format. Invalid TOML rejects the reload rather than applying a partial file.

`[MOUSE."Application"]` and `[TRACKPAD."Application"]` limit the bindings below them to one application. The quoted selector may be its display name or exact bundle identifier. Application bindings override the device-global binding for the same gesture. `"off"` excludes a global binding in that application.

An expanded binding is a TOML inline table: `gesture = { action = "escape", haptic = false }`. `action` is required globally and may be omitted in an application scope to inherit the global action. `defer` is valid only for tap gestures. `haptic` is valid only for trackpad bindings and overrides `haptic-feedback` for that binding.

`config-version` identifies the file format and is currently `3`. A missing version means the current format while the project is in alpha. An unsupported value rejects the entire reload so another format cannot be partially reinterpreted.

Four value forms:

- A keystroke: any modifiers plus one key. Separators may be `+`, `-`, or a space, and modifier symbols may run together with no separator at all.
- A built-in action. `actionNames` maps each slug to the exact string `dispatchCommand` in `Gesture.m` compares against.
- A custom URL prefixed with `url:`. The parser validates its scheme, whitespace, and percent escapes while preserving the payload's case. `NSWorkspace` resolves the installed handler when the gesture fires.
- An executable path prefixed with `script:`. Reload expands `~`, requires an absolute regular executable file, and records the resolved path. `ScriptRunner` launches it directly through its shebang, uses its parent folder as the working directory, discards output, retains it through asynchronous termination, and logs launch failures or nonzero exits. There is no shell parsing, argument syntax, substitution, or interactive shell environment.

A **substitution** is a named expression in a URL binding that resolves when its gesture fires. Use this term in code and documentation; avoid snippet, variable, and token. The supported forms are `{{clipboard}}`, `{{clipboard|urlencode}}`, and `{{datetime:FORMAT}}`. URL encoding treats the clipboard as one component. Date formats use `NSDateFormatter`, the POSIX locale, and the Mac's local time zone.

Reload validates substitution names, filters, braces, empty date formats, unmatched date-format quotes, and the URL with safe placeholder values. Dispatch reads the clipboard, resolves the current date and time, and validates the expanded URL. Logs may include the configured binding but never expanded clipboard contents.

Use **URL binding** for the configuration capability. An **app deep link** is a URL binding that opens a specific place or action in an app. A **URL scheme** is the protocol name at the start, such as `raycast`, `obsidian`, or `things`. Do not use URI in user-facing copy; it adds no useful distinction here.

Unknown schema keys are skipped and reported after TOML parsing succeeds.

`mouseGestureSlugs` and `trackpadGestureSlugs` hold the gesture vocabulary. One slug may bind several engine names that differ only by how far apart two fingers land. The two devices keep separate tables, enable flags, and vocabularies, so a binding on one does not reach the other.

Every engine name a slug reaches needs a phrase in `humanNameForGesture:`, or Current Gestures falls back to the engine's internal name.

`haptic-feedback = true` is the default and requests the public AppKit generic haptic pattern for configured trackpad gestures. The request is best effort: AppKit chooses the actuator and may suppress feedback after the fingers lift. Magic Mouse gestures never request haptics. Deferred taps request feedback only if their delayed action survives cancellation. Set it to `false` to opt out globally, or set `haptic` in an expanded trackpad binding for one override.

`menu-bar-icon = "trickpad"` uses the bundled template mark. `"sf:SYMBOL"` uses any available SF Symbol by name and falls back to a hand if macOS does not provide it. Turning gestures off dims the selected icon without changing its shape.

`experimental-mouse-click-gestures = false` keeps Magic Mouse two- and three-finger physical clicks unavailable by default. Set it to `true` to load those bindings. Their contact timing and classification remain sensitive to hand posture, so do not describe them as supported or reliable without a fresh hardware calibration pass.

`dominant-hand = right` preserves the engine's original coordinate axis. `dominant-hand = left` mirrors positional recognition on both devices, including hold-tap direction and thumb-side filtering.

Shift, Control, Option, and Command are the available modifiers. Fn is a HID usage rather than a key event and cannot be synthesized. Written modifiers may use a `left-` or `right-` prefix. An unspecified side and modifier symbols use the left-side key.

The `appID` CFPreferences domain in `Settings.h` is vestigial — only the removed preference pane wrote to it.

`GESTURES.md` is the user-facing reference for every slug, key, action, and setting.

## Checks

`./scripts/check.sh` compiles `src/Config.m` with `src/ConfigCheck.m` and runs the result against the parser. No framework, no fixtures.

It asserts keystroke parsing, app scopes, exclusions, expanded options, action and deferred dispatch, URL substitution parsing and resolution, script validation and execution, skipped bad lines, boolean spellings, and comment stripping. It also asserts that every slug appears in both `GESTURES.md` and `config-notes.default.md`, and that every engine name reachable from a slug has a menu phrase. Adding a gesture without documenting it fails the check. Direct gesture dispatch is allowlisted so a recognizer that bypasses contact-sequence ownership also fails the check.

## Login item

`./scripts/install-login-agent.sh` writes a launchd plist to `~/Library/LaunchAgents/fyi.thirdwind.trickpad.agent.plist`, which starts the agent at login and restarts it if it exits. The generated plist opens with a comment naming what it does and pointing back here, since a bare launchd label is easy to find and hard to identify.

`./scripts/uninstall-login-agent.sh` removes it. Deleting the plist by hand has the same effect and leaves the project alone.

`./scripts/uninstall.sh` removes the login item, the running app, and the build. It keeps the settings folder unless called with `--all`, and prints the two steps that cannot be scripted.

The project writes two things outside its own directory: the launchd plist, and `~/.config/trickpad/`, which holds `config.toml`, `AGENTS.md`, and `manage-with-agent.command`.

## Logging

Set `verbose-logging = true` in `config.toml` for per-gesture and per-keystroke logging:

```bash
/usr/bin/log show --style compact --last 5m --predicate 'process == "Trickpad"'
```

## Guided traces

Guided traces are internal and absent from the menu by default. Reveal them for local development, then restart the app:

```bash
defaults write fyi.thirdwind.trickpad InternalTraceDiagnostics -bool true
```

Delete that preference to restore the release menu:

```bash
defaults delete fyi.thirdwind.trickpad InternalTraceDiagnostics
```

`TraceRecorder.m` owns bounded hardware capture. It assigns monotonic sequence numbers before sending typed events to a serial writer queue, caps pending events at 4,096 and output at 50 MB, and writes deterministic NDJSON. Device names are ephemeral within one session. Its interface does not accept application names, configured values, keyboard details, clipboard contents, cursor positions, or persistent device identifiers.

Diagnostics > Gesture testing offers guided calibration protocols and an open-ended normal-use capture. The latter records every configured Magic Mouse gesture that would dispatch while suppressing its action, so an intermittent false trigger can be identified from one ordinary-use session. The same submenu can enable a system tone immediately before any configured gesture action is dispatched.

Audit Gesture Catalog is a separate open-ended capture that shadow-evaluates supported Magic Mouse recognizers absent from the user's configuration. Shadow recognitions never claim the contact sequence, dispatch an action, or suppress native scrolling. The exported report lists them under `catalog_candidates`. Keep this separate from configured dispatch counts because enabling every binding would create artificial conflicts.

A trace opens a persistent floating `NSPanel` inside the menu-bar app. The panel shows the whole protocol overview, current step, progress, explicit phase, keyboard shortcuts, and an inert surface where native clicks have no UI effect. It remains visible throughout the session; the Diagnostics menu only reports status and brings it forward. Configured actions are suppressed while the recorder captures raw contact frames, filter decisions, mouse/drag/scroll events, recognizer outcomes, ownership, safe dispatch kinds, and human Clean/Botched/Unsure/Skip execution-quality labels. Recognition is reported automatically as the observed dispatch count against the expected count; the human label never stands in for recognizer success. Each step starts capture with a tone after a two-second neutral countdown. A full lift closes the scored window before the window enables labels. Window-local shortcuts avoid global keyboard capture. Stopping offers Discard, Export Partial, or Continue. The protocol includes three clean repetitions of both two- and three-finger physical clicks. Expected dispatch counts distinguish exact, under-, and over-dispatches, including two expected dispatches for the rapid pair. Export runs the bundled `TraceAnalyzer.m` executable before moving one redacted bundle to a location the user chooses. `scripts/analyze-trace.sh BUNDLE` reruns the same analyzer from source.

Synthetic fixtures under `fixtures/trace/` exercise click correlation, contact filtering, sequence ownership, analyzer classification, malformed bundles, and serialization without committing captured hand geometry. Raw trace bundles are private diagnostic material and do not belong in the repository.

## Standing constraints

- **Add, never replace.** A binding extends what the hardware does. Anything System Settings owns — tap-to-click, secondary click, the built-in swipes — keeps behaving as the user configured it. Experimental Magic Mouse physical clicks are the one explicit exception: a confidently recognized configured click replaces the normal primary click. Ambiguous clicks remain native and do not dispatch the binding.
- **Check both conflict surfaces before binding.** macOS claims some motions, listed in `GESTURES.md`. The user's own hotkeys claim some chords, and a Caps Lock remapped to Cmd+Alt+Ctrl is a common one worth asking about.
- **Hold gestures carry anything consequential.** macOS does not claim the hold-one-tap-one shape. On a Magic Mouse, its discrete tap contacts still use fingertip-quality filtering because a narrow resting edge contact can imitate the held finger.

## Hotkey compatibility

Some applications watch the keyboard through a CGEventTap and require explicit modifier transitions instead of reading only the flags on one key event. Trickpad sends modifier key-down events, the key down and up with complete modifier flags, then modifier key-up events. Aqua Voice and Wispr Flow accept this sequence. System Events may produce a different sequence, so its result does not predict whether a Trickpad binding will work. Test the actual gesture in the target application.

## Local modifications to the vendored engine

These changes are deliberate and are not present upstream. Reverting them can silently regress the configuration contract.

`KeyUtility.m`, `simulateKeyCode:` posts a hardware-shaped sequence through `CGEventCreateKeyboardEvent`: modifier presses, the key press and release, then modifier releases. The key events retain the full modifier flags conventional hotkey APIs inspect. Each modifier also sets its requested device-dependent side bit (`NX_DEVICELSHIFTKEYMASK`, `NX_DEVICERSHIFTKEYMASK`, and kin), since an application can register a side-specific hotkey that the generic masks cannot satisfy. Modifiers already held on the requested side are neither pressed nor released by the sequence.

`Gesture.m`, `gestureMagicMouseOneFingerSwipe` returns early when nothing is bound to a one-finger swipe. The suppression below that point disables horizontal scrolling on any one-finger horizontal movement, and upstream runs it whether or not a swipe is bound, degrading ordinary scrolling in an unbound configuration.

`TrackpadInteraction.m` classifies each trackpad contact sequence before the tap recognizers claim it. Broad palm contacts and physical clicks reject tap-only gestures, one recognizer may claim a sequence, and raw full lift resets the state. Physical clicks use the filtered contact count already observed by the module, retain its peak through a brief missing-contact frame, and reject the configured action when the CG event stream becomes a drag. Physical mouse-up clears the peak so the next click cannot inherit it. Keep gesture-specific geometry and timing in `Gesture.m`; shared eligibility and inter-gesture arbitration belong in this module.

`GestureSequence.m` gives each device one gesture owner until every raw contact lifts. `dispatchExclusiveCommand` checks that a binding exists before claiming, allows the owning recognizer to repeat, and blocks a click, tap, swipe, or hold recognizer from dispatching over a different owner. Tap dispatch adds the shared trackpad contact-eligibility check. A bound swipe family suppresses native scroll events from the moment its required contacts arrive until raw full lift; an unbound family never suppresses scrolling. New recognizers that can share a contact sequence with an existing gesture must use one of these paths.

`MouseContactFilter.m` rejects measured rear-palm and narrow side-edge contacts while retaining substantial fingertips in those regions. The filtered contact list feeds Magic Mouse one- and multi-finger taps, hold-one-tap-one recognition, and physical-click counting. Counted physical-click fingertips must form a connected cluster; `gestureMagicMouseThumb` identifies and excludes a thumb from that cluster; with other contacts present, a corner contact counts as a thumb only when it sits clearly below the next-lowest contact, so the leftmost fingertip of a level three-finger row is not mistaken for one. A single narrow side contact may join a physical three-finger click only when two normal fingertips are already present and all three form one cluster. This does not make an ordinary click plus one resting edge contact a two-finger click. Do not apply fingertip filtering blindly to swipes or positional gestures whose contact geometry has different meaning. Physical-click filtering runs only when `experimental-mouse-click-gestures` enables a configured Magic Mouse physical-click binding.

`MouseClickInteraction.m` serializes the CG physical-click stream with Magic Mouse touch frames, which arrive on separate callback threads and in either order. It retains eligible two- or three-finger contact counts through a bounded mouse-up grace period and prevents immediate recognition from dispatching again on release. A configured experimental click waits only when two or three raw contacts need one filtering frame. Confident clicks replace the native lifecycle; arbitrary actions dispatch on release, middle-click substitutes down/drag/up, and a native drag is restored once movement crosses the drag threshold. Keep this cross-stream lifetime separate from contact filtering and recognizer ownership.
