#!/bin/sh
# printer-studio-print-cmd.sh
#
# Invoked once per IPP job by `ippeveprinter -c ...`. Convention:
# - argv[1] (if present) = absolute path to the spooled document
# - file extension reflects ippeveprinter's content-type: .pdf, .pwg, .urf, .jpg
# - stderr is logged by ippeveprinter; keep it human-readable
# - non-zero exit fails the job
#
# This wrapper:
#   1. Detects the spooled document's format from its extension
#   2. If it's not already PWG-Raster, converts it via `cupsfilter`
#      (which uses the CUPS filter chain: cgpdftoraster, etc.)
#   3. Invokes `printer-studio print-job` on the (possibly converted) file
#   4. Optionally transmits to USB if PRINTER_STUDIO_TRANSMIT=1
#
# Why the wrapper exists at all: `ippeveprinter -c` doesn't let us pass
# subcommand args to the binary it calls.

set -eu

# Resolve the printer-studio binary alongside this script.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRINTER_STUDIO=""
for cand in \
    "$SCRIPT_DIR/../printer-studio" \
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

DUMP_DIR="${PRINTER_STUDIO_DRY_RUN_DIR:-/tmp/printer-studio-jobs}"
mkdir -p "$DUMP_DIR" 2>/dev/null || true
JOB_TAG="job-$(date +%Y%m%d-%H%M%S)-$$"

# Working scratch space, cleaned up on exit.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

INPUT="${1:-}"

# Step 1 — figure out what we got and convert to PWG-Raster if needed.
if [ -n "$INPUT" ] && [ -f "$INPUT" ]; then
    EXT="$(printf '%s' "$INPUT" | awk -F. '{print tolower($NF)}')"
    case "$EXT" in
        pwg)
            echo "printer-studio-print-cmd: input is PWG-Raster ($INPUT)" >&2
            CONVERTED="$INPUT"
            ;;
        pdf|urf|jpg|jpeg|ps)
            CONVERTED="$WORK/job.pwg"
            echo "printer-studio-print-cmd: converting $EXT → PWG-Raster via cupsfilter" >&2
            if ! /usr/bin/cupsfilter -m image/pwg-raster "$INPUT" \
                    > "$CONVERTED" 2> "$WORK/cupsfilter.err" ; then
                echo "cupsfilter conversion failed:" >&2
                cat "$WORK/cupsfilter.err" >&2
                # Save the original for forensics.
                cp "$INPUT" "$DUMP_DIR/$JOB_TAG.input.$EXT" 2>/dev/null || true
                exit 1
            fi
            echo "printer-studio-print-cmd: converted $(stat -f%z "$INPUT") byte $EXT into $(stat -f%z "$CONVERTED") byte PWG-Raster" >&2
            # Keep a copy of the converted PWG for inspection.
            cp "$CONVERTED" "$DUMP_DIR/$JOB_TAG.converted.pwg" 2>/dev/null || true
            ;;
        *)
            echo "printer-studio-print-cmd: unknown extension .$EXT — assuming PWG-Raster" >&2
            CONVERTED="$INPUT"
            ;;
    esac
else
    # No file argument — stdin path. printer-studio reads PWG-Raster from
    # stdin directly. Save a copy for inspection.
    CONVERTED="$WORK/job-stdin.pwg"
    cat > "$CONVERTED"
    echo "printer-studio-print-cmd: read $(stat -f%z "$CONVERTED") bytes from stdin" >&2
fi

# Step 2 — build the print-job invocation.
ARGS="print-job --dry-run-out $DUMP_DIR/$JOB_TAG.spl"
if [ "${PRINTER_STUDIO_TRANSMIT:-0}" = "1" ]; then
    ARGS="$ARGS --i-know-what-im-doing"
fi
ARGS="$ARGS $CONVERTED"

echo "printer-studio-print-cmd: $PRINTER_STUDIO $ARGS" >&2
exec "$PRINTER_STUDIO" $ARGS
