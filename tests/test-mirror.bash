#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ucs-fonts-test.XXXXXX")"
REAL_CP="$(command -v cp)"
REAL_MV="$(command -v mv)"
REAL_HASH="$(command -v shasum || command -v sha256sum)"
MOCK_BIN="$TEST_ROOT/bin"

trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/curl" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
output=""
url=""
while (($#)); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --retry) shift 2 ;;
    --*) shift ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  *[[:space:]]*|*\"*|*\'*) exit 3 ;;
esac
printf '%s\n' "$url" >> "$REQUESTS"
case "$url" in
  https://www.cl.cam.ac.uk/~mgk25/ucs-fonts.html)
    "$REAL_CP" "$HTML_FIXTURE" "$output"
    ;;
  https://www.cl.cam.ac.uk/~mgk25/ucs/examples/)
    "$REAL_CP" "$EXAMPLES_FIXTURE" "$output"
    ;;
  https://www.cl.cam.ac.uk/~mgk25/ucs/examples/nested/)
    printf '<a href="../">Parent</a><a href="./new.txt">New example</a>\n' > "$output"
    ;;
  *)
    [[ "${FAIL_DOWNLOAD:-0}" != 1 ]] || exit 7
    if [[ "$url" == */UTF-8-test.txt ]]; then
      printf 'invalid UTF-8: \300\257\377\000\n' > "$output"
    else
      printf 'fixture asset: %s\n' "$url" > "$output"
    fi
    ;;
esac
BASH

cat > "$MOCK_BIN/cp" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${FAIL_COPY:-0}" == 1 && "${1:-}" == */templates/index.md ]]; then
  printf 'injected template copy failure\n' >&2
  exit 7
fi
exec "$REAL_CP" "$@"
BASH

cat > "$MOCK_BIN/mv" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
source=""
destination=""
for argument in "$@"; do source="$destination"; destination="$argument"; done
if [[ "${FAIL_PUBLISH:-0}" == 1 && "$source" == */SHA256SUMS &&
      "$destination" == */scripts/upstream-sha256sums.txt ]]; then
  printf 'injected manifest publication failure\n' >&2
  exit 7
fi
exec "$REAL_MV" "$@"
BASH

cat > "$MOCK_BIN/shasum" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
case "${HASH_MODE:-ok}" in
  failure) exit 7 ;;
  malformed) printf 'not-a-digest\n'; exit 0 ;;
esac
if [[ "$REAL_HASH" == */shasum ]]; then
  exec "$REAL_HASH" -a 256 "${@: -1}"
else
  exec "$REAL_HASH" "${@: -1}"
fi
BASH
chmod +x "$MOCK_BIN/curl" "$MOCK_BIN/cp" "$MOCK_BIN/mv" "$MOCK_BIN/shasum"
ln -s shasum "$MOCK_BIN/sha256sum"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  if [[ -f "$CASE/output.log" ]]; then cat "$CASE/output.log" >&2; fi
  exit 1
}

setup_case() {
  CASE="$TEST_ROOT/$1"
  PROJECT="$CASE/repository with spaces"
  HTML_FIXTURE="$CASE/upstream.html"
  EXAMPLES_FIXTURE="$CASE/examples.html"
  REQUESTS="$CASE/requests"
  mkdir -p "$PROJECT/scripts" "$PROJECT/templates/assets" \
    "$PROJECT/templates/_layouts" "$PROJECT/LICENSES" "$PROJECT/docs"
  "$REAL_CP" "$ROOT/scripts/mirror.bash" "$ROOT/scripts/check-mirror.bash" "$PROJECT/scripts/"
  printf 'examples/excluded.txt\n' > "$PROJECT/scripts/excluded-paths.txt"
  printf '[Sample](downloads/sample.tar.gz)\n' > "$PROJECT/templates/index.md"
  printf 'File directory\n' > "$PROJECT/templates/directory.md"
  printf 'Attribution\n' > "$PROJECT/templates/attribution.md"
  printf 'styles\n' > "$PROJECT/templates/assets/styles.css"
  printf '{{ content }}\n' > "$PROJECT/templates/_layouts/default.html"
  printf 'title: Fixture\n' > "$PROJECT/templates/_config.yml"
  printf 'fixture license\n' > "$PROJECT/LICENSES/LICENSE"
  printf 'previous site\n' > "$PROJECT/docs/previous.txt"
  printf 'previous manifest\n' > "$PROJECT/scripts/upstream-sha256sums.txt"
  "$REAL_CP" -R "$PROJECT/docs" "$CASE/previous-docs"
  "$REAL_CP" "$PROJECT/scripts/upstream-sha256sums.txt" "$CASE/previous-checksums"
  printf '<a href="download/sample.tar.gz">Font</a>\n' > "$HTML_FIXTURE"
  printf '<a href="UTF-8-test.txt">Test data</a>\n' > "$EXAMPLES_FIXTURE"
}

