#!/bin/bash
#
# Extracts release notes for a specific version from CHANGELOG.md.
# Matches "## <version> — <date>" (or a bare "## <version>") headings exactly.
# Outputs trimmed lines or exits non-zero if missing or empty.
#
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <version> <changelog-path>" >&2
  exit 2
fi

VERSION="$1"
CHANGELOG="$2"

if [ -z "$VERSION" ]; then
  echo "!! error: version string cannot be empty" >&2
  exit 1
fi

if [ ! -f "$CHANGELOG" ]; then
  echo "!! error: changelog missing at $CHANGELOG" >&2
  exit 1
fi

RAW_NOTES=$(awk -v ver="$VERSION" '
  $0 == "## " ver || index($0, "## " ver " — ") == 1 { found=1; next }
  found && /^## / { exit }
  found { print }
' "$CHANGELOG")

if ! printf '%s\n' "$RAW_NOTES" | grep -q '[^[:space:]]'; then
  echo "!! error: no release notes found for version $VERSION in $CHANGELOG" >&2
  exit 1
fi

printf '%s\n' "$RAW_NOTES" | awk '
  NF { found=1 }
  found { lines[i++] = $0 }
  END {
    while (i > 0 && lines[i-1] ~ /^[[:space:]]*$/) i--
    for (j = 0; j < i; j++) print lines[j]
  }
'
