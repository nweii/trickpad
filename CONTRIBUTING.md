# Contributing to Trickpad

Bug reports, fixes, and gesture improvements are welcome. This guide addresses both humans and coding agents.

## Before you start

Trickpad builds and runs only on macOS 11 or later, with the Xcode Command Line Tools installed. Only real hardware can confirm a change to gesture recognition. A coding agent running on Linux can still edit the code, but it cannot build the app or run the checks. GitHub Actions builds every pull request and runs the checks on macOS, so the pull request shows whether the change compiles. Only you can show that the gesture behaves correctly.

Read these before changing code:

- `AGENTS.md` describes the build, the configuration model, the standing constraints, and every deliberate change to the vendored Jitouch engine. Coding agents load it automatically.
- `GLOSSARY.md` defines the project's terms. Use them in code, issues, and pull requests.
- `docs/agents/verification.md` explains how to confirm that a result is true. It covers proving that a check can fail, reading a build's exit code, and testing on both devices.

Open an issue or a draft pull request before finishing a new gesture, a change to the recognizers, or a change to a configuration name, so we can agree on the approach. Small fixes can go straight to a pull request.

## Make the change

Most changes belong in `src/Config.m`. Change the recognizers in `src/jitouch/` if you can show the engine is wrong, and describe the evidence in the pull request.

Test through the development bundle, which leaves your installed copy alone:

```bash
./scripts/build.sh --dev
open "build/Trickpad DEV.app"
./scripts/check.sh
```

The development bundle needs its own Accessibility permission the first time it runs. Quit it when you finish, and the installed copy resumes on its own.

Add a line for each new gesture, key, action, or setting to `GESTURES.md`, or `check.sh` fails. Say so in the pull request if a change renames or removes a configuration name, because existing configuration files stop matching it.

Leave the version number, tags, and release scripts alone. The maintainer cuts releases.

## Open a pull request

Describe what changed and why, in a sentence or two of your own. Then report what you verified:

- The macOS version you tested on.
- The devices you tested: Magic Mouse, Magic Trackpad, or a built-in trackpad.
- The result of `./scripts/check.sh`.
- For a bug fix, whether you saw the bug before your change and saw it stop after.
- For a new gesture, action, or setting, the `config.toml` line you tested and what happened when you used it.
- The verbose log lines for the gesture, if the change affects how a gesture is recognized or dispatched. The Logging section of `AGENTS.md` gives the setting and the command.
- Anything you could not test.

Say whether a person tested the change on hardware if a coding agent wrote it. Keep the visible description short. Fold any longer description the agent wrote into a `<details>` block whose summary names the agent and model. Keep the report of what you verified above that block. The [pull request template](.github/pull_request_template.md) lays this out. An agent that opens the pull request through `gh pr create --body` or the GitHub API never sees the template and should follow this section instead.

## Report a bug

Include the Trickpad version from **About Trickpad** in the menu bar item, your macOS version, and the device. **About Trickpad** > **Diagnostics** > **Copy Debug Info** copies a summary that covers most of these details. Include the relevant lines from `config.toml` if a binding misbehaves.

The issue tracker is public. Leave out anything private in your configuration.

## License

Trickpad is licensed under GPL-3.0. By contributing, you agree that your contribution is licensed under the same terms.
