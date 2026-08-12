#!/bin/zsh
# Publishes an existing Sparkle update set to its fixed R2 feed, with a
# read-only preview first and public read-back verification after every write.
set -euo pipefail

ROOT="${0:A:h:h}"
UPDATES_DIR="${TRICKPAD_PUBLISH_UPDATES_DIR:-$ROOT/build/updates}"
CURL_BIN="${TRICKPAD_PUBLISH_CURL:-curl}"
SLEEP_BIN="${TRICKPAD_PUBLISH_SLEEP:-sleep}"
INFISICAL_RUNNER="$HOME/.local/bin/infisical-macos-run"
ACCOUNT_ID="f37ef727745eb9b364f87806a00f7bd2"
BUCKET="thirdwind-updates"
OBJECT_PREFIX="trickpad/9zvff4"
PUBLIC_BASE="https://updates.thirdwind.fyi/$OBJECT_PREFIX"
S3_BASE="https://$ACCOUNT_ID.r2.cloudflarestorage.com/$BUCKET/$OBJECT_PREFIX"
ARCHIVE_CACHE_CONTROL="public, max-age=31536000, immutable"
APPCAST_CACHE_CONTROL="public, max-age=60"
APPCAST="$UPDATES_DIR/appcast.xml"
PUBLISH=0
ASSUME_YES=0
REQUESTED_VERSION=""
ORIGINAL_ARGUMENTS=("$@")

CONFIGURED_FEED="$(sed -n 's/^SPARKLE_FEED_URL="\(.*\)"$/\1/p' "$ROOT/scripts/build.sh")"
[[ "$CONFIGURED_FEED" == "$PUBLIC_BASE/appcast.xml" ]] || {
  echo "scripts/build.sh and publish.sh disagree about the permanent feed URL." >&2
  exit 1
}

usage() {
  echo "Usage: $0 [--publish VERSION] [--yes]"
  echo "Without --publish, shows a read-only preview and uploads nothing."
}

