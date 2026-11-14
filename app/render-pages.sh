#!/bin/bash
# Offscreen page-acceptance harness for Printer Studio KH.
# Renders real SwiftUI views to PNGs in a hidden, offscreen window with a temp
# data environment. Never activates a window, never uses screencapture/cliclick/
# System Events, never touches ~/Library/Application Support/PrinterStudio or
# launchd, never runs the shipped dist app.
#
#   app/render-pages.sh [pages|all] [out-dir] [WxH ...]
#
# Pages: overview, printers, printers-table, sharing, setup, stickers, activity,
# settings, whats-new. "all" = every page; "all-empty" = the empty first-run
# overview/printers/sharing. "window" renders the full MainWindow; "window-printers"
# and "window-sharing" render those pages inside the real window.
# Default sizes: pages 375x900 768x900 1440x900; window 860x580 1024x720 1440x900.
# "switch-check" drives the Cards/Table control; "keyboard-check" drives it with the
# keyboard and records Tab focus movement.
# If WxH arguments are given they override defaults for all targets.
# Every render is produced in light and dark (-light/-dark suffix).

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
PAGE_SPEC="${1:-all}"
OUT_DIR="${2:-$ROOT_DIR/harness-out}"
shift 2 2>/dev/null || true

PAGE_SIZES=(375x900 768x900 1440x900)
WINDOW_SIZES=(860x580 1024x720 1440x900)

# Collect explicit sizes if provided.
EXPLICIT_SIZES=()
for arg in "$@"; do
  case "$arg" in
    *x*|*X*) EXPLICIT_SIZES+=("$arg") ;;
  esac
done

ALL_PAGES=(overview printers printers-table sharing setup stickers activity settings whats-new)
EMPTY_PAGES=(overview-empty printers-empty sharing-empty)

# Resolve targets.
TARGETS=()
if [ "$PAGE_SPEC" = "all" ]; then
  TARGETS=("${ALL_PAGES[@]}")
elif [ "$PAGE_SPEC" = "all-empty" ]; then
  TARGETS=("${EMPTY_PAGES[@]}")
elif [ "$PAGE_SPEC" = "all+window" ] || [ "$PAGE_SPEC" = "all,window" ]; then
  TARGETS=("${ALL_PAGES[@]}" window window-printers window-sharing)
else
  IFS=',' read -r -a TARGETS <<< "$PAGE_SPEC"
fi

mkdir -p "$OUT_DIR"

