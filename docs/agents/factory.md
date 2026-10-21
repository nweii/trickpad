# Trickpad factory

How work on Trickpad gets found, done, checked, released, and learned from, and where Nathan steps in. Agents take their instructions from `AGENTS.md`; this guide is for the person who changes the arrangement. Revise it through the `software-factory` skill, which keeps the rest of this file in step.

Status: **discovery draft**. Everything below describes the factory as it is, except the section marked as proposed.

## One piece of work, end to end

Issue #18, "Suggest near-miss gesture names when a line is skipped", shows the usual path.

1. **Enters.** Nathan, or an agent working with him, files a GitHub issue in `nweii/trickpad`. External people file issues and occasionally PRs (#70, #78).
2. **Triaged.** Nathan applies one of the five triage labels in `docs/agents/triage-labels.md` (Matt Pocock's `triage` lifecycle). `ready-for-agent` means fully specified; `ready-for-human` usually means it needs hands on a Magic Mouse or Magic Trackpad. Larger work gets a spec in `docs/specs/` or a `wayfinder:map` issue (#71).
3. **Picked up.** Only when Nathan opens a session and asks: a Claude Code session on his Mac, a cloud thread in the Trickpad Claude project, or Codex. Nothing picks up `ready-for-agent` work on its own; #18, #56, #57, and #60 have waited since August.
4. **Done.** On a branch with a readable name, as a PR into `main`.
5. **Checked.** `scripts/check.sh` and `scripts/build.sh` need macOS (`xcrun`, `clang` against the macOS SDK). Cloud threads run on Linux and cannot run either, so every cloud PR waits for Nathan to run the checks on his Mac. Gesture behavior needs both devices in hand (`docs/agents/verification.md`).
6. **Lands.** Nathan merges.
7. **Released.** Only on Nathan's Mac, through the `trickpad-release` skill: build, tag, package, `publish.sh` (R2 and the Sparkle feed), `storefront.sh` (Polar), GitHub release.
8. **Reaches buyers.** `thirdwind-site` rebuilds the changelog and latest version from `CHANGELOG.md` only when it deploys, and nothing triggers that deploy after a release. Configuration docs are hand-ported from `GESTURES.md` into `src/trickpad-content.ts`, with nothing to detect drift.

## What the factory runs on

| Part | Where it lives | Pause or remove | What breaks without it | State |
| --- | --- | --- | --- | --- |
| Standing instructions | `AGENTS.md` (`CLAUDE.md` links to it) | Edit the file | Agents lose the release, verification, and engine rules | Running |
| Matt Pocock's skills (triage, domain docs, wayfinder) | Nathan's account plugin `mattpocock-skills`; repo config in `docs/agents/` | Remove the plugin | Triage labels and domain-doc reading go unused | Running, unpinned |
| `trickpad-release` skill | `.agents/skills/trickpad-release`, symlinked into `.claude/skills/` | Delete the folder | Releases fall back to the `AGENTS.md` checklist | Running |
| Configuration checks | `scripts/check.sh`, macOS only | None needed | The only automated proof that config parsing, docs, and menu phrases agree | Running locally only |
| Release publishing | `scripts/publish.sh`, `scripts/storefront.sh`; R2 and Polar credentials in Infisical `workstation/prod/trickpad-publish` | Skip the step | Buyers get no update | Running on Nathan's Mac |
| Claude project "Trickpad" | claude.ai project with both repos | Archive the project | Cloud threads and shared project memory | Running |
| Project memory | claude.ai project memory (`MEMORY.md` and topic files) | Delete a file | Threads re-ask settled facts | Running |
| Private product vision | `VISION.md`, a gitignored local pointer into the Brain vault | n/a | Agents in the cloud cannot read the product's intent | Mac only |
| CI | none in either repository | n/a | n/a | Absent |
| Scheduled routines | none for Trickpad | n/a | n/a | Absent |

## Kinds of work and where they sit

The range runs from 1 (Nathan does it) to 4 (runs unattended to an agreed stopping point).

| Kind of work | Now | Ceiling and why |
| --- | --- | --- |
| Configuration parser, menu, docs inside the app repo | 3: agent writes, Nathan runs checks and reviews | Could reach 4 if the checks ran without him |
| Recognizer and engine changes (`Gesture.m`, interaction modules) | 3, with Nathan testing on both devices | Stays 3: results need hands on hardware |
| Website content and doc ports | 3 | Could reach 4 with a drift check against `GESTURES.md` |
| Triage of incoming issues | 1 | 3: an agent can draft labels and questions for him to confirm |
| Releases | 2: agent prepares, Nathan runs every Mac step | Stays 2 until signing and publishing can run off his Mac |
| Storefront copy and pricing | 1 | Stays 1: buyer-facing and Polar's token cannot write products |

## Other people who bring work

Hariketsu opened #70 (closed unmerged). An external reporter filed #78, a first-launch crash, which has had no triage for eleven days. Buyers reach Nathan through Polar; whether support email arrives anywhere an agent can read is unknown.

## Frictions found

Ranked by how much of Nathan's attention each one frees.

1. **No check runs without Nathan's Mac.** Every cloud PR stalls on him running `check.sh`. The public repository gets free GitHub-hosted macOS runners, which can run `build.sh` and `check.sh` on every PR. Hardware behavior stays his.
2. **A release is not visible to buyers until someone redeploys the site.** A small workflow on a published GitHub release could call the site's deploy hook.
3. **`GESTURES.md` and the website guide drift silently.** The site already fetches `CHANGELOG.md` at build time; a test could fetch `GESTURES.md` the same way and fail when a slug or setting is missing from `trickpad-content.ts`.
4. **`ready-for-agent` issues wait for Nathan to start a session.** A trigger on the label could start a cloud run that stops at a PR. Worth doing only after friction 1, or every run ends in "please run the checks".
5. **New issues wait for Nathan to notice them.** A weekly sweep could draft triage on unlabeled issues and leave the labeling to him.
6. **No owner profile file.** Nathan's taste and conventions live in his Claude account preferences and the Brain vault; bandwidth, harness list, and review habits are not written down anywhere a factory can read.

## Next review

Not set. Proposed: after the first ten PRs that pass through macOS CI, or 2026-11-21, whichever comes first. Bring PRs that still waited on Nathan, reverts, rework, questions agents asked that a file could answer, and stalled `ready-for-agent` issues.

## Changing a part later

Each row in "What the factory runs on" names its file or setting. Change it there, then rerun `software-factory` on this guide so the rest stays consistent.

## Status note

- **Stage:** discovery done; design not started.
- **Decided:** guide lives here, beside Matt Pocock's `docs/agents/` files.
- **Open:** which frictions to take first; where the owner profile lives; Nathan's weekly review bandwidth; whether Codex or another vendor should review PRs an agent wrote.
- **Ideas for later:** a replay oracle for contact frames (see the `refactor/contact-frames` note in `AGENTS.md`); a support inbox route for Polar buyers.
