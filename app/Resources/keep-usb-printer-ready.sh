#!/bin/bash
# Runs as root from launchd. Release only a supported USB printer whose serial
# is already configured in CUPS; other IPP-over-USB printers stay untouched.
set -euo pipefail

queues=$(/usr/bin/lpstat -v 2>/dev/null) || exit 1
pids=$(/usr/bin/pgrep -x ippusbd) || exit 0
for pid in $pids; do
  executable=$(/bin/ps -p "$pid" -o comm=) || continue
  [ "$executable" = /usr/libexec/ippusbd ] || continue
  command=$(/bin/ps -p "$pid" -o args=) || continue
  case "$command" in
    '/usr/libexec/ippusbd usb://HP%20Inc./HP%20Laser%20107a?serial='*) ;;
    *) continue ;;
  esac
  serial=${command#*?serial=}
  # A serial is an opaque USB identifier, never shell input or a regex.
  case "$serial" in ''|*[!a-zA-Z0-9_-]*) continue ;; esac
  if printf '%s\n' "$queues" | /usr/bin/awk -v serial="$serial" '
    /^device for / {
      uri=$NF
      if (uri == "usb://HP/HP%20Laser%20103%20107%20108?serial=" serial) found=1
    }
    END { exit !found }
  '; then
    # Recheck the command before signalling, in case the process exited.
    [ "$(/bin/ps -p "$pid" -o args=)" = "$command" ] || continue
    /bin/kill -TERM "$pid"
    echo 'Released the configured HP Laser 107a from IPP-over-USB.'
  fi
done
