# Trickpad

Maps Magic Mouse and Magic Trackpad multi-touch gestures to keystrokes, built-in actions, URLs, or scripts on macOS. This glossary pins the project's canonical vocabulary; `CLAUDE.md` and `GESTURES.md` use these terms.

## Language

### Bindings and actions

**Binding**:
One configuration line that pairs a gesture with an action: the gesture slug on the left of `=`, the binding value on the right. Bindings live under a device table (`[MOUSE]` or `[TRACKPAD]`) or an application scope within one.

**Action**:
What Trickpad does when a bound gesture fires. The reader-facing umbrella for everything a binding value can name: a keystroke, a built-in action, a custom URL, or an executable script.
_Avoid_: command, mapping, output

**Binding value**:
The exact TOML value after `=` in a binding. Either a quoted string naming the action directly, or an expanded binding whose `action` key names it. Use this term when the precise TOML syntax matters; use "action" when describing what the gesture does.

**Built-in action**:
An action the engine performs itself, named by a slug such as `mission-control`, rather than by sending a keystroke, URL, or script.

**Expanded binding**:
A binding value written as a TOML inline table, such as `{ action = "escape", haptic = false }`, so per-binding options can ride alongside the action.

**Substitution**:
A named expression in a URL binding, such as `{{clipboard}}` or `{{datetime:FORMAT}}`, that resolves when its gesture fires.
_Avoid_: snippet, variable, token

### Gestures and recognition

**Gesture**:
A motion or touch pattern on one device that Trickpad recognizes, named by a slug such as `three-finger-tap`. A gesture with no binding does nothing.

**Contact sequence**:
The run of touch frames on one device from the first contact landing to every raw contact lifting. One gesture owner may claim a sequence; ownership resets at full lift.
_Avoid_: touch session, gesture window

### Area gestures

**Area gesture**:
A trackpad gesture whose meaning comes from where on the surface it happens, not from finger count or motion alone. The family name for corner pulls, corner clicks, and edge click regions.
_Avoid_: region gesture, zone gesture

**Corner pull**:
A drag that starts in a trackpad corner and travels inward past a distance threshold before it is recognized.
_Avoid_: corner drag, corner swipe

**Corner click**:
A physical click that lands inside a trackpad corner region.

**Edge click region**:
A named span of one trackpad edge — the whole edge, a half, or a third — that a physical click can land in.
_Avoid_: edge zone, edge segment
