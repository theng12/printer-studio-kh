#!/bin/bash
# The owner's defect: the sidebar jumps when it is clicked and several buttons
# do the same. This drives the real MainWindow offscreen — every sidebar row is
# selected through the list's own selection API, a busy action runs, and a
# result banner appears — and fails if any measured part moves, at the app's
# minimum window (860x580) and at its usual one (1024x720).
#
# A real mouse click cannot be delivered to a window whose app is not active,
# and activating would take the owner's desktop; the list's selection API is
# what a click makes the control do.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/printer-sidebar.XXXXXX")"

bash "$ROOT/render-pages.sh" sidebar-check "$OUT" > "$OUT/sidebar-check.log" 2>&1
rc=$?
tail -6 "$OUT/sidebar-check.log"
if [ "$rc" -ne 0 ]; then
  echo "FAIL: the sidebar moved (render-pages exit $rc); evidence in $OUT"
  exit 1
fi
/usr/bin/grep -q "SIDEBAR_CHECK PASS" "$OUT/sidebar-check.log" \
  || { echo "FAIL: the sidebar check printed no verdict"; exit 1; }
/usr/bin/grep -q "SIDEBAR_CHECK_EXIT 0" "$OUT/sidebar-check.log" \
  || { echo "FAIL: the sidebar check did not exit 0"; exit 1; }
echo "PASS: the sidebar, its footer and the page stayed still at 860x580 and 1024x720"
