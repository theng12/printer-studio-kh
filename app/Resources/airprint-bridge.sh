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
# This publishes a Bonjour record per shared queue, pointing at the same CUPS
# queue and carrying the AirPrint markers. Nothing is converted, proxied or
# intercepted: dns-sd only advertises. A print job travels exactly the path it
# did before — CUPS, the queue's own driver, then the printer.
#
# ONE ENTRY PER PHYSICAL PRINTER
#
# A network printer that already reaches the phone — the printer advertising
# itself, or another Mac's CUPS advertising the queue as AirPrint — must not
# be advertised a second time, or the phone shows that printer twice. So
# before advertising a network queue the script looks on the LAN for a
# record for the same printer (its own UUID) or an AirPrint record for the
# same queue, and leaves that queue alone when one exists. The native record
# wins: it is the printer's own.
#
# A USB queue is never skipped: nothing on the LAN advertises it, so the
# phone can only reach it through this Mac's CUPS.
#
# Usage:
#   airprint-bridge.sh run        advertise, and keep running (the daemon)
#   airprint-bridge.sh list       show what would be advertised, then exit
#
set -u

SERVICE="_ipp._tcp,_universal"
PORT=631
# The timings can be shortened by the test suite through the environment.
RESCAN_SECONDS="${PRINTER_STUDIO_RESCAN_SECONDS:-60}"
BROWSE_SECONDS="${PRINTER_STUDIO_BROWSE_SECONDS:-2}"
RESOLVE_SECONDS="${PRINTER_STUDIO_RESOLVE_SECONDS:-2}"
MAX_RESOLVES=12
# Marks our own records so the LAN scan can tell them from a printer's.
MARK_KEY="psbridge"

# The tools this script drives. PRINTER_STUDIO_TOOL_DIR points them at mock
# binaries in the test suite; unset, they are the real system tools.
TOOL_DIR="${PRINTER_STUDIO_TOOL_DIR:-}"
if [ -n "$TOOL_DIR" ]; then
  LPSTAT="$TOOL_DIR/lpstat"
  LPOPTIONS="$TOOL_DIR/lpoptions"
  IPPTOOL="$TOOL_DIR/ipptool"
  DNSSD="$TOOL_DIR/dns-sd"
  CUPSCTL="$TOOL_DIR/cupsctl"
  SCUTIL="$TOOL_DIR/scutil"
  HOSTNAME="$TOOL_DIR/hostname"
else
  LPSTAT="/usr/bin/lpstat"
  LPOPTIONS="/usr/bin/lpoptions"
  IPPTOOL="/usr/bin/ipptool"
  DNSSD="/usr/bin/dns-sd"
  CUPSCTL="/usr/sbin/cupsctl"
  SCUTIL="/usr/sbin/scutil"
  HOSTNAME="/bin/hostname"
fi

PIDS=()
CURRENT=""
TMP=""
PLAN=""
NATIVE=""
LOCAL_HOST=""
LOCAL_SHORT=""

stop_all() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
  done
  PIDS=()
}

cleanup() {
  stop_all
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then rm -rf "$TMP"; fi
}

trap 'cleanup; exit 0' EXIT INT TERM

