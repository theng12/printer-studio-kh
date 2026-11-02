#!/bin/bash
#
# Tests for app/retain-dmgs.sh:
# 1. Retains only the latest 2 versions, moves older versions and legacy aliases to _trash.
# 2. Renames retained legacy DMGs to canonical format with contents/hash unchanged.
# 3. Moves unversioned DMGs to _trash.
# 4. Handles semantic versions correctly (e.g. 1.0.10 > 1.0.9).
# 5. Never touches other files or other apps' DMGs.
# 6. Requires only 2 args (dist dir and app name).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RETAIN_SCRIPT="$ROOT/app/retain-dmgs.sh"

if [ ! -x "$RETAIN_SCRIPT" ]; then
  echo "FAIL: retain-dmgs.sh not executable at $RETAIN_SCRIPT" >&2
  exit 1
fi

# Fixtures directory stored under _trash; no rm or trap deletion
mkdir -p "$ROOT/_trash"
FIXTURES_DIR=$(mktemp -d "$ROOT/_trash/test-dmg-retention-XXXXXX")
TRASH_PARENT="$FIXTURES_DIR/_trash"

run_retention() {
  local target="$1"
  "$RETAIN_SCRIPT" "$target" "Printer Studio KH"
}

verify_trash() {
  local expected_in_trash="$1"
  if [ -z "$(find "$TRASH_PARENT" -type f -name "$expected_in_trash" -print)" ]; then
    echo "FAIL: Expected $expected_in_trash in _trash but not found!" >&2
    exit 1
  fi
}

echo "==> Test 1: Retains only latest 2 release DMGs, moves older versions to _trash"
FIX1=$(mktemp -d "$FIXTURES_DIR/fix1-XXXXXX")
touch "$FIX1/Printer-Studio-KH-1.0.1.dmg"
touch "$FIX1/Printer-Studio-KH-1.0.2.dmg"
touch "$FIX1/Printer-Studio-KH-1.0.3.dmg"
touch "$FIX1/Printer Studio KH-1.0.3.dmg"
run_retention "$FIX1"

if [ ! -f "$FIX1/Printer Studio KH-1.0.3.dmg" ]; then
  echo "FAIL: Expected canonical 1.0.3 DMG retained" >&2
  exit 1
fi
if [ ! -f "$FIX1/Printer Studio KH-1.0.2.dmg" ]; then
  echo "FAIL: Expected 1.0.2 renamed to canonical and retained" >&2
  exit 1
fi
if [ -f "$FIX1/Printer-Studio-KH-1.0.1.dmg" ]; then
  echo "FAIL: Older 1.0.1 should not be in dist" >&2
  exit 1
fi
if [ -f "$FIX1/Printer-Studio-KH-1.0.3.dmg" ]; then
  echo "FAIL: Legacy 1.0.3 should not be in dist when canonical exists" >&2
  exit 1
fi
verify_trash "Printer-Studio-KH-1.0.1.dmg"
verify_trash "Printer-Studio-KH-1.0.3.dmg"
echo "PASS: Latest 2 retained, older and duplicate legacy DMGs moved to _trash"

echo "==> Test 2: Semantic version ordering (1.0.10 > 1.0.9)"
FIX2=$(mktemp -d "$FIXTURES_DIR/fix2-XXXXXX")
touch "$FIX2/Printer-Studio-KH-1.0.8.dmg"
touch "$FIX2/Printer-Studio-KH-1.0.9.dmg"
touch "$FIX2/Printer-Studio-KH-1.0.10.dmg"
touch "$FIX2/Printer Studio KH-1.0.9.dmg"
touch "$FIX2/Printer Studio KH-1.0.10.dmg"
run_retention "$FIX2"

if [ ! -f "$FIX2/Printer Studio KH-1.0.10.dmg" ]; then
  echo "FAIL: Expected canonical 1.0.10 DMG retained" >&2
  exit 1
fi
if [ ! -f "$FIX2/Printer Studio KH-1.0.9.dmg" ]; then
  echo "FAIL: Expected canonical 1.0.9 DMG retained" >&2
  exit 1
fi
if [ -f "$FIX2/Printer-Studio-KH-1.0.10.dmg" ]; then
  echo "FAIL: Legacy 1.0.10 should not be in dist" >&2
  exit 1
fi
if [ -f "$FIX2/Printer-Studio-KH-1.0.9.dmg" ]; then
  echo "FAIL: Legacy 1.0.9 should not be in dist" >&2
  exit 1
fi
if [ -e "$FIX2/Printer-Studio-KH-1.0.8.dmg" ]; then
  echo "FAIL: 1.0.8 should be retired before 1.0.9 or 1.0.10" >&2
  exit 1
fi
verify_trash "Printer-Studio-KH-1.0.8.dmg"
verify_trash "Printer-Studio-KH-1.0.9.dmg"
verify_trash "Printer-Studio-KH-1.0.10.dmg"
echo "PASS: 1.0.10 correctly identified as newer than 1.0.9 and retained"

