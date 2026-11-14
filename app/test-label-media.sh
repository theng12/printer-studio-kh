#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$ROOT/../_trash/test-label-media-$(/bin/date +%Y%m%d-%H%M%S)-$$}"
/bin/mkdir -p "$OUT/bin" "$OUT/vendor/filter"
OUT="$(cd "$OUT" && pwd -P)"
SOURCES=()
while IFS= read -r file; do
  case "$(/usr/bin/basename "$file")" in App.swift|Views.swift|RenderFixtures.swift) continue ;; esac
  SOURCES+=("$file")
done < <(/usr/bin/find "$ROOT/Sources/PrinterStudio" -name '*.swift' | /usr/bin/sort)
/usr/bin/swiftc -parse-as-library -swift-version 5 "${SOURCES[@]}" "$ROOT/Tools/TestLabelRoute.swift" -o "$OUT/check-ppds"
"$OUT/check-ppds" "$OUT"
/usr/bin/clang -Wno-deprecated-declarations "$ROOT/Filters/label-options.c" -lcups -o "$OUT/bin/label-options"
/usr/bin/clang "$ROOT/Tools/CheckLabelRaster.c" -lcups -o "$OUT/check-raster"
/bin/cp "$ROOT/Filters/label-filter" "$OUT/bin/label-pdf"
/bin/cp "$ROOT/Filters/label-filter" "$OUT/bin/label-urf"
/bin/chmod 755 "$OUT/bin/label-pdf" "$OUT/bin/label-urf"
printf '#!/bin/bash\nexec /bin/cat\n' > "$OUT/vendor/filter/rastertosnailtspl-xprinter"
/bin/chmod 755 "$OUT/vendor/filter/rastertosnailtspl-xprinter"
export PPD="$OUT/xprinter-routed.ppd"
export CUPS_SERVERBIN="$OUT/vendor"
OPTIONS='media-col={media-size={x-dimension=4000 y-dimension=3000} media-right-margin=0 media-left-margin=0 media-top-margin=0 media-bottom-margin=0} copies=1 print-scaling=fit'
NORMALIZED="$("$OUT/bin/label-options" "$OPTIONS")"
case "$NORMALIZED" in *'PageSize=psz400x300-barcode PageRegion=psz400x300-barcode'*) ;; *) printf 'FAIL: media-col was not mapped to the PPD page\n'; exit 1 ;; esac
for INVALID in 'media-col={media-size={x-dimension=0 y-dimension=3000}}' 'media-col={media-size={x-dimension=4000}}' 'media-col={media-size={x-dimension=999999 y-dimension=3000}}' 'PageSize=missing' 'media=unrecognized-stock' 'PageSize=Custom.0x0'; do
  if "$OUT/bin/label-options" "$INVALID" > "$OUT/invalid-output.txt" 2> "$OUT/invalid-error.txt"; then
    printf 'FAIL: invalid media accepted\n'; exit 1
  fi
done
"$OUT/bin/label-pdf" 1 test synthetic 1 "$OPTIONS" "$OUT/synthetic.pdf" > "$OUT/pdf-40x30.raster" 2> "$OUT/pdf-40x30.log"
"$OUT/check-raster" "$OUT/pdf-40x30.raster" 40 30 203
CUSTOM='media-col={media-size={x-dimension=4500 y-dimension=6000}} copies=1 print-scaling=fit'
CUSTOM_NORMALIZED="$("$OUT/bin/label-options" "$CUSTOM")"
case "$CUSTOM_NORMALIZED" in *'PageSize=Custom.'*'x'*) ;; *) printf 'FAIL: custom dimensions lost\n'; exit 1 ;; esac
"$OUT/bin/label-pdf" 1 test synthetic 1 "$CUSTOM" "$OUT/synthetic.pdf" > "$OUT/pdf-custom.raster" 2> "$OUT/pdf-custom.log"
"$OUT/check-raster" "$OUT/pdf-custom.raster" 45 60 203
NAMED="$("$OUT/bin/label-options" 'media=custom_50x70mm_50x70mm copies=1')"
case "$NAMED" in *'PageSize=psz500x700-50x70'*) ;; *) printf 'FAIL: IPP named media not mapped\n'; exit 1 ;; esac
/bin/cp "$OUT/bin/label-urf" "$OUT/bin/label-pdf" "$OUT/bin/label-options" "$OUT/vendor/filter/"
/usr/bin/sed 's|/Library/Printers/PrinterStudio/Filters/label-|label-|g' "$PPD" > "$OUT/local-routed.ppd"
for FORMAT in image/urf application/pdf; do
  /usr/sbin/cupsfilter --list-filters -e -p "$OUT/local-routed.ppd" -i "$FORMAT" -m printer/label "$OUT/synthetic.pdf" > "$OUT/route-${FORMAT##*/}.txt" 2> "$OUT/route-${FORMAT##*/}.log"
done
/usr/bin/grep -q 'label-urf' "$OUT/route-urf.txt"
/usr/bin/grep -q 'label-pdf' "$OUT/route-pdf.txt"
if /usr/bin/grep -q 'cgimagetopdf' "$OUT/route-urf.txt"; then printf 'FAIL: URF still enters the image-to-PDF filter\n'; exit 1; fi
printf 'PASS: job 2244 media-col maps to 40x30mm; one PDF raster page at 203dpi; scoped URF/PDF routes\n'
printf 'Artifacts retained: %s\n' "$OUT"
