#!/bin/bash
# Compiles the helper with its ceiling driver and proves, without a printer and
# without a window: a quick command answers whole, a stuck command is stopped at
# its ceiling and says so, and a large stderr cannot deadlock the reader.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# Own scratch dir under TMPDIR; a checkout never gets a _trash.
OUT="$(mktemp -d "${TMPDIR:-/tmp}/printer-helper-ceiling.XXXXXX")"

/usr/bin/swiftc -swift-version 5 -D HELPER_CEILING_TEST \
  "$ROOT/Helper/main.swift" "$ROOT/Tools/TestHelperCeiling.swift" \
  -o "$OUT/check"
PRINTER_STUDIO_CEILING_DRIVER=1 "$OUT/check"

# The termination path on its own: the helper's handlers, no services, no data.
# The source has no timer between SIGTERM and exit, so the bound measured here
# is "immediately after withdrawAll", not a ceiling the code enforces.
echo "==> SIGTERM handler in isolation"
START=$(/usr/bin/python3 -I -c 'import time; print(time.time())')
PRINTER_STUDIO_CEILING_DRIVER=1 PRINTER_STUDIO_TERM_DRIVER=1 "$OUT/check" &
PID=$!
sleep 0.3
kill -TERM "$PID"
for _ in $(seq 1 40); do kill -0 "$PID" 2>/dev/null || break; sleep 0.05; done
if kill -0 "$PID" 2>/dev/null; then
  echo "FAIL: the helper's SIGTERM handler left the process running past 2 s" >&2
  kill -KILL "$PID" 2>/dev/null || true
  exit 1
fi
wait "$PID"; RC=$?
TOOK=$(/usr/bin/python3 -I -c "import time; print(round(time.time() - $START, 2))")
[ "$RC" -eq 0 ] || { echo "FAIL: the handler exited $RC, not 0" >&2; exit 1; }
echo "PASS: the helper's SIGTERM handler exited 0 in ${TOOK}s (no timer in the path)"
