#!/bin/bash
# Read local state and Bonjour replies. Only the new report folder is written.
set -u
APP="${1:-/Applications/Printer Studio KH.app}"
STAMP=$(/bin/date +%Y%m%d-%H%M%S)
OUT="$HOME/Desktop/All YouTube Stuff/Apps/Printer Studio KH/Discovery check $STAMP-$$"
/bin/mkdir -p "$OUT" || exit 1
REPORT="$OUT/iMac discovery.txt"

capture_dns() {
  # A pseudo-terminal keeps dns-sd replies from being buffered until after timeout.
  /usr/bin/script -q /dev/null /bin/bash -c '
    /usr/bin/dns-sd "$@" &
    pid=$!
    ( /bin/sleep 4; /bin/kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    timer=$!
    wait "$pid" 2>/dev/null || true
    /bin/kill "$timer" 2>/dev/null || true
    wait "$timer" 2>/dev/null || true
  ' printer-studio-dns "$@" < /dev/null
  printf '[lookup ended after at most 4 seconds; no reply means not observed]\n'
}

report() {
  printf 'Printer Studio KH — read-only iMac discovery check\n'
  /bin/date -u '+Collected: %Y-%m-%d %H:%M:%S UTC'
  printf 'iPhone visibility: NOT CHECKED by this report.\n'
  printf 'No sharing, agent, printer or security setting is changed; no print job is sent.\n\n'
  /usr/bin/sw_vers
  printf '\nMac: '
  /bin/hostname
  printf '\nApp: %s\n' "$APP"
  for key in CFBundleShortVersionString CFBundleVersion; do
    printf '%s: ' "$key"
    /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Contents/Info.plist" 2>&1 || true
  done
  local installed="$HOME/Library/Application Support/PrinterStudio/airprint-bridge.sh"
  local bundled="$APP/Contents/Resources/airprint-bridge.sh"
  printf '\nInstalled bridge: %s\nBundled bridge: %s\n' "$installed" "$bundled"
  if [ -r "$installed" ] && [ -r "$bundled" ]; then
    if /usr/bin/cmp -s "$installed" "$bundled"; then
      printf 'Script match: YES (byte for byte)\n'
    else
      printf 'Script match: NO — installed agent may be using another version\n'
    fi
    /usr/bin/shasum -a 256 "$installed" "$bundled"
    /usr/bin/stat -f 'Script modified: %Sm — %N' -t '%Y-%m-%d %H:%M:%S %z' "$installed"
  else
    printf 'Script match: NOT CHECKED — a script is missing or unreadable\n'
  fi
  printf '\nAirPrint agent (current logged-in user)\n'
  local agent pid
  agent=$(/bin/launchctl print "gui/$(/usr/bin/id -u)/com.theng12.printerstudio.airprint" 2>&1)
  if [ "$?" -eq 0 ]; then
    printf '%s\n' "$agent" | /usr/bin/awk '/^[[:space:]]*(path|state|pid|runs|last exit code) =/ {print}'
    pid=$(printf '%s\n' "$agent" | /usr/bin/awk '$1 == "pid" && $2 == "=" {print $3; exit}')
    case "$pid" in
      ''|*[!0-9]*) printf 'Agent start: NOT CHECKED — no running PID\n' ;;
      *) printf 'Agent process start (Mac local time), elapsed time and executable:\n'
         /bin/ps -p "$pid" -o lstart= -o etime= -o comm= ;;
    esac
  else
    printf 'Agent: not loaded or not readable for this user\n'
  fi
  printf '\nPrinter Sharing (read only)\n'
  /usr/sbin/cupsctl 2>&1 | /usr/bin/grep -E '^(_share_printers|_remote_any|_remote_admin)=' || true
  printf '\nQueues\n'
  /usr/bin/lpstat -p 2>&1 || true
  printf '\nUniversal subtype records (raw PTR replies)\n'
  capture_dns -Q _universal._sub._ipp._tcp.local. PTR
  local queue description host
  host=$(/usr/sbin/scutil --get LocalHostName 2>/dev/null)
  for queue in TSC_TTP_244_Pro Xprinter_XP_D463B; do
    description=$(/usr/bin/lpstat -l -p "$queue" 2>/dev/null | /usr/bin/sed -n 's/^[[:space:]]*Description:[[:space:]]*//p' | /usr/bin/head -1)
    if [ -z "$description" ]; then
      case "$queue" in TSC*) description='TSC TTP-244 Pro' ;; *) description='Xprinter XP-D463B' ;; esac
      printf '\nQueue %s: description unavailable; looking up its last recorded name\n' "$queue"
    else
      printf '\nQueue %s — %s\n' "$queue" "$description"
    fi
    printf '\n1.0.4/restored bridge instance: %s (AirPrint)\n' "$description"
    capture_dns -L "$description (AirPrint)" _ipp._tcp local.
    printf '\n1.0.5–1.0.8 bridge instance: %s\n' "$description"
    capture_dns -L "$description" _ipp._tcp local.
    if [ -n "$host" ]; then
      printf '\nmacOS Printer Sharing instance: %s @ %s\n' "$description" "$host"
      capture_dns -L "$description @ $host" _ipp._tcp local.
    fi
  done
  printf '\nTXT above is the raw resolved DNS-SD output, not a bridge preview.\n'
  printf 'A reply on this Mac does not prove visibility on the iPhone.\n'
  printf 'iPhone visibility remains NOT CHECKED until the owner sees the printers.\n'
}
report 2>&1 | /usr/bin/tee "$REPORT"
printf '\nReport saved: %s\n' "$REPORT"
