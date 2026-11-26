#!/bin/bash
# Compiles and runs the shell ceiling suite: a command answers, fails with its
# reason, is stopped at its own ceiling, or is cancelled — and a big stderr
# cannot deadlock it. No window, no desktop, no printer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/test-shell-ceiling.XXXXXX")"

/usr/bin/swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/PrinterStudio/Shell.swift" "$ROOT/Tools/TestShell.swift" \
  -o "$OUT/check"
"$OUT/check"

# The Escape key itself cannot be pressed without a desktop, so the wiring is
# asserted from source the way app/test-reopen.sh asserts the reopen handler:
# the main window carries a cancel button with the platform cancel shortcut,
# and it exists only while an action is running.
SRC="$ROOT/Sources/PrinterStudio"
if grep -A 4 'Label("Cancel", systemImage: "stop.fill")' "$SRC/Views.swift" | grep -q '.keyboardShortcut(.cancelAction)'; then
  echo "PASS: the Escape cancel button is wired with .keyboardShortcut(.cancelAction)"
else
  echo "FAIL: the Escape cancel button is not wired with .keyboardShortcut(.cancelAction)" >&2
  exit 1
fi
if grep -B 8 '.keyboardShortcut(.cancelAction)' "$SRC/Views.swift" | grep -q 'if state.busy {'; then
  echo "PASS: the Escape cancel button exists only while an action is running"
else
  echo "FAIL: the Escape cancel button is not gated on the running action" >&2
  exit 1
fi
if grep -q 'keyboardShortcut(.cancelAction)' "$SRC/Views.swift" \
   && grep -q 'func cancelRunningAction()' "$SRC/App.swift" \
   && grep -q 'Shell.cancelCurrent()' "$SRC/App.swift"; then
  echo "PASS: Escape reaches Shell.cancelCurrent through AppState"
else
  echo "FAIL: Escape does not reach Shell.cancelCurrent through AppState" >&2
  exit 1
fi
