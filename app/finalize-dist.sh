#!/bin/bash
# Retains the newest two installers in dist from one installed-acceptance
# receipt, so nobody has to write the pins by hand.
#
# The receipt is still the gate: retain-dmgs.sh refuses it unless launch health
# and exact built hashes are verified, so this script cannot approve anything.
#
#   app/finalize-dist.sh <installed-readme-receipt.json>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: %s <installed-readback-receipt.json>\n' "$0" >&2
  exit 2
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECEIPT="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
[ -f "$RECEIPT" ] || { printf 'No such receipt: %s\n' "$RECEIPT" >&2; exit 2; }

PINS="$ROOT/_trash/finalize-dist-$(date +%Y%m%d-%H%M%S)-$$.json"
mkdir -p "$ROOT/_trash"

/usr/bin/python3 -I -B - "$ROOT" "$RECEIPT" "$PINS" <<'PY'
import hashlib, json, re, sys
from pathlib import Path

root, receipt_path, pins_path = map(Path, sys.argv[1:])
receipt = json.loads(receipt_path.read_text())
version = receipt["version"]
dmg = root / "dist" / f"Printer Studio KH-{version}.dmg"
if not dmg.is_file():
    sys.exit(f"No installer for {version} in dist: {dmg}")

# The receipt must carry the gate that produced these exact bytes, and that gate
# must have passed. Without it the receipt proves an install, not the installer.
gate = receipt.get("gate")
if not isinstance(gate, dict):
    sys.exit(f"Receipt has no gate evidence for {version}; refusing to retain it")
log = Path(gate.get("log", ""))
if not log.is_absolute():
    log = receipt_path.parent / log
if gate.get("exit") != 0 or not log.is_file():
    sys.exit(f"Receipt's gate is missing or did not pass (exit={gate.get('exit')!r}, log={log}); refusing to retain {version}")
digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
if gate.get("artifactSha256") != digest:
    sys.exit(f"Receipt's gate covers {gate.get('artifactSha256')!r}, not the installer in dist ({digest}); refusing to retain {version}")

manifest = {}
state = root / "dist/.release-dist.json"
if state.is_file():
    manifest = json.loads(state.read_text())["apps"]["Printer Studio KH"]["files"]

def version_of(path):
    return path.stem.split("Printer Studio KH-", 1)[1]

def key(path):
    return tuple(int(p) for p in re.findall(r"\d+", version_of(path)))

others = [p for p in (root / "dist").glob("Printer Studio KH-*.dmg") if p != dmg and p.is_file()]
others.sort(key=key, reverse=True)
previous = others[0] if others else None
evidence = manifest.get(previous.name, {}).get("evidence") if previous else None
if previous and not (evidence and Path(evidence).is_file()):
    sys.exit(f"No recorded evidence for the retained installer {previous.name}")

releases = [{"version": version, "source": str(dmg), "evidence": str(receipt_path)}]
if previous:
    releases.append({"version": version_of(previous),
                     "source": str(previous), "evidence": evidence})
for release in releases:
    data = Path(release["source"]).read_bytes()
    release["sha256"] = hashlib.sha256(data).hexdigest()
    release["bytes"] = len(data)

pins = {"schema": 1, "apps": [{"app": "Printer Studio KH", "project": str(root),
                               "releases": releases,
                               "retirement_trash": str(Path.home() / "Desktop/_trash")}]}
pins_path.write_text(json.dumps(pins, indent=2) + "\n")
print(f"Pinning {', '.join(r['version'] for r in releases)}")
PY

bash "$ROOT/app/retain-dmgs.sh" "$RECEIPT" "$PINS"
