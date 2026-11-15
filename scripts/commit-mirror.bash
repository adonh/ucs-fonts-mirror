#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT

: "${DEFAULT_BRANCH:?DEFAULT_BRANCH is required}"
cd "$ROOT"

git add -- docs scripts/upstream-sha256sums.txt
diff_status=0
git diff --cached --quiet \
  --ignore-matching-lines='^(# Mirrored at: |mirrored_at: )' \
  -- docs scripts/upstream-sha256sums.txt || diff_status=$?
case "$diff_status" in
  0)
    echo "No changes beyond mirror timestamps."
    exit 0
    ;;
  1) ;;
  *) exit "$diff_status" ;;
esac

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git commit -m "Refresh upstream UCS fonts mirror"
git push origin "HEAD:refs/heads/$DEFAULT_BRANCH"
