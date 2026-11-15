#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly OUTPUT="$ROOT/docs"
readonly TEMPLATE_DIR="$ROOT/templates"
readonly LICENSE_DIR="$ROOT/LICENSES"
readonly CHECKSUMS="$ROOT/scripts/upstream-sha256sums.txt"
readonly EXCLUDED_PATHS="$ROOT/scripts/excluded-paths.txt"
readonly LOCK_DIR="$ROOT/._mirror-lock"
readonly UPSTREAM_ORIGIN="https://www.cl.cam.ac.uk"
readonly UPSTREAM_DIRECTORY="/~mgk25"
readonly UPSTREAM_PAGE="$UPSTREAM_ORIGIN$UPSTREAM_DIRECTORY/ucs-fonts.html"
readonly DOWNLOAD_DIRECTORY="$UPSTREAM_DIRECTORY/download"
readonly EXAMPLES_DIRECTORY="$UPSTREAM_DIRECTORY/ucs/examples"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

status() {
  printf '[mirror] %s\n' "$*"
}

sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    fail "neither shasum nor sha256sum is available"
  fi
}

for required in awk cat cp curl date dirname find grep mkdir mktemp mv rm rmdir sed sort tr wc; do
  command -v "$required" >/dev/null 2>&1 || fail "$required is required"
done

[[ -f "$TEMPLATE_DIR/index.md" ]] || fail "missing template: index.md"
[[ -d "$LICENSE_DIR" ]] || fail "missing license directory: $LICENSE_DIR"
[[ -f "$EXCLUDED_PATHS" ]] || fail "missing exclusion list: $EXCLUDED_PATHS"
[[ "$ROOT" != "/" && "$OUTPUT" == "$ROOT/docs" ]] || fail "unsafe output directory"

STAGING="$(mktemp -d "$ROOT/.ucs-fonts-mirror.XXXXXX")"
SOURCE_HTML="$STAGING/upstream.html"
MIRROR_ROOT="$STAGING/site"
CANDIDATES="$STAGING/candidates.tsv"
DISCOVERED="$STAGING/discovered.tsv"
DIRECTORIES="$STAGING/directories.txt"
CHECKSUMS_TMP="$STAGING/SHA256SUMS"
PUBLISH_STARTED=0
PUBLISH_COMPLETE=0
HAD_OUTPUT=0
HAD_CHECKSUMS=0
LOCK_HELD=0

cleanup() {
  local exit_status=$?
  local rollback_failed=0

  trap - EXIT
  if ((PUBLISH_STARTED && !PUBLISH_COMPLETE)); then
    status "Publication failed; restoring the previous site and checksum manifest." >&2 || true
    if [[ -e "$STAGING/previous-docs" || -L "$STAGING/previous-docs" ]]; then
      if ! rm -rf -- "$OUTPUT" || ! mv -- "$STAGING/previous-docs" "$OUTPUT"; then
        rollback_failed=1
      fi
    elif (( !HAD_OUTPUT )); then
      rm -rf -- "$OUTPUT" || rollback_failed=1
    fi

    if ((HAD_CHECKSUMS)); then
      mv -f -- "$STAGING/previous-checksums" "$CHECKSUMS" || rollback_failed=1
    else
      rm -f -- "$CHECKSUMS" || rollback_failed=1
    fi
  fi

  if ((rollback_failed)); then
    printf 'error: rollback incomplete; recovery files retained at %s; lock retained at %s\n' \
      "$STAGING" "$LOCK_DIR" >&2
    exit 1
  fi
  rm -rf -- "$STAGING"
  if ((LOCK_HELD)); then
    rmdir -- "$LOCK_DIR"
  fi
  exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

status "Acquiring exclusive mirror lock."
mkdir "$LOCK_DIR" 2>/dev/null ||
  fail "another mirror run is active or a stale lock remains: $LOCK_DIR"
LOCK_HELD=1

normalize_path() {
  local path="$1"
  local component
  local output=""

  while [[ -n "$path" ]]; do
    component="${path%%/*}"
    if [[ "$path" == */* ]]; then path="${path#*/}"; else path=""; fi
    case "$component" in
      ""|.) ;;
      ..)
        [[ -n "$output" ]] || fail "upstream reference escapes its root: $1"
        output="${output%/*}"
        ;;
      *) output+="/$component" ;;
    esac
  done
  printf '%s\n' "${output:-/}"
}

is_safe_path() {
  local path="$1"
  case "$path" in
    ""|*[!a-zA-Z0-9._/+@~-]*) return 1 ;;
    *) return 0 ;;
  esac
}

