#!/bin/zsh
# Exercises the release publisher through its command-line interface without
# contacting Infisical, R2, or the public update feed.
set -euo pipefail

ROOT="${0:A:h:h}"
WORK_ROOT="$(mktemp -d)"
UPDATES_DIR="$WORK_ROOT/updates"
REMOTE_DIR="$WORK_ROOT/remote"
PUBLIC_DIR="$WORK_ROOT/public"
REQUEST_LOG="$WORK_ROOT/requests.log"
FAKE_CURL="$WORK_ROOT/curl"

mkdir -p "$UPDATES_DIR" "$REMOTE_DIR" "$PUBLIC_DIR"
printf 'archive-1.0.0\n' > "$UPDATES_DIR/Trickpad-1.0.0.zip"
printf 'delta-0.9.0-to-1.0.0\n' > "$UPDATES_DIR/Trickpad-0.9.0-1.0.0.delta"
ARCHIVE_LENGTH="$(stat -f %z "$UPDATES_DIR/Trickpad-1.0.0.zip")"
DELTA_LENGTH="$(stat -f %z "$UPDATES_DIR/Trickpad-0.9.0-1.0.0.delta")"
cat > "$UPDATES_DIR/appcast.xml" <<XML
<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
      <enclosure url="https://updates.thirdwind.fyi/trickpad/9zvff4/Trickpad-1.0.0.zip" length="$ARCHIVE_LENGTH" />
      <sparkle:deltas>
        <sparkle:delta url="https://updates.thirdwind.fyi/trickpad/9zvff4/Trickpad-0.9.0-1.0.0.delta" length="$DELTA_LENGTH" />
      </sparkle:deltas>
    </item>
  </channel>
</rss>
XML

cat > "$FAKE_CURL" <<'SH'
#!/bin/zsh
# Records requests and emulates the R2 bucket plus its public custom domain.
set -euo pipefail

method="GET"
output=""
header_output=""
write_out=""
upload_file=""
cache_control=""
url=""
while (( $# > 0 )); do
  case "$1" in
    --request) method="$2"; shift 2 ;;
    --head) method="HEAD"; shift ;;
    --output) output="$2"; shift 2 ;;
    --dump-header) header_output="$2"; shift 2 ;;
    --write-out) write_out="$2"; shift 2 ;;
    --upload-file) upload_file="$2"; shift 2 ;;
    --header)
      [[ "$2" == 'Cache-Control: '* ]] && cache_control="${2#Cache-Control: }"
      shift 2
      ;;
    --aws-sigv4|--user) shift 2 ;;
    --silent|--show-error|--fail) shift ;;
    http://*|https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done

print -r -- "$method $url" >> "$TRICKPAD_PUBLISH_TEST_REQUEST_LOG"
name="${url##*/}"
if [[ "$url" == *'.r2.cloudflarestorage.com/'* ]]; then
  store="$TRICKPAD_PUBLISH_TEST_REMOTE_DIR"
else
  store="$TRICKPAD_PUBLISH_TEST_PUBLIC_DIR"
fi
stored="$store/$name"
http_code=404

if [[ "$method" == PUT ]]; then
  cp "$upload_file" "$TRICKPAD_PUBLISH_TEST_REMOTE_DIR/$name"
  print -r -- "$cache_control" > "$TRICKPAD_PUBLISH_TEST_REMOTE_DIR/$name.cache"
  if [[ "${TRICKPAD_PUBLISH_TEST_STALE_PUBLIC:-0}" != 1 ]]; then
    cp "$upload_file" "$TRICKPAD_PUBLISH_TEST_PUBLIC_DIR/$name"
    print -r -- "$cache_control" > "$TRICKPAD_PUBLISH_TEST_PUBLIC_DIR/$name.cache"
  fi
  http_code=200
elif [[ -f "$stored" ]]; then
  http_code=200
  if [[ "$method" == GET && -n "$output" && "$output" != /dev/null ]]; then
    cp "$stored" "$output"
  fi
elif [[ -n "$output" && "$output" != /dev/null ]]; then
  : > "$output"
fi

if [[ -n "$header_output" ]]; then
  print "HTTP/2 $http_code" > "$header_output"
  if [[ "$http_code" == 200 && -f "$stored.cache" ]]; then
    print "Cache-Control: $(<"$stored.cache")" >> "$header_output"
  fi
fi
[[ -n "$write_out" ]] && print -n "$http_code"
SH
chmod +x "$FAKE_CURL"

run_publisher() {
  R2_ACCESS_KEY_ID=test-access \
  R2_SECRET_ACCESS_KEY=test-secret \
  TRICKPAD_PUBLISH_UPDATES_DIR="$UPDATES_DIR" \
  TRICKPAD_PUBLISH_CURL="$FAKE_CURL" \
  TRICKPAD_PUBLISH_TEST_REQUEST_LOG="$REQUEST_LOG" \
  TRICKPAD_PUBLISH_TEST_REMOTE_DIR="$REMOTE_DIR" \
  TRICKPAD_PUBLISH_TEST_PUBLIC_DIR="$PUBLIC_DIR" \
    "$ROOT/scripts/publish.sh" "$@"
}

