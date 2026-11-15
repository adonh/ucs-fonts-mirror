#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT

if ! cmp -s "$ROOT/scripts/upstream-sha256sums.txt" "$ROOT/docs/SHA256SUMS"; then
  printf 'error: the public and upstream checksum manifests differ\n' >&2
  exit 1
fi

if ! grep -Eq '^[[:xdigit:]]{64}  .+' "$ROOT/docs/SHA256SUMS"; then
  printf 'error: the checksum manifest has no asset digests\n' >&2
  exit 1
fi

cd "$ROOT/docs"
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 --check --strict SHA256SUMS
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum --check --strict SHA256SUMS
else
  printf 'error: neither shasum nor sha256sum is available\n' >&2
  exit 1
fi
