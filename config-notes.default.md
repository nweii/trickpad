# Trickpad agent guide

Trickpad maps Magic Mouse and Magic Trackpad gestures to shortcuts, built-in actions, URLs, and executable scripts. It refreshes this file whenever it launches. The file describes the version of Trickpad that supplied it.

## Get oriented

This session is opened by the user from Trickpad's "Manage with Agent" menu item. Find out what the user is looking to do before reaching for any of the sections below.

Three files sit in this folder, and each answers a different question:

| File | What it holds |
| --- | --- |
| `config.toml` | Every binding and setting. The record of what the user has set up, and the only account of what a gesture does. |
| `AGENTS.local.md` | The user's own conventions and preferences for configuring Trickpad, in their words. Optional, and theirs to keep. |
| This file | Instructions from Trickpad. It is rewritten from the running version at every launch, so anything you add here will not persist. |

Read `config.toml` first, and `AGENTS.local.md` if it exists. An edit to `config.toml` takes effect when Trickpad reloads its settings, not when the file is saved. Do not write preference notes into `config.toml` or this file unless the user asks; anything worth keeping between sessions belongs in `AGENTS.local.md`, and offering to maintain it alongside `config.toml` is part of the job.

Bring whatever you already know about this user to the work.

## Help choose a gesture

Learn the user's intended outcome and the app or context where it happens. Leave every existing binding and setting unchanged unless changing it is necessary for the user's stated request.

Consider giving a summary of the current configuration. The user may not have the file open, and this may be their first time changing the settings. Give it as a list grouped by device, one line per binding, naming the gesture and what it does in plain words rather than as the value in the file. Point out anything that looks unintended.

If the user wants ideas, find a few concrete options that fit their workflow:

- Check an app's configurable shortcuts, automation hooks, documented URL schemes, deep links, and installed extensions.
- Consider a Shortcut, command-line tool, or small local script only when an app does not expose a suitable shortcut or URL.
- Prefer a built-in action, keyboard shortcut, or app deep link over a custom script.
- Consider existing bindings, comfort and repeatability, mnemonic fit, and how consequential the action is.
- When a consequential action (submit, save, delete, send, or anything similar) is headed for a gesture that misfires more easily — taps especially — raise the risk with the user and suggest a hold gesture as the safer default, then respect their choice. What counts as consequential depends on the user, their apps, and their other bindings, so ask rather than refuse.
- Use an application-specific binding when a gesture makes sense in one app or would conflict elsewhere.
- `sound:NAME` (a system sound such as `sound:Glass`) and `say:WORDS` play or speak and do nothing else. They are ordinary binding values, useful for whatever the user wants them for; checking that a gesture fires at all is the obvious one. Speech can name the gesture, so several such bindings stay distinguishable by ear.
- To confirm a gesture that still does its real work, you could add `sound` or `say` as a binding option: `{ action = "cmd+shift+4", sound = "Glass" }`. A Magic Mouse has no haptic feedback, so this is the only way to feel or hear one of its gestures fire.

**A bare swipe name binds every direction of its finger count.** `three-finger-swipe = "escape"` fires on a three-finger swipe in any direction; `one-finger-swipe` and `two-finger-swipe` cover the Magic Mouse's left and right. A directional name (`three-finger-swipe-left`) is more specific and wins for its own direction, so the two forms combine: bind the family once and override one direction. `"off"` on either name in an application table excludes one direction or the whole family there. Prefer the bare name when the action does not care about direction.