echo "==> Test 3: Moves unversioned DMG to _trash"
FIX3=$(mktemp -d "$FIXTURES_DIR/fix3-XXXXXX")
touch "$FIX3/Printer Studio KH.dmg"
touch "$FIX3/Printer Studio KH-1.0.1.dmg"
touch "$FIX3/Printer Studio KH-1.0.2.dmg"
touch "$FIX3/printer-studio-report"
touch "$FIX3/.DS_Store"
run_retention "$FIX3"

if [ -f "$FIX3/Printer Studio KH.dmg" ]; then
  echo "FAIL: Unversioned DMG should not be in dist" >&2
  exit 1
fi
if [ ! -f "$FIX3/Printer Studio KH-1.0.2.dmg" ]; then
  echo "FAIL: Expected 1.0.2 retained" >&2
  exit 1
fi
if [ ! -f "$FIX3/printer-studio-report" ]; then
  echo "FAIL: Other file (printer-studio-report) should remain untouched" >&2
  exit 1
fi
if [ ! -f "$FIX3/.DS_Store" ]; then
  echo "FAIL: Other file (.DS_Store) should remain untouched" >&2
  exit 1
fi
verify_trash "Printer Studio KH.dmg"
echo "PASS: Unversioned DMG moved to _trash, other files untouched"

echo "==> Test 4: Hash unchanged when renaming legacy DMG to canonical"
FIX4=$(mktemp -d "$FIXTURES_DIR/fix4-XXXXXX")
echo "Legacy 1.0.2 content hash test" > "$FIX4/Printer-Studio-KH-1.0.2.dmg"
touch "$FIX4/Printer-Studio-KH-1.0.3.dmg"
H_BEFORE=$(shasum -a 256 "$FIX4/Printer-Studio-KH-1.0.2.dmg" | cut -d" " -f1)
run_retention "$FIX4"

if [ ! -f "$FIX4/Printer Studio KH-1.0.2.dmg" ]; then
  echo "FAIL: Expected 1.0.2 renamed to canonical" >&2
  exit 1
fi
H_AFTER=$(shasum -a 256 "$FIX4/Printer Studio KH-1.0.2.dmg" | cut -d" " -f1)
if [ "$H_BEFORE" != "$H_AFTER" ]; then
  echo "FAIL: Hash changed when renaming legacy DMG!" >&2
  exit 1
fi
echo "PASS: Hash and contents identical after rename"

echo "==> Test 5: Retains only 2 versions even with 5 versions and legacy aliases"
FIX5=$(mktemp -d "$FIXTURES_DIR/fix5-XXXXXX")
touch "$FIX5/Printer-Studio-KH-1.0.1.dmg"
touch "$FIX5/Printer-Studio-KH-1.0.2.dmg"
touch "$FIX5/Printer-Studio-KH-1.0.3.dmg"
touch "$FIX5/Printer-Studio-KH-1.0.4.dmg"
touch "$FIX5/Printer-Studio-KH-1.0.5.dmg"
touch "$FIX5/Printer Studio KH-1.0.5.dmg"
run_retention "$FIX5"

if [ ! -f "$FIX5/Printer Studio KH-1.0.5.dmg" ]; then
  echo "FAIL: Expected canonical 1.0.5 retained" >&2
  exit 1
fi
if [ ! -f "$FIX5/Printer Studio KH-1.0.4.dmg" ]; then
  echo "FAIL: Expected 1.0.4 renamed to canonical and retained" >&2
  exit 1
fi
if [ -f "$FIX5/Printer-Studio-KH-1.0.5.dmg" ]; then
  echo "FAIL: Legacy 1.0.5 should not be in dist when canonical exists" >&2
  exit 1
fi
for older in 1.0.1 1.0.2 1.0.3; do
  if [ -f "$FIX5/Printer-Studio-KH-$older.dmg" ] || [ -f "$FIX5/Printer Studio KH-$older.dmg" ]; then
    echo "FAIL: Older version $older should not be in dist" >&2
    exit 1
  fi
done
echo "PASS: With 5 versions and aliases, only latest 2 kept in dist"

echo "==> Test 6: Other apps and malformed filenames remain untouched"
FIX6=$(mktemp -d "$FIXTURES_DIR/fix6-XXXXXX")
touch "$FIX6/Other App-1.0.0.dmg" "$FIX6/Printer Studio KH-not-a-version.dmg" "$FIX6/notes.txt"
run_retention "$FIX6"
for unrelated in "Other App-1.0.0.dmg" "Printer Studio KH-not-a-version.dmg" "notes.txt"; do
  test -f "$FIX6/$unrelated"
done
echo "PASS: Unrelated and malformed files untouched"

echo "==> Test 7: Retiring the same filename twice never overwrites a backup"
for value in first second; do
  FIX7=$(mktemp -d "$FIXTURES_DIR/fix7-XXXXXX")
  printf '%s' "$value" > "$FIX7/Printer Studio KH.dmg"
  run_retention "$FIX7"
done
for value in first second; do
  found=0
  while IFS= read -r backup; do
    if [ "$(cat "$backup")" = "$value" ]; then found=1; fi
  done < <(find "$TRASH_PARENT" -type f -name 'Printer Studio KH.dmg')
  test "$found" -eq 1
done
echo "PASS: Both retired files preserved in distinct backup folders"
echo "==> All seven DMG retention tests passed."
