#!/bin/bash
# Proves the packaged app serves the update hold — no window, no desktop, no printer services.
#   app/test-maintenance-hold-live.sh <path/to/Printer Studio KH.app> <version> <receipt.json>
set -euo pipefail
if [ "$#" -ne 3 ]; then
  printf 'usage: %s <app> <version> <receipt.json>\n' "$0" >&2
  exit 2
fi
ROOT="$(cd "$(dirname "$0")" && pwd)"
/usr/bin/python3 -I "$ROOT/Tools/TestHoldLive.py" "$1" --expect-version "$2" --receipt "$3"
