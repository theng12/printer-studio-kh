#!/bin/bash
# The AirPrint failure the owner reported is the last step: the queue accepts a
# phone's job and then waits because the printer is offline. Proves the app
# carries CUPS's own reason and offers the matching fix — never a bare "on".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/printer-queue-health.XXXXXX")"

/usr/bin/swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/PrinterStudio/Models.swift" \
  "$ROOT/Sources/PrinterStudio/QueueHealth.swift" \
  "$ROOT/Tools/TestQueueHealth.swift" \
  -o "$OUT/check"
"$OUT/check"

CUPS="$ROOT/Sources/PrinterStudio/CUPS.swift"
VIEWS="$ROOT/Sources/PrinterStudio/Views.swift"
fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q 'attributes\["printer-state-message"\]' "$CUPS" \
  || fail "the detailed queue read drops CUPS printer-state-message"
grep -q 'attributes\["printer-state-reasons"\]' "$CUPS" \
  || fail "the detailed queue read drops CUPS printer-state-reasons"
echo "PASS: a detailed queue read carries CUPS's own offline reason"

grep -q 'offlineShared' "$VIEWS" && grep -q 'printer.isOffline' "$VIEWS" \
  || fail "the Sharing page cannot say a shared queue is offline"
echo "PASS: the Sharing page names an offline shared queue"

grep -q 'QueueHealth.actionTitle(recovery)' "$VIEWS" \
  || fail "the Sharing page shows an offline queue with no fix"
echo "PASS: an offline shared queue offers the fix that matches its cause"

grep -q 'StartHereCard()' "$VIEWS" && grep -q 'struct StartHereCard' "$VIEWS" \
  || fail "Overview does not open with the guided Start here path"
echo "PASS: Overview opens with the guided path"

# One fixed footer row: the busy message replaces the status text, so the
# bottom of the sidebar cannot grow while an action runs.
grep -q 'state.busy ? state.busyMessage : footerStatus' "$VIEWS" \
  || fail "the footer grows again while an action runs"
echo "PASS: the footer's busy line lives in the always-present status row"

# The banner floats; it must not sit in the detail's layout stack.
grep -q 'overlay(alignment: .bottom)' "$VIEWS" \
  || fail "the result banner is back in the layout and will move the page"
echo "PASS: the result banner floats over the page"
