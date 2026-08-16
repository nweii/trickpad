# Debug tools

Small single-file programs for diagnosing keyboard and input problems by hand. Nothing builds or runs them automatically, and the app does not depend on them.

- `check-secure-input.m` — reports whether macOS currently considers Secure Input active. Secure Input suppresses synthesized keystrokes, so a binding that dispatches without any visible effect is often this.
- `release-secure-input.m` — attempts to release a Secure Input state a terminated process left behind.
- `right-control-test.m` — posts one right-Control-plus-Space chord through the same event-planning path a binding uses, which separates a recognition problem from a keystroke problem.
- `release-right-control.m` — releases a right-Control modifier left held down.
- `dock-notification-probe.m` — reports which `CoreDockSendNotification` call form macOS honors, so a Mission Control or App Expose action that does nothing can be told apart from a gesture that never fired.
- `watch-middle-button.m` — prints every middle-button down, drag, and up, so a `middle-click` binding can be watched without an application that uses the middle button. A press that never prints its up left the button down.

Compile one with clang, naming the frameworks it imports:

```bash
clang -framework Carbon scripts/debug/check-secure-input.m -o /tmp/check-secure-input
clang -framework ApplicationServices scripts/debug/right-control-test.m -o /tmp/right-control-test
```

To check a trackpad middle-click lifecycle:

1. Compile the watcher with `clang -framework ApplicationServices scripts/debug/watch-middle-button.m -o /tmp/watch-middle-button`.
2. Run `/tmp/watch-middle-button`, then do a stationary bound click. The output must contain one down and one up.
3. Hold the bound click and move. The output must contain drag events between the down and up.
4. Interrupt a held click with a reload, wake, or device disable. Each down must have one up. A click on the other device must pass through while the middle button stays held.
5. Bind the same physical click to a non-middle action. The action must run once, with no middle-button events.
6. Drag across selectable text with one finger. Native selection must continue to work.
