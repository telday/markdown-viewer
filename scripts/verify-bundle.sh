#!/usr/bin/env bash
# Answer "is this bundle shippable?" against an assembled .app. Run via
# `make verify-bundle`; see the README for what the gate covers and why it is
# not part of `make check`.
#
# Every assertion is about the observable shape of the finished artifact — the
# paths, the plist, the signature, the architectures — never about how the
# Makefile produced it. Signing-specific assertions (issue #31) belong here too.
set -euo pipefail

APP="${1:-}"
EXPECTED_VERSION="${2:-}"

# What the shipped app must claim, stated here rather than read from the
# Makefile: an expectation that follows whatever the build already produces
# asserts nothing.
APP_NAME="Folium"
BUNDLE_ID="com.telday.Folium"
# The Uniform Type Identifier (UTI) MarkdownDocument.swift imports as
# UTType.markdown. If the plist ever names a different one, the app claims a
# document type Launch Services never routes to it.
DOCUMENT_TYPE="net.daringfireball.markdown"
REQUIRED_ARCHS=(arm64 x86_64)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIRST_PARTY_SRC="$ROOT/Sources/$APP_NAME/Resources"

fail() {
  echo
  echo "FAIL: $*" >&2
  exit 1
}

ok() { printf '      ok  %s\n' "$*"; }

skip() { printf '      --  %s\n' "$*"; }

[ -n "$APP" ] || {
  echo "usage: $(basename "$0") <path-to-.app> [expected-version]" >&2
  exit 2
}

CONTENTS="$APP/Contents"
RESOURCES="$CONTENTS/Resources"
PLIST="$CONTENTS/Info.plist"
BINARY="$CONTENTS/MacOS/$APP_NAME"

echo "==> Verifying $APP"

# ---------------------------------------------------------------------------
# The bundle is there, and it is not left over from an older checkout
# ---------------------------------------------------------------------------

[ -d "$APP" ] || fail "no bundle at $APP — run \`make bundle\` first."
[ -f "$BINARY" ] || fail "no executable at $BINARY — the bundle is incomplete; re-run \`make bundle\`."

# Two checks compare the bundle against this checkout's source tree. That
# comparison only says something about a bundle this checkout built; one from
# anywhere else — /Applications, a downloaded release — is verified on its own
# contents alone.
case "$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")" in
  "$ROOT"/*) FROM_THIS_CHECKOUT=true ;;
  *) FROM_THIS_CHECKOUT=false ;;
esac

# A bundle older than the sources it was built from would be verified happily
# and tell you nothing about the code you just changed. Compare against the
# executable rather than the bundle directory: `cp` stamps the copy with the
# time it ran, and the signature rewrites it again afterwards.
if $FROM_THIS_CHECKOUT; then
  NEWER_SOURCE=$(find "$ROOT/Sources" "$ROOT/packaging" "$ROOT/Makefile" \
    -newer "$BINARY" -not -path '*/.*' -print -quit)
  [ -z "$NEWER_SOURCE" ] || fail "the bundle is older than $NEWER_SOURCE — re-run \`make bundle\`."
  ok "bundle is newer than Sources/, packaging/ and the Makefile"
else
  skip "bundle was built outside this checkout — not comparing it against Sources/"
fi

# ---------------------------------------------------------------------------
# Nothing at the bundle root but Contents/
# ---------------------------------------------------------------------------
# The regression this gate exists to prevent. codesign refuses to seal files
# sitting at the bundle root, so anything that lands there is unsigned baggage
# that a notarized build would reject — and SwiftPM's generated resource
# bundle resolves to exactly that spot (see ADR 0003).

echo
echo "==> Bundle root"
ROOT_ENTRIES=$(ls -A "$APP")
[ "$ROOT_ENTRIES" = "Contents" ] || fail \
  "bundle root holds more than Contents/ — codesign cannot seal files there:
$(echo "$ROOT_ENTRIES" | sed 's/^/        /')"
ok "holds Contents/ and nothing else"

# ---------------------------------------------------------------------------
# The files the app reads at runtime
# ---------------------------------------------------------------------------

echo
echo "==> Resources"
for rel in \
  "Info.plist" \
  "PkgInfo" \
  "MacOS/$APP_NAME" \
  "Resources/$APP_NAME.icns" \
  "Resources/Resources/page.html"
do
  [ -e "$CONTENTS/$rel" ] || fail "missing Contents/$rel."
  ok "Contents/$rel"
done

