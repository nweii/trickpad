# Gesture reference

Everything you can write in `config.toml`. The file uses TOML, with quoted strings and `#` comments. Each device has its own table, and a name from one table does nothing on the other.

The recognizers are compiled in. Reload Settings reports and skips a name that is not listed here.

The words of a gesture name can come in any order, so `swipe-up-three-finger` loads as `three-finger-swipe-up`. The menu and reports show the canonical name.

Gestures that hold one finger still are named by where the fingers sit, not by which finger does what. `hold-left-tap-right` means hold a finger and tap to its right, which on a right hand is the index finger holding and the middle finger tapping. Either hand works, and either finger can play either part.

## Supported finger counts

| Device | Taps | Multi-finger clicks | Swipes |
|---|---:|---:|---:|
| Magic Mouse | 1–3 | 2–3 | 1–3 |
| Magic Trackpad | 2–5 | 3–4 | 3–4 |

Magic Mouse gestures use up to three fingers. Trackpad taps use up to five fingers, while its multi-finger clicks and swipes use up to four. Trackpad area clicks use one finger.

## Magic Mouse

| Write this | Hand motion |
|---|---|
| `hold-left-tap-right` | Hold one finger still and tap to its right with another, keeping the hold through the tap |
| `hold-right-tap-left` | Hold one finger still and tap to its left with another, keeping the hold through the tap |
| `hold-two-tap-left` | Hold two fingers still and tap to their left with another, keeping both holds through the tap |
| `hold-two-tap-right` | Hold two fingers still and tap to their right with another, keeping both holds through the tap |
| `hold-two-tap-between` | Hold two fingers still and tap between them with another, keeping both holds through the tap |
| `one-finger-tap` | Tap with one finger |
| `two-finger-tap` | Tap with two fingers |
| `three-finger-tap` | Tap with three fingers |
| `one-finger-double-tap` | Tap twice with one finger |
| `two-finger-double-tap` | Tap twice with two fingers |
| `three-finger-double-tap` | Tap twice with three fingers |
| `front-right-tap` | Tap the front right of the surface |
| `two-finger-click` | Physically click with two fingers touching; replaces the normal click |
| `three-finger-click` | Physically click with three fingers touching; replaces the normal click |
| `one-finger-swipe` | Swipe with one finger, either direction |
| `one-finger-swipe-left` | Swipe left with one finger |
| `one-finger-swipe-right` | Swipe right with one finger |
| `two-finger-swipe` | Swipe with two fingers, either direction |
| `two-finger-swipe-left` | Swipe left with two fingers |
| `two-finger-swipe-right` | Swipe right with two fingers |
| `three-finger-swipe` | Swipe with three fingers, any direction |
| `three-finger-swipe-left` | Swipe left with three fingers |
| `three-finger-swipe-right` | Swipe right with three fingers |
| `three-finger-swipe-up` | Swipe up with three fingers |
| `three-finger-swipe-down` | Swipe down with three fingers |

A bare swipe name such as `three-finger-swipe` binds every direction of that finger count to one action. A directional name is more specific and wins for its own direction. An `"off"` on either name works the same way in an application table: it excludes one direction or the whole family there.

Physical clicks ignore narrow contacts at either side and palm contacts at the rear. Counted fingertips must form one connected cluster; a recognized thumb does not count toward the gesture.

## Magic Trackpad

The trackpad recognizes a hold-and-slide in one direction only, so it has one slide name where the mouse has two.

| Write this | Hand motion |
|---|---|
| `hold-left-tap-right` | Hold one finger still and tap to its right with another, keeping the hold through the tap |
| `hold-right-tap-left` | Hold one finger still and tap to its left with another, keeping the hold through the tap |
| `hold-two-tap-left` | Hold two fingers still and tap to their left with another, keeping the hold through the tap |
| `hold-two-tap-right` | Hold two fingers still and tap to their right with another, keeping the hold through the tap |
| `hold-two-tap-between` | Hold two fingers still and tap between them with another, keeping the hold through the tap |
| `hold-three-tap-left` | Hold three fingers still and tap to their left with another, keeping the hold through the tap |
| `hold-three-tap-right` | Hold three fingers still and tap to their right with another, keeping the hold through the tap |
| `hold-slide` | Hold one finger still, slide another |
| `two-finger-tap` | Tap with two fingers |
| `three-finger-tap` | Tap with three fingers |
| `four-finger-tap` | Tap with four fingers |
| `five-finger-tap` | Tap with five fingers together |
| `two-finger-double-tap` | Tap twice with two fingers |
| `three-finger-double-tap` | Tap twice with three fingers |
| `four-finger-double-tap` | Tap twice with four fingers |
| `five-finger-double-tap` | Tap twice with five fingers |
| `three-finger-click` | Physically click with three fingers touching |
| `four-finger-click` | Physically click with four fingers touching |
| `three-finger-swipe` | Swipe with three fingers, any direction |
| `three-finger-swipe-left` | Swipe left with three fingers |
| `three-finger-swipe-right` | Swipe right with three fingers |
| `three-finger-swipe-up` | Swipe up with three fingers |
| `three-finger-swipe-down` | Swipe down with three fingers |
| `four-finger-swipe` | Swipe with four fingers, any direction |
| `four-finger-swipe-left` | Swipe left with four fingers |
| `four-finger-swipe-right` | Swipe right with four fingers |
| `four-finger-swipe-up` | Swipe up with four fingers |
| `four-finger-swipe-down` | Swipe down with four fingers |
| `index-to-pinky` | Brush your fingers across in sequence, index first |
| `pinky-to-index` | Brush your fingers across in sequence, pinky first |

