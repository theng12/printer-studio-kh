#!/bin/bash
# "Remove everything" must be unreachable past its guard.
#
#   app/test-removal-guard.sh
#
# Two halves, because either alone is a pass that proves nothing: the decision is run
# (a token that is missing, stale or from the future is refused), and the wiring is read
# (the command path asks, and only the Settings dialog issues a token).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/removal-guard.XXXXXX")"

/usr/bin/swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/PrinterStudio/RemovalGuard.swift" "$ROOT/Tools/TestRemovalGuard.swift" \
  -o "$OUT/check"
"$OUT/check"

python3 -I - "$ROOT/Sources/PrinterStudio/App.swift" "$ROOT/Sources/PrinterStudio/Views.swift" <<'PY'
import sys
app, views = (open(p).read() for p in sys.argv[1:])
guard = "guard RemovalGuard.permits(removalAuthorisation) else {"
assert guard in app, "the command path no longer asks the guard"
assert "static let removalRefusal" in app, "the refusal sentence is gone"
assert "reportFeedback = AppState.removalRefusal" in app, "a refusal no longer reaches the person"
# The token is consumed: the only place it is cleared is the removal itself.
assert app.count("removalAuthorisation = nil") == 2, "the token is not consumed by the attempt"
# Issued in one place, and that place is the dialog's destructive button.
assert views.count("state.authoriseRemoval()") == 1, "the dialog is not the only issuer"
assert "state.removeEverything()" in views, "the dialog no longer runs the removal"
assert app.count("func authoriseRemoval()") == 1, "more than one issuer exists"
assert app.count("func removeEverything()") == 1, "more than one removal entry point exists"
print("PASS: the command path asks, and the dialog is the only issuer")
PY

echo "Removal guard checks passed."
