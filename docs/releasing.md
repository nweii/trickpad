# Releasing Trickpad

How a release is versioned, cut, published, and delivered. Releases are built, signed, and published only on the maintainer's Mac, because they need the Sparkle signing key, the update host's credentials, and the storefront token. `AGENTS.md` covers everything a change needs before it reaches a release.

## Versions

`AGENTS.md` describes where the version lives and the build stamp an unreleased build carries.

Between releases, `APP_VERSION` carries the next patch number with a `-dev` suffix, set as the last step of each release. The suffix names the release train, not a promise: no `-dev` version is ever tagged, packaging refuses it because its tag cannot exist, and the release that ends the cycle sets its real number then, which the semantic-versioning read below may raise past the `-dev` guess.

Semantic versioning, read against the configuration file rather than the code, because the config is the only interface anyone depends on. Before 1.0, a minor release may intentionally change that alpha interface and must carry a migration note. After 1.0:

- **Patch** — a fix that leaves every existing `config.toml` working.
- **Minor** — new gestures, keys, actions, or settings. An existing config keeps working, since unknown names are reported and skipped rather than failing.
- **Major** — a rename or removal that makes an existing `config.toml` behave differently. The positional gesture rename would have been one.

## Cutting a release

```bash
# set APP_VERSION to the release number (drop -dev) and bump APP_BUILD_NUMBER in scripts/build.sh
./scripts/build.sh && ./scripts/check.sh
git commit -am "Release X.Y.Z"
git tag -a vX.Y.Z -m "X.Y.Z"  # local until the package and preview verify
./scripts/package.sh          # requires the tag at HEAD; prints every file the update feed names
./scripts/publish.sh          # read-only preview of R2 and the public feed
./scripts/publish.sh --publish X.Y.Z  # after approving that preview
./scripts/storefront.sh       # preview, then --publish X.Y.Z: replace the Polar benefit DMG
git push origin main --tags
gh release create vX.Y.Z --title "X.Y.Z" --notes "..."
# start the next train: set APP_VERSION to the next patch number plus -dev, commit
```

GitHub releases carry the tag, changelog, and automatic source archives without a packaged binary. The DMG that `scripts/package.sh` produces is delivered through Polar and must not be attached to GitHub. Packaging requires the version's tag to exist at the packaged commit — a missing tag or one pointing elsewhere refuses — and verifies the styled drag-to-Applications layout, app signature, license, notices, trademark notice, and exact-source link. The tag stays local until the package and publish preview verify, so a bad package means deleting an unpushed tag rather than moving a published one.

The release title is the bare version. The repository name sits above it on every page that shows a release, so repeating it adds nothing.

`gh release create` has been seen to report a missing `workflow` scope that the token already holds. Creating it through `gh api repos/OWNER/REPO/releases` works.

Moving a published tag turns its GitHub release back into a draft. Republishing it is a separate step, and a release left drafted is invisible.

## Publishing updates

The build-time Sparkle rules (the fixed feed URL, signing order, and public key) live under Updates in `AGENTS.md`. Publication adds these.

**Publishing is not uploading the archive.** The feed also names deltas, and Sparkle prefers a delta when one applies, so an unpublished delta breaks the update for exactly the people it was built for. `package.sh` prints every file the feed names and refuses when one is missing. Upload those before the appcast, so the feed never names something absent, and set the cache header each wants: archives never change, the appcast changes every release. Inheriting the host default caches both for four hours, which hides a release and lets the feed and its archives disagree. After publishing, compare each archive's served length against the length the appcast names. They must match before the release is announced. An archive published under a name already used caches to the edge for a year, so replacing one needs a cache purge and not another upload, which reports success either way.

The edge also caches a 404 for a URL that does not exist yet, and any probe of an unpublished URL plants one — including the publish preview's own occupancy check, which runs seconds before upload and verification. The zone must carry an edge-TTL rule that stores no 404 from the updates host; without it, first publication of every new archive fails verification against its own cached miss, and the recovery is a per-URL cache purge.

`scripts/publish.sh` automates that publication without joining it to packaging. Its default mode authenticates through the repository's non-secret Infisical pointer, reads `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` from `workstation/prod/trickpad-publish`, and previews both R2 and the public URLs without writing. Those credentials are an R2 account token restricted to Object Read & Write on `thirdwind-updates`; the publisher needs no zone permission. Live mode requires `--publish VERSION`, repeats the preview, and asks for the exact version unless `--yes` follows Nathan's approval. It uploads every archive and delta before `appcast.xml`, then reads each public URL back and compares its bytes and cache header. A different file at an immutable archive URL stops publication; replacement and cache purge remain a separate recovery operation.

## What a release commits this repository to

Both of these fail quietly unless guarded.

**The corresponding-source link is generated, not written.** GPLv3 requires the buyer of a binary to be able to obtain its exact source, and `scripts/package.sh` satisfies that without anyone typing a URL: it derives the link from the app version, refuses to package unless that version's tag points at the packaged commit, and greps the mounted image to confirm the link before finishing. Leave it generated. A hand-maintained copy of that link anywhere else would have no such guard, so proposing one is a decision to take deliberately rather than a gap to fill.

The changelog rules under Changelog in `AGENTS.md` also bind every release, because the website parses that file.

**Publishing the tag does not publish the release.** Surfaces that read this repository do so when they build, not when it changes, so each needs a rebuild of its own before a customer sees the new version. Treat a release as delivered only once every surface below has been refreshed.

## After a release

1. The product website's reference pages, which carry their own copy of the configuration syntax and are updated by hand, so a change to `GESTURES.md` reaches them only when someone ports it.
2. Any surface that derives from `CHANGELOG.md`, which needs a rebuild to pick up the new entry.
3. The storefront listing, where any copy naming a feature the release changed is maintained by hand. The listing's downloadable DMG is not hand-maintained: `scripts/storefront.sh` uploads the packaged image to Polar and points the benefit at it, with the same preview, `--publish`, and read-back discipline as `publish.sh`, reading `POLAR_ACCESS_TOKEN` from the same Infisical folder.