run_mirror() {
  env PATH="$MOCK_BIN:$PATH" REAL_CP="$REAL_CP" REAL_MV="$REAL_MV" \
    REAL_HASH="$REAL_HASH" HTML_FIXTURE="$HTML_FIXTURE" \
    EXAMPLES_FIXTURE="$EXAMPLES_FIXTURE" REQUESTS="$REQUESTS" \
    "$@" "$BASH" "$PROJECT/scripts/mirror.bash" > "$CASE/output.log" 2>&1
}

assert_preserved() {
  diff -r "$CASE/previous-docs" "$PROJECT/docs" || fail "previous site changed"
  cmp -s "$CASE/previous-checksums" "$PROJECT/scripts/upstream-sha256sums.txt" ||
    fail "previous manifest changed"
}

expect_failure() {
  local message="$1"
  shift
  if run_mirror "$@"; then fail "mirror unexpectedly succeeded"; fi
  grep -Fq "$message" "$CASE/output.log" || fail "missing error: $message"
  assert_preserved
}

setup_case discovery
cat > "$HTML_FIXTURE" <<'HTML'
<a href="/">Home</a>
<a HREF = 'download/sample.tar.gz'>Font</a>
<a
  href
  =
  "/~mgk25/download/new.tar.gz"
>New font</a>
<a href=download/new.changes>Change log</a>
<a href="https://www.cl.cam.ac.uk/~mgk25/ucs/examples">Examples without slash</a>
<a href="//www.cl.cam.ac.uk/~mgk25/download/absolute.zip">Absolute URL</a>
<a href="//other.example/~mgk25/download/external.zip">External</a>
<a href="unicode.html">Unrelated page</a>
<a href="download/decoration.png">Image</a>
<img src="screen.gif">
HTML
cat > "$EXAMPLES_FIXTURE" <<'HTML'
<a href="?C=N;O=D">Sort</a>
<a href="../">Parent</a>
<a href="./">This directory</a>
<a href="UTF-8-test.txt">Test</a>
<a href='new.txt'>New example</a>
<a href="nested/">Subdirectory</a>
<a href="excluded.txt">Excluded fixture</a>
<a href="../../../other/secret.txt">Outside the depot</a>
HTML
run_mirror || fail "discovery failed"
for path in downloads/sample.tar.gz downloads/new.tar.gz downloads/new.changes \
  downloads/absolute.zip examples/UTF-8-test.txt examples/new.txt examples/nested/new.txt; do
  [[ -f "$PROJECT/docs/$path" ]] || fail "missing discovered file: $path"
  grep -Fq "$path" "$PROJECT/docs/SOURCES.tsv" || fail "missing source mapping: $path"
done
if grep -Eq 'other\.example|unicode\.html|decoration\.png|screen\.gif|secret\.txt|excluded\.txt|\?C=' "$REQUESTS"; then
  fail "an excluded, unrelated, or decorative resource was requested"
fi
[[ "$(grep -Fxc 'https://www.cl.cam.ac.uk/~mgk25/ucs/examples/' "$REQUESTS")" == 1 ]] ||
  fail "directory aliases caused repeated crawling"
printf 'invalid UTF-8: \300\257\377\000\n' > "$CASE/expected-bytes"
cmp -s "$CASE/expected-bytes" "$PROJECT/docs/examples/UTF-8-test.txt" ||
  fail "invalid UTF-8 or NUL bytes were changed"
timestamp="$(sed -n 's/^# Mirrored at: //p' "$PROJECT/docs/SHA256SUMS")"
[[ -n "$timestamp" ]] || fail "manifest timestamp missing"
grep -Fq "mirrored_at: \"$timestamp\"" "$PROJECT/docs/_data/mirror.yml" ||
  fail "metadata timestamp differs"
[[ -f "$PROJECT/docs/directory.md" ]] || fail "directory template was not published"
"$BASH" "$PROJECT/scripts/check-mirror.bash" > "$CASE/check-output.log" 2>&1 ||
  fail "read-only verification rejected the mirror"