Bare swipe names bind every direction of a finger count, and directional names win for their own direction, as in the Magic Mouse table above.

### Area clicks

An area click is a physical click with one finger that lands in a named region of the trackpad surface. A click in a region with no binding stays a normal native click. When bound regions overlap, the most specific bound region wins: a bound named corner beats `corner-click`, either beats any edge region, a bound third beats a bound half, a bound half beats the whole edge, and `edge-click` comes last.

`corner-click` binds all four corners to one action, and `edge-click` binds a click anywhere in any edge band. A named region overrides the bare name for its own spot, and an `"off"` on either form works in an application table.

Slugs read edge first, then span, then action. Vertical edges divide top to bottom; horizontal edges divide left to right.

Regions stay narrow by default so a click during ordinary pointing does not land in one by accident. `trackpad-edge-gesture-depth` under `[GENERAL]` sets how far an edge band reaches in from its edge, as a fraction of the surface; corner squares span twice that depth. On a surface wider than it is tall, the same fraction reaches physically deeper on the left and right edges than on the top and bottom, and both scale together.

An area click fires only when the clicking finger is the only contact on the surface. Lift your palm and resting fingers for the click. This keeps a resting hand from triggering regions, at the cost of making each area click a deliberate motion. Binding many regions at once works, but neighboring regions sit close together, so a dense layout asks for conscious aim; most configurations are better served by a few well-separated regions.

| Write this | Part |
|---|---|
| `edge-click` | Anywhere in any edge band |
| `corner-click` | Any of the four corners |
| `left-edge-click` | Anywhere along the left edge |
| `right-edge-click` | Anywhere along the right edge |
| `top-edge-click` | Anywhere along the top edge |
| `bottom-edge-click` | Anywhere along the bottom edge |
| `left-edge-top-half-click` | Top half of the left edge |
| `left-edge-bottom-half-click` | Bottom half of the left edge |
| `right-edge-top-half-click` | Top half of the right edge |
| `right-edge-bottom-half-click` | Bottom half of the right edge |
| `top-edge-left-half-click` | Left half of the top edge |
| `top-edge-right-half-click` | Right half of the top edge |
| `bottom-edge-left-half-click` | Left half of the bottom edge |
| `bottom-edge-right-half-click` | Right half of the bottom edge |
| `left-edge-top-third-click` | Top third of the left edge |
| `left-edge-middle-third-click` | Middle third of the left edge |
| `left-edge-bottom-third-click` | Bottom third of the left edge |
| `right-edge-top-third-click` | Top third of the right edge |
| `right-edge-middle-third-click` | Middle third of the right edge |
| `right-edge-bottom-third-click` | Bottom third of the right edge |
| `top-edge-left-third-click` | Left third of the top edge |
| `top-edge-middle-third-click` | Middle third of the top edge |
| `top-edge-right-third-click` | Right third of the top edge |
| `bottom-edge-left-third-click` | Left third of the bottom edge |
| `bottom-edge-middle-third-click` | Middle third of the bottom edge |
| `bottom-edge-right-third-click` | Right third of the bottom edge |
| `top-left-corner-click` | The top left corner |
| `top-right-corner-click` | The top right corner |
| `bottom-left-corner-click` | The bottom left corner |
| `bottom-right-corner-click` | The bottom right corner |

