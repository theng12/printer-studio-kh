#!/bin/bash
#
# Proves that app/release-notes.sh:
# 1. Extracts non-empty notes for the current Info.plist version from CHANGELOG.md (content-agnostic).
# 2. Matches exact strings in controlled fixtures and stops before the next ## section.
# 3. Rejects lookalike version headers (e.g. 1x0x1 for 1.0.1).
# 4. Refuses nonexistent versions.
# 5. Refuses empty version sections.
# 6. Refuses missing changelog files.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXTRACTOR="$ROOT/app/release-notes.sh"
PLIST="$ROOT/app/Resources/Info.plist"
CHANGELOG="$ROOT/CHANGELOG.md"

if [ ! -x "$EXTRACTOR" ]; then
  echo "FAIL: Extractor not executable at $EXTRACTOR" >&2
  exit 1
fi

echo "==> Test 1: Content-agnostic check for current Info.plist version"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
NOTES=$("$EXTRACTOR" "$VERSION" "$CHANGELOG")
if [ -z "$(printf '%s\n' "$NOTES" | tr -d '[:space:]')" ]; then
  echo "FAIL: Extracted notes for current version $VERSION are empty" >&2
  exit 1
fi
echo "PASS: Current version $VERSION has non-empty release notes"

# Fixtures in TMPDIR; a checkout never gets a _trash.
FIXTURES_DIR=$(mktemp -d "${TMPDIR:-/tmp}/printer-release-notes.XXXXXX")

echo "==> Test 2: Controlled fixture exact match and next-version stop"
cat << 'EOF' > "$FIXTURES_DIR/changelog_controlled.md"
# Changelog

## 2.3.4 — 2026-11-02
- Alpha note
- Beta note

## 2.3.3 — 2026-11-01
- Gamma note
EOF

CONTROLLED_NOTES=$("$EXTRACTOR" "2.3.4" "$FIXTURES_DIR/changelog_controlled.md")
EXPECTED=$(printf -- "- Alpha note\n- Beta note")
if [ "$CONTROLLED_NOTES" != "$EXPECTED" ]; then
  echo "FAIL: Controlled notes mismatch" >&2
  echo "Expected:"
  echo "$EXPECTED"
  echo "Got:"
  echo "$CONTROLLED_NOTES"
  exit 1
fi
if printf '%s\n' "$CONTROLLED_NOTES" | grep -q "Gamma note"; then
  echo "FAIL: Extractor leaked notes from next ## section" >&2
  exit 1
fi
echo "PASS: Controlled notes matched exactly and stopped before next section"

echo "==> Test 3: Reject lookalike header 1x0x1 for version 1.0.1"
cat << 'EOF' > "$FIXTURES_DIR/changelog_lookalike.md"
# Changelog

## 1x0x1
- Lookalike note
EOF

if "$EXTRACTOR" "1.0.1" "$FIXTURES_DIR/changelog_lookalike.md" 2>/dev/null; then
  echo "FAIL: Extractor matched regex lookalike 1x0x1 instead of literal 1.0.1" >&2
  exit 1
fi
echo "PASS: Lookalike header 1x0x1 correctly rejected for 1.0.1"

echo "==> Test 4: Refuse nonexistent version"
if "$EXTRACTOR" "99.99.99" "$CHANGELOG" 2>/dev/null; then
  echo "FAIL: Extractor did not refuse nonexistent version 99.99.99" >&2
  exit 1
fi
echo "PASS: Nonexistent version refused"

echo "==> Test 5: Refuse empty version section"
cat << 'EOF' > "$FIXTURES_DIR/changelog_empty.md"
# Changelog

## 1.0.1

## 1.0.0
- Older note
EOF

if "$EXTRACTOR" "1.0.1" "$FIXTURES_DIR/changelog_empty.md" 2>/dev/null; then
  echo "FAIL: Extractor did not refuse empty version section" >&2
  exit 1
fi
echo "PASS: Empty version section refused"

echo "==> Test 6: Refuse missing changelog file"
if "$EXTRACTOR" "1.0.1" "$FIXTURES_DIR/nonexistent.md" 2>/dev/null; then
  echo "FAIL: Extractor did not refuse missing changelog" >&2
  exit 1
fi
echo "PASS: Missing changelog refused"

echo "==> All release notes tests passed."
