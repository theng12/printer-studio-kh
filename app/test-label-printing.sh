#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/test-label-printing.XXXXXX")"
OUT="$(cd "$OUT" && pwd -P)"
/bin/bash "$ROOT/test-label-media.sh" "$OUT/media"
/bin/bash "$ROOT/test-urf-to-pdf.sh" "$OUT/urf" "$OUT/media/xprinter-routed.ppd"
/bin/cp "$OUT/urf/bin/urftopdf" "$OUT/media/vendor/filter/urftopdf"
export CUPS_SERVERBIN="$OUT/media/vendor"
for sample_name in asymmetric-50x70mm-203dpi-mono asymmetric-50x70mm-203dpi-1bit asymmetric-50x70mm-203dpi-w8 asymmetric-50x70mm-300dpi-mono asymmetric-50x70mm-300dpi-rgb; do
  /usr/sbin/cupsfilter -e -p "$OUT/media/local-routed.ppd" -i image/urf -m printer/label \
    -o 'media-col={media-size={x-dimension=5000 y-dimension=7000}}' -o print-scaling=fit \
    "$OUT/urf/fixtures/$sample_name.urf" > "$OUT/$sample_name-vendor-input.raster" 2> "$OUT/$sample_name-route.log"
  "$OUT/media/check-raster" "$OUT/$sample_name-vendor-input.raster" 50 70 203
  "$OUT/urf/bin/TestURFToPDF" verify-rendered-raster "$OUT/$sample_name-vendor-input.raster" 400 559 203
done
/usr/sbin/cupsfilter -e -p "$OUT/media/local-routed.ppd" -i application/pdf -m printer/label \
  -o 'media-col={media-size={x-dimension=4000 y-dimension=3000}}' -o print-scaling=fit \
  "$OUT/media/synthetic.pdf" > "$OUT/job2244-media-vendor-input.raster" 2> "$OUT/job2244-media-route.log"
"$OUT/media/check-raster" "$OUT/job2244-media-vendor-input.raster" 40 30 203
printf 'PASS: selected CUPS routes deliver complete, correctly-sized monochrome 203dpi rasters to the vendor slot\n'
printf 'Vendor slot is a byte-capture stub; physical iPhone output remains NOT CHECKED.\n'
printf 'Artifacts retained: %s\n' "$OUT"