while (( $# > 0 )); do
  case "$1" in
    --publish)
      (( $# >= 2 )) || { echo "--publish needs a version." >&2; exit 2; }
      PUBLISH=1
      REQUESTED_VERSION="$2"
      shift 2
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if (( ASSUME_YES && ! PUBLISH )); then
  echo "--yes is valid only with --publish VERSION." >&2
  exit 2
fi

if [[ -z "${R2_ACCESS_KEY_ID:-}" || -z "${R2_SECRET_ACCESS_KEY:-}" ]]; then
  [[ -x "$INFISICAL_RUNNER" ]] || {
    echo "Missing R2 credentials and Infisical runner: $INFISICAL_RUNNER" >&2
    exit 1
  }
  exec "$INFISICAL_RUNNER" \
    --project-config-dir "$ROOT" \
    --env prod \
    --path /trickpad-publish \
    -- "$0" "${ORIGINAL_ARGUMENTS[@]}"
fi

if [[ "$R2_ACCESS_KEY_ID" == REPLACE_ME || "$R2_SECRET_ACCESS_KEY" == REPLACE_ME ]]; then
  echo "Replace the Trickpad publishing credential placeholders in Infisical." >&2
  exit 1
fi

[[ -s "$APPCAST" ]] || {
  echo "Missing packaged appcast: $APPCAST" >&2
  echo "Run scripts/package.sh before publishing." >&2
  exit 1
}

VERSION="$(perl -0777 -ne 'print $1 if m{<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>}' "$APPCAST")"
[[ -n "$VERSION" ]] || {
  echo "The appcast has no release version." >&2
  exit 1
}
if [[ -n "$REQUESTED_VERSION" && "$REQUESTED_VERSION" != "$VERSION" ]]; then
  echo "Requested version $REQUESTED_VERSION, but the packaged appcast starts with $VERSION." >&2
  exit 1
fi

typeset -a REFERENCED_NAMES REFERENCED_LENGTHS REFERENCED_PATHS
while IFS=$'\t' read -r referenced_url referenced_length; do
  [[ -n "$referenced_url" ]] || continue
  [[ "$referenced_url" == "$PUBLIC_BASE/"* ]] || {
    echo "The appcast references a file outside the fixed Trickpad feed: $referenced_url" >&2
    exit 1
  }
  referenced_name="${referenced_url##*/}"
  [[ -n "$referenced_name" && "$referenced_name" != *'?'* && "$referenced_name" != *'#'* ]] || {
    echo "The appcast has an unsupported update URL: $referenced_url" >&2
    exit 1
  }
  [[ "$referenced_url" == "$PUBLIC_BASE/$referenced_name" ]] || {
    echo "The appcast nests an update below the fixed feed directory: $referenced_url" >&2
    exit 1
  }
  referenced_path="$UPDATES_DIR/$referenced_name"
  [[ -f "$referenced_path" ]] || {
    echo "The appcast names $referenced_name, which is missing from $UPDATES_DIR." >&2
    exit 1
  }
  actual_length="$(stat -f %z "$referenced_path")"
  [[ "$actual_length" == "$referenced_length" ]] || {
    echo "$referenced_name is $actual_length bytes, but the appcast declares $referenced_length." >&2
    exit 1
  }
  REFERENCED_NAMES+=("$referenced_name")
  REFERENCED_LENGTHS+=("$referenced_length")
  REFERENCED_PATHS+=("$referenced_path")
done < <(perl -0777 -ne '
  while (/<[^>]+\burl="[^"]+"[^>]*>/g) {
    $tag = $&;
    next unless $tag =~ /\blength="([0-9]+)"/;
    $length = $1;
    next unless $tag =~ /\burl="([^"]+)"/;
    print "$1\t$length\n";
  }
' "$APPCAST")

(( ${#REFERENCED_NAMES[@]} > 0 )) || {
  echo "The appcast names no update archives or deltas." >&2
  exit 1
}

request() {
  printf 'user = "%s:%s"\n' "$R2_ACCESS_KEY_ID" "$R2_SECRET_ACCESS_KEY" |
    "$CURL_BIN" --config - --silent --show-error \
      --aws-sigv4 "aws:amz:auto:s3" \
      "$@"
}

header_value() {
  local name="$1"
  local headers="$2"
  awk -v wanted="${name:l}:" '
    tolower($1) == wanted {
      sub(/^[^:]+:[[:space:]]*/, "")
      sub(/\r$/, "")
      value = $0
    }
    END { print value }
  ' "$headers"
}

s3_head() {
  local name="$1"
  local headers="$2"
  request --head --dump-header "$headers" --output /dev/null \
    --write-out '%{http_code}' "$S3_BASE/$name"
}

s3_download() {
  local name="$1"
  local destination="$2"
  request --output "$destination" --write-out '%{http_code}' "$S3_BASE/$name"
}

public_download() {
  local name="$1"
  local destination="$2"
  local headers="$3"
  "$CURL_BIN" --silent --show-error --dump-header "$headers" \
    --output "$destination" --write-out '%{http_code}' "$PUBLIC_BASE/$name"
}

verify_copy() {
  local name="$1"
  local local_path="$2"
  local expected_cache="$3"
  local source="$4"
  local attempts="$5"
  local attempt=1 downloaded headers http_code served_cache head_code

  while (( attempt <= attempts )); do
    downloaded="$(mktemp)"
    headers="$(mktemp)"
    if [[ "$source" == s3 ]]; then
      http_code="$(s3_download "$name" "$downloaded")"
      served_cache=""
      if [[ "$http_code" == 200 ]]; then
        head_code="$(s3_head "$name" "$headers")"
        [[ "$head_code" == 200 ]] || http_code="$head_code"
        served_cache="$(header_value cache-control "$headers")"
      fi
    else
      http_code="$(public_download "$name" "$downloaded" "$headers")"
      served_cache="$(header_value cache-control "$headers")"
    fi

    if [[ "$http_code" == 200 ]] && cmp -s "$local_path" "$downloaded" &&
       [[ "$served_cache" == "$expected_cache" ]]; then
      return 0
    fi
    (( attempt == attempts )) && break
    "$SLEEP_BIN" 2
    (( attempt += 1 ))
  done

  echo "$source verification failed for $name." >&2
  [[ "$http_code" == 200 ]] || echo "  HTTP status: $http_code" >&2
  [[ "$served_cache" == "$expected_cache" ]] || {
    echo "  Cache-Control: ${served_cache:-missing}" >&2
    echo "  Expected: $expected_cache" >&2
  }
  cmp -s "$local_path" "$downloaded" || echo "  Served content differs from the packaged file." >&2
  return 1
}

typeset -a ARCHIVE_ACTIONS
echo "Trickpad $VERSION publishing preview"
echo "Feed: $PUBLIC_BASE/appcast.xml"
echo "R2: $BUCKET/$OBJECT_PREFIX/"
echo
echo "Archives and deltas, uploaded before the appcast:"
for index in {1..${#REFERENCED_NAMES[@]}}; do
  name="$REFERENCED_NAMES[$index]"
  file_path="$REFERENCED_PATHS[$index]"
  length="$REFERENCED_LENGTHS[$index]"
  headers="$(mktemp)"
  http_code="$(s3_head "$name" "$headers")"
  case "$http_code" in
    404)
      archive_action=upload
      ARCHIVE_ACTIONS+=(upload)
      printf '  upload  %s  %s bytes  %s\n' "$name" "$length" "$ARCHIVE_CACHE_CONTROL"
      ;;
    200)
      archive_action=skip
      remote_copy="$(mktemp)"
      get_code="$(s3_download "$name" "$remote_copy")"
      [[ "$get_code" == 200 ]] || {
        echo "R2 returned HTTP $get_code while reading $name." >&2
        exit 1
      }
      if ! cmp -s "$file_path" "$remote_copy"; then
        echo "R2 already contains different bytes at immutable archive $name." >&2
        echo "Replacing it requires a separate cache-purge recovery operation." >&2
        exit 1
      fi
      remote_cache="$(header_value cache-control "$headers")"
      [[ "$remote_cache" == "$ARCHIVE_CACHE_CONTROL" ]] || {
        echo "R2 already contains $name with the wrong Cache-Control metadata." >&2
        echo "Repair it through the separate cache-purge recovery operation." >&2
        exit 1
      }
      ARCHIVE_ACTIONS+=(skip)
      printf '  keep    %s  %s bytes  identical and immutable\n' "$name" "$length"
      ;;
    *)
      echo "R2 returned HTTP $http_code while checking $name." >&2
      exit 1
      ;;
  esac

  public_copy="$(mktemp)"
  public_file_headers="$(mktemp)"
  public_file_code="$(public_download "$name" "$public_copy" "$public_file_headers")"
  case "$public_file_code" in
    200)
      cmp -s "$file_path" "$public_copy" || {
        echo "The public URL already serves different bytes for immutable archive $name." >&2
        echo "Replacing it requires a separate cache-purge recovery operation." >&2
        exit 1
      }
      public_cache="$(header_value cache-control "$public_file_headers")"
      [[ "$public_cache" == "$ARCHIVE_CACHE_CONTROL" ]] || {
        echo "The public URL serves $name with the wrong Cache-Control header." >&2
        echo "Repair it through the separate cache-purge recovery operation." >&2
        exit 1
      }
      echo "          public URL serves identical bytes"
      ;;
    404)
      [[ "$archive_action" == upload ]] || {
        echo "R2 contains $name, but its public URL returns 404." >&2
        exit 1
      }
      echo "          public URL is not occupied"
      ;;
    *)
      echo "The public URL returned HTTP $public_file_code while checking $name." >&2
      exit 1
      ;;
  esac
