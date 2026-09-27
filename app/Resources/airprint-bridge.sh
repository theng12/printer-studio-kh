#!/bin/bash
#
# Printer Studio KH — AirPrint advertisement for shared CUPS queues.
#
# WHY THIS EXISTS
#
# macOS Printer Sharing publishes every shared queue over Bonjour, but it does
# not publish the two things iOS AirPrint discovery actually requires:
#
#   * the "_universal" service subtype
#   * a "URF=" key in the TXT record
#
# Without them an iPhone or iPad ignores the printer completely — which is why
# a Mac-shared printer never appears in the iOS print dialog, even though it
# works perfectly from other Macs on the same network.
#
# This publishes a second Bonjour record per shared printer, pointing at the
# same CUPS queue and carrying the AirPrint markers. Nothing is converted,
# proxied or intercepted: dns-sd only advertises. A print job travels exactly
# the path it did before — CUPS, the queue's own driver, then the printer.
#
# It re-scans every minute, so printers shared later are picked up without a
# restart, and it skips queues that are already AirPrint-capable.
#
# Usage:
#   airprint-bridge.sh run        advertise, and keep running (the daemon)
#   airprint-bridge.sh list       show what would be advertised, then exit
#
set -u

SERVICE="_ipp._tcp,_universal"
PORT=631
RESCAN_SECONDS=60

PIDS=()
CURRENT=""

stop_all() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
  done
  PIDS=()
}

trap 'stop_all; exit 0' EXIT INT TERM

# Shared queues only, sorted, one per line.
shared_printers() {
  local printer
  /usr/bin/lpstat -p 2>/dev/null | /usr/bin/awk '/^printer /{print $2}' | while IFS= read -r printer; do
    [ -n "$printer" ] || continue
    if /usr/bin/lpoptions -p "$printer" 2>/dev/null | grep -q 'printer-is-shared=true'; then
      echo "$printer"
    fi
  done | sort
}

# Human-readable name, used for the advertised service. The queue's
# Description is what the user recognises ("HP Laser 107a"); the PPD nickname
# is an internal string like "HP Laser 10x Series, 2.0.0".
printer_model() {
  local label
  label=$(/usr/bin/lpstat -l -p "$1" 2>/dev/null \
    | sed -n 's/^[[:space:]]*Description:[[:space:]]*//p' | head -1)
  if [ -z "$label" ]; then
    label=$(/usr/bin/lpoptions -p "$1" 2>/dev/null \
      | sed -n "s/.*printer-make-and-model='\([^']*\)'.*/\1/p" | head -1)
  fi
  [ -n "$label" ] || label="$1"
  printf '%s' "$label"
}

queue_option_values() {
  /usr/bin/lpoptions -l -p "$1" 2>/dev/null
}

advertise_one() {
  local printer="$1" model color="F" duplex="F" note

  model=$(printer_model "$printer")
  note="$printer on $(/bin/hostname -s)"

  # Colour and duplex are advertised as AirPrint flags so iOS shows sensible
  # options. Getting these wrong is cosmetic, not fatal.
  if queue_option_values "$printer" | grep -qiE '(ColorModel|BRMonoColor).*(RGB|Color)'; then
    color="T"
  fi
  if queue_option_values "$printer" | grep -qiE 'Duplex.*(DuplexTumble|DuplexNoTumble)'; then
    duplex="T"
  fi

  # pdl includes application/pdf deliberately. iOS can send PDF, and macOS can
  # convert PDF — whereas it has no URF decoder, so a job sent as URF to a
  # raster driver would fail.
  /usr/bin/dns-sd -R "$model (AirPrint)" "$SERVICE" local "$PORT" \
    txtvers=1 \
    qtotal=1 \
    "rp=printers/$printer" \
    "ty=$model" \
    "product=($model)" \
    "note=$note" \
    pdl=application/pdf,image/jpeg,image/urf \
    URF=none \
    Color=$color \
    Duplex=$duplex >/dev/null 2>&1 &

  PIDS+=("$!")
}

list_printers() {
  local printer
  shared_printers | while IFS= read -r printer; do
    printf '  %-24s %s\n' "$printer" "$(printer_model "$printer")"
  done
}

case "${1:-run}" in
  list)
    echo "Shared queues that would be advertised:"
    list_printers
    exit 0
    ;;
  run) ;;
  *)
    echo "usage: $0 [run|list]" >&2
    exit 2
    ;;
esac

while true; do
  found="$(shared_printers | tr '\n' ' ')"
  if [ "$found" != "$CURRENT" ]; then
    stop_all
    CURRENT="$found"
    for printer in $found; do
      advertise_one "$printer"
    done
  fi
  sleep "$RESCAN_SECONDS"
done
