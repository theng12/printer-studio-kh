#!/bin/bash
#
# Swaps the installed splix filter between the two build variants, so the
# page-header question can be settled with one command and one sheet of paper.
#
#   ./app/use-driver.sh patched   # 300-DPI page header (currently installed)
#   ./app/use-driver.sh stock     # splix as released, 600-DPI page header
#   ./app/use-driver.sh status    # show which is installed, no password needed
#
# Why this exists: splix has TWO bugs for this printer, and only one is fixed
# upstream.
#
#   1. Band width must exactly match Samsung's table. Fixed in splix 2.0.2,
#      verified for this model (640 bytes for Letter at 600 dpi).
#
#   2. The page header must sit on ULD's 300-DPI grid. STILL BROKEN upstream,
#      fixed here by vendor/splix/patches/300dpi-header.patch. That fix is
#      confirmed for the sibling HP Laser 1003-1008 but is UNPROVEN on the
#      107a, and a wrong page header is exactly what produces "paper feeds
#      through, nothing is printed".
#
# Both variants emit identical band widths, so the only difference is the
# 17-byte page header. If pages come out blank with one, try the other.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="/usr/libexec/cups/filter/rastertoqpdl"
PATCHED="$ROOT/vendor/splix/bin/rastertoqpdl"
STOCK="$ROOT/vendor/splix/bin/rastertoqpdl.stock"

page_header_of() {
  # Renders the reference raster and decodes the page header width and height.
  # From splix src/qpdl.cpp the header is 17 bytes after the PJL block, with
  # width at [5..6] and height at [7..8], big-endian.
  local binary="$1"
  PPD="$ROOT/vendor/splix/ppd/laser10x.ppd" "$binary" 1 t t 1 "PageSize=Letter" \
    "$ROOT/vendor/splix/reference/testpage-600.rast" 2>/dev/null \
  | /usr/bin/python3 -c '
import sys
d = sys.stdin.buffer.read()
m = b"@PJL ENTER LANGUAGE = QPDL\n"
i = d.find(m)
if i < 0:
    print("unreadable"); raise SystemExit
h = d[i+len(m):][:17]
print(f"{(h[5] << 8) | h[6]} x {(h[7] << 8) | h[8]}")
'
}

variant_of() {
  case "$(page_header_of "$1")" in
    "2550 x 3300") echo "patched (300-DPI header)" ;;
    "5104 x 6495") echo "stock (600-DPI header)" ;;
    *)             echo "unknown" ;;
  esac
}

if [ "${1:-status}" = "status" ]; then
  echo "installed : $(variant_of "$DEST" 2>/dev/null || echo 'not installed')"
  echo "patched   : $(variant_of "$PATCHED")"
  echo "stock     : $(variant_of "$STOCK")"
  exit 0
fi

case "${1:-}" in
  patched) SOURCE="$PATCHED" ;;
  stock)   SOURCE="$STOCK" ;;
  *) echo "usage: $0 patched|stock|status" >&2; exit 2 ;;
esac

if [ ! -f "$SOURCE" ]; then
  echo "!! Missing $SOURCE" >&2
  exit 1
fi

# Written to a space-free path: the installer hands this to `do shell script`,
# and quoting a path containing a space through AppleScript is not worth it.
STAGE="$(mktemp -d)/install-filter.sh"
cat > "$STAGE" <<SCRIPT
set -e
/bin/cp -f '$SOURCE' '$DEST'
/usr/sbin/chown root:wheel '$DEST'
/bin/chmod 555 '$DEST'
/usr/bin/xattr -c '$DEST' 2>/dev/null || true
/usr/bin/codesign --force --sign - '$DEST' 2>/dev/null || true
/usr/bin/codesign --verify '$DEST' 2>/dev/null || echo "warning: signature did not verify"
echo "installed: \$(/usr/bin/shasum -a 256 '$DEST' | cut -c1-16)"
SCRIPT

echo "==> Installing the $(basename "$SOURCE") variant (password prompt)"
/usr/bin/osascript -e "do shell script \"/bin/bash '$STAGE'\" with administrator privileges"
rm -rf "$(dirname "$STAGE")"

echo "==> Now installed: $(variant_of "$DEST")"
echo "    Send a page with:  lp -d HPLaser107a \"$ROOT/dist/test-page.pdf\""
