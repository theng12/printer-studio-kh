#!/bin/bash
#
# Focused tests for the AirPrint advertisement bridge.
#
# The bridge is driven by mock binaries instead of the real cupsd and the
# real Bonjour daemon, so the tests never touch a print queue, never publish
# a service and never print. Every mock reads its fixture from
# PRINTER_STUDIO_FIXTURES.
#
#   ./app/test-airprint-bridge.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BRIDGE="$ROOT/Resources/airprint-bridge.sh"
TRASH="$ROOT/../_trash/test-airprint-bridge-$(date +%Y%m%d-%H%M)-$$"

PASSED=0
FAILED=0

check() {
  # check <name> <expected substring> <actual text>
  if printf '%s' "$3" | grep -qF -- "$2"; then
    PASSED=$((PASSED + 1))
    printf '  ✓ %s\n' "$1"
  else
    FAILED=$((FAILED + 1))
    printf '  ✗ FAIL: %s\n      expected to contain: %s\n      got: %s\n' "$1" "$2" "$3"
  fi
}

check_absent() {
  if printf '%s' "$3" | grep -qF -- "$2"; then
    FAILED=$((FAILED + 1))
    printf '  ✗ FAIL: %s\n      expected NOT to contain: %s\n      got: %s\n' "$1" "$2" "$3"
  else
    PASSED=$((PASSED + 1))
    printf '  ✓ %s\n' "$1"
  fi
}

# ---------------------------------------------------------------- mocks ----

# make_mocks <dir>
#
# Each mock is a small shell script that answers from the fixture files in
# $PRINTER_STUDIO_FIXTURES.
make_mocks() {
  local dir="$1"
  mkdir -p "$dir"

  cat > "$dir/lpstat" <<'MOCK'
#!/bin/bash
# lpstat -p | -l -p <queue> | -v
F="$PRINTER_STUDIO_FIXTURES"
case "$1" in
  -p)
    cat "$F/lpstat-p"
    ;;
  -l)
    # -l -p <queue>
    queue="${3:-}"
    cat "$F/description-$queue"
    ;;
  -v)
    cat "$F/lpstat-v"
    ;;
esac
MOCK

  cat > "$dir/lpoptions" <<'MOCK'
#!/bin/bash
# lpoptions -p <queue> | lpoptions -l -p <queue>
F="$PRINTER_STUDIO_FIXTURES"
case "$1" in
  -l) cat "$F/options-$3" ;;
  -p) cat "$F/shared-$2" ;;
esac
MOCK

  cat > "$dir/ipptool" <<'MOCK'
#!/bin/bash
# ipptool -tv ipp://localhost/printers/<queue> ...
F="$PRINTER_STUDIO_FIXTURES"
queue="${2}"
queue="${queue##*/}"
cat "$F/uuid-$queue"
MOCK

  cat > "$dir/cupsctl" <<'MOCK'
#!/bin/bash
cat "$PRINTER_STUDIO_FIXTURES/cupsctl"
MOCK

  cat > "$dir/scutil" <<'MOCK'
#!/bin/bash
echo "Test-Local-Host"
MOCK

  cat > "$dir/hostname" <<'MOCK'
#!/bin/bash
echo "Test-Mac"
MOCK

  # dns-sd -B <service> local  |  dns-sd -L <name> <type> local
  cat > "$dir/dns-sd" <<'MOCK'
#!/bin/bash
F="$PRINTER_STUDIO_FIXTURES"
if [ "$1" = "-B" ]; then
  service="$2"
  file="$F/browse-$(printf '%s' "$service" | tr ',.' '__')"
  [ -f "$file" ] && cat "$file"
  exit 0
fi
if [ "$1" = "-L" ]; then
  name="$2"
  file="$F/resolve-$(printf '%s' "$name" | tr ' /' '__')"
  [ -f "$file" ] && cat "$file"
  exit 0
fi
# -R: record what would be published, so the test can read it back.
if [ "$1" = "-R" ]; then
  printf '%s\n' "$*" >> "$PRINTER_STUDIO_FIXTURES/published"
  exit 0
