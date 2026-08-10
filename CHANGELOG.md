<!-- Records user-visible Trickpad releases in reverse chronological order.
     Entries are written in the imperative, following Keep a Changelog: the
     Added/Changed/Fixed heading supplies the tense, so the bullet does not.
     Entries follow ASD-STE100 Simplified Technical English: one idea per
     sentence, sentences under 25 words, no semicolons, and no "should", "may",
     or "might". A reader decides from this file whether an update affects
     them, and many of them do not read English as a first language.

     Lead with what changed for the reader, not with the mechanism behind it.
     Keep the voice neutral: no "you" or "your", and no claim about the state
     of a reader's own Mac, which this file cannot see. -->

# Changelog

## Unreleased

### Added

- Add trackpad area clicks. A physical click with one finger in a named region of the surface runs a bound action. The regions are the four edges, their halves and thirds, and the four corners. A click in a bound region replaces the native click. A click in a region with no binding stays a normal click. When bound regions overlap, the most specific bound region wins. Regions are narrow by default. The `trackpad-edge-gesture-depth` setting adjusts how far they reach in from the edge.
- Support clicking in any edge or corner with `edge-click` and `corner-click`, without naming an edge section or a corner. A named region stays more specific and wins for its own spot.
- Add double-tap gesture names on both devices. The Magic Mouse has `one-finger-double-tap`, `two-finger-double-tap`, and `three-finger-double-tap`. The trackpad has `two-finger-double-tap` through `five-finger-double-tap`. The action runs on two taps of that finger count inside the Mac double-click interval. A double tap that is bound alone adds no delay to the single tap. To use a single tap and its own double tap together, set `defer = true` on the single tap. Triple taps are not available.
- Add bare swipe names such as `three-finger-swipe`. A bare name binds every direction of that finger count to one action. A directional name such as `three-finger-swipe-left` stays more specific and wins for its own direction.
- Accept the words of a gesture name in any order, on both devices. For example, `swipe-up-three-finger` loads as `three-finger-swipe-up`. The menu and reports show the canonical name.
- Add the `app-expose`, `show-desktop`, and `app-switcher` actions, beside the existing `mission-control`. Each asks macOS for that view directly. No application can intercept them, and they work whether or not the matching keyboard shortcut is enabled.
- Add an Open Docs item to the About menu. It opens the documentation site.
- Show the build commit beside the version in About and in Copy Debug Info for a build that is not a tagged release.

### Changed

- Make trackpad multi-finger click gestures consume the native click, so the click and the action do not both fire. This matches the Magic Mouse click gestures.
- Make the Magic Mouse `two-finger-click` and `three-finger-click` gestures standard. They load without the `experimental-mouse-click-gestures` setting. The setting is no longer needed. A configuration file that sets it keeps loading.
- Play a binding's `sound` before its `say` words when a binding sets both. Before, the sound and the speech started together.
- Strengthen the haptic tap a trackpad gesture makes. It uses the firmest pattern macOS offers, which is easier to feel than the one before it.
- Make the gesture list easier to scan. Rows show at full strength, and the device names use the system section-header style.
- Describe hold gestures without a side for the held finger. The list now reads "Hold a finger, tap to its right".
- Remove the ellipsis from menu items that only open a page.

### Fixed

- Fix the `mission-control` action, which did nothing. The call it makes to macOS needed a second value that a macOS release added. The new `app-expose`, `show-desktop`, and `app-switcher` actions use the corrected call.
- Lower the work Trickpad does while fingers rest on a device. Before, it asked macOS which application was in front many times per second. It now asks again only after the settings reload or a different application comes forward.
- Stop a four-finger trackpad swipe and a two-finger Magic Mouse swipe from also scrolling. Before, only three-finger swipes held back the scroll their fingers would otherwise make.
- Stop a resting palm from blocking scrolling. Before, a palm touching the trackpad at scroll start counted toward a configured three-finger swipe, and normal scrolling stopped.

## 0.8.1

Released 2026-08-07.

### Fixed

