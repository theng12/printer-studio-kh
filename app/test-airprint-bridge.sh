#!/bin/bash
# Offline advertisement-plan checks; only stand-in tools and the helper run.
# The helper never touches real launchd, sharing settings or the network here:
# `list` only reads through the mock tools.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../_trash/test-airprint-discovery-$(/bin/date +%Y%m%d-%H%M%S)-$$"
/bin/mkdir -p "$OUT/tools" "$OUT/home"
export PRINTER_STUDIO_TOOL_DIR="$OUT/tools" PRINTER_STUDIO_FIXTURES="$OUT"
export PRINTER_STUDIO_DNSSD_SECONDS=2 HOME="$OUT/home"

cat > "$OUT/tools/lpstat" <<'MOCK'
#!/bin/bash
case "$1" in
-p) printf '%s\n' 'printer TSC_TTP_244_Pro is idle.' 'printer Xprinter_XP_D463B is idle.' 'printer Brother_HL_L2370DN_series is idle.' 'printer HP_Laser_108w is idle.' ;;
-l) case "$3" in
      TSC*) printf '\tDescription: %s\n' "$(cat "$PRINTER_STUDIO_FIXTURES/tsc-name")" ;;
      Xprinter*) printf '\tDescription: Xprinter XP-D463B\n' ;;
      HP*) printf '\tDescription: HP Laser 108w\n' ;;
      *) printf '\tDescription: Brother HL-L2370DN series-AirPrint\n' ;;
    esac ;;
-v) printf '%s\n' \
      'device for TSC_TTP_244_Pro: usb://TSC/TTP-244%20Pro?serial=000001' \
      'device for Xprinter_XP_D463B: usb://Xprinter/XP-D463B?serial=00000000000011' \
      'device for Brother_HL_L2370DN_series: ippusb://Brother%20HL-L2370DN%20series._ipp._tcp.local/?uuid=2a48000-80ce-11db-8c00-3c2af470c7c4' \
      'device for HP_Laser_108w: ipps://HP%20Laser%20108w._ipps._tcp.local./' ;;
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
# A queue's PPD options, which is all lpoptions prints. Sharing is a CUPS
# attribute, so a fixture can reproduce the Brother's real answer here: no
# shared flag at all.
if [ -f "$PRINTER_STUDIO_FIXTURES/lpoptions-$queue" ]; then
  cat "$PRINTER_STUDIO_FIXTURES/lpoptions-$queue"
  exit
fi
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
[ ! -f "$PRINTER_STUDIO_FIXTURES/ipptool-failure-$queue" ] || exit 1
if [ -f "$PRINTER_STUDIO_FIXTURES/shared-$queue" ]; then
  cat "$PRINTER_STUDIO_FIXTURES/shared-$queue"
else
  printf 'printer-is-shared (boolean) = true\n'
fi
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

HELPER="${1:-}"
if [ -z "$HELPER" ]; then
  HELPER="$OUT/helper"
  /usr/bin/swiftc -O -swift-version 5 \
    -target "$(uname -m)-apple-macos13.0" \
    -o "$HELPER" "$ROOT/Helper/main.swift"
fi

run_list() {
  "$HELPER" list > "$OUT/plan" 2> "$OUT/plan.err"
}
plan_for() {
  /usr/bin/awk -v q="$1" '$0 == "Shared queue: " q {inside=1; next} /^Shared queue: / {inside=0} inside' "$OUT/plan"
}

run_list
for queue in TSC_TTP_244_Pro Xprinter_XP_D463B; do
  plan_for "$queue" > "$OUT/registered-$queue"
  /usr/bin/diff -u "$ROOT/Tools/Fixtures/airprint-1.0.4-$queue.txt" "$OUT/registered-$queue"
done
printf 'PASS: exact 1.0.4 label registration argv, names, subtype, port and all TXT fields\n'
/usr/bin/grep -qx 'rp=printers/Brother_HL_L2370DN_series' "$OUT/plan"
printf 'PASS: every shared queue is advertised; existing LAN records do not suppress labels or Brother\n'

printf 'TSC label desk\n' > "$OUT/tsc-name"
run_list
/usr/bin/grep -qx 'TSC label desk (AirPrint)' "$OUT/plan"
printf 'PASS: registration follows a saved printer name\n'

printf 'printer-uuid (uri) = urn:uuid:11111111-2222-3333-4444-555555555555\n' > "$OUT/uuid-TSC_TTP_244_Pro"
printf 'printer-uuid (uri) = urn:uuid:AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\n' > "$OUT/uuid-Xprinter_XP_D463B"
run_list
for queue in TSC_TTP_244_Pro Xprinter_XP_D463B; do
  plan_for "$queue" > "$OUT/registered-$queue"
  # The complete known-good payload stays intact; only the stable UUID is added.
  /usr/bin/grep -v '^UUID=' "$OUT/registered-$queue" > "$OUT/legacy-$queue"