# Derived from the source tree rather than listed here, so an asset added under
# Sources/Folium/Resources/ that packaging forgets to copy fails this gate on
# the pull request that adds it.
if $FROM_THIS_CHECKOUT; then
  FIRST_PARTY_COUNT=0
  while IFS= read -r rel; do
    [ -f "$RESOURCES/Resources/$rel" ] || fail \
      "first-party asset Contents/Resources/Resources/$rel is missing (it exists at Sources/$APP_NAME/Resources/$rel)."
    FIRST_PARTY_COUNT=$((FIRST_PARTY_COUNT + 1))
  done < <(cd "$FIRST_PARTY_SRC" && find . -type f -not -name '.DS_Store' | sed 's|^\./||')
  [ "$FIRST_PARTY_COUNT" -gt 0 ] || fail \
    "no first-party assets found under $FIRST_PARTY_SRC — the source tree is incomplete, so this gate would pass vacuously."
  ok "all $FIRST_PARTY_COUNT first-party assets from Sources/$APP_NAME/Resources/ are present"
else
  skip "not checking the bundle's first-party assets against Sources/$APP_NAME/Resources/"
fi

# The vendored assets are gitignored and regenerated by `make vendor`, so a
# fresh clone that skipped it produces a bundle that renders code blocks
# unstyled and unhighlighted. Named explicitly, not derived: the source
# directory may not exist, and an empty expectation set proves nothing.
for rel in \
  "HighlightJS/highlight.min.js" \
  "HighlightJS/styles/github.min.css" \
  "HighlightJS/styles/github-dark.min.css" \
  "HighlightJS/LICENSE"
do
  [ -f "$RESOURCES/$rel" ] || fail \
    "vendored asset Contents/Resources/$rel is missing — run \`make vendor && make bundle\`."
  ok "Contents/Resources/$rel"
done

# ---------------------------------------------------------------------------
# What the app claims about itself
# ---------------------------------------------------------------------------

echo
echo "==> Info.plist"

plist_value() {
  plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null || fail "Info.plist has no $1."
}

expect_plist() {
  local key="$1" want="$2" got
  got=$(plist_value "$key")
  [ "$got" = "$want" ] || fail "Info.plist $key is \"$got\", expected \"$want\"."
  ok "$key = $got"
}

expect_plist CFBundleIdentifier "$BUNDLE_ID"
expect_plist CFBundleExecutable "$APP_NAME"

# The document type is nested: the first CFBundleDocumentTypes entry declares
# the UTIs Launch Services binds to this app.
DECLARED_TYPES=$(plutil -extract CFBundleDocumentTypes.0.LSItemContentTypes json -o - "$PLIST" 2>/dev/null) \
  || fail "Info.plist has no CFBundleDocumentTypes.0.LSItemContentTypes — the app would open no documents."
case "$DECLARED_TYPES" in
  *"\"$DOCUMENT_TYPE\""*) ok "CFBundleDocumentTypes declares $DOCUMENT_TYPE" ;;
  *) fail "CFBundleDocumentTypes declares $DECLARED_TYPES, which does not include $DOCUMENT_TYPE (the UTI MarkdownDocument.swift reads)." ;;
esac

VERSION=$(plist_value CFBundleShortVersionString)
if [ -n "$EXPECTED_VERSION" ]; then
  [ "$VERSION" = "$EXPECTED_VERSION" ] || fail \
    "CFBundleShortVersionString is \"$VERSION\", expected \"$EXPECTED_VERSION\" — the bundle predates the version you asked for."
  ok "CFBundleShortVersionString = $VERSION"
else
  skip "CFBundleShortVersionString is $VERSION (no expected version given)"
fi

# ---------------------------------------------------------------------------
# The signature
# ---------------------------------------------------------------------------

echo
echo "==> Signature"
codesign --verify --strict --deep "$APP" 2>&1 | sed 's/^/      /' || fail \
  "codesign --verify --strict --deep rejected the bundle (output above)."
ok "codesign --verify --strict --deep passes"

# codesign writes its report to stderr. An ad-hoc signature has no Authority
# line — it says Signature=adhoc — which is how this gate tells a contributor's
# machine and today's CI apart from a Developer ID build.
AUTHORITY=$(codesign --display --verbose=2 "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
if [[ "$AUTHORITY" == "Developer ID Application:"* ]]; then
  ok "signed by $AUTHORITY"
  skip "hardened runtime, secure timestamp and notarization ticket: added by issue #31"
else
  skip "ad-hoc signature, no Developer ID — skipping the Developer ID assertions"
fi

# ---------------------------------------------------------------------------
# Both architectures
# ---------------------------------------------------------------------------
# A host-only build runs under Rosetta on the other Mac architecture, or not at
# all — and it is the easy mistake to make, since every development-loop build
# is deliberately single-architecture.

echo
echo "==> Architectures"
ARCHS=$(lipo -archs "$BINARY") || fail "lipo could not read $BINARY."
for arch in "${REQUIRED_ARCHS[@]}"; do
  case " $ARCHS " in
    *" $arch "*) ok "$arch" ;;
    *) fail "executable is $ARCHS — missing $arch. A universal build is \`make bundle\`, not a bare \`swift build\`." ;;
  esac
done

echo
echo "PASS: $APP is shippable."