# Nothing stale survives: every PNG in an evidence folder must be one this run
# produced and measured, so earlier files are retired recoverably first.
case "$PAGE_SPEC" in
  switch-check|keyboard-check) ;;
  *)
    if compgen -G "$OUT_DIR/*.png" > /dev/null 2>&1; then
      STALE="$(dirname "$OUT_DIR")/_trash/$(basename "$OUT_DIR")-replaced-$(date +%Y%m%dT%H%M%SZ)"
      mkdir -p "$STALE"
      mv "$OUT_DIR"/*.png "$STALE"/
      echo "STALE_MOVED $(find "$STALE" -name '*.png' | wc -l | tr -d ' ') -> $STALE"
    fi
    ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ps-render.XXXXXX")
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Copy real app sources and patch a temp copy only.
mkdir -p "$WORK/Sources/PrinterStudio" "$WORK/Tools"
cp "$ROOT_DIR/app/Sources/PrinterStudio/"*.swift "$WORK/Sources/PrinterStudio/"
cp "$ROOT_DIR/app/Tools/render_main.swift" "$WORK/Tools/"

# Strip @main from the app entry so the harness is the entry point.
python3 - "$WORK/Sources/PrinterStudio/App.swift" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()

# Strip @main on the app struct.
marker = '@main\nstruct PrinterStudioApp'
if marker in text:
    text = text.replace(marker, 'struct PrinterStudioApp', 1)
else:
    # fallback: remove a lone @main line before PrinterStudioApp
    text = text.replace('@main\n', '', 1)

# Avoid touching real app support during property init in render mode.
old = '@Published var stickerSizes: [StickerSize] = ProcessInfo.processInfo.environment["PRINTER_STUDIO_SIGNING_SMOKE"] == nil ? StickerSizeStore.load() : []'
new = '@Published var stickerSizes: [StickerSize] = (ProcessInfo.processInfo.environment["PRINTER_STUDIO_SIGNING_SMOKE"] == nil && ProcessInfo.processInfo.environment["PRINTER_STUDIO_RENDER"] != "1") ? StickerSizeStore.load() : []'
if old in text:
    text = text.replace(old, new)

# Skip side effects in AppState.init when rendering.
needle = '    init() {\n'
if needle not in text:
    raise SystemExit('AppState.init() not found for render patch')
guard = '''    init() {
        if ProcessInfo.processInfo.environment["PRINTER_STUDIO_RENDER"] == "1" {
            return
        }
'''
text = text.replace(needle, guard, 1)

# Strip the duplicate-copy NSAlert .task in MainWindow for render safety (it
# would try to show an alert and terminate). Render harness does not exercise it.
p.write_text(text)
PY

# Neutralize MainWindow's duplicate-copy check in the temp copy so offscreen
# render never shows an alert or terminates.
python3 - "$WORK/Sources/PrinterStudio/Views.swift" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
old = '''        .task {
            // Two copies would fight over the same launchd jobs; say so plainly
            // and let the newer one step aside.
            guard let other = Removal.anotherCopyIsRunning() else { return }
            let alert = NSAlert()
            alert.messageText = "Printer Studio KH is already running"
            alert.informativeText = "Another copy is open from \\(other.path). This copy will quit so the two do not fight over the same background jobs."
            alert.addButton(withTitle: "Quit this copy")
            alert.runModal()
            NSApp.terminate(nil)
        }'''
if old in text:
    text = text.replace(old, '        .task { _ = ProcessInfo.processInfo.environment["PRINTER_STUDIO_RENDER"] }')

# SwiftUI 5/6 on macOS 13 aborts the offscreen host with "setting value during
# update" when this save-on-change fires while the sticker list lays out. It is
# not part of the page's appearance, so drop it in the throwaway copy only.
old_onchange = '''            .onChange(of: state.stickerSizes) { _ in
                state.saveStickerSizes()
            }'''
if old_onchange in text:
    text = text.replace(old_onchange, '')
p.write_text(text)
PY

SDK_PATH=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || true)
if [ -z "$SDK_PATH" ]; then
  echo "could not locate macOS SDK" >&2
  exit 1
fi

# Collect sources (app sources without @main now, plus render harness as entry).
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find "$WORK/Sources/PrinterStudio" -name '*.swift' | sort)
SOURCES+=("$WORK/Tools/render_main.swift")

# Compile into a minimal temp app bundle so Bundle.main has the real version,
# build and What's New text. A bare executable shows "— (build —)" on About and
# "Release notes could not be loaded" on What's New, which is not evidence.
APP_BUNDLE="$WORK/RenderHarness.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
BIN="$APP_BUNDLE/Contents/MacOS/RenderHarness"
xcrun swiftc -sdk "$SDK_PATH" -target arm64-apple-macos13.0 -parse-as-library -swift-version 5 \
  -framework SwiftUI -framework AppKit -framework CoreGraphics \
  -o "$BIN" "${SOURCES[@]}"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/app/Resources/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/app/Resources/Info.plist")
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Printer Studio KH</string>
    <key>CFBundleDisplayName</key>
    <string>Printer Studio KH</string>
    <key>CFBundleIdentifier</key>
    <string>com.theng12.printerstudio</string>
    <key>CFBundleExecutable</key>
    <string>RenderHarness</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST
if ! "$ROOT_DIR/app/release-notes.sh" "$VERSION" "$ROOT_DIR/CHANGELOG.md" \
    > "$APP_BUNDLE/Contents/Resources/WhatsNew.txt" 2>/dev/null; then
  echo "Release notes could not be loaded for this version." > "$APP_BUNDLE/Contents/Resources/WhatsNew.txt"
fi

# Optional UI-control check: drive the Printers Table/Cards control with a real
# offscreen mouse event. Skips cleanly when the Fleet UI switch is not present.
if [ "$PAGE_SPEC" = "switch-check" ]; then
  set +e
  PRINTER_STUDIO_RENDER=1 PRINTER_STUDIO_NO_WINDOW=1 HOME="$WORK/home" \
    "$BIN" switch-check "$OUT_DIR" 2>&1 | tee "$OUT_DIR/switch-check.log"
  rc=${PIPESTATUS[0]}
  set -e
  echo "SWITCH_CHECK_EXIT $rc"
  exit "$rc"
fi

# Keyboard pass: focus the Cards/Table control, drive it with an arrow key, and
# record whether Tab moves focus. Offscreen; no window is ever shown.
if [ "$PAGE_SPEC" = "keyboard-check" ]; then
  set +e
  PRINTER_STUDIO_RENDER=1 PRINTER_STUDIO_NO_WINDOW=1 HOME="$WORK/home" \
    "$BIN" keyboard-check "$OUT_DIR" 2>&1 | tee "$OUT_DIR/keyboard-check.log"
  rc=${PIPESTATUS[0]}
  set -e
  echo "KEYBOARD_CHECK_EXIT $rc"
  exit "$rc"
fi

# Page interactions: one driven control per page, each asserting its own
# outcome (banner text, activity row, stored setting) and failing otherwise.
if [ "$PAGE_SPEC" = "interaction" ]; then
  rc=0
  for page in overview printers sharing setup stickers activity settings whats-new; do
    set +e
    PRINTER_STUDIO_RENDER=1 PRINTER_STUDIO_NO_WINDOW=1 HOME="$WORK/home" \
      "$BIN" interaction "$page" "$OUT_DIR" 2>&1
    page_rc=$?
    set -e
    if [ "$page_rc" -ne 0 ]; then rc=$page_rc; fi
  done
  echo "INTERACTION_BATCH_EXIT $rc"
  exit "$rc"
fi

# Contrast probe (independent of renders). It exits non-zero when body or muted
# drops below 4.5; print the measured line either way so the failure is readable.
set +e
CONTRAST_OUT=$("$BIN" contrast 2>&1)
CONTRAST_RC=$?
set -e
CONTRAST_JSON=$(printf '%s\n' "$CONTRAST_OUT" | awk '/^CONTRAST /{sub(/^CONTRAST /,""); print; exit}')
if [ -z "$CONTRAST_JSON" ]; then
  echo "CONTRAST probe failed or missing"
  echo "PAGE_ACCEPTANCE FAIL"
  exit 1
fi
echo "CONTRAST $CONTRAST_JSON"
if [ "$CONTRAST_RC" -ne 0 ]; then
  echo "PAGE_ACCEPTANCE FAIL"
  exit 1
fi

HAD_FAIL=0
TOTAL=0
CLIPPED_PAGES=()

render_one() {
  local mode="$1" target="$2" size="$3" appearance="$4" mode_arg="${5:-}"
  local outfile
  TOTAL=$((TOTAL + 1))
  local out
  if [ -n "$mode_arg" ]; then
    out=$("$BIN" "$mode" "$target" "$OUT_DIR" "$size" "$appearance" "$mode_arg" 2>&1) || true
  else
    out=$("$BIN" "$mode" "$target" "$OUT_DIR" "$size" "$appearance" 2>&1) || true
  fi
  local measure
  measure=$(printf '%s\n' "$out" | awk '/^MEASURE /{sub(/^MEASURE /,""); print; exit}')
  if [ -z "$measure" ]; then
    echo "RENDER_ERROR target=$target size=$size appearance=$appearance output=$out"
    HAD_FAIL=1
    return
  fi
  echo "MEASURE $measure"
  # Check ok and clipped via python for reliable JSON parsing.
  local verdict
  verdict=$(python3 - "$measure" <<'PY'
import json, sys
m = json.loads(sys.argv[1])
ok = m.get('ok')
clipped = m.get('clipped')
print('ok' if ok else 'bad')
print('clipped' if clipped else 'clear')
PY
)
  local okv clippedv
  okv=$(printf '%s\n' "$verdict" | sed -n '1p')
  clippedv=$(printf '%s\n' "$verdict" | sed -n '2p')
  if [ "$okv" != "ok" ]; then
    HAD_FAIL=1
  fi
  if [ "$clippedv" = "clipped" ]; then
    HAD_FAIL=1
    CLIPPED_PAGES+=("$target:$size:$appearance")
  fi
}

for target in "${TARGETS[@]}"; do
  # Choose sizes for this target.
  sizes_to_use=()
  if [ ${#EXPLICIT_SIZES[@]} -gt 0 ]; then
    sizes_to_use=("${EXPLICIT_SIZES[@]}")
  elif [[ "$target" == window* ]]; then
    sizes_to_use=("${WINDOW_SIZES[@]}")
  else
    sizes_to_use=("${PAGE_SIZES[@]}")
  fi

  for size in "${sizes_to_use[@]}"; do
    # What's New is a dialog whose window minimum is 420 pt; below that it would
    # overflow rather than reflow, so render it at its real minimum.
    if [ "$target" = "whats-new" ] && [[ "$size" == 375x* ]]; then size="420x900"; fi
    for appearance in light dark; do
      if [[ "$target" == window* ]]; then
        if [[ "$target" == *-outcome ]]; then
          PRINTER_STUDIO_RENDER=1 PRINTER_STUDIO_RENDER_OUTCOME=1 PRINTER_STUDIO_NO_WINDOW=1 HOME="$WORK/home" \
            render_one window "$target" "$size" "$appearance"
        else
          PRINTER_STUDIO_RENDER=1 PRINTER_STUDIO_NO_WINDOW=1 HOME="$WORK/home" \
            render_one window "$target" "$size" "$appearance"
        fi
      elif [ "$target" = "printers-table" ]; then
        PRINTER_STUDIO_RENDER=1 PRINTER_STUDIO_NO_WINDOW=1 HOME="$WORK/home" \
          render_one page printers-table "$size" "$appearance" table
      elif [ "$target" = "printers" ]; then
        PRINTER_STUDIO_RENDER=1 PRINTER_STUDIO_NO_WINDOW=1 HOME="$WORK/home" \
          render_one page printers "$size" "$appearance" cards
      elif [[ "$target" == *-empty ]]; then
        PRINTER_STUDIO_RENDER=1 PRINTER_STUDIO_RENDER_EMPTY=1 PRINTER_STUDIO_NO_WINDOW=1 HOME="$WORK/home" \
          render_one page "$target" "$size" "$appearance"
      elif [[ "$target" == *-error ]]; then
        PRINTER_STUDIO_RENDER=1 PRINTER_STUDIO_RENDER_ERROR=1 PRINTER_STUDIO_NO_WINDOW=1 HOME="$WORK/home" \
          render_one page "$target" "$size" "$appearance"
      else
        PRINTER_STUDIO_RENDER=1 PRINTER_STUDIO_NO_WINDOW=1 HOME="$WORK/home" \
          render_one page "$target" "$size" "$appearance"
      fi
    done
  done
done

if [ ${#CLIPPED_PAGES[@]} -gt 0 ]; then
  echo "CLIPPED: ${CLIPPED_PAGES[*]}"
fi

echo "TOTAL_RENDERS $TOTAL"
if [ "$HAD_FAIL" -ne 0 ]; then
  echo "PAGE_ACCEPTANCE FAIL"
  exit 1
fi
echo "PAGE_ACCEPTANCE PASS"
exit 0