- Fix the check for a two-finger trackpad tap. Secondary click claims that tap only when tap to click is also on, so the warning appeared where no conflict existed.
- Fix conflict warnings that appeared for macOS settings that have never been changed. Trickpad now reports when it cannot tell.

### Changed

- Improve the agent guidance so an agent starts from the existing configuration and the request at hand, rather than assuming a new gesture is wanted.
- Let a user's own conventions survive an update. `AGENTS.local.md` beside the settings holds them, and an agent offers to maintain that file.

## 0.8.0

Released 2026-08-07.

### Added

- Warn when a binding shares its trigger with a gesture macOS already uses, and name the System Settings pane that holds it. Both still fire, so the warning is a prompt to rebind rather than a failure. Agents read the same report from `Contents/Resources/system-gestures.sh` in the app bundle.
- Add the `sound:` and `say:` binding values for testing a gesture. `"sound:Glass"` plays a system sound and `"say:three fingers"` speaks, with no other action, so a gesture can be proven before a real action rides on it. A repeat interrupts and restarts the sound, so silence means the gesture did not fire.
- Add `sound` and `say` as options beside a binding's real action, as in `{ action = "cmd+shift+4", sound = "Glass" }`. A Magic Mouse has no haptic feedback, so this is the way to confirm one of its gestures by ear. Each starts immediately and delays neither the action nor the next gesture.
- Show each binding's own line comment beside it in the Current Gestures menu.
- Add menu key equivalents that work while the menu is open: `⌘,` for settings, `⌘R` to reload, `⌘C` for the agent prompt, `⌥⌘C` for that prompt with `config.toml` attached, and `⌘Q` to quit.
- Title the gesture list with its binding count, so one row carries the configuration state and opens the details of any skipped line.
- Open the menu once at first launch, so a new installation shows where the app lives instead of leaving an icon to be found.
- Expand the agent guide on designing bindings worth keeping: what earns a gesture, cheap trial and error, the file's own formatting, and the conflict checks that come before a proposal.
- Teach the agent guide to draft a support email to support@thirdwind.fyi, carrying the version, macOS version, device, and the bindings that bear on the problem. The agent drafts and shows it, and the user sends it.

### Changed

- Rework the starter configuration for a first reading: a header explaining how to comment out a line, two examples per device, and no catalog of optional bindings.
- Move Open at Login below the separator with the app-lifecycle rows, leaving the group above to configuration actions.

### Fixed

- Correct a `script:` example that named a path Trickpad does not ship, so uncommenting it failed at reload.
- Open the Manage with Agent submenu without delay, by probing installed agents in one background shell rather than one shell per agent.
- Stop a two-finger tap from being read as a hold-tap. A hold gesture now requires its resting finger to settle before the second lands, which also makes `defer = true` behave as documented.
- Stop a resting hand from firing a tap when a Magic Mouse physical click releases.
- Stop some three-finger Magic Mouse clicks from dispatching as two-finger clicks. The index finger of a level row was counted as a thumb.

This is a backward-compatible minor release. Existing version 3 configuration files keep working.

## 0.7.1

Released 2026-08-05.

### Changed

- Point Copy Prompt at the stable web documentation, and have it note that the installed version can differ from the latest reference.
- Rework the agent guide around safe configuration edits and gesture choice, keeping the detailed syntax in the canonical reference.
- Document how a macOS shortcut for an existing app menu command can become a Trickpad binding.

This is a backward-compatible patch release. Existing version 3 configuration files keep working.

## 0.7.0

Released 2026-08-05.

### Added

- Add experimental two- and three-finger physical-click bindings for a Magic Mouse, off by default. A confidently recognized click replaces the normal click, and ambiguous clicks and drags stay native.
- Add universal Intel and Apple silicon builds for macOS 11 and later.
- Add a configurable menu bar icon: the bundled Trickpad mark, or any SF Symbol named in `config.toml`. Suspended gestures dim either choice.
- Add a Get Latest Version menu item that opens Trickpad's stable download page, independent of any store.

### Changed

