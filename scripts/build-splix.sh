#!/bin/bash
#
# Rebuilds the splix driver payload in vendor/splix from source.
#
# You only need this if you want to regenerate the binaries or the PPD. The
# built artefacts are already committed, because they are not reproducible
# without network access and because the app bundles them.
#
# Result:
#   vendor/splix/bin/rastertoqpdl, pstoqpdl
#   vendor/splix/ppd/laser10x.ppd, m2020.ppd
#
# Requirements: Command Line Tools only. No Xcode, no Homebrew packages.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/splix-build"
SDK="$(/usr/bin/xcrun --show-sdk-path)"

echo "==> Working in $WORK"
rm -rf "$WORK"
mkdir -p "$WORK/bin"

# ---------------------------------------------------------------------------
# splix's build wants pkg-config, which macOS does not ship. Rather than
# install one, provide a shim that answers with the CLT SDK's CUPS headers.
# The headers ARE present in the SDK: $SDK/usr/include/cups/raster.h
# ---------------------------------------------------------------------------
cat > "$WORK/bin/pkg-config" <<EOF
#!/bin/bash
SDK="$SDK"
case "\$*" in
  *--cflags*) echo "-I\$SDK/usr/include" ;;
  *--libs*)   echo "-L\$SDK/usr/lib -lcups" ;;
  *--variable=cups_serverbin*) echo "/usr/libexec/cups" ;;
  *--variable=cups_datadir*)   echo "/usr/share/cups" ;;
  *--modversion*) echo "2.3.4" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$WORK/bin/pkg-config"

# ---------------------------------------------------------------------------
# splix 2.0.2 is the first release supporting the Samsung M2020 series and the
# HP Laser 10x. Anything older does NOT support this printer.
# ---------------------------------------------------------------------------
echo "==> Cloning OpenPrinting/splix"
/usr/bin/git clone --quiet https://github.com/OpenPrinting/splix "$WORK/splix"

cd "$WORK/splix"
if ! /usr/bin/git merge-base --is-ancestor 206e283 HEAD 2>/dev/null; then
  echo "!! This checkout is missing commit 206e283 (M2020 / HP Laser 10x support)." >&2
  echo "!! The resulting driver will NOT work with the HP Laser 107a." >&2
  exit 1
fi
echo "    $(/usr/bin/git describe --always) — has the M2020/HP Laser 10x support commit"

# ---------------------------------------------------------------------------
# The 300-DPI page-header fix is NOT upstream, in 2.0.2 or in master. Without
# it a SpecialBandWidth printer gets a 600-DPI-sized page header (5104x6495
# for Letter) where the firmware expects the 300-DPI grid (2550x3300).
# ---------------------------------------------------------------------------
PATCH="$ROOT/vendor/splix/patches/300dpi-header.patch"
if [ -f "$PATCH" ]; then
  echo "==> Applying $(basename "$PATCH")"
  /usr/bin/git apply "$PATCH" || {
    echo "!! Could not apply the 300-DPI header patch." >&2
    exit 1
  }
else
  echo "!! The 300-DPI header patch is missing; the driver will emit a 600-DPI page header." >&2
  exit 1
fi

# CC/CXX must be overridden: the Makefile hardcodes gcc/g++, which do not exist
# here. DISABLE_JBIG because there is no libjbig85; QPDL v3 mono never uses it.
echo "==> Building"
PATH="$WORK/bin:$PATH" /usr/bin/make -j4 \
  CC=/usr/bin/clang \
  CXX=/usr/bin/clang++ \
  DISABLE_JBIG=1 \
  >"$WORK/build.log" 2>&1 || {
    echo "!! Build failed — last 30 lines:" >&2
    tail -30 "$WORK/build.log" >&2
    exit 1
  }

FILTER="$(find "$WORK/splix" -type f -name rastertoqpdl -perm +111 | head -1)"
if [ -z "$FILTER" ]; then
  echo "!! rastertoqpdl was not produced" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# The .ppd files are NOT checked into splix's git tree; they are generated
# from the .drv.in templates by ppdc, which macOS ships at /usr/bin/ppdc.
# ---------------------------------------------------------------------------
echo "==> Generating PPDs"
cd "$WORK/splix/ppd"
./compile.sh hp.drv.in drv >/dev/null
/usr/bin/ppdc -I . -d ./ hp.drv >/dev/null
./compile.sh samsung.drv.in drv >/dev/null
/usr/bin/ppdc -I . -d ./ samsung.drv >/dev/null

echo "==> Installing into vendor/splix"
mkdir -p "$ROOT/vendor/splix/bin" "$ROOT/vendor/splix/ppd"
cp "$FILTER" "$ROOT/vendor/splix/bin/rastertoqpdl"
find "$WORK/splix" -type f -name pstoqpdl -perm +111 -exec cp {} "$ROOT/vendor/splix/bin/pstoqpdl" \;
cp "$WORK/splix/ppd/laser10x.ppd" "$ROOT/vendor/splix/ppd/laser10x.ppd"
cp "$WORK/splix/ppd/m2020.ppd" "$ROOT/vendor/splix/ppd/m2020.ppd"

# The PPD must keep the band-width gate, or the printer silently eats pages.
if ! grep -q 'SpecialBandWidth' "$ROOT/vendor/splix/ppd/laser10x.ppd"; then
  echo "!! laser10x.ppd is missing *QPDL SpecialBandWidth — pages will be silently discarded" >&2
  exit 1
fi

echo "==> Done"
"$ROOT/app/verify-bandwidth.sh"
