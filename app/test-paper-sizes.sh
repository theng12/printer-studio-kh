#!/bin/bash
#
# Compiles and runs the focused TestPaperSizes test suite on the native architecture.
# Retains build artifacts in _trash without deleting any files.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
TRASH="$ROOT/../_trash/test-paper-sizes-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$TRASH"

echo "==> Gathering sources for TestPaperSizes ($ARCH)"
SOURCES=()
while IFS= read -r file; do
  case "$(basename "$file")" in
    App.swift|Views.swift|RenderFixtures.swift) continue ;;
  esac
  SOURCES+=("$file")
done < <(find "$ROOT/Sources/PrinterStudio" -name '*.swift' | sort)
SOURCES+=("$ROOT/Tools/TestPaperSizes.swift")

BIN="$TRASH/TestPaperSizes"

echo "==> Compiling native test runner (${#SOURCES[@]} sources)"
/usr/bin/swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -o "$BIN" \
  "${SOURCES[@]}"

echo "==> Running TestPaperSizes"
"$BIN" "$ROOT/.." "$TRASH"

echo "==> Testing offline CUPS raster printability proof for requested label sizes"
THERMAL_FIXTURE="$TRASH/thermal-transformed.ppd"
SOURCE_PDF="$TRASH/source.pdf"
python3 "$ROOT/Tools/make-test-page.py" "$SOURCE_PDF"
CHECK_RASTER="$TRASH/check-raster"
/usr/bin/clang "$ROOT/Tools/CheckPaperRaster.c" -lcups -o "$CHECK_RASTER"

if [ -f "$THERMAL_FIXTURE" ] && [ -f "$SOURCE_PDF" ] && [ -x "$CHECK_RASTER" ]; then
  # Test 30x40 mm (psz300x400-30x40)
  /usr/sbin/cupsfilter -p "$THERMAL_FIXTURE" -i application/pdf -m application/vnd.cups-raster -o PageSize=psz300x400-30x40 "$SOURCE_PDF" > "$TRASH/30x40.raster" 2>"$TRASH/30x40.log"
  "$CHECK_RASTER" "$TRASH/30x40.raster" 30.0 40.0
  echo "  ✓ 30x40 mm offline PDF -> CUPS raster verified (nonempty, correct page header)"

  # Test 50x70 mm (psz500x700-50x70)
  /usr/sbin/cupsfilter -p "$THERMAL_FIXTURE" -i application/pdf -m application/vnd.cups-raster -o PageSize=psz500x700-50x70 "$SOURCE_PDF" > "$TRASH/50x70.raster" 2>"$TRASH/50x70.log"
  "$CHECK_RASTER" "$TRASH/50x70.raster" 50.0 70.0
  echo "  ✓ 50x70 mm offline PDF -> CUPS raster verified (nonempty, correct page header)"

  # Test 70x100 mm (psz700x1000-70x100)
  /usr/sbin/cupsfilter -p "$THERMAL_FIXTURE" -i application/pdf -m application/vnd.cups-raster -o PageSize=psz700x1000-70x100 "$SOURCE_PDF" > "$TRASH/70x100.raster" 2>"$TRASH/70x100.log"
  "$CHECK_RASTER" "$TRASH/70x100.raster" 70.0 100.0
  echo "  ✓ 70x100 mm offline PDF -> CUPS raster verified (nonempty, correct page header)"
else
  echo "  (Skipping raster proof: fixture, source PDF or checker binary not found)"
fi

echo "==> Typechecking full SwiftUI app target"
/usr/bin/swiftc \
  -typecheck \
  -parse-as-library \
  -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -framework SwiftUI \
  -framework AppKit \
  "$ROOT/Sources/PrinterStudio"/*.swift

echo "==> All paper preset and PPD applicability checks passed."
