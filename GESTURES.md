# Gesture reference

Every name and value form `config.toml` accepts, one line each. The [Trickpad guide](https://thirdwind.fyi/trickpad/docs/) explains how each one behaves and how to choose between them.

Reload Settings reports and skips a name that is not listed here. The words of a gesture name can come in any order, so `swipe-up-three-finger` loads as `three-finger-swipe-up`. Each device has its own table, and a name from one table does nothing on the other.

## Supported finger counts

| Device | Taps | Multi-finger clicks | Swipes |
|---|---:|---:|---:|
| Magic Mouse | 1–3 | 2–3 | 1–3 |
| Magic Trackpad | 2–5 | 3–4 | 3–4 |

Magic Mouse gestures use up to three fingers. Trackpad taps use up to five fingers, while its multi-finger clicks and swipes use up to four. Trackpad area clicks use one finger.

## Magic Mouse

Hold gestures are named by where the fingers sit: `hold-left-tap-right` holds one finger and taps to its right.

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

A bare swipe name such as `three-finger-swipe` binds every direction of that finger count. A directional name wins for its own direction.

## Magic Trackpad

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

### Area clicks

A one-finger physical click in a named region of the trackpad. `trackpad-edge-gesture-depth` sets how far the regions reach. When bound regions overlap, the most specific one wins.

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

## What a gesture can send

| Write this | Sends |
|---|---|
| `"cmd+shift+a"` | A keystroke: one key with optional modifiers, or modifiers alone, such as `left-cmd+right-cmd` |
| `"mission-control"` | A built-in action from the list below |
| `"url:obsidian://daily"` | Opens a URL or app deep link, with optional substitutions |
| `"script:~/bin/my-script"` | Runs an executable file through its shebang |
| `"sound:Glass"` | Plays a macOS system sound and does nothing else |
| `"say:three fingers"` | Speaks the words and does nothing else |
| `"menu:History > Back"` | Chooses that command from the menu bar of the app under the pointer |
| `["cmd+shift+p", "wait:150", "escape"]` | Runs each value in order; `wait:MS` pauses, up to 3000 ms per sequence |
| `"off"` | In an application table, turns off the global binding for that gesture |

### Keystrokes

| Modifier | Write any of |
|---|---|
| Command | `cmd` `command` `⌘` |
| Control | `ctrl` `control` `⌃` |
| Option | `opt` `option` `alt` `⌥` |
| Shift | `shift` `⇧` |
| Fn | `fn` `function` `globe` |

Modifiers default to the left-side key. Prefix a written name with `left-` or `right-`, such as `right-ctrl`. Separators may be `+`, `-`, or a space, and symbols may run together, as in `⌘⇧A`.

Keys: any letter or digit, `return` `escape` `tab` `space` `delete` `forward-delete` `up` `down` `left` `right` `home` `end` `page-up` `page-down` `f1` through `f12`, and `[` `]` `-` `=` `;` `'` `,` `.` `/` `\` and backtick (`` ` ``).

Aliases: `enter` is `return`, `esc` is `escape`, `backspace` and `del` are `delete`, `spacebar` is `space`, and `backslash` is `\`.

### Actions

`middle-click` `mouse-3` through `mouse-32` `mission-control` `app-expose` `show-desktop` `app-switcher` `next-tab` `previous-tab` `new-tab` `close-tab` `reopen-tab` `maximize` `minimize`

`play-pause` `next-track` `previous-track` `mute` `volume-up` `volume-down` `brightness-up` `brightness-down` `keyboard-backlight-up` `keyboard-backlight-down`

### URL substitutions

| Substitution | Resolved value |
|---|---|
| `{{clipboard}}` | Clipboard text unchanged |
| `{{clipboard\|urlencode}}` | Clipboard text encoded as one URL component |
| `{{datetime:FORMAT}}` | Current local date and time in the given Apple date format |

### Sounds

`Basso` `Blow` `Bottle` `Frog` `Funk` `Glass` `Hero` `Morse` `Ping` `Pop` `Purr` `Sosumi` `Submarine` `Tink`, in any capitalization.

## Binding options

Write a binding as an inline table when it needs options, such as `three-finger-tap = { action = "escape", defer = true }`.

| Option | Meaning |
|---|---|
| `action` | The value to send. An application table may omit it to inherit the global action |
| `defer = true` | A single tap waits through the double-click interval so a double tap can replace it |
| `haptic` | `true` or `false`; overrides `haptic-feedback` for one trackpad binding |
| `sound` | Plays a system sound when the gesture fires, alongside the action |
| `say` | Speaks words when the gesture fires, alongside the action |

## Application tables

| Write this | Meaning |
|---|---|
| `[MOUSE."Safari"]` or `[TRACKPAD."com.apple.Safari"]` | Bindings below apply only in that app, named by display name or bundle identifier |
| `inherit = false` | In an application table, ignores every global binding for that device |

## Fn layer

| Write this | Meaning |
|---|---|
| `fn_three-finger-tap` | Runs only while the physical Fn key is held, ahead of the ordinary binding |
| `function_`, `"fn+…"`, `"function+…"` | Other spellings of `fn_` |

## Settings

These go under `[GENERAL]`.

| Setting | Value |
|---|---|
| `config-version` | Configuration format used by this file, currently `3` |
| `enable-mouse` | `true` or `false` |
| `enable-trackpad` | `true` or `false` |
| `dominant-hand` | `left` or `right`; mirrors positional recognition for left-handed use, default `right` |
| `tap-speed` | Seconds a tap may last, default `0.25` |
| `trackpad-edge-gesture-depth` | Fraction of the trackpad an edge region reaches inward, up to 0.25; corners span twice this, up to 0.20. Default `0.06` |
| `haptic-feedback` | `true` requests confirmation for configured trackpad gestures, default `true` |
| `menu-bar-icon` | `trickpad`, or `sf:` followed by a name from [SF Symbols](https://developer.apple.com/sf-symbols/); default `trickpad` |
| `verbose-logging` | `true` logs every gesture and keystroke to Console |

Booleans are `true` or `false`, following TOML.