record_reference() {
  local kind="$1"
  local reference="$2"
  local base="$3"
  local path
  local destination
  local directory=0

  [[ "$kind" == "href" ]] || return 0
  reference="$(printf '%s' "$reference" | sed 's/&amp;/\&/g')"
  case "$reference" in ""|\#*|\?*) return 0 ;; esac
  reference="${reference%%#*}"
  reference="${reference%%\?*}"
  case "$reference" in
    "$UPSTREAM_ORIGIN"/*) path="${reference#"$UPSTREAM_ORIGIN"}" ;;
    http://www.cl.cam.ac.uk/*) path="${reference#http://www.cl.cam.ac.uk}" ;;
    //www.cl.cam.ac.uk/*) path="${reference#//www.cl.cam.ac.uk}" ;;
    *://*|//*|*:* ) return 0 ;;
    /*) path="$reference" ;;
    *) path="$base/$reference" ;;
  esac
  [[ "$path" != */ ]] || directory=1
  path="$(normalize_path "$path")"

  case "$path" in
    "$EXAMPLES_DIRECTORY"|"$EXAMPLES_DIRECTORY"/*)
      if ((directory)) || [[ "$path" == "$EXAMPLES_DIRECTORY" ]]; then
        is_safe_path "$path" || fail "unsafe examples directory: $path"
        if ! grep -Fxq "$path/" "$DIRECTORIES"; then
          printf '%s/\n' "$path" >> "$DIRECTORIES"
        fi
        return 0
      fi
      destination="examples/${path#"$EXAMPLES_DIRECTORY/"}"
      ;;
    "$DOWNLOAD_DIRECTORY"/*)
      (( !directory )) || return 0
      destination="downloads/${path#"$DOWNLOAD_DIRECTORY/"}"
      ;;
    *) return 0 ;;
  esac

  case "$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')" in
    *.apng|*.avif|*.gif|*.ico|*.jpeg|*.jpg|*.png|*.svg|*.webp) return 0 ;;
  esac
  is_safe_path "$destination" || fail "unsafe destination: $destination"
  if grep -Fxq "$destination" "$EXCLUDED_PATHS"; then
    status "Leaving excluded file upstream: $destination"
    return 0
  fi
  [[ ! -e "$TEMPLATE_DIR/$destination" && ! -L "$TEMPLATE_DIR/$destination" ]] ||
    fail "upstream asset conflicts with a maintained template: $destination"
  printf '%s%s\t%s\n' "$UPSTREAM_ORIGIN" "$path" "$destination" >> "$CANDIDATES"
}

collect_references() {
  local source="$1"
  local base="$2"
  local kind
  local reference

  awk '
    BEGIN { RS = "<"; single_quote = sprintf("%c", 39) }
    /^[[:alpha:]][[:alnum:]:-]*[[:space:]>\/]/ {
      tag = $0
      sub(/^[^[:space:]>]+/, "", tag)
      while (length(tag)) {
        sub(/^[[:space:]]+/, "", tag)
        if (tag ~ /^[>\/]/) break
        if (!match(tag, /^[^[:space:]=\/>]+/)) break
        name = tolower(substr(tag, 1, RLENGTH))
        tag = substr(tag, RLENGTH + 1)
        sub(/^[[:space:]]+/, "", tag)
        if (substr(tag, 1, 1) != "=") continue
        tag = substr(tag, 2)
        sub(/^[[:space:]]+/, "", tag)
        quote = substr(tag, 1, 1)
        if (quote == "\"" || quote == single_quote) {
          tag = substr(tag, 2)
          end = index(tag, quote)
          if (!end) break
          value = substr(tag, 1, end - 1)
          tag = substr(tag, end + 1)
        } else {
          if (!match(tag, /^[^[:space:]>]+/)) break
          value = substr(tag, 1, RLENGTH)
          tag = substr(tag, RLENGTH + 1)
        }
        if (name == "href" || name == "src") {
          gsub(/[[:space:]]/, " ", value)
          print name "\t" value
        }
      }
    }
  ' "$source" > "$STAGING/attributes.tsv"

  while IFS=$'\t' read -r kind reference; do
    record_reference "$kind" "$reference" "$base"
  done < "$STAGING/attributes.tsv"
}

fetch() {
  curl --fail --silent --show-error --location --retry 2 --output "$2" "$1"
  [[ -s "$2" ]] || fail "downloaded an empty file: $1"
}

write_checksum_file() {
  local file
  local digest

  {
    printf '# Mirrored at: %s\n' "$MIRRORED_AT"
    printf '# Source: %s\n' "$UPSTREAM_PAGE"
    printf '# Files: %s\n' "$asset_count"
    while IFS= read -r file; do
      if ! digest="$(sha256 "$file")"; then
        fail "could not calculate SHA-256 for ${file#"$MIRROR_ROOT/"}"
      fi
      [[ ${#digest} == 64 && "$digest" != *[!0-9a-fA-F]* ]] ||
        fail "invalid SHA-256 for ${file#"$MIRROR_ROOT/"}"
      printf '%s  %s\n' "$digest" "${file#"$MIRROR_ROOT/"}"
    done < <(find "$MIRROR_ROOT" -type f -print | LC_ALL=C sort)
  } > "$CHECKSUMS_TMP"
}

validate_page_links() {
  local page
  local target

  for page in "$MIRROR_ROOT"/*.md; do
    while IFS= read -r target; do
      target="${target#\]\(}"
      target="${target%%#*}"
      [[ -f "$MIRROR_ROOT/$target" ]] ||
        fail "missing mirrored target in ${page##*/}: $target"
    done < <(grep -Eo '\]\((assets|downloads|examples)/[^)]*' "$page" || true)
  done
}