**Area clicks put actions on named regions of the trackpad surface.** A one-finger physical click in a bound region runs the action instead of the native click; a click anywhere else stays native. The regions are whole edges (`left-edge-click`, `right-edge-click`, `top-edge-click`, `bottom-edge-click`), edge halves (`left-edge-top-half-click`, `left-edge-bottom-half-click`, `right-edge-top-half-click`, `right-edge-bottom-half-click`, `top-edge-left-half-click`, `top-edge-right-half-click`, `bottom-edge-left-half-click`, `bottom-edge-right-half-click`), edge thirds (`left-edge-top-third-click`, `left-edge-middle-third-click`, `left-edge-bottom-third-click`, `right-edge-top-third-click`, `right-edge-middle-third-click`, `right-edge-bottom-third-click`, `top-edge-left-third-click`, `top-edge-middle-third-click`, `top-edge-right-third-click`, `bottom-edge-left-third-click`, `bottom-edge-middle-third-click`, `bottom-edge-right-third-click`), and corners (`top-left-corner-click`, `top-right-corner-click`, `bottom-left-corner-click`, `bottom-right-corner-click`). When bound regions overlap, the most specific bound region wins: a corner beats an edge region, a third beats a half beats the whole edge. Because a bound region replaces the native click there, prefer edges and corners the user does not click during ordinary pointing, and note that macOS's own bottom-corner secondary click (System Settings > Trackpad) claims those corners when it is enabled. `trackpad-edge-gesture-depth` under `[GENERAL]` sets how far a region reaches in from its edge (a fraction of the surface, default `0.06`, corners twice that); widen it only if the user reports missed clicks, since a deeper band catches more ordinary pointing. An area click fires only when the clicking finger is the only contact, so a resting palm blocks it by design — tell the user to lift the hand for the click, and steer them toward a few well-separated regions rather than a dense layout, which demands conscious aim near every boundary.

Some useful app commands appear in the menu bar without their own shortcut. Recommend a macOS App Shortcut when appropriate. The user creates one in **System Settings > Keyboard > Keyboard Shortcuts > App Shortcuts**. It targets an existing menu command in one app or all apps. Use its full menu path exactly as shown, with `->` and no spaces between path components. Titles are case-sensitive, and an ellipsis is three periods (`...`), not `…`. Verify it in the target app before binding a Trickpad gesture to it. Do not automate System Settings for this. Its interface and the app's menu titles can change across macOS and app releases.

Do not inspect private content, browser history, credentials, clipboard contents, or unrelated files to generate ideas. Ask before reading another local file or creating a script.

## What makes a binding stick

A good configuration is personal: it reflects one user's apps, habits, and taste, and it usually gets there through revision rather than in one pass.

**A binding earns its place in one of a few ways.** Any one of these can justify it, and the mix differs per user and per app:

- Frequency. Something done many times an hour is worth a gesture; something rare rarely is.
- Flow. The strongest case is a hand already on the mouse or trackpad doing continuous work — dragging, scrubbing, navigating — where the action interleaves with that work. A gesture that saves an easy shortcut can still be a big win if it keeps the hand in place mid-flow.
- Ergonomics. A genuinely awkward chord, three or four modifiers or a long reach, benefits even when it is less frequent.
- No keyboard equivalent. Opening a URL or deep link, running a script, or a middle click has no keystroke to save, so a gesture is a natural fit.

Ask about the user's workflows and propose bindings they would plausibly try, not a showcase of what the app can do.

**Work with the user's associations.** People remember gesture bindings as meaning attached to motion, so bindings that share structure are cheaper to learn and harder to mix up. Paired actions sit well on paired gestures, with symmetric motions paralleling symmetric actions. A gesture rebound per application holds up best when its action stays the same kind of thing in each. When the user offers their own mnemonic, help them refine and develop it.

## Check for conflicts

If a recommendation carries a risk, tell the user plainly what could collide and when, in terms of what their hand does.

**Gestures may overlap with simpler variants.** A double tap contains a single tap, and a three-finger gesture could pass through a two-finger moment as fingers land and lift. When one binding sits inside another this way, the simpler one might fire during the fuller one. Trickpad works to tell such intentions apart, but bindings that cannot overlap in the first place beat any amount of filtering, so we prefer them at the planning stage.

**The device counts contacts, not fingers.** A resting finger can add one to the count. A light touch or an edge contact can drop one. That makes gestures at neighboring finger counts easy to mistake for each other now and then. When two actions must never substitute for each other, give them gestures that differ in kind — a hold against a tap, a swipe against a click — rather than by one finger.

**Conflicts can come from three places. Check each.**

- Triggers macOS has claimed. Run the claims report, substituting the running app path from the prompt:

  ```
  "<app>/Contents/Resources/system-gestures.sh"
  ```

  Run it by path. It is a zsh script, and naming another interpreter fails with a substitution error that reads as a broken script. You might need to ask for permission to run this script.

  `claimed=yes` means macOS acts on that trigger: prefer a different gesture, or tell the user what would double-fire. `claimed=default` means macOS has never written the preference, so ask the user to check System Settings. A `gate=` field means a second preference decided the answer, and the report names it.

  If the report will not run, recommend from the gestures whose safety does not depend on it. Name the check that could not run and what follows from it: macOS may already act on a proposed trigger, so a binding could double-fire.

  Always rely on authoritative sources of gesture configuration state (the config file and what you can see of the gestures configured in macOS System Settings) over your own memory.
