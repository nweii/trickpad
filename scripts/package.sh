#!/bin/zsh
# Builds a styled Trickpad disk image containing the app, Applications link,
# license notices, and exact corresponding-source link.
set -euo pipefail
export COPYFILE_DISABLE=1

ROOT="${0:A:h:h}"
APP_NAME="Trickpad"
BUILD_ROOT="$ROOT/build"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"
BACKGROUND="$ROOT/packaging/dmg-background.png"
BACKGROUND_RETINA="$ROOT/packaging/dmg-background@2x.png"

command -v appdmg >/dev/null || {
  echo "Packaging requires appdmg. Install it with: npm install -g appdmg" >&2
  exit 1
}

"$ROOT/scripts/build.sh" >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
DMG_PATH="$BUILD_ROOT/$APP_NAME-$VERSION.dmg"
VOLUME_NAME="$APP_NAME $VERSION"
WORK_ROOT="$(mktemp -d)"
STAGE="$WORK_ROOT/$APP_NAME-$VERSION"
SPEC="$WORK_ROOT/appdmg.json"
VERIFY_DIR="$WORK_ROOT/verify"
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet 2>/dev/null || true
  fi
}
trap cleanup EXIT

if TAG_COMMIT="$(git -C "$ROOT" rev-list -n 1 "v$VERSION" 2>/dev/null)" &&
   [[ -n "$TAG_COMMIT" && "$TAG_COMMIT" != "$(git -C "$ROOT" rev-parse HEAD)" ]]; then
  echo "Version $VERSION already belongs to a different source commit." >&2
  echo "Bump the app version before packaging this build." >&2
  exit 1
fi

# An updater decides whether a release is newer by comparing build numbers, so a
# number that repeats or goes backwards leaves everyone already installed with
# no way to be offered this release. The failure is silent at the customer's
# end, which is why it is caught here rather than noticed later.
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist")"
[[ "$BUILD_NUMBER" == <-> ]] || {
  echo "CFBundleVersion must be a plain integer, found \"$BUILD_NUMBER\"." >&2
  exit 1
}

# Compared against the highest build number any earlier release carries, not
# just the previous tag's. Tags predating APP_BUILD_NUMBER declare none, and
# skipping those is correct rather than an error. Read from tagged source, which
# the working tree cannot edit.
HIGHEST_RELEASED_BUILD_NUMBER=0
HIGHEST_RELEASED_TAG=""
for tag in $(git -C "$ROOT" tag --list 'v*' --sort=-v:refname | grep -v "^v$VERSION\$"); do
  # Braced because zsh reads an unbraced $tag:s… as a substitution modifier.
  # The trailing fallback matters under pipefail: a tag with no build number
  # makes grep exit non-zero, which would otherwise abort packaging outright.
  tagged_number="$(git -C "$ROOT" show "${tag}:scripts/build.sh" 2>/dev/null |
    grep -m 1 '^APP_BUILD_NUMBER=' | tr -dc '0-9' || true)"
  [[ -n "$tagged_number" ]] || continue
  if (( tagged_number > HIGHEST_RELEASED_BUILD_NUMBER )); then
    HIGHEST_RELEASED_BUILD_NUMBER=$tagged_number
    HIGHEST_RELEASED_TAG="$tag"
  fi
done

if [[ -n "$HIGHEST_RELEASED_TAG" ]] &&
   (( BUILD_NUMBER <= HIGHEST_RELEASED_BUILD_NUMBER )); then
  echo "Build number $BUILD_NUMBER does not exceed $HIGHEST_RELEASED_BUILD_NUMBER from $HIGHEST_RELEASED_TAG." >&2
  echo "Raise APP_BUILD_NUMBER in scripts/build.sh before packaging." >&2
  exit 1
fi

[[ -f "$BACKGROUND" ]] || {
  echo "Missing DMG background: $BACKGROUND" >&2
  exit 1
}
[[ -f "$BACKGROUND_RETINA" ]] || {
  echo "Missing Retina DMG background: $BACKGROUND_RETINA" >&2
  exit 1
}

