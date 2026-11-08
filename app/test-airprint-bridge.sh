#!/bin/bash
# Offline registration checks; only stand-in tools and this test's children run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BRIDGE="${1:-$ROOT/Resources/airprint-bridge.sh}"
OUT="$ROOT/../_trash/test-airprint-discovery-$(/bin/date +%Y%m%d-%H%M%S)-$$"
/bin/mkdir -p "$OUT/tools" "$OUT/home"
export PRINTER_STUDIO_TOOL_DIR="$OUT/tools" PRINTER_STUDIO_FIXTURES="$OUT"
export PRINTER_STUDIO_RESCAN_SECONDS=1 HOME="$OUT/home"
/usr/bin/mkfifo "$OUT/ready" "$OUT/withdrawing" "$OUT/release"
exec 3<> "$OUT/ready"
exec 4<> "$OUT/withdrawing"
exec 5<> "$OUT/release"
await_registrations() {
  local queue
  for queue in 1 2 3; do
    read -r -t 15 -u 3 queue || { printf 'FAIL: timed out waiting for mock registration\n' >&2; exit 1; }
  done
}
cat > "$OUT/tools/lpstat" <<'MOCK'
#!/bin/bash
case "$1" in
-p) printf '%s\n' 'printer TSC_TTP_244_Pro is idle.' 'printer Xprinter_XP_D463B is idle.' 'printer Brother_HL_L2370DN_series is idle.' ;;
-l) case "$3" in TSC*) printf '\tDescription: %s\n' "$(cat "$PRINTER_STUDIO_FIXTURES/tsc-name")" ;; Xprinter*) printf '\tDescription: Xprinter XP-D463B\n' ;; *) printf '\tDescription: Brother HL-L2370DN series\n' ;; esac ;;
-v) printf '%s\n' 'device for TSC_TTP_244_Pro: usb://TSC/TTP-244%20Pro?serial=000001' 'device for Xprinter_XP_D463B: usb://Xprinter/XP-D463B?serial=00000000000011' ;;
esac
MOCK
cat > "$OUT/tools/lpoptions" <<'MOCK'
#!/bin/bash
queue=default
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p) queue="$2"; shift 2 ;;
    -l) case "$queue" in TSC*|Xprinter*) printf 'PageSize/Media Size: *50x70mm 30x40mm\n' ;; *) printf 'ColorModel/Color Mode: *Gray\nDuplex/Two-Sided: None *DuplexNoTumble\n' ;; esac; exit ;;
    *) shift ;;
  esac
done
printf 'printer-is-shared=true\n'
MOCK
cat > "$OUT/tools/hostname" <<'MOCK'
#!/bin/bash
printf 'kt-pdt-imac-m1-8-256\n'
MOCK
cat > "$OUT/tools/scutil" <<'MOCK'
#!/bin/bash
printf 'kt-pdt-imac-m1-8-256\n'
MOCK
cat > "$OUT/tools/cupsctl" <<'MOCK'
#!/bin/bash
cat "$PRINTER_STUDIO_FIXTURES/sharing"
MOCK
cat > "$OUT/tools/ipptool" <<'MOCK'
#!/bin/bash
queue="${2##*/}"
if [ -f "$PRINTER_STUDIO_FIXTURES/uuid-$queue" ]; then
  cat "$PRINTER_STUDIO_FIXTURES/uuid-$queue"
else
  printf 'printer-uuid (uri) = urn:uuid:test-queue\n'
fi
MOCK
cat > "$OUT/tools/dns-sd" <<'MOCK'
#!/bin/bash
local_only=0
while [ "${1:-}" = '-lo' ] || [ "${1:-}" = '-m' ]; do
  [ "$1" != '-lo' ] || local_only=1
  shift
done
if [ "$1" = '-L' ] || [ "$1" = '-B' ]; then
  [ "$local_only" = 1 ] || { printf 'FAIL: query escaped local-only scope\n' >&2; exit 1; }
  [ ! -e "$PRINTER_STUDIO_FIXTURES/native-query-failure" ] || exit 1
