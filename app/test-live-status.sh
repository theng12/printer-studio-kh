#!/bin/bash
# Proves the status is re-read when the app is brought forward, not held from launch.
#
# Runtime: the shipped activation hook fires on becoming active and on nothing else.
# Source:  the app, its window and its menu bar are wired to it, an offscreen render
#          keeps its fixtures, and no timer was added (nothing polls while idle).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/printer-live-status.XXXXXX")"

/usr/bin/swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/PrinterStudio/LiveStatus.swift" "$ROOT/Tools/TestLiveStatus.swift" \
  -o "$OUT/check"
"$OUT/check"

APP="$ROOT/Sources/PrinterStudio/App.swift"
VIEWS="$ROOT/Sources/PrinterStudio/Views.swift"
fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q 'LiveStatus.observeActivation { \[weak self\] in self?.refresh() }' "$APP" \
  || fail "AppState does not re-read status when the app is brought forward"
echo "PASS: AppState re-reads the status on activation"

grep -q 'if !renderActionsStubbed {' "$APP" \
  || fail "the activation re-read is not skipped for an offscreen render run"
echo "PASS: an offscreen render run keeps its fixture state"

grep -q 'Text(state.statusSummary)' "$APP" && grep -q '.onAppear { state.refresh() }' "$APP" \
  || fail "the menu bar summary is shown without re-reading it first"
echo "PASS: opening the menu bar re-reads the summary"

grep -q '.onAppear { state.refresh() }' "$VIEWS" \
  || fail "showing the main window does not re-read the status"
echo "PASS: showing the main window re-reads the status"

/usr/bin/python3 -I - "$APP" <<'PY' || exit 1
import re, sys
text = open(sys.argv[1]).read()
# The only timer in the app is the opt-in job watch. It must not drive a refresh:
# the status is re-read on events, so nothing polls while the app is idle.
for match in re.finditer(r'scheduledTimer', text):
    start = match.start()
    depth, index = 0, start
    while index < len(text):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                break
        index += 1
    block = text[start:index]
    if 'refresh(' in block:
        print('FAIL: a timer drives refresh(); the status must stay event-driven', file=sys.stderr)
        raise SystemExit(1)
print('PASS: no timer drives the status refresh; nothing polls while idle')
PY