done
plan_for Brother_HL_L2370DN_series > "$OUT/registered-Brother_HL_L2370DN_series"
/usr/bin/grep -qx 'UUID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' "$OUT/registered-Xprinter_XP_D463B"
/usr/bin/grep -qx 'UUID=11111111-2222-3333-4444-555555555555' "$OUT/registered-TSC_TTP_244_Pro"
/usr/bin/diff -u "$ROOT/Tools/Fixtures/airprint-1.0.4-Xprinter_XP_D463B.txt" "$OUT/legacy-Xprinter_XP_D463B"
/usr/bin/grep -qx 'TSC label desk (AirPrint)' "$OUT/legacy-TSC_TTP_244_Pro"
! /usr/bin/grep -q '^UUID=' "$OUT/registered-Brother_HL_L2370DN_series"
printf 'TSC label desk renamed again\n' > "$OUT/tsc-name"
run_list
/usr/bin/grep -qx 'UUID=11111111-2222-3333-4444-555555555555' "$OUT/plan"
printf 'PASS: CUPS UUID survives rename, stays distinct per queue; invalid identity keeps discovery\n'

printf '_share_printers=0\n' > "$OUT/sharing"
run_list
! /usr/bin/grep -q '^rp=' "$OUT/plan"
/usr/bin/grep -qx 'Printer Sharing is off, so nothing would be advertised.' "$OUT/plan"
printf 'PASS: sharing-off guard prevents advertisements pointing at a closed service\n'