done

appcast_headers="$(mktemp)"
appcast_code="$(s3_head appcast.xml "$appcast_headers")"
APPCAST_ACTION=upload
if [[ "$appcast_code" == 200 ]]; then
  remote_appcast="$(mktemp)"
  get_code="$(s3_download appcast.xml "$remote_appcast")"
  [[ "$get_code" == 200 ]] || {
    echo "R2 returned HTTP $get_code while reading appcast.xml." >&2
    exit 1
  }
  if cmp -s "$APPCAST" "$remote_appcast" &&
     [[ "$(header_value cache-control "$appcast_headers")" == "$APPCAST_CACHE_CONTROL" ]]; then
    APPCAST_ACTION=skip
  fi
elif [[ "$appcast_code" != 404 ]]; then
  echo "R2 returned HTTP $appcast_code while checking appcast.xml." >&2
  exit 1
fi

appcast_length="$(stat -f %z "$APPCAST")"
if [[ "$APPCAST_ACTION" == skip ]]; then
  printf '  keep    appcast.xml  %s bytes  identical\n' "$appcast_length"
else
  printf '  upload  appcast.xml  %s bytes  %s  LAST\n' "$appcast_length" "$APPCAST_CACHE_CONTROL"
fi

public_appcast="$(mktemp)"
public_headers="$(mktemp)"
public_code="$(public_download appcast.xml "$public_appcast" "$public_headers")"
if [[ "$public_code" == 200 ]]; then
  current_versions="$(perl -0777 -ne 'while (m{<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>}g) { push @v, $1 } END { print join(", ", @v) }' "$public_appcast")"
  echo "Public feed versions: ${current_versions:-unreadable}"