fi
case "$1" in
-R)
  queue=''
  for arg in "$@"; do case "$arg" in rp=printers/*) queue="${arg#rp=printers/}" ;; esac; done
  printf '%s\n' "$@" > "$PRINTER_STUDIO_FIXTURES/registered-$queue"
  printf '%s\n' "$queue" > "$PRINTER_STUDIO_FIXTURES/ready"
  /bin/sleep 30 &
  sleeper=$!
  withdraw() {
    /bin/kill "$sleeper" 2>/dev/null || true
    if [ "$queue" = Xprinter_XP_D463B ] && [ -f "$PRINTER_STUDIO_FIXTURES/hold-withdrawal" ]; then
      printf '%s\n' "$queue" >&4
      read -r -t 15 -u 5 released || exit 1
    fi
    exit 0
  }
  trap withdraw TERM INT
  wait "$sleeper" ;;
-B)
  if [ -f "$PRINTER_STUDIO_FIXTURES/native-browse" ]; then
    cat "$PRINTER_STUDIO_FIXTURES/native-browse"
    exit
  fi
  printf '%s\n' '15:00:00 Add 2 12 local. _ipp._tcp. TSC TTP-244 Pro @ kt-pdt-imac-m1-8-256' '15:00:00 Add 2 12 local. _ipp._tcp. Xprinter XP-D463B @ kt-pdt-imac-m1-8-256' ;;
-L)
  if [ -f "$PRINTER_STUDIO_FIXTURES/native-$2" ]; then
    cat "$PRINTER_STUDIO_FIXTURES/native-$2"
    exit
  fi
  case "$2" in TSC*) queue=TSC_TTP_244_Pro ;; *) queue=Xprinter_XP_D463B ;; esac
  printf '%s\n' "$2._ipp._tcp.local. can be reached at kt-pdt-imac-m1-8-256.local.:631 (interface 12)" "txtvers=1 rp=printers/$queue UUID=test-queue pdl=application/pdf" ;;
esac
MOCK
/bin/chmod 755 "$OUT/tools/"*
printf 'TSC TTP-244 Pro\n' > "$OUT/tsc-name"
printf '_share_printers=1\n' > "$OUT/sharing"
bridge_pid=''
trap '[ -z "$bridge_pid" ] || /bin/kill "$bridge_pid" 2>/dev/null || true' EXIT
/bin/bash "$BRIDGE" run > "$OUT/bridge.log" 2>&1 &
bridge_pid=$!
await_registrations
for queue in TSC_TTP_244_Pro Xprinter_XP_D463B; do
  /usr/bin/diff -u "$ROOT/Tools/Fixtures/airprint-1.0.4-$queue.txt" "$OUT/registered-$queue"
done
printf 'PASS: exact 1.0.4 label registration argv, names, subtype, port and all TXT fields\n'
[ -s "$OUT/registered-Brother_HL_L2370DN_series" ]
printf 'PASS: every shared queue is advertised; existing LAN records do not suppress labels or Brother\n'
# Delay Xprinter withdrawal to expose overlapping registrations during refresh.
printf 'hold\n' > "$OUT/hold-withdrawal"
printf 'TSC label desk\n' > "$OUT/tsc-name"
read -r -t 15 -u 4 withdrawing || { printf 'FAIL: no withdrawal signal\n' >&2; exit 1; }
if read -r -t 1 -u 3 premature; then
  printf 'FAIL: replacement %s registered before Xprinter withdrew\n' "$premature" >&2
  printf 'release\n' >&5
  exit 1
fi
/bin/mv "$OUT/hold-withdrawal" "$OUT/hold-withdrawal.used"
printf 'release\n' >&5
await_registrations
printf 'PASS: no replacement registration until the previous Xprinter publisher exits\n'
/usr/bin/grep -qxF 'TSC label desk (AirPrint)' "$OUT/registered-TSC_TTP_244_Pro"
printf 'PASS: registration follows a saved printer name\n'
/bin/kill "$bridge_pid"
wait "$bridge_pid" || true
bridge_pid=''
printf 'printer-uuid (uri) = urn:uuid:11111111-2222-3333-4444-555555555555\n' > "$OUT/uuid-TSC_TTP_244_Pro"
printf 'printer-uuid (uri) = urn:uuid:AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\n' > "$OUT/uuid-Xprinter_XP_D463B"
/bin/bash "$BRIDGE" run > "$OUT/identity.log" 2>&1 &
bridge_pid=$!
await_registrations
for queue in TSC_TTP_244_Pro Xprinter_XP_D463B; do
  # The complete known-good payload stays intact; only the stable UUID is added.
  /usr/bin/grep -v '^UUID=' "$OUT/registered-$queue" > "$OUT/legacy-$queue"
done
/usr/bin/grep -qx 'UUID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' "$OUT/registered-Xprinter_XP_D463B"
/usr/bin/grep -qx 'UUID=11111111-2222-3333-4444-555555555555' "$OUT/registered-TSC_TTP_244_Pro"
/usr/bin/diff -u "$ROOT/Tools/Fixtures/airprint-1.0.4-Xprinter_XP_D463B.txt" "$OUT/legacy-Xprinter_XP_D463B"
/usr/bin/grep -qx 'TSC label desk (AirPrint)' "$OUT/legacy-TSC_TTP_244_Pro"
! /usr/bin/grep -q '^UUID=' "$OUT/registered-Brother_HL_L2370DN_series"
printf 'TSC label desk renamed again\n' > "$OUT/tsc-name"
await_registrations
/usr/bin/grep -qx 'UUID=11111111-2222-3333-4444-555555555555' "$OUT/registered-TSC_TTP_244_Pro"
printf 'PASS: CUPS UUID survives rename, stays distinct per queue; invalid identity keeps discovery\n'
/bin/kill "$bridge_pid"
wait "$bridge_pid" || true
bridge_pid=''
for file in "$OUT"/registered-*; do /bin/mv "$file" "$file.before-sharing-off"; done
printf '_share_printers=0\n' > "$OUT/sharing"
/bin/bash "$BRIDGE" run > "$OUT/sharing-off.log" 2>&1 &
bridge_pid=$!
/bin/sleep 2
[ ! -e "$OUT/registered-TSC_TTP_244_Pro" ]
[ ! -e "$OUT/registered-Xprinter_XP_D463B" ]
/bin/kill "$bridge_pid"
wait "$bridge_pid" || true
bridge_pid=''
printf 'PASS: sharing-off guard prevents advertisements pointing at a closed service\n'

# One known native AirPrint publisher per physical printer must not gain a bridge twin.
printf '_share_printers=1\n' > "$OUT/sharing"
printf 'printer-uuid (uri) = urn:uuid:99999999-2222-3333-4444-555555555555\n' > "$OUT/uuid-Brother_HL_L2370DN_series"
for queue in TSC_TTP_244_Pro Xprinter_XP_D463B Brother_HL_L2370DN_series; do
  printf 'printer-dns-sd-name (nameWithoutLanguage) = %s native\n' "$queue" >> "$OUT/uuid-$queue"
  uuid=$(/usr/bin/awk '$1 == "printer-uuid" {print $4}' "$OUT/uuid-$queue")
  uuid=$(printf '%s' "${uuid#urn:uuid:}" | /usr/bin/tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$queue native._ipp._tcp.local. can be reached at fixture.local.:631 (interface 0)" \
    " txtvers=1 rp=printers/$queue UUID=$uuid pdl=application/pdf,image/urf URF=W8,RS300" > "$OUT/native-$queue native"
  printf '15:00:00 Add 2 0 local. _ipp._tcp. %s native\n' "$queue" >> "$OUT/native-browse"
done
check_native_plan() {
  local expected="$1" count
  /bin/bash "$BRIDGE" list > "$OUT/native-plan" 2> "$OUT/native-plan.err"
  count=$(/usr/bin/grep -c '^-R$' "$OUT/native-plan" || true)
  [ "$count" = "$expected" ] || { printf 'FAIL: expected %s bridge entries beside native printers, found %s\n' "$expected" "$count" >&2; exit 1; }
}
check_native_plan 0
printf 'PASS: one native entry per physical USB/network printer, no second bridge entry\n'
# A plain CUPS record or an unrelated/malformed record must never hide a label printer.
/bin/cp "$OUT/native-TSC_TTP_244_Pro native" "$OUT/native-tsc-original"
/usr/bin/sed 's/ URF=W8,RS300//' "$OUT/native-tsc-original" > "$OUT/native-TSC_TTP_244_Pro native"
check_native_plan 1
/usr/bin/grep -qx 'rp=printers/TSC_TTP_244_Pro' "$OUT/native-plan"
printf 'PASS: plain native IPP without URF keeps legacy label discovery\n'
for replacement in 's/UUID=[^ ]*/UUID=99999999-2222-3333-4444-555555555555/' 's@rp=printers/TSC_TTP_244_Pro@rp=printers/unrelated@' 's/:631 /:8631 /' 's@pdl=application/pdf,image/urf@pdl=application/postscript@'; do
  /usr/bin/sed "$replacement" "$OUT/native-tsc-original" > "$OUT/native-TSC_TTP_244_Pro native"
  check_native_plan 1
done
printf 'PASS: foreign UUID, different queue/port and unusable format cannot suppress a printer\n'
/bin/cp "$OUT/native-tsc-original" "$OUT/native-TSC_TTP_244_Pro native"
printf 'failure\n' > "$OUT/native-query-failure"
check_native_plan 3
/bin/mv "$OUT/native-query-failure" "$OUT/native-query-failure.used"
printf 'PASS: failed native lookup keeps every bridge entry\n'
/bin/mv "$OUT/native-browse" "$OUT/native-browse.saved"
check_native_plan 3
printf 'PASS: missing confirmed AirPrint subtype keeps every bridge entry\n'
/usr/bin/sed 's/ native$/ (AirPrint)/' "$OUT/native-browse.saved" > "$OUT/native-browse"
check_native_plan 3
printf 'PASS: bridge copies alone never count as native coverage\n'
printf 'Artifacts retained: %s\n' "$OUT"
