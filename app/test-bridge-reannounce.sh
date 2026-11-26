#!/bin/bash
#
# The bridge must notice when its AirPrint advertisement stops being visible and
# announce it again — the failure seen after an app update, where the helper was
# alive but the service had vanished until the job was restarted.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/test-bridge-reannounce.XXXXXX")"
mkdir -p "$OUT/tools" "$OUT/home" "$OUT/fixtures"
export HOME="$OUT/home"
export PRINTER_STUDIO_TOOL_DIR="$OUT/tools"
export PRINTER_STUDIO_FIXTURES="$OUT/fixtures"
echo 0 > "$OUT/fixtures/browse-count"

cat > "$OUT/tools/cupsctl" <<'MOCK'
#!/bin/bash
printf '%s\n' "_share_printers=1"
MOCK
cat > "$OUT/tools/lpstat" <<'MOCK'
#!/bin/bash
case "$1" in
  -p) printf '%s\n' 'printer Q is idle.  enabled since now' ;;
  -l) printf '\tDescription: Model\n' ;;
esac
MOCK
cat > "$OUT/tools/lpoptions" <<'MOCK'
#!/bin/bash
printf '%s\n' 'printer-is-shared=true'
MOCK
cat > "$OUT/tools/ipptool" <<'MOCK'
#!/bin/bash
# Sharing is read from the scheduler's attributes, not from lpoptions.
printf '%s\n' ' printer-is-shared (boolean) = true' ' printer-uuid = urn:uuid:11111111-2222-3333-4444-555555555555'
MOCK
# The browse shows our service twice, then it is gone: the helper must react.
cat > "$OUT/tools/dns-sd" <<'MOCK'
#!/bin/bash
if [ "$1" = "-B" ]; then
  n=$(cat "$PRINTER_STUDIO_FIXTURES/browse-count"); n=$((n+1)); echo "$n" > "$PRINTER_STUDIO_FIXTURES/browse-count"
  if [ "$n" -le 2 ]; then
    printf '%s\n' '12:00:00.000  Add  3 18 local.  _ipp._tcp.  Model (AirPrint)'
  fi
fi
exit 0
MOCK
chmod +x "$OUT/tools/"*

echo "==> Building the helper"
/usr/bin/swiftc -O -swift-version 5 -target "${ARCH}-apple-macos13.0" \
  -o "$OUT/helper" "$ROOT/Helper/main.swift"

echo "==> Running it with a vanishing advertisement"
PRINTER_STUDIO_RESCAN_SECONDS=1 "$OUT/helper" bridge > "$OUT/run.log" 2>&1 &
PID=$!
sleep 9
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

grep -q "went missing" "$OUT/run.log" \
  || { echo "FAIL: the helper never noticed its advertisement was gone"; sed -n 1,10p "$OUT/run.log"; exit 1; }
echo "  ✓ it noticed the advertisement had gone"
grep -q "announcing it again" "$OUT/run.log" \
  || { echo "FAIL: it noticed but did not re-announce"; exit 1; }
echo "  ✓ it announced it again without a restart"
echo "==> Advertisement recovery checks passed."
