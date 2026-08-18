#!/bin/zsh
# Replaces the storefront's downloadable DMG on Polar with the packaged release,
# with a read-only preview first and API read-back verification after every write.
set -euo pipefail

ROOT="${0:A:h:h}"
CURL_BIN="${TRICKPAD_STOREFRONT_CURL:-curl}"
INFISICAL_RUNNER="$HOME/.local/bin/infisical-macos-run"
API="https://api.polar.sh"
DMG_MIME="application/x-apple-diskimage"
PUBLISH=0
ASSUME_YES=0
REQUESTED_VERSION=""
ORIGINAL_ARGUMENTS=("$@")

usage() {
  echo "Usage: $0 [--publish VERSION] [--yes]"
  echo "Without --publish, shows a read-only preview and changes nothing."
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

if [[ -z "${POLAR_ACCESS_TOKEN:-}" ]]; then
  [[ -x "$INFISICAL_RUNNER" ]] || {
    echo "Missing POLAR_ACCESS_TOKEN and Infisical runner: $INFISICAL_RUNNER" >&2
    exit 1
  }
  exec "$INFISICAL_RUNNER" \
    --project-config-dir "$ROOT" \
    --env prod \
    --path /trickpad-publish \
    -- "$0" "${ORIGINAL_ARGUMENTS[@]}"
fi

if [[ "$POLAR_ACCESS_TOKEN" == REPLACE_ME ]]; then
  echo "Replace the Polar access token placeholder in Infisical." >&2
  exit 1
fi

# The packaged DMG names its version. Old images linger in build/, so the
# preview describes the newest and a publish names its exact file.
if (( PUBLISH )); then
  DMG="$ROOT/build/Trickpad-$REQUESTED_VERSION.dmg"
  [[ -s "$DMG" ]] || {
    echo "Missing $DMG. Run scripts/package.sh before publishing." >&2
    exit 1
  }
else
  DMG_MATCHES=("$ROOT"/build/Trickpad-*.dmg(Nom))
  (( ${#DMG_MATCHES[@]} > 0 )) || {
    echo "No packaged DMG in build/. Run scripts/package.sh first." >&2
    exit 1
  }
  DMG="${DMG_MATCHES[1]}"
fi
DMG_NAME="${DMG:t}"
VERSION="${${DMG_NAME#Trickpad-}%.dmg}"
SIZE=$(stat -f %z "$DMG")
SHA256_B64=$(openssl dgst -sha256 -binary "$DMG" | base64)

api() {
  # "path" would shadow zsh's PATH-linked array and break command lookup.
  local method="$1" endpoint="$2" body="${3:-}"
  local -a args
  args=(-sS --fail-with-body -X "$method" "$API$endpoint" \
        -H "Authorization: Bearer $POLAR_ACCESS_TOKEN")
  [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" -d "$body")
  "$CURL_BIN" "${args[@]}"
}

json() { python3 -c "import json,sys; $1" ; }

# One downloadables benefit is the DMG's home. A pinned id would go stale
# silently; discovery refuses ambiguity instead.
BENEFITS_JSON=$(api GET "/v1/benefits/?type=downloadables&limit=20")
BENEFIT_COUNT=$(print -r -- "$BENEFITS_JSON" | json 'd=json.load(sys.stdin); print(len(d["items"]))')
if [[ "$BENEFIT_COUNT" != 1 ]]; then
  echo "Expected exactly one downloadables benefit on Polar, found $BENEFIT_COUNT:" >&2
  print -r -- "$BENEFITS_JSON" | json 'd=json.load(sys.stdin); [print(" ", b["id"], b.get("description","")) for b in d["items"]]' >&2
  exit 1
fi
BENEFIT_ID=$(print -r -- "$BENEFITS_JSON" | json 'd=json.load(sys.stdin); print(d["items"][0]["id"])')
BENEFIT_DESC=$(print -r -- "$BENEFITS_JSON" | json 'd=json.load(sys.stdin); print(d["items"][0].get("description",""))')
CURRENT_FILES=$(print -r -- "$BENEFITS_JSON" | json 'd=json.load(sys.stdin); print(json.dumps(d["items"][0]["properties"]["files"]))')

echo "Trickpad $VERSION storefront preview"
echo "Benefit: $BENEFIT_ID ($BENEFIT_DESC)"
echo "Current benefit files: $CURRENT_FILES"
echo "  upload  $DMG_NAME  $SIZE bytes  sha256/base64 $SHA256_B64"
echo "  then point the benefit at the new file, replacing the list above."

if (( ! PUBLISH )); then
  echo "Dry run: nothing uploaded, benefit unchanged."
  exit 0
fi

if (( ! ASSUME_YES )); then
  printf "Type the version to publish to the storefront: "
  read -r CONFIRMED
  [[ "$CONFIRMED" == "$VERSION" ]] || {
    echo "Version mismatch; nothing published." >&2
    exit 1
  }
fi

CREATE_BODY=$(python3 - "$DMG_NAME" "$DMG_MIME" "$SIZE" "$SHA256_B64" <<'PY'
import json, sys
name, mime, size, sha = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
print(json.dumps({
    "name": name,
    "mime_type": mime,
    "size": size,
    "checksum_sha256_base64": sha,
    "service": "downloadable",
    "upload": {"parts": [{"number": 1, "chunk_start": 0, "chunk_end": size,
                          "checksum_sha256_base64": sha}]},
}))
PY
)
CREATED=$(api POST "/v1/files/" "$CREATE_BODY")
FILE_ID=$(print -r -- "$CREATED" | json 'd=json.load(sys.stdin); print(d["id"])')
PART_URL=$(print -r -- "$CREATED" | json 'd=json.load(sys.stdin); print(d["upload"]["parts"][0]["url"])')
PART_HEADERS=$(print -r -- "$CREATED" | json 'd=json.load(sys.stdin); [print(f"{k}: {v}") for k,v in d["upload"]["parts"][0].get("headers",{}).items()]')

echo "Uploading $DMG_NAME as file $FILE_ID"
typeset -a header_args
header_args=()
while IFS= read -r line; do
  [[ -n "$line" ]] && header_args+=(-H "$line")
done <<< "$PART_HEADERS"
ETAG=$("$CURL_BIN" -sS --fail-with-body -X PUT --data-binary "@$DMG" "${header_args[@]}" \
        -D - -o /dev/null "$PART_URL" | perl -ne 'print $1 if m/^etag:\s*"?([^"\r\n]+)/i')
[[ -n "$ETAG" ]] || {
  echo "The storage upload returned no ETag; the file stays incomplete on Polar." >&2
  exit 1
}

COMPLETE_BODY=$(python3 - "$FILE_ID" "$ETAG" "$SHA256_B64" <<'PY'
import json, sys
print(json.dumps({"id": sys.argv[1], "path": "", "parts": [{
    "number": 1, "checksum_etag": sys.argv[2],
    "checksum_sha256_base64": sys.argv[3]}]}))
PY
)
UPLOADED=$(api POST "/v1/files/$FILE_ID/uploaded" "$COMPLETE_BODY")
IS_UPLOADED=$(print -r -- "$UPLOADED" | json 'd=json.load(sys.stdin); print(d.get("is_uploaded"))')
[[ "$IS_UPLOADED" == True ]] || {
  echo "Polar did not confirm the upload; the benefit was not changed." >&2
  exit 1
}

PATCH_BODY=$(python3 - "$FILE_ID" <<'PY'
import json, sys
print(json.dumps({"type": "downloadables",
                  "properties": {"files": [sys.argv[1]]}}))
PY
)
api PATCH "/v1/benefits/$BENEFIT_ID" "$PATCH_BODY" > /dev/null

# Read back through the API: the benefit must now name exactly the new file,
# and the file must report the uploaded size.
FINAL=$(api GET "/v1/benefits/$BENEFIT_ID")
FINAL_FILES=$(print -r -- "$FINAL" | json 'd=json.load(sys.stdin); print(json.dumps(d["properties"]["files"]))')
[[ "$FINAL_FILES" == "[\"$FILE_ID\"]" ]] || {
  echo "Benefit read-back names $FINAL_FILES, not the new file." >&2
  exit 1
}
FINAL_SIZE=$(api GET "/v1/files/?ids=$FILE_ID" | json 'd=json.load(sys.stdin); print(d["items"][0]["size"])')
[[ "$FINAL_SIZE" == "$SIZE" ]] || {
  echo "File read-back reports $FINAL_SIZE bytes, expected $SIZE." >&2
  exit 1
}

echo "Published $DMG_NAME to the storefront benefit and verified the read-back."
echo "A buyer's next download serves Trickpad $VERSION."