# One known native AirPrint publisher per physical printer must not gain a bridge
# twin — except a USB queue, whose macOS IPP-over-USB record is local-only and
# never reaches an iPhone. The owner's Brother HL-L2370DN is the latter: ippusb
# URI, a model ending in -AirPrint, and a complete native local record.
printf '_share_printers=1\n' > "$OUT/sharing"
printf 'printer-uuid (uri) = urn:uuid:99999999-2222-3333-4444-555555555555\n' > "$OUT/uuid-Brother_HL_L2370DN_series"
printf 'printer-uuid (uri) = urn:uuid:77777777-2222-3333-4444-555555555555\n' > "$OUT/uuid-HP_Laser_108w"
add_native_queue() {
  local queue="$1" uuid
  printf 'printer-dns-sd-name (nameWithoutLanguage) = %s native\n' "$queue" >> "$OUT/uuid-$queue"
  uuid=$(/usr/bin/awk '$1 == "printer-uuid" {print $4}' "$OUT/uuid-$queue")
  uuid=$(printf '%s' "${uuid#urn:uuid:}" | /usr/bin/tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$queue native._ipp._tcp.local. can be reached at fixture.local.:631 (interface 0)" \
    " txtvers=1 rp=printers/$queue UUID=$uuid pdl=application/pdf,image/urf URF=W8,RS300" > "$OUT/native-$queue native"
  printf '15:00:00 Add 2 0 local. _ipp._tcp. %s native\n' "$queue" >> "$OUT/native-browse"
}
check_native_plan() {
  local expected="$1" count
  run_list
  count=$(/usr/bin/grep -c '^-R$' "$OUT/plan" || true)
  [ "$count" = "$expected" ] || { printf 'FAIL: expected %s bridge entries beside native printers, found %s\n' "$expected" "$count" >&2; exit 1; }
}
add_native_queue TSC_TTP_244_Pro
add_native_queue Xprinter_XP_D463B
add_native_queue HP_Laser_108w
check_native_plan 1
/usr/bin/grep -qx 'rp=printers/Brother_HL_L2370DN_series' "$OUT/plan"
! /usr/bin/grep -q 'rp=printers/HP_Laser_108w' "$OUT/plan"
! /usr/bin/grep -q 'rp=printers/TSC_TTP_244_Pro' "$OUT/plan"
printf 'PASS: native network and usb:// queues are not twinned; only the ippusb Brother stays bridged\n'

# The real Brother shape: its complete native local record still must not hide it.
add_native_queue Brother_HL_L2370DN_series
check_native_plan 1
/usr/bin/grep -qx 'Brother HL-L2370DN series (AirPrint)' "$OUT/plan"
/usr/bin/grep -qx 'rp=printers/Brother_HL_L2370DN_series' "$OUT/plan"
/usr/bin/grep -qx 'ty=Brother HL-L2370DN series' "$OUT/plan"
/usr/bin/grep -qx 'product=(Brother HL-L2370DN series)' "$OUT/plan"
/usr/bin/grep -qx 'pdl=application/pdf,image/jpeg,image/urf' "$OUT/plan"
printf 'PASS: an ippusb/AirPrint-shaped USB queue is advertised exactly like the label queues\n'

# A plain or malformed native record must fall back to the bridge for the network queue.
/bin/cp "$OUT/native-HP_Laser_108w native" "$OUT/native-hp-original"
/usr/bin/sed 's/ URF=W8,RS300//' "$OUT/native-hp-original" > "$OUT/native-HP_Laser_108w native"
check_native_plan 2
/usr/bin/grep -qx 'rp=printers/HP_Laser_108w' "$OUT/plan"
printf 'PASS: plain native IPP without URF keeps the bridge copy\n'
for replacement in 's/UUID=[^ ]*/UUID=99999999-2222-3333-4444-555555555555/' 's@rp=printers/HP_Laser_108w@rp=printers/unrelated@' 's/:631 /:8631 /' 's@pdl=application/pdf,image/urf@pdl=application/postscript@'; do
  /usr/bin/sed "$replacement" "$OUT/native-hp-original" > "$OUT/native-HP_Laser_108w native"
  check_native_plan 2
done
printf 'PASS: foreign UUID, different queue/port and unusable format keep the bridge copy\n'
/bin/cp "$OUT/native-hp-original" "$OUT/native-HP_Laser_108w native"
printf 'failure\n' > "$OUT/native-query-failure"
check_native_plan 4
/bin/mv "$OUT/native-query-failure" "$OUT/native-query-failure.used"
printf 'PASS: failed native lookup keeps every bridge entry\n'
/bin/mv "$OUT/native-browse" "$OUT/native-browse.saved"
check_native_plan 4
printf 'PASS: missing confirmed AirPrint subtype keeps every bridge entry\n'
/usr/bin/sed 's/ native$/ (AirPrint)/' "$OUT/native-browse.saved" > "$OUT/native-browse"
check_native_plan 4
printf 'PASS: bridge copies alone never count as native coverage\n'
# Sharing is a CUPS attribute, not a PPD option (owner's Brother HL-L2370DN).
# That queue is shared, while `lpoptions -p Brother_HL_L2370DN_series` prints only
# discovery/device/model fields — the old detection read lpoptions and dropped it
# before the bridge ever saw it. A fresh fixtures dir keeps this independent of
# the runs above.
ATTR="$OUT/sharing-attribute"
/bin/mkdir -p "$ATTR"
export PRINTER_STUDIO_FIXTURES="$ATTR"
printf '_share_printers=1\n' > "$ATTR/sharing"
printf '%s\n' \
  'printer-make-and-model=Brother HL-L2370DN series-AirPrint' \
  'device-uri=ippusb://Brother%20HL-L2370DN%20series._ipp._tcp.local/?uuid=2a48000-80ce-11db-8c00-3c2af470c7c4' \
  'printer-info=Brother HL-L2370DN series' \
  'printer-state=3' > "$ATTR/lpoptions-Brother_HL_L2370DN_series"
printf 'printer-is-shared (boolean) = true\n' > "$ATTR/shared-Brother_HL_L2370DN_series"
# The reverse shape: CUPS holds the queue unshared, its PPD still carries a stale
# flag. The scheduler's answer must win.
printf 'printer-is-shared (boolean) = false\n' > "$ATTR/shared-HP_Laser_108w"
printf 'printer-is-shared=true\n' > "$ATTR/lpoptions-HP_Laser_108w"
# An unreadable attribute query must never be read as "shared" or as "not shared".
touch "$ATTR/ipptool-failure-TSC_TTP_244_Pro"

run_list
! /usr/bin/grep -q 'printer-is-shared' "$ATTR/lpoptions-Brother_HL_L2370DN_series" \
  || { printf 'FAIL: the Brother fixture must carry no shared flag in lpoptions\n' >&2; exit 1; }
/usr/bin/grep -qx 'rp=printers/Brother_HL_L2370DN_series' "$OUT/plan" \
  || { printf 'FAIL: a CUPS-shared queue was dropped because lpoptions had no flag\n' >&2; exit 1; }
printf 'PASS: a CUPS-shared queue is advertised even though lpoptions carries no shared flag\n'
! /usr/bin/grep -q 'rp=printers/HP_Laser_108w' "$OUT/plan" \
  || { printf 'FAIL: a stale lpoptions flag advertised a queue CUPS holds unshared\n' >&2; exit 1; }
printf 'PASS: the scheduler answer outranks a stale lpoptions flag\n'
! /usr/bin/grep -q 'rp=printers/TSC_TTP_244_Pro' "$OUT/plan" \
  || { printf 'FAIL: an unreadable sharing attribute still advertised the queue\n' >&2; exit 1; }
/usr/bin/grep -q 'could not read whether TSC_TTP_244_Pro is shared' "$OUT/plan.err" \
  || { printf 'FAIL: an unreadable sharing attribute was skipped silently\n' >&2; exit 1; }
printf 'PASS: an unreadable sharing attribute is skipped and said out loud, never guessed\n'
export PRINTER_STUDIO_FIXTURES="$OUT"

printf 'Artifacts retained: %s\n' "$OUT"
