#!/bin/bash
# Advertise every shared CUPS queue using the working 1.0.4 registration.
# A macOS Printer Sharing record is not proof that an iPhone can see a queue.
# Keep the CUPS queue identity across advertisements without suppressing labels.
set -u

SERVICE="_ipp._tcp,_universal"
PORT=631
RESCAN_SECONDS="${PRINTER_STUDIO_RESCAN_SECONDS:-60}"
TOOL_DIR="${PRINTER_STUDIO_TOOL_DIR:-}"
LPSTAT="${TOOL_DIR:-/usr/bin}/lpstat"
LPOPTIONS="${TOOL_DIR:-/usr/bin}/lpoptions"
DNSSD="${TOOL_DIR:-/usr/bin}/dns-sd"
CUPSCTL="${TOOL_DIR:-/usr/sbin}/cupsctl"
IPPTOOL="${TOOL_DIR:-/usr/bin}/ipptool"
HOSTNAME="${TOOL_DIR:-/bin}/hostname"
PIDS=()
CURRENT=""

stop_all() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
  done
  # Wait for DNSServiceRegister connections to close before replacing their records.
  for pid in "${PIDS[@]:-}"; do
    [ -n "$pid" ] && wait "$pid" 2>/dev/null
  done
  PIDS=()
}
trap 'stop_all; exit 0' EXIT INT TERM

sharing_enabled() {
  "$CUPSCTL" 2>/dev/null | /usr/bin/grep -q '^_share_printers=1$'
}

shared_printers() {
  local printer
  "$LPSTAT" -p 2>/dev/null | /usr/bin/awk '/^printer /{print $2}' | while IFS= read -r printer; do
    [ -n "$printer" ] || continue
    if "$LPOPTIONS" -p "$printer" 2>/dev/null | /usr/bin/grep -q 'printer-is-shared=true'; then
      printf '%s\n' "$printer"
    fi
  done | /usr/bin/sort
}

printer_model() {
  local label
  label=$("$LPSTAT" -l -p "$1" 2>/dev/null \
    | /usr/bin/sed -n 's/^[[:space:]]*Description:[[:space:]]*//p' | /usr/bin/head -1)
  if [ -z "$label" ]; then
    label=$("$LPOPTIONS" -p "$1" 2>/dev/null \
      | /usr/bin/sed -n "s/.*printer-make-and-model='\([^']*\)'.*/\1/p" | /usr/bin/head -1)
  fi
  [ -n "$label" ] || label="$1"
  printf '%s' "$label"
}

queue_flags() {
  # Select the queue before -l; labels such as "Color Mode" are not values.
  "$LPOPTIONS" -p "$1" -l 2>/dev/null | /usr/bin/awk '
    {
      pos = index($0, ": ")
      if (!pos) next
      key = substr($0, 1, pos - 1); sub(/\/.*/, "", key)
      value = substr($0, pos + 2)
      if (key == "ColorModel" || key == "BRMonoColor") color = value
      if (key == "Duplex") duplex = value
    }
    END { printf "%s|%s", color ~ /RGB|CMYK/ ? "T" : "F", duplex ~ /DuplexTumble|DuplexNoTumble/ ? "T" : "F" }'
}

queue_uuid() {
  local attributes uuid
  if attributes=$("$IPPTOOL" -tv "ipp://localhost/printers/$1" get-printer-attributes.test 2>/dev/null); then
    uuid=$(printf '%s\n' "$attributes" | /usr/bin/awk '$1 == "printer-uuid" && $3 == "=" {print $4; exit}')
    uuid="${uuid#urn:uuid:}"
    if [[ "$uuid" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
      printf '%s' "$uuid" | /usr/bin/tr '[:upper:]' '[:lower:]'
      return 0
    fi
  fi
  printf 'AirPrint: no valid CUPS printer-uuid for %s; keeping its legacy advertisement.\n' "$1" >&2
  return 1
}

advertisement_args() {
  local printer="$1" model flags uuid
  model=$(printer_model "$printer")
  flags=$(queue_flags "$printer")
  # Keep the legacy instance suffix, TXT keys, note, format list and URF marker.
  printf '%s\n' '-R' "$model (AirPrint)" "$SERVICE" 'local' "$PORT" \
    'txtvers=1' 'qtotal=1' "rp=printers/$printer" "ty=$model" \
    "product=($model)" "note=$printer on $("$HOSTNAME" -s)" \
    'pdl=application/pdf,image/jpeg,image/urf' 'URF=none' \
    "Color=${flags%%|*}" "Duplex=${flags#*|}"
  # Match CUPS Printer Sharing and every interface using the queue's actual UUID.
  if uuid=$(queue_uuid "$printer"); then
    printf '%s\n' "UUID=$uuid"
  fi
}

advertise_one() {
  local printer="$1" line args=()
  while IFS= read -r line; do args+=("$line"); done < <(advertisement_args "$printer")
  "$DNSSD" "${args[@]}" >/dev/null 2>&1 &
  PIDS+=("$!")
}

case "${1:-run}" in
  list)
    if sharing_enabled; then
      while IFS= read -r printer; do
        [ -n "$printer" ] || continue
        printf 'Shared queue: %s\n' "$printer"
        advertisement_args "$printer"
      done < <(shared_printers)
    else
      printf 'Printer Sharing is off, so nothing would be advertised.\n'
    fi
    exit 0 ;;
  run) ;;
  *) printf 'usage: %s [run|list]\n' "$0" >&2; exit 2 ;;
esac

while true; do
  found=""
  queues=""
  if sharing_enabled; then
    queues=$(shared_printers)
    # Compare only what we register, so a saved name or capability change refreshes it.
    found=$(while IFS= read -r printer; do
      [ -n "$printer" ] && advertisement_args "$printer"
    done <<< "$queues")
  fi
  if [ "$found" != "$CURRENT" ]; then
    stop_all
    CURRENT="$found"
    while IFS= read -r printer; do
      [ -n "$printer" ] && advertise_one "$printer"
    done <<< "$queues"
  fi
  /bin/sleep "$RESCAN_SECONDS"
done
