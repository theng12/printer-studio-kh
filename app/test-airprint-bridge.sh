#!/bin/bash
# Offline registration checks; only stand-in tools and this test's children run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/../_trash/test-airprint-discovery-$(/bin/date +%Y%m%d-%H%M%S)-$$"
/bin/mkdir -p "$OUT/tools" "$OUT/home"
export PRINTER_STUDIO_TOOL_DIR="$OUT/tools" PRINTER_STUDIO_FIXTURES="$OUT"
export PRINTER_STUDIO_RESCAN_SECONDS=1 HOME="$OUT/home"
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
printf 'printer-uuid (uri) = urn:uuid:test-queue\n'
MOCK
cat > "$OUT/tools/dns-sd" <<'MOCK'
#!/bin/bash
case "$1" in
-R)
  queue=''
  for arg in "$@"; do case "$arg" in rp=printers/*) queue="${arg#rp=printers/}" ;; esac; done
  printf '%s\n' "$@" > "$PRINTER_STUDIO_FIXTURES/registered-$queue"
  exec /bin/sleep 30 ;;
-B)
  printf '%s\n' '15:00:00 Add 2 12 local. _ipp._tcp. TSC TTP-244 Pro @ kt-pdt-imac-m1-8-256' '15:00:00 Add 2 12 local. _ipp._tcp. Xprinter XP-D463B @ kt-pdt-imac-m1-8-256' ;;
-L)
  case "$2" in TSC*) queue=TSC_TTP_244_Pro ;; *) queue=Xprinter_XP_D463B ;; esac
  printf '%s\n' "$2._ipp._tcp.local. can be reached at kt-pdt-imac-m1-8-256.local.:631 (interface 12)" "txtvers=1 rp=printers/$queue UUID=test-queue pdl=application/pdf" ;;
esac
MOCK
/bin/chmod 755 "$OUT/tools/"*
printf 'TSC TTP-244 Pro\n' > "$OUT/tsc-name"
printf '_share_printers=1\n' > "$OUT/sharing"
bridge_pid=''
trap '[ -z "$bridge_pid" ] || /bin/kill "$bridge_pid" 2>/dev/null || true' EXIT
/bin/bash "$ROOT/Resources/airprint-bridge.sh" run > "$OUT/bridge.log" 2>&1 &
bridge_pid=$!
/bin/sleep 2
for queue in TSC_TTP_244_Pro Xprinter_XP_D463B; do
  /usr/bin/diff -u "$ROOT/Tools/Fixtures/airprint-1.0.4-$queue.txt" "$OUT/registered-$queue"
done
printf 'PASS: exact 1.0.4 label registration argv, names, subtype, port and all TXT fields\n'
[ -s "$OUT/registered-Brother_HL_L2370DN_series" ]
printf 'PASS: every shared queue is advertised; existing LAN records do not suppress labels or Brother\n'
# A rename must update the same registration without LAN scans or temporary plans.
printf 'TSC label desk\n' > "$OUT/tsc-name"
/bin/sleep 2
/usr/bin/grep -qxF 'TSC label desk (AirPrint)' "$OUT/registered-TSC_TTP_244_Pro"
printf 'PASS: registration follows a saved printer name\n'
/bin/kill "$bridge_pid"
wait "$bridge_pid" || true
bridge_pid=''
for file in "$OUT"/registered-*; do /bin/mv "$file" "$file.before-sharing-off"; done
printf '_share_printers=0\n' > "$OUT/sharing"
/bin/bash "$ROOT/Resources/airprint-bridge.sh" run > "$OUT/sharing-off.log" 2>&1 &
bridge_pid=$!
/bin/sleep 2
[ ! -e "$OUT/registered-TSC_TTP_244_Pro" ]
[ ! -e "$OUT/registered-Xprinter_XP_D463B" ]
/bin/kill "$bridge_pid"
wait "$bridge_pid" || true
bridge_pid=''
printf 'PASS: sharing-off guard prevents advertisements pointing at a closed service\n'
printf 'Artifacts retained: %s\n' "$OUT"
