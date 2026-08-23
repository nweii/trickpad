---
status: Planned
last: 2026-08-14
---

> [!NOTE]
> Context: This specification defines opt-in cancellation for pending work started by configured bindings.
> This document reflects the product thinking at the time of the last update.

# Binding interruption

## Goal

Let one binding cancel unfinished work from earlier bindings before it runs, without changing the existing behavior of any binding that does not opt in.

## Configuration

`interrupt` is an optional property of an expanded binding:

```toml
three-finger-tap = {
  action = "escape",
  interrupt = true
}
```

`interrupt = true` means: cancel unfinished interruptible work started by earlier bindings, then run this binding.

The property belongs to the binding, not to an element inside an action sequence. It is valid with any otherwise valid expanded action. An application-specific expanded binding can inherit its action under the existing inheritance rules.

`interrupt` accepts the same boolean spellings as `defer`, `haptic`, and general boolean settings. An invalid value skips that binding and reports the existing line-based configuration diagnostic.

Bindings without `interrupt`, and bindings with `interrupt = false`, retain their current behavior.

## Dispatch semantics

Interruption happens when the binding begins dispatch, immediately before its confirmation and action.

This timing has these consequences:

- A deferred single tap that is replaced by its double tap never interrupts anything because its action never begins.
- A binding suppressed during a diagnostic trace never interrupts anything.
- An excluded or disabled binding never interrupts anything.
- The interrupting binding's confirmation sound or speech starts after earlier work is canceled.
- Work that already completed cannot be undone.

Interruption is active, not passive. `interrupt = true` means that this binding interrupts earlier work. It does not mean that future ordinary bindings interrupt this one.

## Interruptible work

| Work | Result of interruption |
|---|---|
| Sequence | Cancel its remaining steps, active wait, and queued sequence invocations. |
| Configured sound | Stop sounds still playing from binding actions or binding confirmation. |
| Configured speech | Stop the current utterance, including its pre-utterance delay. |
| Held modifier session | Release its owned modifiers and cancel its pending steps when held bindings exist. This compatibility does not block the first implementation. |
| Script | Continue running. Trickpad does not terminate external processes. |
| Keystroke | No effect after its events have been posted. |
| URL or built-in action | No effect after dispatch. |
| Haptic feedback | No effect after the request has been made. |
| Diagnostic or guided-trace tone | Continue. Internal feedback is not configured binding work. |

The cancellation applies to work from the same binding and from other bindings. Repeating an interrupting sequence therefore replaces its unfinished earlier invocation instead of joining the existing FIFO queue.

An ordinary sequence keeps the existing FIFO behavior:

```text
ordinary A starts -> ordinary B queues -> A finishes -> B starts
```

An interrupting binding is an explicit exception:

```text
A starts -> interrupting B fires -> A and queued sequences cancel -> B starts
```

An ordinary binding fired after B does not cancel B. It follows the existing dispatch behavior for its action type.

## Ownership

One interruption module owns cancellation. Individual bindings and action implementations do not cancel one another directly.

The module's interface is one operation equivalent to:

```objc
- (void)interruptPendingBindingWork;
```

The implementation coordinates the existing sequence dispatcher, configured sound playback, configured speech, and future held-modifier sessions. Each action type keeps ownership of its own cleanup operation.

The shared binding-dispatch seam calls the interruption module only when the resolved binding has `interrupt = true`. A binding without the property does not enter a new execution path.

Cancellation and the interrupting binding's start must be ordered. A canceled sequence timer must not run after the interrupting action begins, and sound or speech cancellation must reach the main queue before new confirmation starts there.

## Compatibility

The feature is additive:

- Existing configuration syntax keeps the same interpretation.
- Existing sequence bindings keep FIFO completion.
- Existing sound and speech restart behavior remains unchanged.
- Existing keystroke planning and posting remains unchanged.
- Existing lifecycle cancellation on reload and gestures-off remains unchanged.
- Scripts retain their current asynchronous lifetime.

Adding the property does not require a configuration-version change because no existing value changes meaning. An older Trickpad version will report and skip a binding that uses the unknown property, matching existing unknown-property behavior.

The menu continues to describe the binding's action. It does not need an interruption badge or separate row.

## Validation

Parser checks must cover:

- `interrupt = true` and every accepted boolean spelling.
- `interrupt = false` preserving ordinary behavior.
- An invalid value producing one line-specific diagnostic.
- Use with a single action, a sequence action, and an inherited application action.
- Existing expanded bindings producing unchanged parsed dictionaries when `interrupt` is absent.

Dispatch checks must cover:

- An ordinary sequence continuing and preserving its queued FIFO work.
- An interrupting keystroke canceling the active sequence wait and queued sequences before posting its key.
- An interrupting sequence canceling earlier sequence work, then starting itself.
- Repeating an interrupting sequence replacing its unfinished invocation.
- A deferred action that never runs causing no interruption.
- Configured sounds stopping before the interrupting binding's confirmation or action sound starts.
- Configured speech stopping before the interrupting binding's confirmation or action speech starts.
- Scripts continuing after interruption.
- Internal diagnostic tones remaining outside interruption.
- A stale scheduled sequence block doing nothing after cancellation.

Prove the sequence-cancellation check with controlled sabotage: remove or bypass the generation invalidation and confirm that the stale step makes the check fail.

## Manual verification

Use the development bundle and temporary low-consequence bindings:

1. Start a sequence with a visible first step, `wait:1000`, and a visible final step.
2. Fire a non-interrupting binding during the wait and confirm that the final step still runs.
3. Repeat with `interrupt = true` on the second binding and confirm that the final step does not run.
4. Queue two sequence invocations, fire the interrupting binding, and confirm that neither unfinished invocation resumes.
5. Start a long configured sound and interrupt it with a keystroke binding.
6. Start configured speech and interrupt it with a keystroke binding.
7. Confirm that the interrupting binding itself runs in every case.

Implementation also requires the normal repository checks and build. `GESTURES.md` and `config-notes.default.md` must document the property. `CHANGELOG.md` must describe the behavior in its release entry.

## Non-goals

- Pausing and resuming work.
- Priorities or named cancellation groups.
- Choosing individual action types to interrupt.
- Terminating scripts or their child processes.
- Undoing posted keystrokes, opened URLs, built-in actions, or haptic requests.
- Turning sequences into a general automation language.
- Implementing held modifiers as part of this feature.

## Changelog

- 2026-08-14: Initial specification.
