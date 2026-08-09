#!/usr/bin/env bash
# Regenerates Sources/Folium/Vendor/HighlightJS/ (gitignored) from the pinned
# version in vendor/package.json + vendor/package-lock.json.
#
# Run via `make vendor` — a prerequisite of `build`/`vet`/`test-unit`/
# `test-integration`/`coverage`, so a plain `make check` always has the
# right assets in place. A bare `swift build`/`swift test` (bypassing make)
# needs this to have been run at least once first.
#
# These files aren't committed to git so that keeping highlight.js current
# is a normal Dependabot version-bump PR against vendor/package.json (a real
# npm manifest) rather than a multi-thousand-line diff of vendored source.
# See vendor/package.json's "//" key for why highlight.js is listed there
# even though we only consume files from @highlightjs/cdn-assets.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT/vendor"
DEST="$ROOT/Sources/Folium/Vendor/HighlightJS"
MARKER="$DEST/.vendored-version"

PINNED_VERSION=$(python3 -c "
import json
print(json.load(open('$VENDOR_DIR/package.json'))['dependencies']['@highlightjs/cdn-assets'])
")

if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$PINNED_VERSION" ]; then
  echo "==> Vendored highlight.js $PINNED_VERSION is already up to date, skipping npm."
  exit 0
fi

command -v npm >/dev/null 2>&1 || {
  echo "npm not found. Install Node.js (e.g. brew install node) to vendor highlight.js."
  exit 1
}

echo "==> npm ci in $VENDOR_DIR (pinned highlight.js $PINNED_VERSION)"
(cd "$VENDOR_DIR" && npm ci --no-audit --no-fund)

SRC="$VENDOR_DIR/node_modules/@highlightjs/cdn-assets"
INSTALLED_VERSION=$(python3 -c "import json; print(json.load(open('$SRC/package.json'))['version'])")
if [ "$INSTALLED_VERSION" != "$PINNED_VERSION" ]; then
  echo "FAIL: installed @highlightjs/cdn-assets $INSTALLED_VERSION does not match" \
       "vendor/package.json's pinned $PINNED_VERSION."
  exit 1
fi

echo "==> Copying vendored assets to $DEST"
rm -rf "$DEST"
mkdir -p "$DEST/styles"
cp "$SRC/highlight.min.js" "$DEST/highlight.min.js"
cp "$SRC/styles/github.min.css" "$DEST/styles/github.min.css"
cp "$SRC/styles/github-dark.min.css" "$DEST/styles/github-dark.min.css"
cp "$SRC/LICENSE" "$DEST/LICENSE"
echo "$PINNED_VERSION" > "$MARKER"

echo "==> Vendored highlight.js $PINNED_VERSION into $DEST"
