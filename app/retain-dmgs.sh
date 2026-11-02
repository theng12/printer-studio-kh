#!/bin/bash
#
# Retains only the latest 2 release DMGs for an app in dist.
# Moves older DMGs, duplicate/legacy aliases, and unversioned DMGs to _trash.
# Renames retained legacy-formatted DMGs to canonical app name format.
# Never touches other apps' files or non-DMG files.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${1:-$ROOT/../dist}"
APP_NAME="${2:-Printer Studio KH}"
TRASH_DIR=""
LEGACY_NAME="${APP_NAME// /-}"

if [ ! -d "$DIST_DIR" ]; then
  echo "!! error: dist directory not found: $DIST_DIR" >&2
  exit 1
fi

ensure_trash_dir() {
  if [ -z "$TRASH_DIR" ]; then
    local trash_parent="$DIST_DIR/../_trash"
    mkdir -p "$trash_parent"
    TRASH_DIR=$(mktemp -d "$trash_parent/retention-XXXXXX")
  fi
}

move_to_trash() {
  local file="$1"
  ensure_trash_dir
  mv "$file" "$TRASH_DIR/"
  echo "==> Moved to _trash: $(basename "$file")"
}

# 1. Move unversioned DMGs for this app to _trash
if [ -f "$DIST_DIR/$APP_NAME.dmg" ]; then
  move_to_trash "$DIST_DIR/$APP_NAME.dmg"
fi
if [ "$APP_NAME" != "$LEGACY_NAME" ] && [ -f "$DIST_DIR/$LEGACY_NAME.dmg" ]; then
  move_to_trash "$DIST_DIR/$LEGACY_NAME.dmg"
fi

# 2. Discover all release versions for this app from DMGs in dist
VERSIONS=()
shopt -s nullglob
for f in "$DIST_DIR"/*.dmg; do
  [ -f "$f" ] || continue
  fname="$(basename "$f")"
  ver=""
  if [[ "$fname" == "$APP_NAME-"*.dmg ]]; then
    ver="${fname#"$APP_NAME-"}"
    ver="${ver%.dmg}"
  elif [ "$APP_NAME" != "$LEGACY_NAME" ] && [[ "$fname" == "$LEGACY_NAME-"*.dmg ]]; then
    ver="${fname#"$LEGACY_NAME-"}"
    ver="${ver%.dmg}"
  fi
  if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    VERSIONS+=("$ver")
  fi
done

# If no versioned DMGs found, nothing more to retain
if [ ${#VERSIONS[@]} -eq 0 ]; then
  exit 0
fi

# 3. Determine the latest 2 distinct release versions using version sort
RETAINED_VERSIONS=()
while IFS= read -r v; do
  [ -n "$v" ] || continue
  RETAINED_VERSIONS+=("$v")
done < <(printf "%s\n" "${VERSIONS[@]}" | sort -V -u | tail -n 2)

# 4. List all unique versions
UNIQUE_VERSIONS=()
while IFS= read -r v; do
  [ -n "$v" ] || continue
  UNIQUE_VERSIONS+=("$v")
done < <(printf "%s\n" "${VERSIONS[@]}" | sort -V -u)

is_retained() {
  local target="$1"
  for rv in "${RETAINED_VERSIONS[@]}"; do
    if [ "$rv" = "$target" ]; then
      return 0
    fi
  done
  return 1
}

# 5. Process each version: retain latest 2 (canonical preferred, legacy renamed/trashed),
# move older versions to _trash
for ver in "${UNIQUE_VERSIONS[@]}"; do
  can_file="$DIST_DIR/$APP_NAME-$ver.dmg"
  leg_file="$DIST_DIR/$LEGACY_NAME-$ver.dmg"

  if is_retained "$ver"; then
    if [ "$APP_NAME" != "$LEGACY_NAME" ] && [ -f "$leg_file" ]; then
      if [ -f "$can_file" ]; then
        # Canonical already exists; move duplicate legacy alias to _trash
        move_to_trash "$leg_file"
      else
        # Only legacy exists; rename to canonical format (hash and contents unchanged)
        mv "$leg_file" "$can_file"
        echo "==> Renamed retained legacy DMG to canonical: $(basename "$leg_file") -> $(basename "$can_file")"
      fi
    fi
    echo "==> Retained release DMG: $(basename "$can_file")"
  else
    # Not among latest 2: move both canonical and legacy to _trash
    if [ -f "$can_file" ]; then
      move_to_trash "$can_file"
    fi
    if [ "$APP_NAME" != "$LEGACY_NAME" ] && [ -f "$leg_file" ]; then
      move_to_trash "$leg_file"
    fi
  fi
done