- Read the user's other bindings on the same device for anything the proposal contains, sits inside, or neighbors by one finger. Name the current binding on every gesture you discuss, read from the file as you write the sentence.
- The keystroke a binding sends can collide with app or global hotkeys.

**Judge a gesture against the hand at rest.** Between gestures a hand might be already on or over the device — resting, clicking, scrolling. A good gesture is one that background is unlikely to produce by accident, so weigh a proposal against the contacts and motions ordinary use of that surface involves. The less it resembles them, the more the binding can safely carry.

## Tend the configuration over time

**Treat the configuration as a draft, always.** Trying, disliking, and rebinding is the normal path, not a failure of planning. The loop is cheap: edit, Reload Settings, try it in real work. Offer `sound:NAME` or `say:WORDS` when the user wants to feel a gesture out before giving it a real action. Suggest revisiting a binding after a few days of real use rather than defending the first draft.

**Think about the set, not only the binding in front of you.** A configuration is a system the user carries in their hands, so a new binding is worth weighing against the ones already there: whether it follows the patterns they have established, whether it crowds a gesture they use for something else, and whether an older binding it duplicates should go. Bindings that went unused are worth raising, since a gesture nobody reaches for still costs them a gesture they could reach for.

**Tend the file the way its owner keeps it.** The configuration is a plain-text file the user lives in, so its readability is part of the product. Offer, when it would help, to tidy section dividers, comments, ordering, and spacing — and match the conventions already in the file rather than imposing new ones. If the user has their own formatting rules, treat them as the file's lint and keep every edit consistent with them. `AGENTS.local.md` beside this file is where those conventions belong. Offer to record one there as it emerges, so the user does not restate it every session: how comments are worded and aligned, how sections are divided and ordered, which parts they want left alone. Keep that file to conventions. Do not describe the bindings themselves in it, so that `config.toml` and its comments remain the sole source of truth. A comment on a binding's own line appears in the menu bar item's Current Gestures list, so a well-commented file documents itself in the app.

## Edit and apply settings

Read the relevant part of `config.toml` before editing. Make the smallest valid TOML change that accomplishes the request. Keep all bindings for the same device and application together because TOML table headings cannot repeat.

After an edit, confirm the exact lines changed. Trickpad has no supported command-line configuration reload. Do not send `SIGHUP`; it rebuilds touch-device registration without rereading `config.toml`. If the user asked to apply the change, restart Trickpad. Otherwise, tell them to choose **Reload Settings** from the menu bar.

Ask before enabling experimental settings, changing a script, replacing the installed app, or changing its update path.

## Help report a problem

When something Trickpad does is wrong, offer to draft an email to support@thirdwind.fyi. Show them the draft and let them send it. Never send mail yourself, including through a connected mail tool.

The address is Third Wind's, not Trickpad's, so name the product in the subject:

```
Trickpad — three-finger click stopped working
```

Quote their description verbatim, then end the email with this block:

```
--- Trickpad diagnostics ---
version: 0.8.0
macos: 26.0
device: Magic Mouse
gesture: mouse three-finger-tap
binding: "ctrl+cmd+a"
```

`version` comes from `defaults read "<app>/Contents/Info" CFBundleShortVersionString` on the bundle named in the prompt, and `macos` from `sw_vers -productVersion`.

Include the binding lines that bear on the problem. Configuration and logs carry private content: a script path naming a client, a URL binding holding a token, an application name they would not want quoted. Read what you are about to include, tell them what is in it, and ask before including anything personal. Attach logs only if they ask.

When they want something Trickpad does not do, build it out of what exists first. A keystroke, an app deep link, a macOS App Shortcut, or a small script covers many wants that sound like features, and a working binding today beats a request answered someday. If nothing reaches it, say so and mention support@thirdwind.fyi.

## Reference

Read the full configuration reference before proposing gesture, action, or setting names:

https://thirdwind.fyi/trickpad/docs.md

The online reference describes the latest release. If a setting may be new, confirm the installed Trickpad version before using it.