# dns-sd never exits by itself, so every call is bounded: start it, wait a
# fixed time, stop it, and read what it printed. The wait is at least a
# second, so a tool that answers quickly is never killed mid-answer.
dnssd_capture() {
  local seconds="$1"; shift
  [ "$seconds" -lt 1 ] && seconds=1
  local out="$TMP/dnssd.$RANDOM"
  "$DNSSD" "$@" >"$out" 2>&1 &
  local pid=$!
  ( /bin/sleep "$seconds"; /bin/kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local killer=$!
  wait "$pid" 2>/dev/null
  /bin/kill "$killer" 2>/dev/null
  wait "$killer" 2>/dev/null
  cat "$out"
  rm -f "$out"
}

# Printer Sharing has to be on, or cupsd does not serve the LAN and a
# published record would point a phone at a port that refuses connections.
sharing_enabled() {
  "$CUPSCTL" 2>/dev/null | grep -q '^_share_printers=1$'
}

# Shared queues only, sorted, one per line.
shared_printers() {
  local printer
  "$LPSTAT" -p 2>/dev/null | /usr/bin/awk '/^printer /{print $2}' | while IFS= read -r printer; do
    [ -n "$printer" ] || continue
    if "$LPOPTIONS" -p "$printer" 2>/dev/null | grep -q 'printer-is-shared=true'; then
      echo "$printer"
    fi
  done | sort
}

# Human-readable name, used for the advertised service. The queue's
# Description is what the user recognises ("HP Laser 107a"); the PPD nickname
# is an internal string like "HP Laser 10x Series, 2.0.0".
printer_model() {
  local label
  label=$("$LPSTAT" -l -p "$1" 2>/dev/null \
    | sed -n 's/^[[:space:]]*Description:[[:space:]]*//p' | head -1)
  if [ -z "$label" ]; then
    label=$("$LPOPTIONS" -p "$1" 2>/dev/null \
      | sed -n "s/.*printer-make-and-model='\([^']*\)'.*/\1/p" | head -1)
  fi
  [ -n "$label" ] || label="$1"
  printf '%s' "$label"
}

# The queue's device URI, e.g. dnssd://Name._ipp._tcp.local./?uuid=...
device_uri() {
  local queue="$1" line name
  while IFS= read -r line; do
    case "$line" in
      "device for "*) ;;
      *) continue ;;
    esac
    name="${line#device for }"
    name="${name%%: *}"
    if [ "$name" = "$queue" ]; then
      printf '%s' "${line#*: }"
      return 0
    fi
  done < <("$LPSTAT" -v 2>/dev/null)
  return 1
}

# The UUID of the network device behind the queue, taken from a dnssd device
# URI. It is the identity that device publishes for itself.
device_uuid() {
  local uri rest
  uri="$(device_uri "$1")" || return 1
  case "$uri" in
    *dnssd://*uuid=*) ;;
    *) return 1 ;;
  esac
  rest="${uri##*uuid=}"
  printf '%s' "${rest%%[\?\&]*}"
}

# The UUID of the queue itself.
queue_uuid() {
  "$IPPTOOL" -tv "ipp://localhost/printers/$1" get-printer-attributes.test 2>/dev/null \
    | /usr/bin/awk '$1=="printer-uuid"{print $NF; exit}' | sed 's|^urn:uuid:||'
}

# Colour, duplex and the offered page sizes, in one call.
#
# The values are read from the option VALUE, never from the label:
# "ColorModel/Color Mode: *Gray" is monochrome, and a label-matching regex
# reads it as colour and advertises Color=T for a black-and-white printer.
queue_flags() {
  "$LPOPTIONS" -l -p "$1" 2>/dev/null | /usr/bin/awk '
    {
      pos = index($0, ": ")
      if (pos == 0) next
      key = substr($0, 1, pos - 1)
      sub(/\/.*/, "", key)
      value = substr($0, pos + 2)
      if (key == "ColorModel" || key == "BRMonoColor") color = value
      else if (key == "Duplex") duplex = value
      else if (key == "PageSize") media = media " " value
    }
    END {
      c = (color ~ /RGB|CMYK/) ? "T" : "F"
      d = (duplex ~ /DuplexTumble|DuplexNoTumble/) ? "T" : "F"
      printf "%s|%s|%s", c, d, media
    }'
}

# Instance names from a Bonjour browse, one per line.
#
# A browse of a subtype also lists the subtype's records, and dns-sd prints
# the parent type in the Service Type column, so the parent type is what the
# name is matched against.
browse_names() {
  local parent="$1" service="$2" out="$3"
  dnssd_capture "$BROWSE_SECONDS" -B "$service" local \
    | /usr/bin/awk -v base="$parent." '
      {
        for (i = 1; i <= NF; i++) {
          if ($i == base) {
            name = ""
            for (j = i + 1; j <= NF; j++) name = name (j > i + 1 ? " " : "") $j
            if (name != "") print name
            break
          }
        }
      }' | sort -u > "$out"
}

