---
name: trickpad-release
description: "Use when discussing, planning, preparing, cutting, publishing, or verifying a Trickpad release, including versioning, changelogs, packaging, delivery, and the next development train."
compatibility: "Advisory use has no special requirements. Release execution requires macOS and the repository's release tools. Publishing accepts ambient R2 and Polar environment variables; the configured MacBook can load them from Infisical through ~/.local/bin/infisical-macos-run."
---

# Trickpad release

Use the repository's release conventions while preserving their approval gates and consumer-boundary checks. Treat `AGENTS.md` and the repository scripts as the sources of truth. Read the full `## Releasing` section through `## Configuration model` because the release contract includes update publication, downstream surfaces, and recovery constraints.

## Choose the mode

- In advisory mode, answer questions, compare options, or plan the release using the repository's conventions. Use read-only inspection when current repository state matters. Do not begin the release sequence or change files unless the user asks you to prepare or execute it.
- In execution mode, follow the sequence below when the user asks to prepare, cut, publish, or finish a release. Manual invocation as `/trickpad-release VERSION` selects this mode.

If execution mode has no VERSION, inspect `APP_VERSION` in `scripts/build.sh`, the latest tag, and the configuration-interface changes since that tag. Propose the semantic version and get the user's confirmation before editing it.

## Use a release train branch

When unreleased work needs to soak away from `main`, create `releases/X.Y.Z` from the current `main` branch after the version is confirmed. Set `APP_VERSION` to `X.Y.Z-dev` and keep the complete train there. Committing or pushing this branch does not publish a release.

Before cutting the release, require a clean release train with passing checks, then get approval to integrate it into local `main`. Run the preparation checks again on `main`. The `Release X.Y.Z` commit, annotated tag, package, and publication all remain on `main`; never tag or publish directly from the release train branch.

## Prepare the release

1. Run these read-only checks from the repository root:

   ```bash
   git status --short
   git branch --show-current
   git log --oneline --decorate "$(git describe --tags --abbrev=0)..HEAD"
   git diff --stat "$(git describe --tags --abbrev=0)..HEAD"
   git tag --points-at HEAD
   rg -n '^(APP_VERSION|APP_BUILD_NUMBER)=' scripts/build.sh
   ```

2. Accept `main` or the exact `releases/X.Y.Z` branch during preparation. Stop if the branch is anything else, the checkout contains unrelated work, or the release contents are not committed. List the exact condition the user must settle. Do not absorb unrelated changes into the release. Do not begin the build-and-stage sequence until the approved train has been integrated into local `main`.

3. Determine the version from Trickpad's configuration-interface semantic versioning in `AGENTS.md`. Identify every renamed or removed configuration name since the previous release. Any rename or removal requires a migration note.

4. Inspect all customer-visible changes since the latest tag. Draft the `CHANGELOG.md` entry in its existing structure:

   - `## X.Y.Z`
   - `Released YYYY-MM-DD.`
   - one `### Section` heading per group
   - imperative bullets
   - an optional trailing paragraph for closing notes

   Follow the [Google developer documentation style guide](https://developers.google.com/style), starting with its highlights. Use clear, concise US English for a global audience. Prefer active voice, familiar words, and unambiguous sentences. Describe customer effects rather than implementation details. Preserve Trickpad's project-specific imperative and neutral-voice rules even where the general guide uses second person.

5. Search every mirror named under `## Cross-surface product facts` in `AGENTS.md`. Report which mirrors require changes. A repository release is not delivered until each relevant downstream surface has been refreshed.

6. Present the proposed version, build number, changelog, migration notes, included commits, and required mirror updates. Get the user's approval before editing release files.

The preparation step is complete when the user has approved an exact version and changelog, every included change is committed, the checkout is otherwise clean, and every affected mirror has an owner.

## Build and stage locally

1. Set `APP_VERSION` to the approved release version and increment `APP_BUILD_NUMBER` in `scripts/build.sh`. Apply approved changelog and in-repository mirror changes only.

2. Run:

   ```bash
   ./scripts/build.sh
   ./scripts/check.sh
   ```

3. Inspect the diff. Commit the release files as `Release X.Y.Z` only after the user approves the diff. Do not add an AI attribution trailer.

4. Create the annotated tag locally:

   ```bash
   git tag -a vX.Y.Z -m "X.Y.Z"
   ```

5. Run `./scripts/package.sh`. Read its exit status and output. Confirm that it verified the clean tagged commit, mounted DMG contents, signature, notices, and exact-source link.

6. Run the read-only publication preview:

   ```bash
   ./scripts/publish.sh
   ```

7. Run the read-only storefront preview:

   ```bash
   ./scripts/storefront.sh
   ```

Stop on any failed check or preview. Keep the tag local. Never move or replace a published tag.

The local stage is complete when the clean tagged commit builds, checks, packages, and passes both publication previews.

## Publish with approval

Each numbered action below changes an external consumer. Show the current preview and get the user's explicit approval immediately before running it. Approval for one action does not authorize the next.

1. Publish the Sparkle archives, deltas, and appcast:

   ```bash
   ./scripts/publish.sh --publish X.Y.Z
   ```

   Confirm the script read every public URL back and verified its byte length and cache header.

2. Replace the Polar benefit DMG:

   ```bash
   ./scripts/storefront.sh --publish X.Y.Z
   ```

   Confirm the storefront read-back names the intended artifact.

3. Push the commit and tag:

   ```bash
   git push origin main --tags
   ```

   Fetch or query the remote and confirm that `origin/main` and `vX.Y.Z` point at the release commit.

4. Create the GitHub release with the bare version as its title and the approved changelog as its notes. Attach no DMG. If `gh release create` reports the known false `workflow`-scope error, use the GitHub releases API route documented in `AGENTS.md`. Read the release back and confirm it is published rather than drafted.

5. Refresh each affected downstream surface listed under `### After a release` in `AGENTS.md`. Treat repository edits, deployed pages, rebuilt changelog consumers, and storefront copy as separate states. Verify the live consumer for each surface you can reach; identify anything only the user can verify.

The publication stage is complete when the update feed and every named archive are served correctly, Polar delivers the intended DMG, the commit and tag are remote, the GitHub release is public, and every affected downstream surface is refreshed or explicitly assigned to the user.

## Start the next release train

1. Set `APP_VERSION` in `scripts/build.sh` to the next patch version with a `-dev` suffix. Do not change `APP_BUILD_NUMBER` again.

2. Run `./scripts/build.sh && ./scripts/check.sh`.

3. Commit the train change with a concise conventional commit. Push only after the user approves the push.

4. Report final state by boundary: local release commit, local tag, packaged DMG, Sparkle publication, Polar benefit, pushed commit and tag, GitHub release, downstream surfaces, and next-train commit.

The release is complete only when no required boundary remains implied or unverified.

## Guardrails

- Never use `--yes` without the user approving the exact preview it bypasses.
- Never force-push, move a published tag, attach the DMG to GitHub, or publish an archive under a reused name.
- Never report a working-tree state as pushed, a successful upload as served, or a repository change as deployed.
- Preserve `CHANGELOG.md` structure because another surface parses it.
- Leave recovery actions such as cache purges and published-artifact replacement outside this workflow. Stop and present a recovery plan if they become necessary.
