#!/bin/sh
# printer-studio-print-cmd.sh
#
# Invoked once per IPP job by `ippeveprinter -c ...`. The convention is:
# - argv[1] (if present) is the path to the spooled document
# - otherwise the document is on stdin
# - env vars carry job metadata: IPP_JOB_NAME, IPP_REQUESTING_USER_NAME,
#   IPP_DOCUMENT_FORMAT, CONTENT_TYPE, DEVICE_URI, ...
# - stderr is logged by ippeveprinter; keep it human-readable
# - non-zero exit fails the job
#
# This wrapper exists because `ippeveprinter -c` doesn't allow passing
# subcommand args — we need to inject `print-job` ourselves.

set -eu

# Resolve the binary next to this script (release build preferred, debug fallback).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRINTER_STUDIO=""
for cand in \
    "$SCRIPT_DIR/../target/release/printer-studio" \
    "$SCRIPT_DIR/../target/debug/printer-studio" \
    "$SCRIPT_DIR/printer-studio" ; do
    if [ -x "$cand" ]; then
        PRINTER_STUDIO="$cand"
        break
    fi
done
if [ -z "$PRINTER_STUDIO" ]; then
    echo "printer-studio-print-cmd: cannot find printer-studio binary near $SCRIPT_DIR" >&2
    exit 1
fi

# Per-job dry-run dump for debugging. Override with PRINTER_STUDIO_DRY_RUN_DIR=
# in the LaunchAgent plist. Empty value = no dump.
DUMP_DIR="${PRINTER_STUDIO_DRY_RUN_DIR:-/tmp/printer-studio-jobs}"
mkdir -p "$DUMP_DIR" 2>/dev/null || true
JOB_TAG="job-$(date +%Y%m%d-%H%M%S)-$$"

ARGS="print-job --dry-run-out $DUMP_DIR/$JOB_TAG.spl"

# Pass through "transmit for real" if explicitly opted-in via env. Leave OFF
# by default until Phase 1b encoder validation is done.
if [ "${PRINTER_STUDIO_TRANSMIT:-0}" = "1" ]; then
    ARGS="$ARGS --i-know-what-im-doing"
fi

# Optional input file (ippeveprinter passes path as $1 for some PDLs)
if [ $# -gt 0 ] && [ -f "$1" ]; then
    ARGS="$ARGS $1"
fi

echo "printer-studio-print-cmd: $PRINTER_STUDIO $ARGS" >&2
exec "$PRINTER_STUDIO" $ARGS