publish() {
  if [[ -e "$OUTPUT" || -L "$OUTPUT" ]]; then HAD_OUTPUT=1; fi
  if [[ -e "$CHECKSUMS" ]]; then
    cp -p "$CHECKSUMS" "$STAGING/previous-checksums"
    HAD_CHECKSUMS=1
  fi

  PUBLISH_STARTED=1
  if ((HAD_OUTPUT)); then mv -- "$OUTPUT" "$STAGING/previous-docs"; fi
  mv -- "$MIRROR_ROOT" "$OUTPUT"
  mv -f -- "$CHECKSUMS_TMP" "$CHECKSUMS"
  PUBLISH_COMPLETE=1
}

mkdir -p "$MIRROR_ROOT"
: > "$CANDIDATES"
printf '%s/\n' "$EXAMPLES_DIRECTORY" > "$DIRECTORIES"
status "Fetching upstream font page."
fetch "$UPSTREAM_PAGE" "$SOURCE_HTML"
collect_references "$SOURCE_HTML" "$UPSTREAM_DIRECTORY"

while IFS= read -r directory; do
  status "Discovering examples: $directory"
  fetch "$UPSTREAM_ORIGIN$directory" "$STAGING/directory.html"
  collect_references "$STAGING/directory.html" "${directory%/}"
done < "$DIRECTORIES"

LC_ALL=C sort -u "$CANDIDATES" > "$DISCOVERED"
[[ -s "$DISCOVERED" ]] || fail "no upstream assets were discovered"
if ! awk -F '\t' '
  {
    if ($2 in urls && urls[$2] != $1) {
      print "conflicting upstream URLs for " $2
      exit 1
    }
    urls[$2] = $1
  }
' "$DISCOVERED"; then
  fail "multiple upstream URLs map to the same destination"
fi

asset_count="$(wc -l < "$DISCOVERED" | tr -d '[:space:]')"
status "Discovered $asset_count files."
current_asset=0
while IFS=$'\t' read -r url destination; do
  current_asset=$((current_asset + 1))
  status "Downloading $current_asset/$asset_count: $destination"
  mkdir -p "$(dirname "$MIRROR_ROOT/$destination")"
  fetch "$url" "$MIRROR_ROOT/$destination"
done < "$DISCOVERED"

mirrored_count="$(find "$MIRROR_ROOT" -type f | wc -l | tr -d '[:space:]')"
[[ "$mirrored_count" == "$asset_count" ]] ||
  fail "download count mismatch: expected $asset_count, received $mirrored_count"

MIRRORED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
status "Writing timestamped SHA-256 manifests and provenance."
write_checksum_file
cp "$CHECKSUMS_TMP" "$MIRROR_ROOT/SHA256SUMS"
{
  printf '# Source URL\tMirror path\n'
  cat "$DISCOVERED"
} > "$MIRROR_ROOT/SOURCES.tsv"
mkdir -p "$MIRROR_ROOT/_data"
{
  printf 'mirrored_at: "%s"\n' "$MIRRORED_AT"
  printf 'source_url: "%s"\n' "$UPSTREAM_PAGE"
  printf 'examples_url: "%s%s/"\n' "$UPSTREAM_ORIGIN" "$EXAMPLES_DIRECTORY"
  printf 'asset_count: %s\n' "$asset_count"
} > "$MIRROR_ROOT/_data/mirror.yml"

status "Assembling and validating GitHub Pages files."
mkdir -p "$MIRROR_ROOT/assets"
cp -R "$LICENSE_DIR" "$MIRROR_ROOT/"
cp -R "$TEMPLATE_DIR/assets/." "$MIRROR_ROOT/assets/"
cp -R "$TEMPLATE_DIR/_layouts" "$MIRROR_ROOT/"
cp "$TEMPLATE_DIR/_config.yml" "$MIRROR_ROOT/_config.yml"
for page in "$TEMPLATE_DIR"/*.md; do
  cp "$page" "$MIRROR_ROOT/"
done
validate_page_links

status "Publishing the site and checksum manifest."
publish
status "Complete: $OUTPUT contains $asset_count upstream files mirrored at $MIRRORED_AT."
