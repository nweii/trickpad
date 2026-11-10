# Contributing to Trickpad

Bug reports, fixes, and gesture improvements are welcome. Many contributors work with a coding agent such as Claude Code, Codex, or Cursor, and this guide is written for both the person and the agent.

## Before you start

Trickpad builds and runs only on macOS 11 or later, with the Xcode Command Line Tools installed. A change to gesture recognition can be confirmed only on real hardware. A coding agent running on Linux can still edit the code, but it cannot build the app or run the checks. GitHub Actions builds every pull request and runs the checks on macOS, so the pull request shows whether the change compiles. Only you can show that the gesture behaves correctly.

Read these before changing code:

- `AGENTS.md` describes the build, the configuration model, the standing constraints, and every deliberate change to the vendored Jitouch engine. Coding agents load it automatically.
- `GLOSSARY.md` defines the project's terms. Use them in code, issues, and pull requests.
- `docs/agents/verification.md` lists the ways a step in this project has reported success it did not achieve.

For anything larger than a small fix, open an issue first so the approach can be agreed before you build it.

## Make the change

Most changes belong in `src/Config.m`. Change the recognizers in `src/jitouch/` only when the engine is demonstrably wrong, and describe the evidence in the pull request.

Test through the development bundle so your installed copy is left alone:

```bash
./scripts/build.sh --dev
open "build/Trickpad DEV.app"
./scripts/check.sh
```

The development bundle needs its own Accessibility permission the first time it runs. Quit it when you finish, and the installed copy resumes on its own.

A new gesture, key, action, or setting needs a line in `GESTURES.md`, or `check.sh` fails. A change that renames or removes a configuration name breaks existing configuration files, so say so in the pull request.

Leave the version number, tags, and release scripts alone. Releases are cut by the maintainer.

## Open a pull request

Describe what changed and why, in a sentence or two of your own. Then report what you verified:

- The macOS version you tested on.
- The devices you tested: Magic Mouse, Magic Trackpad, or a built-in trackpad.
- The result of `./scripts/check.sh`.
- For a bug fix, whether you saw the bug before your change and saw it stop after.
- Anything you could not test.

If a coding agent wrote the change, say whether a person tested it on hardware. Keep the visible description short. If the agent wrote a longer description, fold it into a `<details>` block whose summary names the agent and model. The pull request template lays this out; an agent that opens the pull request through `gh pr create --body` or the GitHub API skips the template, so it should follow this section instead.

## Report a bug

Include the Trickpad version from **About Trickpad** in the menu bar item, your macOS version, and the device. **About Trickpad** > **Diagnostics** > **Copy Debug Info** copies a summary that covers most of this. Include the relevant lines from `config.toml` if a binding misbehaves.

The issue tracker is public. Leave out anything private in your configuration.

## License

Trickpad is licensed under GPL-3.0. By contributing, you agree that your contribution is licensed under the same terms.
