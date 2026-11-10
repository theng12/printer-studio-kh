#!/bin/bash
# Release finalization only: never call from the build or before installed acceptance.
set -euo pipefail
if [ "$#" -ne 2 ]; then
  printf 'usage: %s <installed-readback.json> <accepted-dist-pins.json>\n' "$0" >&2
  exit 2
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="${PRINTER_STUDIO_RELEASE_DIST_HELPER:-$HOME/Developer/Shared Tools/portfolio/tools/release-dist.py}"
/usr/bin/python3 -I -B - "$ROOT" "$1" "$2" "$HELPER" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

project, receipt_path, pins_path, helper = map(Path, sys.argv[1:])
try:
    receipt = json.loads(receipt_path.read_text())
    pins = json.loads(pins_path.read_text())
    if receipt.get('launchHealthVerified') is not True or receipt.get('exactMainBuiltHashes') is not True:
        raise ValueError('installed launch health and exact built hashes must both be verified')
    apps = pins['apps']
    if len(apps) != 1 or apps[0]['app'] != 'Printer Studio KH':
        raise ValueError('pins must describe only Printer Studio KH')
    if Path(apps[0]['project']).resolve() != project.resolve():
        raise ValueError('pins must target this checkout, not another project')
    current = apps[0]['releases'][0]
    if current['version'] != receipt['version']:
        raise ValueError('first pin must match the installed and verified version')
    if Path(current['evidence']).resolve() != receipt_path.resolve():
        raise ValueError('first pin evidence must name this installed receipt')
    if not helper.is_file():
        raise ValueError(f'shared release-dist helper unavailable: {helper}')
except (OSError, ValueError, KeyError, TypeError, IndexError, AttributeError) as error:
    sys.exit(f'Retention refused before shared helper: {error}')
# The shared helper alone validates/copies pins and retires its recorded files.
raise SystemExit(subprocess.run([sys.executable, '-I', '-B', str(helper), str(pins_path)]).returncode)
PY
