# Debug tools

Small single-file programs for diagnosing keyboard and input problems by hand. Nothing builds or runs them automatically, and the app does not depend on them.

- `check-secure-input.m` — reports whether macOS currently considers Secure Input active. Secure Input suppresses synthesized keystrokes, so a binding that dispatches without any visible effect is often this.
- `release-secure-input.m` — attempts to release a Secure Input state a terminated process left behind.
- `right-control-test.m` — posts one right-Control-plus-Space chord through the same event-planning path a binding uses, which separates a recognition problem from a keystroke problem.
- `release-right-control.m` — releases a right-Control modifier left held down.
- `watch-middle-button.m` — prints every middle-button down, drag, and up, so a `middle-click` binding can be watched without an application that uses the middle button. A press that never prints its up left the button down.

Compile one with clang, naming the frameworks it imports:

```bash
clang -framework Carbon scripts/debug/check-secure-input.m -o /tmp/check-secure-input
clang -framework ApplicationServices scripts/debug/right-control-test.m -o /tmp/right-control-test
```
