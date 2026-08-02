#!/usr/bin/env bash
# Enforce the unit-test line-coverage gate for the logic layer.
#
# Coverage is measured from the UNIT tests only (FoliumTests). UI/host-glue
# files that can't run under unit tests are excluded — the list lives here, in
# one place, and is printed on every run for visibility (see
# docs/agents/definition-of-done.md).
set -euo pipefail

THRESHOLD="${COVERAGE_THRESHOLD:-97}"

# Files excluded from the coverage requirement, with the reason each can't be
# reached by a unit test. Keep this list minimal — per the Definition of Done,
# real logic belongs in testable units, not in these glue files.
EXCLUDED_FILES=(
  "Sources/Folium/FoliumApp.swift"        # @main App/Scene — only runs when the app launches
  "Sources/Folium/MarkdownWebView.swift"  # NSViewRepresentable over WKWebView — needs a live app
  "Sources/Folium/MarkdownDocument.swift" # FileDocument conformance — only the SwiftUI doc framework constructs it
)

# Build an llvm-cov --ignore-filename-regex from the excluded list plus build/test dirs.
IGNORE_REGEX='(\.build/|/Tests/'
for f in "${EXCLUDED_FILES[@]}"; do
  IGNORE_REGEX+="|${f//./\\.}"
done
IGNORE_REGEX+=')'

echo "==> Running unit tests with coverage (FoliumTests)"
swift test --enable-code-coverage --filter FoliumTests >/dev/null

BIN=$(swift build --show-bin-path)
PROF="$BIN/codecov/default.profdata"
XCTEST="$BIN/FoliumPackageTests.xctest/Contents/MacOS/FoliumPackageTests"

echo
echo "==> Covered logic (UI/host-glue files below are excluded):"
xcrun llvm-cov report "$XCTEST" -instr-profile="$PROF" \
  --ignore-filename-regex="$IGNORE_REGEX" Sources

echo
echo "==> Excluded from the ${THRESHOLD}% coverage requirement:"
for f in "${EXCLUDED_FILES[@]}"; do
  echo "      - $f"
done

PERCENT=$(xcrun llvm-cov export "$XCTEST" -instr-profile="$PROF" --summary-only \
  --ignore-filename-regex="$IGNORE_REGEX" Sources \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['totals']['lines']['percent'])")

echo
printf '==> Logic-layer line coverage: %.2f%% (threshold: %s%%)\n' "$PERCENT" "$THRESHOLD"

python3 -c "import sys; sys.exit(0 if float('$PERCENT') >= float('$THRESHOLD') else 1)" || {
  echo "FAIL: coverage below ${THRESHOLD}%. Add unit tests, or move logic out of the excluded glue files into a testable unit."
  exit 1
}
echo "PASS"