output="$(run_publisher)"

grep -q 'Dry run' <<< "$output" || {
  echo "publish check: the default command did not identify itself as a dry run" >&2
  exit 1
}
if grep -q '^PUT ' "$REQUEST_LOG"; then
  echo "publish check: dry run wrote to R2" >&2
  exit 1
fi

: > "$REQUEST_LOG"
output="$(printf '1.0.1\n' | run_publisher --publish 1.0.0)"
grep -q 'Publication canceled' <<< "$output" || {
  echo "publish check: a different typed version did not cancel publication" >&2
  exit 1
}
if grep -q '^PUT ' "$REQUEST_LOG"; then
  echo "publish check: publication wrote before exact-version approval" >&2
  exit 1
fi

: > "$REQUEST_LOG"
output="$(run_publisher --publish 1.0.0 --yes)"
grep -q 'Published and publicly verified Trickpad 1.0.0' <<< "$output" || {
  echo "publish check: live publication did not report verified completion" >&2
  exit 1
}
archive_put="$(grep -n '^PUT .*Trickpad-1.0.0.zip$' "$REQUEST_LOG" | cut -d: -f1)"
delta_put="$(grep -n '^PUT .*Trickpad-0.9.0-1.0.0.delta$' "$REQUEST_LOG" | cut -d: -f1)"
appcast_put="$(grep -n '^PUT .*appcast.xml$' "$REQUEST_LOG" | cut -d: -f1)"
[[ -n "$archive_put" && -n "$delta_put" && -n "$appcast_put" &&
   "$archive_put" -lt "$appcast_put" && "$delta_put" -lt "$appcast_put" ]] || {
  echo "publish check: the appcast was not uploaded after every immutable file" >&2
  exit 1
}
cmp -s "$UPDATES_DIR/Trickpad-1.0.0.zip" "$PUBLIC_DIR/Trickpad-1.0.0.zip" || {
  echo "publish check: the public archive differs after upload" >&2
  exit 1
}
cmp -s "$UPDATES_DIR/Trickpad-0.9.0-1.0.0.delta" "$PUBLIC_DIR/Trickpad-0.9.0-1.0.0.delta" || {
  echo "publish check: the public delta differs after upload" >&2
  exit 1
}
cmp -s "$UPDATES_DIR/appcast.xml" "$PUBLIC_DIR/appcast.xml" || {
  echo "publish check: the public appcast differs after upload" >&2
  exit 1
}

printf 'different archive with same published name\n' > "$REMOTE_DIR/Trickpad-1.0.0.zip"
if run_publisher > "$WORK_ROOT/collision.out" 2>&1; then
  echo "publish check: dry run accepted different bytes at an immutable archive URL" >&2
  exit 1
fi
grep -q 'requires a separate cache-purge recovery operation' "$WORK_ROOT/collision.out" || {
  echo "publish check: immutable collision did not explain the recovery boundary" >&2
  exit 1
}

mv "$REMOTE_DIR/Trickpad-1.0.0.zip" "$WORK_ROOT/removed-archive"
mv "$REMOTE_DIR/Trickpad-1.0.0.zip.cache" "$WORK_ROOT/removed-archive.cache"
printf 'stale public archive\n' > "$PUBLIC_DIR/Trickpad-1.0.0.zip"
if run_publisher > "$WORK_ROOT/public-collision.out" 2>&1; then
  echo "publish check: dry run accepted different bytes already served at an immutable URL" >&2
  exit 1
fi
grep -q 'public URL already serves different bytes' "$WORK_ROOT/public-collision.out" || {
  echo "publish check: public collision did not name the served-state problem" >&2
  exit 1
}

mv "$REMOTE_DIR" "$WORK_ROOT/collision-remote"
mv "$PUBLIC_DIR" "$WORK_ROOT/collision-public"
mkdir "$REMOTE_DIR" "$PUBLIC_DIR"
: > "$REQUEST_LOG"
if TRICKPAD_PUBLISH_TEST_STALE_PUBLIC=1 \
   TRICKPAD_PUBLISH_SLEEP=/usr/bin/true \
   run_publisher --publish 1.0.0 --yes > "$WORK_ROOT/read-back.out" 2>&1; then
  echo "publish check: publication succeeded without public archive read-back" >&2
  exit 1
fi
grep -q 'public verification failed for Trickpad-1.0.0.zip' "$WORK_ROOT/read-back.out" || {
  echo "publish check: public read-back failure did not identify the archive" >&2
  exit 1
}
if grep -q '^PUT .*appcast.xml$' "$REQUEST_LOG"; then
  echo "publish check: appcast uploaded after public archive verification failed" >&2
  exit 1
fi

echo "publish check passed"
