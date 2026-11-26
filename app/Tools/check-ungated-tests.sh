#!/bin/bash
#
# Every test script is either run by some gate config or named as not run.
# Silence is how test-dmg-retention.sh stayed red from 1.0.46 to 1.0.47.
#
#   app/Tools/check-ungated-tests.sh [gate-configs-dir] [named-list]
#
# The named list is docs/UNGATED-TESTS.txt: one script name per line, each
# carrying the reason it is out. Fails when a test is in neither place, when the
# list names something no longer in the repo, or when the list claims a test that
# a gate config does run (a stale excuse reads the same as a green test).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIGS="${1:-$HOME/Developer/_orchestra/tools/gate-configs}"
LIST="${2:-$ROOT/docs/UNGATED-TESTS.txt}"

[ -d "$CONFIGS" ] || { echo "FAIL: no gate configs at $CONFIGS" >&2; exit 1; }
[ -f "$LIST" ] || { echo "FAIL: no named list at $LIST" >&2; exit 1; }

fail=0
gated() { grep -rqs -- "$1" "$CONFIGS"/*.sh; }
named() { sed -e 's/#.*//' "$LIST" | awk 'NF{print $1}' | grep -qxF -- "$1"; }

# Every test script in the repo, by the name a gate config would name it.
while IFS= read -r path; do
  name=$(basename "$path")
  if gated "$name"; then
    if named "$name"; then
      echo "FAIL: $name is run by a gate but still named as not run — stale entry in $LIST" >&2
      fail=1
    fi
  elif ! named "$name"; then
    echo "FAIL: $name is run by no gate config and is not named in $LIST" >&2
    fail=1
  fi
done < <(find "$ROOT/app" -maxdepth 3 \( -name 'test-*.sh' -o -name 'test-*.py' \) \
           -not -path '*/Fixtures/*' | sort)

# A name in the list that no longer exists is a lie the next reader trusts.
while IFS= read -r name; do
  [ -n "$name" ] || continue
  found=$(find "$ROOT/app" -maxdepth 3 -name "$name" -not -path '*/Fixtures/*' | head -1)
  if [ -z "$found" ]; then
    echo "FAIL: $LIST names $name, which is not in the repo" >&2
    fail=1
  fi
done < <(sed -e 's/#.*//' "$LIST" | awk 'NF{print $1}')

if [ "$fail" = 0 ]; then
  echo "PASS: every test script is either run by a gate config or named as not run."
fi
exit "$fail"
