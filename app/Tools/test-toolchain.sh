#!/bin/bash
#
# Proves the packaging toolchain pin (issue row 20261122-318):
# 1. Sourcing app/toolchain.sh twice adds no PATH entry.
# 2. Under a non-login shell's PATH, the pin resolves Homebrew's python3 (not the 3.9 stub)
#    and finds pkg-config — the two things a gate or launchd shell was missing.
# 3. A python3 below the required version stops with the PATH and the version named.
# 4. No script the packaging path runs calls a bare `python3` without sourcing the pin.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PIN="$ROOT/app/toolchain.sh"
BARE='(^|[^/[:alnum:]_])python3([[:space:]]|$)'

if [ ! -f "$PIN" ]; then
  echo "FAIL: $PIN is missing" >&2
  exit 1
fi

echo "==> Test 1: sourcing twice adds no PATH entry"
twice=$(PATH=/usr/bin:/bin bash -c 'source "$1"; a=$PATH; source "$1"; printf "%s" "$PATH"' _ "$PIN")
once=$(PATH=/usr/bin:/bin bash -c 'source "$1"; printf "%s" "$PATH"' _ "$PIN")
if [ "$twice" != "$once" ]; then
  echo "FAIL: a second source changed the PATH ($once -> $twice)" >&2
  exit 1
fi
echo "PASS: idempotent"

echo "==> Test 2: a non-login PATH resolves Homebrew's python3 and pkg-config"
resolved=$(env -i HOME="$HOME" PATH=/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:. bash -c '
  source "$1"
  printf "%s|%s|%s" "$(command -v python3)" "$(python3 -c "import sys; print(\"%d.%d\" % sys.version_info[:2])")" "$(command -v pkg-config || echo missing)"
' _ "$PIN")
py_path=${resolved%%|*}; rest=${resolved#*|}; py_ver=${rest%%|*}; pkg=${rest#*|}
echo "    python3 $py_ver at $py_path; pkg-config $pkg"
if [ ! -d /opt/homebrew/bin ]; then
  echo "SKIP: no Homebrew on this Mac, the pin has nothing to add"
else
  [ "$py_path" != "/usr/bin/python3" ] || { echo "FAIL: the pin left the 3.9 stub first on PATH" >&2; exit 1; }
  [ "$pkg" != "missing" ] || { echo "FAIL: pkg-config is still missing after the pin" >&2; exit 1; }
  echo "PASS: resolved away from the 3.9 stub"
fi

echo "==> Test 3: a missing minimum names the PATH and the version"
out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c 'source "$1"; toolchain_require_python 99.0' _ "$PIN" 2>&1) && rc=0 || rc=$?
if [ "$rc" = 0 ]; then
  echo "FAIL: toolchain_require_python accepted 99.0" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q 'Python 99.0 or later is required' || { echo "FAIL: the reason does not name the version: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q '^PATH searched: ' || { echo "FAIL: the reason does not name the PATH: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q 'Traceback' && { echo "FAIL: it printed a traceback: $out" >&2; exit 1; }
echo "PASS: names the version and the PATH, no traceback"

echo "==> Test 4: every packaging-path script that calls a bare python3 sources the pin"
failed=0
for f in app/build.sh app/render-pages.sh app/finalize-dist.sh app/retain-dmgs.sh app/release-notes.sh app/signing.sh; do
  if grep -qE "$BARE" "$ROOT/$f"; then
    if grep -q 'toolchain\.sh' "$ROOT/$f"; then
      echo "    ok   $f (bare python3, pin sourced)"
    else
      echo "    FAIL $f calls a bare python3 and does not source app/toolchain.sh" >&2
      failed=1
    fi
  fi
done
[ "$failed" = 0 ] || exit 1
echo "PASS: no packaging script resolves python3 unpinned"

echo "Toolchain checks passed."