else
  echo "Public feed: HTTP $public_code"
fi
echo "Proposed first version: $VERSION"

if (( ! PUBLISH )); then
  echo
  echo "Dry run: no files uploaded."
  exit 0
fi

if (( ! ASSUME_YES )); then
  echo
  read "confirmation?Type $VERSION to publish this update: "
  [[ "$confirmation" == "$VERSION" ]] || {
    echo "Publication canceled."
    exit 0
  }
fi

upload_file() {
  local name="$1"
  local file_path="$2"
  local cache_control="$3"
  local content_type="$4"
  local http_code

  http_code="$(request --request PUT --upload-file "$file_path" \
    --header "Content-Type: $content_type" \
    --header "Cache-Control: $cache_control" \
    --output /dev/null --write-out '%{http_code}' "$S3_BASE/$name")"
  [[ "$http_code" == 200 || "$http_code" == 201 ]] || {
    echo "R2 returned HTTP $http_code while uploading $name." >&2
    exit 1
  }
}

for index in {1..${#REFERENCED_NAMES[@]}}; do
  name="$REFERENCED_NAMES[$index]"
  file_path="$REFERENCED_PATHS[$index]"
  if [[ "$ARCHIVE_ACTIONS[$index]" == upload ]]; then
    echo "Uploading $name"
    upload_file "$name" "$file_path" "$ARCHIVE_CACHE_CONTROL" application/octet-stream
  fi
  verify_copy "$name" "$file_path" "$ARCHIVE_CACHE_CONTROL" s3 1
  verify_copy "$name" "$file_path" "$ARCHIVE_CACHE_CONTROL" public 16
  echo "Verified $PUBLIC_BASE/$name"
done

if [[ "$APPCAST_ACTION" == upload ]]; then
  echo "Uploading appcast.xml last"
  upload_file appcast.xml "$APPCAST" "$APPCAST_CACHE_CONTROL" application/xml
fi
verify_copy appcast.xml "$APPCAST" "$APPCAST_CACHE_CONTROL" s3 1
verify_copy appcast.xml "$APPCAST" "$APPCAST_CACHE_CONTROL" public 46

for index in {1..${#REFERENCED_NAMES[@]}}; do
  verify_copy "$REFERENCED_NAMES[$index]" "$REFERENCED_PATHS[$index]" \
    "$ARCHIVE_CACHE_CONTROL" public 1
done

echo "Published and publicly verified Trickpad $VERSION."
