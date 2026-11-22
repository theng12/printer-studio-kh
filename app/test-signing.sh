#!/bin/bash
# Run after the normal packaged build, in the assigned heavy-job slot.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIRST="${1:-$ROOT/dist/Printer Studio KH.app}"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/printer-signing.XXXXXX")"
mkdir -p "$OUT/source"
git -C "$ROOT" archive HEAD | /usr/bin/tar -x -C "$OUT/source"
/usr/bin/python3 -I - "$ROOT" "$OUT/source" <<'PY'
from pathlib import Path
import plistlib, shutil, sys
root, source = map(Path, sys.argv[1:])
# The driver binary is built separately and may be untracked in the checkout.
shutil.copytree(root / 'vendor/splix', source / 'vendor/splix', dirs_exist_ok=True)
path = source / 'app/Resources/Info.plist'
info = plistlib.loads(path.read_bytes())
info['CFBundleShortVersionString'] += '-signing-check'
info['CFBundleVersion'] += '.1'
path.write_bytes(plistlib.dumps(info))
changelog = source / 'CHANGELOG.md'
changelog.write_text('# Signing qualification fixture\n\n## ' + info['CFBundleShortVersionString'] + '\n- Private second-build fixture; never publish.\n\n' + changelog.read_text())
PY
/bin/bash "$OUT/source/app/build.sh"
/usr/bin/python3 -I "$ROOT/app/Tools/TestSigning.py" "$FIRST" "$OUT/source/dist/Printer Studio KH.app" --receipt "$OUT/signing-receipt.json"
printf 'Signing evidence retained: %s\n' "$OUT/signing-receipt.json"
