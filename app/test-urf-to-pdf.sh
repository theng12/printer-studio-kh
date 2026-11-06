#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$ROOT/../_trash/urf-tests-$(/bin/date +%Y%m%d-%H%M%S)-$$}"
PPD_PATH="${2:-${PPD_PATH:-}}"
if [ ! -r "$PPD_PATH" ]; then
  printf 'A readable label PPD is required as argument 2 (test-label-media.sh generates one).\n' >&2
  exit 1
fi
/bin/mkdir -p "$OUT/bin" "$OUT/fixtures" "$OUT/output"
OUT="$(cd "$OUT" && pwd -P)"
/usr/bin/clang -O2 -Wall -Wextra -Werror -mmacosx-version-min=13.0 -arch arm64 -arch x86_64 \
  "$ROOT/Filters/urftopdf.c" -lcups -framework CoreGraphics -framework CoreFoundation -o "$OUT/bin/urftopdf"
/usr/bin/clang -O2 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
  "$ROOT/Tools/TestURFToPDF.c" -lcups -framework CoreGraphics -framework CoreFoundation -o "$OUT/bin/TestURFToPDF"
TEST="$OUT/bin/TestURFToPDF"
CONVERT="$OUT/bin/urftopdf"
passed=0
for spec in '203 K 8 400 559 mono' '203 K 1 400 559 1bit' '203 W 8 400 559 w8' '300 K 8 591 827 mono' '300 RGB 24 591 827 rgb'; do
  read -r dpi space bits width height name <<< "$spec"
  stem="asymmetric-50x70mm-${dpi}dpi-$name"
  "$TEST" generate-asymmetric "$OUT/fixtures/$stem.ras" "$space" "$bits" "$width" "$height" "$dpi" 1
  /usr/libexec/cups/filter/rastertourf 1 test synthetic 1 '' "$OUT/fixtures/$stem.ras" > "$OUT/fixtures/$stem.urf" 2> "$OUT/output/$stem-encoder.log"
  "$CONVERT" 1 test synthetic 1 '' "$OUT/fixtures/$stem.urf" > "$OUT/output/$stem.pdf"
  if [ "$dpi" = 203 ]; then points='141.87 198.46'; else points='141.84 198.48'; fi
  read -r pw ph <<< "$points"
  "$TEST" verify-pdf "$OUT/output/$stem.pdf" 1 "$pw" "$ph"
  PPD="$PPD_PATH" CONTENT_TYPE=application/pdf FINAL_CONTENT_TYPE=application/vnd.cups-raster \
    /usr/libexec/cups/filter/cgpdftoraster 1 test synthetic 1 'PageSize=psz500x700-50x70' "$OUT/output/$stem.pdf" > "$OUT/output/$stem.raster" 2> "$OUT/output/$stem-render.log"
  "$TEST" verify-rendered-raster "$OUT/output/$stem.raster" 400 559 203
  passed=$((passed + 1))
done
"$TEST" generate-asymmetric "$OUT/fixtures/multipage.ras" K 8 400 559 203 2
/usr/libexec/cups/filter/rastertourf 1 test synthetic 1 '' "$OUT/fixtures/multipage.ras" > "$OUT/fixtures/multipage.urf" 2> "$OUT/output/multipage-encoder.log"
"$CONVERT" 1 test synthetic 1 '' "$OUT/fixtures/multipage.urf" > "$OUT/output/multipage.pdf"
"$TEST" verify-pdf "$OUT/output/multipage.pdf" 2 141.87 198.46
passed=$((passed + 1))
"$CONVERT" 1 test synthetic 1 '' < "$OUT/fixtures/asymmetric-50x70mm-203dpi-mono.urf" > "$OUT/output/stdin.pdf"
"$TEST" verify-pdf "$OUT/output/stdin.pdf" 1 141.87 198.46
passed=$((passed + 1))
expect_failure() {
  local name="$1" pattern="$2"; shift 2
  if "$@" > "$OUT/output/$name.pdf" 2> "$OUT/output/$name-error.log"; then
    printf 'FAIL: %s accepted\n' "$name"; exit 1
  fi
  /usr/bin/grep -q "$pattern" "$OUT/output/$name-error.log"
  printf 'PASS: %s rejected loudly\n' "$name"
  passed=$((passed + 1))
}
expect_failure few-args Usage "$CONVERT" 1 2 3 4
expect_failure many-args Usage "$CONVERT" 1 2 3 4 5 6 7
expect_failure missing-file 'Unable to open input file' "$CONVERT" 1 test synthetic 1 '' "$OUT/missing.urf"
expect_failure empty 'Unable to open raster stream' "$CONVERT" 1 test synthetic 1 '' /dev/null
printf 'not a raster' > "$OUT/fixtures/garbage.urf"
expect_failure garbage 'Unable to open raster stream' "$CONVERT" 1 test synthetic 1 '' "$OUT/fixtures/garbage.urf"
/usr/bin/head -c 55 "$OUT/fixtures/asymmetric-50x70mm-203dpi-mono.urf" > "$OUT/fixtures/truncated.urf"
expect_failure truncated 'Truncated raster data' "$CONVERT" 1 test synthetic 1 '' "$OUT/fixtures/truncated.urf"
for spec in 'zero-dim:Invalid positive dimensions' 'zero-dpi:Invalid resolution' 'cmyk:Unsupported cupsColorSpace' 'planar:Unsupported planar/banded'; do
  name="${spec%%:*}"; pattern="${spec#*:}"
  "$TEST" make-invalid "$OUT/fixtures/$name.raster" "$name"
  expect_failure "$name" "$pattern" "$CONVERT" 1 test synthetic 1 '' "$OUT/fixtures/$name.raster"
done
expect_failure output-error 'Could not write the complete PDF' /bin/bash -c 'exec 3</dev/null; "$1" 1 test synthetic 1 "" "$2" 1>&3' bash "$CONVERT" "$OUT/fixtures/asymmetric-50x70mm-203dpi-mono.urf"
printf 'PASS: %s URF decoder cases; genuine native URF, geometry, pixels, polarity, resolution and one-page render checked\n' "$passed"
printf 'Artifacts retained: %s\n' "$OUT"