mkdir -p "$STAGE/Legal"
cp "$ROOT/LICENSE.txt" "$ROOT/NOTICE.txt" "$ROOT/TRADEMARKS.md" "$STAGE/Legal/"
printf '%s\n' \
  "The exact corresponding source for this build is available at:" \
  "https://github.com/nweii/trickpad/tree/v$VERSION" \
  > "$STAGE/Legal/SOURCE.txt"

cat > "$SPEC" <<JSON
{
  "title": "$VOLUME_NAME",
  "background": "$BACKGROUND",
  "icon-size": 104,
  "window": {
    "position": { "x": 120, "y": 120 },
    "size": { "width": 660, "height": 540 }
  },
  "format": "UDZO",
  "filesystem": "HFS+",
  "contents": [
    { "x": 175, "y": 150, "type": "file", "path": "$APP_BUNDLE" },
    { "x": 485, "y": 150, "type": "link", "path": "/Applications" },
    { "x": 330, "y": 445, "type": "file", "path": "$STAGE/Legal" }
  ]
}
JSON

[[ ! -e "$DMG_PATH" ]] || mv "$DMG_PATH" "$WORK_ROOT/previous.dmg"
appdmg "$SPEC" "$DMG_PATH"

hdiutil verify "$DMG_PATH" -quiet
mkdir -p "$VERIFY_DIR"
DEVICE="$(hdiutil attach -readonly -noverify -noautoopen -mountpoint "$VERIFY_DIR" "$DMG_PATH" |
  awk '/Apple_HFS/ { print $1; exit }')"
[[ -n "$DEVICE" ]] || {
  echo "Could not mount the finished disk image." >&2
  exit 1
}

for required in \
  "$APP_NAME.app/Contents/Info.plist" \
  "Applications" \
  "Legal/LICENSE.txt" \
  "Legal/NOTICE.txt" \
  "Legal/TRADEMARKS.md" \
  "Legal/SOURCE.txt"; do
  [[ -e "$VERIFY_DIR/$required" ]] || {
    echo "Disk image is missing $required" >&2
    exit 1
  }
done

grep -Fxq "https://github.com/nweii/trickpad/tree/v$VERSION" \
  "$VERIFY_DIR/Legal/SOURCE.txt" || {
    echo "Disk image has the wrong corresponding-source link." >&2
    exit 1
  }
codesign --verify --deep --strict "$VERIFY_DIR/$APP_NAME.app"

hdiutil detach "$DEVICE" -quiet
DEVICE=""