# Every record on the LAN that could be an AirPrint entry, one per line:
# "<host>|<rp>|<uuid>|<universal>|<pdl>".
#
# A record published by an older version of this script ends in " (AirPrint)"
# and is ours, not the printer's, so it is not evidence of anything. Our own
# records carry the marker key and are skipped the same way.
scan_native() {
  local parent name text host rp uuid pdl is_universal count=0
  NATIVE="$TMP/native"
  : > "$NATIVE"

  for parent in "_ipp._tcp" "_ipps._tcp"; do
    browse_names "$parent" "$parent" "$TMP/n.$parent"
    browse_names "$parent" "$parent,_universal" "$TMP/u.$parent"
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      [ "$count" -lt "$MAX_RESOLVES" ] || break
      count=$((count + 1))
      case "$name" in
        *" (AirPrint)"*) continue ;;
      esac
      text="$(dnssd_capture "$RESOLVE_SECONDS" -L "$name" "$parent" local)"
      case "$text" in
        *"$MARK_KEY="*) continue ;;
      esac
      host="$(printf '%s\n' "$text" | sed -n 's/.*can be reached at \([^.]*\)\.local\..*/\1/p' | head -1)"
      [ -n "$host" ] || continue
      rp="$(printf '%s\n' "$text" | grep -o 'rp=[^ ]*' | head -1)"
      uuid="$(printf '%s\n' "$text" | grep -o 'UUID=[^ ]*' | head -1)"
      pdl="$(printf '%s\n' "$text" | grep -o 'pdl=[^ ]*' | head -1)"
      if grep -qxF "$name" "$TMP/u.$parent"; then
        is_universal="yes"
      else
        is_universal="no"
      fi
      printf '%s|%s|%s|%s|%s\n' "$host" "${rp#rp=}" "${uuid#UUID=}" "$is_universal" "${pdl#pdl=}" >> "$NATIVE"
    done < "$TMP/n.$parent"
  done
}

# Is this queue already reaching the phone without us?
#
# Two kinds of evidence, and only two:
#
#   * the printer behind a dnssd queue advertises itself on the LAN, under
#     its own UUID — the phone can reach that printer directly, so a second
#     entry for it would be a duplicate;
#   * somebody already advertises this queue as AirPrint: a record for
#     printers/<queue> that carries the AirPrint markers (the "_universal"
#     subtype, a UUID, or image/pwg-raster in its pdl). That record is the
#     real one and is preferred over ours.
#
# A queue with no device UUID is a USB queue. Nothing advertises a USB queue
# by its device UUID, so the second rule is what covers it — and a queue that
# macOS advertises natively (it has an AirPrint driver) is exactly the one
# that must not be advertised twice.
covered_natively() {
  local queue="$1" dev_uuid="$2"
  local host rp uuid universal pdl
  while IFS='|' read -r host rp uuid universal pdl; do
    [ -n "$host" ] || continue
    # The printer itself advertises, under its own UUID.
    if [ -n "$dev_uuid" ] && [ -n "$uuid" ] && [ "$uuid" = "$dev_uuid" ]; then
      return 0
    fi
    if [ "$rp" = "printers/$queue" ]; then
      if [ "$universal" = "yes" ] || [ -n "$uuid" ] || case "$pdl" in *image/pwg-raster*) true;; *) false;; esac; then
        return 0
      fi
    fi
  done < "$NATIVE"
  return 1
}