On both devices, a confidently recognized configured click replaces the native click: the bound action fires on release and the click does not reach the application. An ambiguous click, such as one with a resting palm, stays native and does not fire the bound action. A drag keeps its native events and does not fire the configured click action. A click bound to `middle-click` presses the middle button with the physical click, sends middle-button drags during movement, and releases the button when the click ends.

One continuous touch sequence can run one kind of configured gesture. A swipe or hold gesture may repeat while it owns the sequence, but a physical click, tap, or different gesture will not also run until every finger lifts.

## Application-specific bindings

Put an application name or exact bundle identifier in a device heading:

    [TRACKPAD."Final Cut Pro"]

    three-finger-click = "escape"
    four-finger-tap = "off"

The application section overrides global bindings for the same gesture. `off` excludes a global binding in that application. TOML tables cannot repeat, so keep an application's bindings together under its one device table.

Set `inherit = false` to stop an application table from using any device-global bindings. Bindings in the application table still apply, and the other device keeps its global bindings unless its application table also sets `inherit = false`:

    [MOUSE."Final Cut Pro"]

    inherit = false
    three-finger-click = "escape"

## Binding options

Use braces when a binding needs options. Separate properties with commas; line breaks are optional:

    three-finger-tap = {
      action = "ctrl+cmd+a",
      defer = true,
      haptic = false
    }

An application-specific block may omit `action` to inherit the global action:

    [TRACKPAD."Final Cut Pro"]

    three-finger-tap = { haptic = false }

`haptic` is valid only for trackpad bindings. It overrides the global `haptic-feedback` setting for that binding.

### Hearing a gesture fire

`sound` plays a macOS system sound and `say` speaks any words when the gesture fires, alongside whatever the binding already does. A binding carrying both plays the sound first and speaks after it:

    three-finger-tap = { action = "cmd+shift+4", sound = "Glass" }
    three-finger-click = { action = "right-ctrl+space", say = "dictation" }

Both work on either device. A Magic Mouse has no haptic feedback, so this is the only way to confirm one of its gestures by ear. Either starts the moment the gesture fires and never delays the action or the next gesture, and a gesture fired while one is still sounding interrupts it and starts again.

### Deferring a tap

Set `defer = true` when the first tap also begins a double-tap gesture in macOS or another application:

    two-finger-tap = { action = "ctrl+cmd+a", defer = true }

Trickpad waits through the Mac's double-click interval before sending the single-tap action. A second matching tap on the same device cancels it. This preserves the double-tap gesture at the cost of latency on the single tap.

`defer` works only with single-tap gestures. A swipe, slide, hold, or double tap using it is reported and skipped.

### Double taps

A `<count>-finger-double-tap` name runs when you tap twice with that finger count inside the Mac's double-click interval:

    three-finger-double-tap = "cmd+shift+5"

Bind the double tap alone and the single tap of that finger count keeps doing whatever it did before, with no added wait.

To bind both the single tap and its own double tap, set `defer = true` on the single tap:

    three-finger-tap = { action = "escape", defer = true }
    three-finger-double-tap = "cmd+shift+5"

The single tap then waits through the double-click interval, and a second tap inside that interval sends the double-tap action instead. Without `defer`, the single tap sends its action on each of the two taps and the double tap sends its own action as well.

Triple taps are not available.

## What a gesture can send

A keystroke, a built-in action, a URL, an executable script, a sound, speech, or a sequence of these values.

### Sequences

Use a TOML array to run several binding values in order:

    three-finger-tap = ["ctrl+space", "p"]
    four-finger-tap = ["cmd+shift+p", "wait:150", "escape"]

Each element uses the same validation as a standalone keystroke, action, URL, script, sound, or speech binding. Trickpad reports the element number and skips the binding when one element is invalid.

Use `wait:MS` to pause before the next element. `MS` is a positive whole number of milliseconds. The waits in one sequence can total up to 3000 ms. Use a `script:` binding for longer work. A standalone `wait:` value is invalid.

Trickpad adds a short gap between consecutive keystrokes so an application can process a prefix before the next key. If another sequence starts while one runs, Trickpad queues it. Each sequence finishes before the next begins. Reloading settings or turning Trickpad off drops queued sequences and steps that have not started.

URL substitutions resolve when their element runs. Script paths are checked when settings reload, as they are for standalone bindings.

An expanded binding accepts an array for `action`, so the normal `defer`, `haptic`, `sound`, and `say` options still apply once to the gesture:

    three-finger-tap = {
      action = ["cmd+shift+p", "wait:150", "escape"],
      haptic = false
    }

### Keystrokes

Write a key alone, modifiers plus one key, or modifier keys without a regular key. These four are the same binding:

    "cmd+shift+a"
    "command-shift-a"
    "⌘⇧A"
    "Cmd Shift A"