# The styled image is for purchase and first install, where it carries the
# Gatekeeper instructions. An update replaces a bundle that is already in place,
# so it ships as a plain archive and leaves the background art behind.
#
# Skipped entirely when the app carries no updater, which is the same condition
# that leaves SUPublicEDKey unset in scripts/build.sh.
if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP_BUNDLE/Contents/Info.plist" >/dev/null 2>&1; then
  UPDATES_DIR="$BUILD_ROOT/updates"
  UPDATE_ARCHIVE="$UPDATES_DIR/$APP_NAME-$VERSION.zip"
  mkdir -p "$UPDATES_DIR"

  # ditto keeps the bundle's symlinks and signature intact, which a plain zip
  # does not, and Sparkle rejects an archive whose signature no longer verifies.
  rm -f "$UPDATE_ARCHIVE"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$UPDATE_ARCHIVE"

  # generate_appcast reads release notes from a file named after the archive,
  # so the entry a customer sees comes from the changelog rather than being
  # written twice.
  RELEASE_NOTES="$UPDATES_DIR/$APP_NAME-$VERSION.html"
  if [[ -f "$ROOT/CHANGELOG.md" ]]; then
    awk -v version="$VERSION" '
      $0 == "## " version { collecting = 1; next }
      collecting && /^## / { exit }
      collecting { print }
    ' "$ROOT/CHANGELOG.md" > "$WORK_ROOT/notes.md"
    if [[ -s "$WORK_ROOT/notes.md" ]]; then
      # Escaped before any markup is added, so changelog prose containing an
      # ampersand or an angle bracket cannot break the rendered note. Backtick
      # spans become code, since entries name settings constantly.
      sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
          -e 's|`\([^`]*\)`|<code>\1</code>|g' \
          "$WORK_ROOT/notes.md" > "$WORK_ROOT/notes-escaped.md"
      # Deliberately minimal: headings and list items only. Sparkle renders this
      # in a small pane, and anything richer would be styling a release note.
      awk '
        BEGIN { inList = 0 }
        /^### / { if (inList) { print "</ul>"; inList = 0 }
                  sub(/^### /, ""); print "<h3>" $0 "</h3>"; next }
        /^- / { if (!inList) { print "<ul>"; inList = 1 }
                sub(/^- /, ""); print "<li>" $0 "</li>"; next }
        /^[[:space:]]*$/ { next }
        { if (inList) { print "</ul>"; inList = 0 }
          print "<p>" $0 "</p>" }
        END { if (inList) print "</ul>" }
      ' "$WORK_ROOT/notes-escaped.md" > "$RELEASE_NOTES"
    fi
  fi
  [[ -s "$RELEASE_NOTES" ]] || {
    echo "No changelog section found for $VERSION, so the update would ship with no notes." >&2
    echo "Add a '## $VERSION' section to CHANGELOG.md before packaging." >&2
    exit 1
  }

  # Not vendored, because they publish a release rather than build the app.
  # third_party/sparkle/README.md records where they come from.
  GENERATE_APPCAST="${SPARKLE_TOOLS:-$ROOT/third_party/sparkle/bin}/generate_appcast"
  [[ -x "$GENERATE_APPCAST" ]] || GENERATE_APPCAST="$(command -v generate_appcast || true)"
  [[ -n "$GENERATE_APPCAST" && -x "$GENERATE_APPCAST" ]] || {
    echo "generate_appcast not found." >&2
    echo "Put Sparkle's bin/ at third_party/sparkle/bin, or set SPARKLE_TOOLS." >&2
    exit 1
  }

  # Signs each archive with the private key from the Keychain. Without that key
  # it fails here rather than publishing a feed nothing can verify.
  "$GENERATE_APPCAST" "$UPDATES_DIR"

  APPCAST="$UPDATES_DIR/appcast.xml"
  [[ -s "$APPCAST" ]] || {
    echo "generate_appcast produced no appcast." >&2
    exit 1
  }
  grep -q "edSignature" "$APPCAST" || {
    echo "The appcast carries no signature, so no installed copy would accept it." >&2
    exit 1
  }
  grep -Fq "$VERSION" "$APPCAST" || {
    echo "The appcast has no entry for $VERSION." >&2
    exit 1
  }

  # The feed names more than the archive just built. generate_appcast also
  # writes binary deltas between releases, and Sparkle prefers a delta over the
  # full archive, so a delta left unpublished is a broken update for exactly the
  # people the delta was made for. The upload set is read back out of the
  # appcast rather than assumed, and every file it names must exist first.
  MISSING=0
  for referenced in $(grep -oE 'url="[^"]+"' "$APPCAST" | sed -e 's/^url="//' -e 's/"$//'); do
    name="${referenced##*/}"
    if [[ -f "$UPDATES_DIR/$name" ]]; then
      echo "$UPDATES_DIR/$name"
    else
      echo "The appcast names $name, which is not in $UPDATES_DIR." >&2
      MISSING=1
    fi
  done
  (( MISSING == 0 )) || {
    echo "Publishing this feed would reference a file that does not exist." >&2
    exit 1
  }
  echo "$APPCAST"

  # Publishing is deliberately a separate step. Once an appcast is live every
  # installed copy acts on it, so it should follow a decision rather than a
  # build finishing. Upload the files above before the appcast, so the feed
  # never names something that is not there yet.
  echo "To publish, upload every file listed above, appcast last:" >&2
  echo "  CLOUDFLARE_ACCOUNT_ID=… wrangler r2 object put … --remote" >&2
  echo "  See the private delivery note for the bucket and path." >&2
fi

echo "$DMG_PATH"
