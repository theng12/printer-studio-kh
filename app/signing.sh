#!/bin/bash
# Sourced by the packager before replacing an existing build.
SIGNING_IDENTITY="${PRINTER_STUDIO_SIGNING_IDENTITY:-KH Studio Local Signing}"
existing_identity=''
for existing_app in "$APP" '/Applications/Printer Studio KH.app'; do
  [ -d "$existing_app" ] || continue
  authority=$({ /usr/bin/codesign -dv "$existing_app" 2>&1 || true; } | /usr/bin/awk '/^Authority=/{sub(/^Authority=/, ""); print; exit}')
  [ -n "$authority" ] || continue
  if [ -n "$existing_identity" ] && [ "$existing_identity" != "$authority" ]; then
    printf 'Conflicting existing Printer signing identities; preserve both and resolve before building.\n' >&2
    exit 1
  fi
  existing_identity="$authority"
done
if [ -n "$existing_identity" ]; then
  SIGNING_IDENTITY="$existing_identity"
  printf '==> Preserving existing signing identity: %s\n' "$SIGNING_IDENTITY"
fi
if ! /usr/bin/security find-identity -p codesigning | /usr/bin/grep -Fq "\"$SIGNING_IDENTITY\""; then
  printf 'Signing identity and private key unavailable: %s. No ad-hoc fallback.\n' "$SIGNING_IDENTITY" >&2
  exit 1
fi

sign_code() {
  local path="$1" identifier="$2" authority
  authority=$({ /usr/bin/codesign -dv "$path" 2>&1 || true; } | /usr/bin/awk '/^Authority=/{sub(/^Authority=/, ""); print; exit}')
  if [ -n "$authority" ]; then
    printf '==> Preserving signed code: %s (%s)\n' "$path" "$authority"
  else
    /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --identifier "$identifier" "$path"
  fi
  /usr/bin/codesign --verify --strict "$path"
}