- Establish the Trickpad app bundle, the login item, and the `~/.config/trickpad` configuration folder.
- Ship official builds in a styled disk image carrying an Applications link, first-launch guidance, license notices, and an exact corresponding-source link. GitHub releases carry the source and changelog without a binary.

This changes the alpha installation and configuration location.

## 0.6.1

Released 2026-08-03.

### Fixed

- Stop a resting edge contact on a Magic Mouse from joining a two-finger tap. A configured tap starts only when both contacts arrive together, so deliberate taps near an edge still work.
- Track each contact's arrival for simultaneous multi-finger taps on both devices. Holds, swipes, and physical clicks keep their own rules, since their contacts arrive at different times by design.

### Changed

- Group the hidden guided hardware tests under a `Gesture testing` submenu in Diagnostics, absent from a normal installation.

This is a backward-compatible patch release. Existing version 3 configuration files keep working.

## 0.6.0

Released 2026-08-03.

### Changed

- Replace the custom configuration grammar with TOML, at `~/.config/trickpad/config.toml`. Actions, shortcuts, URLs, scripts, and exclusions are quoted strings.
- Change application-specific headings to TOML nested tables, such as `[TRACKPAD."Final Cut Pro"]`.
- Reject a reload on a duplicate table, a duplicate key, an unquoted string, or malformed TOML, keeping the running configuration in place. Unknown settings and bindings are still reported one by one.

This changes the alpha configuration interface from version 2 to version 3. Convert a version 2 file before updating.

## 0.5.1

Released 2026-08-02.

### Added

- Add **Copy Prompt** under **Manage with Agent**. It gives a chat assistant the public reference and asks for a block to paste, without copying the configuration or any private value.

### Changed

- Simplify the starter configuration to a short working setup with a separate examples area, rather than a compact reference document. An update leaves a user-owned configuration alone.
- Keep guided hardware trace capture internal and hidden by default. Diagnostics still offers logs and copied debug state.

### Fixed

- Allow up to three pixels of incidental movement during a Magic Mouse multi-finger click. Four pixels start a drag and cancel the configured action.
- Delay a Magic Mouse physical-click action until mouse-up, so a deliberate click-and-drag no longer fires it early. The native click stays.
- Limit trace results to the physical-click gesture under test, so a configured tap is no longer reported as a false click.
- Let the internal trace window close after it completes, raise its label contrast, and stop its execution-quality buttons truncating.

This is a backward-compatible patch release. Existing version 2 configuration files keep working. Magic Mouse physical-click bindings stay disabled by default behind `experimental-mouse-click-gestures`, because their behavior is still under test in daily use.

## 0.5.0

Released 2026-08-02.

### Added

- Add optional `left-` and `right-` prefixes for Shift, Control, Option, and Command. A modifier with no prefix uses the left-side key.
- Add Magic Mouse physical-click correlation to the verbose logs.
- Add experimental two- and three-finger physical-click bindings for a Magic Mouse, behind `experimental-mouse-click-gestures = true` under `[general]`.

### Fixed

- Correlate physical clicks with touch frames that arrive before mouse-down, after mouse-down, or just after mouse-up.
- Stop a brief contact dropout, a trackpad drag, a palm, a thumb, or an isolated edge contact from changing or triggering a physical-click binding.
- Accept large fingertips near the rear of a Magic Mouse, while still rejecting rear-palm and narrow side-edge contacts.
- Give each contact sequence one gesture owner, so taps, clicks, holds, and swipes cannot dispatch over one another.
- Keep native scrolling for a swipe family with no binding, suppressing it only while a bound swipe owns the contact sequence.
- Keep the native trackpad click alongside a configured multi-finger click action.
- Correct four configuration faults: an application binding inheriting a global action, an explicit `defer = false`, recovery from a malformed block, and the last declaration shown in Current Gestures.
- Report a rejected reload in the menu, rather than presenting an empty configuration as a success.

This is a backward-compatible minor release. Existing version 2 configuration files keep working. Magic Mouse physical-click bindings need an explicit experimental opt-in, because their recognition is still sensitive to contact timing and hand posture.