Modifier names are case-insensitive. For example, `cmd`, `CMD`, `command`, and `Command` all mean the Command modifier.

| Modifier | Write any of |
|---|---|
| Command | `cmd` `command` `⌘` |
| Control | `ctrl` `control` `⌃` |
| Option | `opt` `option` `alt` `⌥` |
| Shift | `shift` `⇧` |

Modifiers default to the left-side key. Prefix a written name with `left-` or `right-` when an application distinguishes the two sides, such as `right-control+space`. The prefix works with every written alias, including `right-ctrl`, `right-cmd`, and `right-alt`. Modifier symbols use the default left side.

A modifier-only binding presses and releases the named modifier keys. For example, `left-cmd+right-cmd` sends the two Command keys together.

Keys: any letter or digit, plus `return` `escape` `tab` `space` `delete` `forward-delete` `up` `down` `left` `right` `home` `end` `page-up` `page-down` and `f1` through `f12`. Punctuation keys: `[` `]` `-` `=` `;` `'` `,` `.` `/` `\` and backtick (`` ` ``).

Aliases: `enter` is `return`, `esc` is `escape`, `backspace` and `del` are `delete`, `spacebar` is `space`.

Fn cannot be sent. It is a HID usage rather than an ordinary key event, so no gesture can stand in for an Fn shortcut.

### Actions

`middle-click` `mission-control` `app-expose` `show-desktop` `app-switcher` `next-tab` `previous-tab` `new-tab` `close-tab` `reopen-tab` `maximize` `minimize`

`play-pause` `next-track` `previous-track` `mute` `volume-up` `volume-down` `brightness-up` `brightness-down` `keyboard-backlight-up` `keyboard-backlight-down`

`mission-control`, `app-expose`, `show-desktop`, and `app-switcher` ask macOS for those views directly rather than sending their keyboard shortcuts. An application cannot intercept them, and they work whether or not the matching shortcut is enabled in System Settings.

`middle-click` posts a real middle-button event, which gives a Magic Mouse a button it does not otherwise have. A physical click bound to it holds the middle button until the click ends. A tap bound to it sends one press and release.

The media, volume, display brightness, and keyboard backlight actions send the matching system function key. They do not change the meaning of `f1` through `f12`, which remain literal function keys.

### URL bindings and app deep links

Prefix an absolute URL with `url:`. macOS opens it in the application registered for its scheme. A URL binding can open a web URL or an app deep link that targets a specific place or action in Raycast, Obsidian, Things, or another app:

    hold-right-tap-left = "url:raycast://extensions/raycast/raycast-ai/ai-chat"
    three-finger-tap = "url:obsidian://daily"
    four-finger-tap = "url:https://example.com/page#section"

The URL must include a scheme followed by `:`. Reload Settings reports malformed URLs, unencoded spaces, and malformed percent escapes. It does not require an application for the scheme to be installed; macOS resolves the handler when the gesture fires.

TOML treats `#` outside a quoted string as a comment. URL fragments stay inside the quoted value. A trailing comment follows the closing quote:

    three-finger-tap = "url:obsidian://daily" # Open today's daily note

#### Substitutions

A URL binding can contain substitutions that resolve when its gesture fires:

| Substitution | Resolved value |
|---|---|
| `{{clipboard}}` | Clipboard text unchanged |
| `{{clipboard\|urlencode}}` | Clipboard text encoded as one URL component |
| `{{datetime:FORMAT}}` | Current local date and time in the given Apple date format |

For example:

    four-finger-tap = "url:things:///add?title={{clipboard|urlencode}}"
    four-finger-tap = "url:things:///add?title={{clipboard|urlencode}}&when={{datetime:yyyy-MM-dd}}"

Use `urlencode` for clipboard text placed in a query parameter. It escapes characters such as spaces, `&`, `=`, `/`, and `?` so the clipboard cannot change the URL's structure. Use raw `{{clipboard}}` only when the copied text is already safe in that position.

An empty clipboard resolves to an empty value. Reload Settings reports unknown substitutions and filters, unmatched braces, empty date formats, and unmatched quotes in date formats. The expanded URL is checked again when the gesture fires. If it is invalid, nothing opens and Console records the problem without the expanded clipboard contents.

### Scripts

Prefix an executable path with `script:`:

    hold-right-tap-left = "script:~/bin/my-script"