fi
MOCK

  chmod +x "$dir"/*
}

# run_list <fixture-dir>
#
# Runs the bridge in "list" mode against the given fixtures and prints what
# it says.
run_list() {
  local fixtures="$1" mocks="$2"
  PRINTER_STUDIO_FIXTURES="$fixtures" \
  PRINTER_STUDIO_TOOL_DIR="$mocks" \
  PRINTER_STUDIO_BROWSE_SECONDS=0 \
  PRINTER_STUDIO_RESOLVE_SECONDS=0 \
  "$BRIDGE" list 2>&1
}

# ------------------------------------------------------------- fixtures ----

# fixture_usb
#
# One shared USB queue (the HP Laser 107a) and one shared network queue
# whose printer advertises itself.
fixture_usb() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/lpstat-p" <<'EOF'
printer Brother_HL_L2370DN_series is idle.  enabled since Tue Sep 22 15:02:53 2026
printer HPLaser107a is idle.  enabled since Sun Sep 27 18:21:54 2026
EOF
  cat > "$dir/lpstat-v" <<'EOF'
device for Brother_HL_L2370DN_series: dnssd://Brother%20HL-L2370DN%20series%20%40%20hq-macmini-m1-8-512._ipps._tcp.local./?uuid=285a4a4a-6582-355b-7b94-1993310906a5
device for HPLaser107a: usb://HP/HP%20Laser%20103%20107%20108?serial=CNB3P899PY
EOF
  printf 'printer-is-shared=false\n' > "$dir/shared-Brother_HL_L2370DN_series"
  printf 'printer-is-shared=true\n' > "$dir/shared-HPLaser107a"
  printf '\tDescription: HP Laser 107a\n' > "$dir/description-HPLaser107a"
  printf '\tDescription: Brother HL-L2370DN series\n' > "$dir/description-Brother_HL_L2370DN_series"
  cat > "$dir/options-HPLaser107a" <<'EOF'
ColorModel/Color Mode: *Gray
Duplex/Duplex: DuplexTumble
PageSize/PageSize: A4 *A4 A5 Letter
EOF
  printf 'printer-uuid (uri) = urn:uuid:515c05c3-af01-3c02-6d90-b60b097194e3\n' > "$dir/uuid-HPLaser107a"
  printf '_share_printers=1\n_remote_any=0\n' > "$dir/cupsctl"
  : > "$dir/published"
}

# fixture_native
#
# The same network queue, plus a native AirPrint record on the LAN for the
# same printer UUID — the printer advertising itself.
fixture_native() {
  local dir="$1"
  fixture_usb "$dir"
  cat > "$dir/lpstat-p" <<'EOF'
printer Brother_HL_L2370DN_series is idle.  enabled since Tue Sep 22 15:02:53 2026
printer HPLaser107a is idle.  enabled since Sun Sep 27 18:21:54 2026
EOF
  printf 'printer-is-shared=true\n' > "$dir/shared-Brother_HL_L2370DN_series"
  # The Brother advertises itself, and its UUID is the one in the dnssd URI.
  cat > "$dir/browse-_ipp__tcp" <<'EOF'
Timestamp     A/R    Flags  if Domain               Service Type         Instance Name
13:03:55.374  Add        2  19 local.               _ipp._tcp.           Brother HL-L2370DN series @ test-printer
EOF
  cat > "$dir/browse-_ipp__tcp__universal" <<'EOF'
Timestamp     A/R    Flags  if Domain               Service Type         Instance Name
13:03:55.374  Add        2  19 local.               _ipp._tcp.           Brother HL-L2370DN series @ test-printer
EOF
  cat > "$dir/resolve-Brother_HL-L2370DN_series_@_test-printer" <<'EOF'
Brother\032HL-L2370DN\032series\032@\032test-printer._ipp._tcp.local. can be reached at test-printer.local.:631 (interface 19)
 txtvers=1 qtotal=1 rp=printers/Brother_HL_L2370DN_series ty=Brother\ HL-L2370DN\ series UUID=285a4a4a-6582-355b-7b94-1993310906a5 URF=none Color=F Duplex=T
EOF
  printf 'printer-uuid (uri) = urn:uuid:160eddc5-0abf-3202-7caa-d150d32db595\n' > "$dir/uuid-Brother_HL_L2370DN_series"
}

# fixture_sharing_off
fixture_sharing_off() {
  local dir="$1"
  fixture_usb "$dir"
  printf '_share_printers=0\n_remote_any=0\n' > "$dir/cupsctl"
}

# ---------------------------------------------------------------- tests ----

echo "==> Building mocks"
mkdir -p "$TRASH"
MOCKS="$TRASH/mocks"
make_mocks "$MOCKS"

echo "==> A USB queue is advertised, with the user's own name"
FIX="$TRASH/usb"
fixture_usb "$FIX"
OUT="$(run_list "$FIX" "$MOCKS")"
check "the USB queue is advertised" "HPLaser107a advertise HP Laser 107a" "$OUT"
check "the name is the queue name, with no suffix" "-R HP Laser 107a _ipp._tcp,_universal" "$OUT"
check_absent "the name has no (AirPrint) suffix" "(AirPrint)" "$OUT"
check "the queue path is in the record" "rp=printers/HPLaser107a" "$OUT"
check "the queue keeps its own UUID" "UUID=515c05c3-af01-3c02-6d90-b60b097194e3" "$OUT"
check "the universal subtype is used" "_ipp._tcp,_universal" "$OUT"

echo "==> A monochrome printer is not advertised as colour"
check "a Gray-only queue is not colour" "Color=F" "$OUT"
check_absent "a Gray-only queue does not claim colour" "Color=T" "$OUT"

echo "==> No URF is claimed"
check "URF is none" "URF=none" "$OUT"
check_absent "URF is not offered as a format" "image/urf" "$OUT"
check "PDF is offered" "pdl=application/pdf,image/jpeg" "$OUT"

echo "==> A network printer that advertises itself is skipped"
FIX="$TRASH/native"
fixture_native "$FIX"
OUT="$(run_list "$FIX" "$MOCKS")"
check "the self-advertising printer is skipped" "Brother_HL_L2370DN_series skip      Brother HL-L2370DN series" "$OUT"
check "the USB queue is still advertised" "HPLaser107a advertise HP Laser 107a" "$OUT"
check_absent "the self-advertising printer is not advertised again" "Brother_HL_L2370DN_series advertise" "$OUT"

echo "==> Nothing is advertised when Printer Sharing is off"
FIX="$TRASH/sharing-off"
fixture_sharing_off "$FIX"
OUT="$(run_list "$FIX" "$MOCKS")"
check "sharing being off is reported" "Printer Sharing is off" "$OUT"
check_absent "no queue is advertised" " advertise " "$OUT"

echo "==> The fingerprint changes when the name changes"
FIX="$TRASH/fingerprint"
fixture_usb "$FIX"
FIRST="$(run_list "$FIX" "$MOCKS" | grep '^Fingerprint:')"
printf '\tDescription: HP Laser 107a Renamed\n' > "$FIX/description-HPLaser107a"
SECOND="$(run_list "$FIX" "$MOCKS" | grep '^Fingerprint:')"
if [ "$FIRST" != "$SECOND" ]; then
  PASSED=$((PASSED + 1)); echo "  ✓ a renamed queue has a different fingerprint"
else
  FAILED=$((FAILED + 1)); echo "  ✗ FAIL: a renamed queue has a different fingerprint"
fi
OUT="$(run_list "$FIX" "$MOCKS")"
check "the new name is advertised" "-R HP Laser 107a Renamed _ipp._tcp,_universal" "$OUT"

echo "==> The fingerprint changes when the paper sizes change"
FIX="$TRASH/media"
fixture_usb "$FIX"
FIRST="$(run_list "$FIX" "$MOCKS" | grep '^Fingerprint:')"
cat > "$FIX/options-HPLaser107a" <<'EOF'
ColorModel/Color Mode: *Gray
PageSize/PageSize: A4 *A4 A5 Letter 100x150mm
EOF
SECOND="$(run_list "$FIX" "$MOCKS" | grep '^Fingerprint:')"
if [ "$FIRST" != "$SECOND" ]; then
  PASSED=$((PASSED + 1)); echo "  ✓ a new paper size has a different fingerprint"
else
  FAILED=$((FAILED + 1)); echo "  ✗ FAIL: a new paper size has a different fingerprint"
fi

echo "==> A queue macOS already advertises as AirPrint is skipped"
FIX="$TRASH/macos-advert"
fixture_usb "$FIX"
printf 'printer Brother_HL_L2370DN_series is idle.\nprinter HPLaser107a is idle.\n' > "$FIX/lpstat-p"
printf 'printer-is-shared=true\n' > "$FIX/shared-Brother_HL_L2370DN_series"
printf '\tDescription: Brother HL-L2370DN series\n' > "$FIX/description-Brother_HL_L2370DN_series"
cat > "$FIX/lpstat-v" <<'EOF'
device for Brother_HL_L2370DN_series: dnssd://Brother%20HL-L2370DN%20series%20%40%20hq-macmini-m1-8-512._ipps._tcp.local./?uuid=285a4a4a-6582-355b-7b94-1993310906a5
device for HPLaser107a: usb://HP/HP%20Laser%20103%20107%20108?serial=CNB3P899PY
EOF
cat > "$FIX/browse-_ipps__tcp" <<'EOF'
Timestamp     A/R    Flags  if Domain               Service Type         Instance Name
13:42:04.400  Add        2  19 local.               _ipps._tcp.          Brother HL-L2370DN series @ kt-pdt-imac-m1-8-256
EOF
printf 'Timestamp     A/R    Flags  if Domain               Service Type         Instance Name\n' > "$FIX/browse-_ipps__tcp__universal"
cat > "$FIX/resolve-Brother_HL-L2370DN_series_@_kt-pdt-imac-m1-8-256" <<'EOF'
Brother\032HL-L2370DN\032series\032@\032kt-pdt-imac-m1-8-256._ipps._tcp.local. can be reached at kt-pdt-imac-m1-8-256.local.:631 (interface 19)
 txtvers=1 qtotal=1 rp=printers/Brother_HL_L2370DN_series ty=Brother\ HL-L2370DN\ series UUID=2125f6b7-0bec-3f89-4729-754cefa2ab25 pdl=application/octet-stream,application/pdf,image/pwg-raster URF=none Color=F Duplex=T
EOF
OUT="$(run_list "$FIX" "$MOCKS")"
check "a queue macOS already advertises is skipped" "Brother_HL_L2370DN_series skip      Brother HL-L2370DN series" "$OUT"
check "the USB queue is still advertised" "HPLaser107a advertise" "$OUT"

echo "==> The fingerprint changes when the colour flag changes"
FIX="$TRASH/color"
fixture_usb "$FIX"
FIRST="$(run_list "$FIX" "$MOCKS" | grep '^Fingerprint:')"
printf 'ColorModel/Color Mode: *RGB\n' > "$FIX/options-HPLaser107a"
SECOND="$(run_list "$FIX" "$MOCKS" | grep '^Fingerprint:')"
if [ "$FIRST" != "$SECOND" ]; then
  PASSED=$((PASSED + 1)); echo "  ✓ a colour change has a different fingerprint"
else
  FAILED=$((FAILED + 1)); echo "  ✗ FAIL: a colour change has a different fingerprint"
fi
OUT="$(run_list "$FIX" "$MOCKS")"
check "a colour queue is advertised as colour" "Color=T" "$OUT"

echo "==> Our own record is not mistaken for the printer's"
FIX="$TRASH/own-record"
fixture_usb "$FIX"
cat > "$FIX/browse-_ipp__tcp" <<'EOF'
Timestamp     A/R    Flags  if Domain               Service Type         Instance Name
13:03:55.374  Add        3  19 local.               _ipp._tcp.           HP Laser 107a
EOF
cat > "$FIX/browse-_ipp__tcp__universal" <<'EOF'
Timestamp     A/R    Flags  if Domain               Service Type         Instance Name
13:03:55.374  Add        3  19 local.               _ipp._tcp.           HP Laser 107a
EOF
cat > "$FIX/resolve-HP_Laser_107a" <<'EOF'
HP\032Laser\032107a._ipp._tcp.local. can be reached at Test-Mac.local.:631 (interface 19)
 txtvers=1 qtotal=1 rp=printers/HPLaser107a UUID=515c05c3-af01-3c02-6d90-b60b097194e3 psbridge=1 URF=none
EOF
OUT="$(run_list "$FIX" "$MOCKS")"
check "our own record does not stop the queue being advertised" "HPLaser107a advertise HP Laser 107a" "$OUT"

echo
printf 'Summary: %d passed, %d failed\n' "$PASSED" "$FAILED"
echo "Fixtures kept in $TRASH"
[ "$FAILED" -eq 0 ] || exit 1