# The plan: one line per shared queue, "queue|decision|name|colour|duplex|
# uuid|media". The whole plan is the fingerprint — a rename, a new page size
# or a queue that became natively advertised changes it, and that is what
# makes the advertisements be replaced instead of left stale.
build_plan() {
  local queue name flags color duplex media dev_uuid decision
  : > "$PLAN"
  while IFS= read -r queue; do
    [ -n "$queue" ] || continue
    name="$(printer_model "$queue")"
    flags="$(queue_flags "$queue")"
    color="${flags%%|*}"
    flags="${flags#*|}"
    duplex="${flags%%|*}"
    media="${flags#*|}"
    dev_uuid="$(device_uuid "$queue" 2>/dev/null)" || dev_uuid=""
    if covered_natively "$queue" "$dev_uuid"; then
      decision="skip"
    else
      decision="adv"
    fi
    printf '%s|%s|%s|%s|%s|%s|%s\n' \
      "$queue" "$decision" "$name" "$color" "$duplex" \
      "$(queue_uuid "$queue" 2>/dev/null)" "$media" >> "$PLAN"
  done < <(shared_printers)
}

# A short, stable hash of the plan. The advertisements are replaced when
# this changes, so a rename or a new page size takes effect.
plan_fingerprint() {
  /usr/bin/cksum < "$PLAN" | /usr/bin/awk '{print $1 "-" $2}'
}

# The dns-sd arguments for one queue, one per line on stdout.
#
# Both the advertisement and the "list" report come from here, so what the
# report shows is exactly what is published.
advertisement_args() {
  local queue="$1" name="$2" color="$3" duplex="$4" uuid="$5"
  printf '%s\n' "-R" "$name" "$SERVICE" "local" "$PORT" \
    "txtvers=1" \
    "qtotal=1" \
    "rp=printers/$queue" \
    "ty=$name" \
    "product=($name)" \
    "note=$name on $LOCAL_SHORT" \
    "pdl=application/pdf,image/jpeg" \
    "URF=none" \
    "$MARK_KEY=1" \
    "Color=$color" \
    "Duplex=$duplex"
  # The queue's own UUID, so the phone can tell this queue from another.
  [ -n "$uuid" ] && printf '%s\n' "UUID=$uuid"
  return 0
}

advertise_one() {
  local queue="$1" name="$2" color="$3" duplex="$4" uuid="$5"
  local args=()
  while IFS= read -r line; do
    args+=("$line")
  done < <(advertisement_args "$queue" "$name" "$color" "$duplex" "$uuid")
  "$DNSSD" "${args[@]}" >/dev/null 2>&1 &
  PIDS+=("$!")
}

advertise_plan() {
  local queue decision name color duplex uuid media
  while IFS='|' read -r queue decision name color duplex uuid media; do
    [ "$decision" = "adv" ] || continue
    advertise_one "$queue" "$name" "$color" "$duplex" "$uuid"
  done < "$PLAN"
}

list_printers() {
  local queue decision name color duplex uuid media args
  echo "Shared queues:"
  while IFS='|' read -r queue decision name color duplex uuid media; do
    if [ "$decision" = "adv" ]; then
      args=""
      while IFS= read -r line; do
        args="$args $line"
      done < <(advertisement_args "$queue" "$name" "$color" "$duplex" "$uuid")
      printf '  %s advertise %s\n' "$queue" "$name"
      printf '    args:%s\n' "$args"
    else
      printf '  %s skip      %s (already advertised natively)\n' "$queue" "$name"
    fi
  done < "$PLAN"
  echo "Fingerprint: $(plan_fingerprint)"
}

TMP="$(/usr/bin/mktemp -d)"
PLAN="$TMP/plan"
LOCAL_HOST="$("$SCUTIL" --get LocalHostName 2>/dev/null)"
LOCAL_SHORT="$("$HOSTNAME" -s 2>/dev/null)"

case "${1:-run}" in
  list)
    if sharing_enabled; then
      scan_native
      build_plan
      list_printers
    else
      echo "Printer Sharing is off, so nothing would be advertised."
    fi
    exit 0
    ;;
  run) ;;
  *)
    echo "usage: $0 [run|list]" >&2
    exit 2
    ;;
esac

while true; do
  if sharing_enabled; then
    scan_native
    build_plan
  else
    : > "$PLAN"
  fi
  fingerprint="$(plan_fingerprint)"
  if [ "$fingerprint" != "$CURRENT" ]; then
    stop_all
    CURRENT="$fingerprint"
    advertise_plan
  fi
  /bin/sleep "$RESCAN_SECONDS"
done