The path may begin with `~` or be absolute. It must exist and be executable when the settings reload. Trickpad launches it directly through its shebang, uses the script's folder as its working directory, and does not wait for it to finish. It does not interpret shell commands, arguments, substitutions, or an interactive shell profile. Console records launch failures and nonzero exits.

### Sounds and speech

Prefix a macOS system sound name with `sound:`, or the words to speak with `say:`:

    three-finger-tap = "sound:Glass"
    three-finger-tap = "say:three fingers"

The gesture plays that sound or speaks that text and does nothing else, which separates a recognition problem from a binding problem: if you hear it, the gesture fired. Speech can carry any words, so several test bindings can each announce which gesture fired. A fire during the previous sound or sentence interrupts it and starts over, so silence always means the gesture did not fire.

Written this way the sound replaces the action, which is what makes it a test. To hear a gesture that still does its real work, use the `sound` or `say` binding option instead.

A sound name is case-sensitive, carries no extension, and must match a file in `/System/Library/Sounds`. Reload Settings reports a name it cannot find, and a `say:` with nothing after it.

## Turn a menu command into a shortcut

An app may offer a useful menu command without its own keyboard shortcut. macOS can assign one: open **System Settings > Keyboard > Keyboard Shortcuts > App Shortcuts**, choose the app, and add the command.

Write the full menu path exactly as it appears in the app, using `->` without spaces between path components. Titles are case-sensitive, and an ellipsis is three periods (`...`), not `…`. An App Shortcut targets an existing menu command only. Test it in the target app before binding a Trickpad gesture to the chord.

App updates and localizations can change menu titles. Update the App Shortcut if the assigned shortcut stops working.

## Settings

| Setting | Value |
|---|---|
| `config-version` | Configuration format used by this file, currently `3` |
| `enable-mouse` | `true` or `false` |
| `enable-trackpad` | `true` or `false` |
| `dominant-hand` | `left` or `right`; mirrors positional recognition for left-handed use, default `right` |
| `tap-speed` | Seconds a tap may last, default `0.25` |
| `trackpad-edge-gesture-depth` | Fraction of the trackpad an edge band reaches in from its edge, above 0 and below 0.5; corners span twice this; default `0.06` |
| `haptic-feedback` | `true` requests confirmation for configured trackpad gestures, default `true` |
| `menu-bar-icon` | `trickpad`, or `sf:` followed by a name from [SF Symbols](https://developer.apple.com/sf-symbols/); default `trickpad` |
| `verbose-logging` | `true` logs every gesture and keystroke to Console |

Booleans are `true` or `false`, following TOML.

Hiding the menu bar icon is not a setting here either. Use System Settings > Menu Bar; gestures keep working without it.

Starting at login is not a setting here. Tick **Open at Login** in the menu bar item. From a source checkout, `scripts/install-login-agent.sh` does the same thing from the shell.

## Conflicts with built-in macOS gestures

macOS assigns its own gestures in System Settings under Trackpad and Mouse. Binding a trigger macOS already acts on adds your action without removing the built-in one. Which triggers are taken depends on your settings, since the finger counts and the individual gestures are adjustable, so no list here can tell you what is free on your Mac.

Trickpad reads those settings when it loads a configuration and reports any binding whose trigger a built-in gesture already uses. The menu bar item shows the count, and the row opens the details.

To see the same thing from the shell:

```bash
/Applications/Trickpad.app/Contents/Resources/system-gestures.sh
```

Each line names one gesture from this reference and whether macOS has claimed the trigger it overlaps. A line reading `claimed=default` means macOS has never written that preference, so the built-in default decides it and System Settings is the only place to confirm.

macOS can assign its own secondary click to a click in the bottom left or bottom right trackpad corner, under System Settings > Trackpad. When that option is on, macOS claims those corners, so a `bottom-left-corner-click` or `bottom-right-corner-click` binding competes with the built-in secondary click there.

One kind of overlap is easy to miss. A built-in gesture that uses a *double* tap, such as the Magic Mouse two-finger double tap, contains two single taps, so a single-tap binding on the same finger count fires while you perform it.

## Choosing one

The `hold-` gestures keep one or more fingers still while another taps or slides. A resting hand does not produce that shape and macOS binds nothing to it, so they stay clear on both counts. Bind those for anything you would regret firing by accident.

A tap fires while your hand rests on the surface. A swipe competes with scrolling. Both are fine for something harmless.

## Where these come from

The recognizers are [Jitouch](https://github.com/JitouchApp/Jitouch), vendored under `src/jitouch/`. `src/Config.m` maps the names above to the engine's internal names, which are longer and encode detail a hand does not distinguish, such as how far apart two fingers land.
