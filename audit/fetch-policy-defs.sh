#!/usr/bin/env bash
set -euo pipefail

# Usage: fetch-policy-defs.sh <chromium-tag-or-ref> <dest-dir>
# Sparse-clones only components/policy/resources/templates/policy_definitions.

REF="${1:?chromium tag or ref required}"
DEST="${2:?destination directory required}"
SUBDIR="components/policy/resources/templates/policy_definitions"

rm -rf -- "$DEST"
git clone --filter=blob:none --no-checkout --depth=1 \
  --branch "$REF" https://github.com/chromium/chromium.git "$DEST" >/dev/null 2>&1

cd "$DEST"
git sparse-checkout init --cone >/dev/null
git sparse-checkout set "$SUBDIR" >/dev/null
git checkout >/dev/null 2>&1

COUNT=$(find "$SUBDIR" -name '*.yaml' | wc -l)
[[ "$COUNT" -gt 100 ]] || { echo "only $COUNT policy files found at $REF" >&2; exit 1; }
echo "$COUNT policy definitions at $REF"