printf 'PASS: dynamic downloads, recursive examples, scoped discovery, exclusions, raw bytes, provenance\n'

printf 'tampered\n' >> "$PROJECT/docs/examples/UTF-8-test.txt"
if "$BASH" "$PROJECT/scripts/check-mirror.bash" > "$CASE/check-output.log" 2>&1; then
  fail "checksum checker accepted changed bytes"
fi
printf 'changed manifest\n' >> "$PROJECT/scripts/upstream-sha256sums.txt"
if "$BASH" "$PROJECT/scripts/check-mirror.bash" > "$CASE/check-output.log" 2>&1; then
  fail "checksum checker accepted mismatched manifests"
fi
printf 'PASS: checksum checking detects byte changes and mismatched manifests\n'

setup_case missing-link
printf '<a href="download/other.zip">Other font</a>\n' > "$HTML_FIXTURE"
expect_failure "missing mirrored target"
printf 'PASS: missing required links preserve the previous snapshot\n'

setup_case download-failure
expect_failure "" FAIL_DOWNLOAD=1
printf 'PASS: download failures preserve the previous snapshot\n'

setup_case hash-failure
expect_failure "could not calculate SHA-256" HASH_MODE=failure
setup_case malformed-hash
expect_failure "invalid SHA-256" HASH_MODE=malformed
printf 'PASS: failed or malformed hashes prevent publication\n'

setup_case missing-template
rm "$PROJECT/templates/index.md"
expect_failure "missing template: index.md"
setup_case copy-failure
expect_failure "injected template copy failure" FAIL_COPY=1
printf 'PASS: template failures preserve the previous snapshot\n'

setup_case collision
mkdir -p "$PROJECT/templates/examples"
printf 'maintained content\n' > "$PROJECT/templates/examples/UTF-8-test.txt"
expect_failure "upstream asset conflicts with a maintained template"
printf 'PASS: upstream files cannot overwrite maintained templates\n'

setup_case unsafe-path
printf '<a href="bad%%2fname.txt">Unsafe</a>\n' >> "$EXAMPLES_FIXTURE"
expect_failure "unsafe destination"
printf 'PASS: unsupported encoded paths are rejected before publication\n'

setup_case publication-failure
expect_failure "injected manifest publication failure" FAIL_PUBLISH=1
printf 'PASS: publication failure restores the site and manifest together\n'

setup_case first-publication-failure
rm "$PROJECT/docs/previous.txt"
rmdir "$PROJECT/docs"
rm "$PROJECT/scripts/upstream-sha256sums.txt"
if run_mirror FAIL_PUBLISH=1; then fail "first publication unexpectedly succeeded"; fi
[[ ! -e "$PROJECT/docs" && ! -e "$PROJECT/scripts/upstream-sha256sums.txt" ]] ||
  fail "failed first publication left partial output"
printf 'PASS: failed first publication leaves no partial output\n'

setup_case locked
mkdir "$PROJECT/._mirror-lock"
expect_failure "another mirror run is active"
[[ -d "$PROJECT/._mirror-lock" ]] || fail "failed lock acquisition removed another run's lock"
printf 'PASS: an existing mirror lock prevents publication without removing the lock\n'

setup_case git-preservation
(
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  "$REAL_CP" "$ROOT/.gitattributes" "$PROJECT/.gitattributes"
  git -C "$PROJECT" init --quiet
  for path in downloads/crlf.txt examples/crlf.txt; do
    mkdir -p "$(dirname "$PROJECT/docs/$path")"
    printf 'first line\r\nsecond line\r\n' > "$PROJECT/docs/$path"
    git -C "$PROJECT" -c core.autocrlf=true add -- .gitattributes "docs/$path"
    git -C "$PROJECT" show ":docs/$path" > "$CASE/staged-bytes"
    cmp -s "$PROJECT/docs/$path" "$CASE/staged-bytes" ||
      fail "Git staging changed original bytes: $path"
  done
  git -C "$PROJECT" -c core.autocrlf=true checkout-index --all --prefix="$CASE/checkout/"
  for path in downloads/crlf.txt examples/crlf.txt; do
    cmp -s "$PROJECT/docs/$path" "$CASE/checkout/docs/$path" ||
      fail "Git checkout changed original bytes: $path"
  done
)
printf 'PASS: Git staging and checkout preserve upstream CRLF bytes with newline conversion enabled\n'
