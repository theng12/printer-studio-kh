#!/bin/bash
# Focused installed-acceptance integration; mock DMG bytes, real shared helper.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
/usr/bin/python3 -I -B - "$ROOT" <<'PY'
from pathlib import Path
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
helper = Path(os.environ.get('PRINTER_STUDIO_RELEASE_DIST_HELPER',
    str(Path.home() / 'Developer/Shared Tools/portfolio/tools/release-dist.py')))
assert helper.is_file(), f'shared helper unavailable: {helper}'
work = Path(tempfile.mkdtemp(prefix='test-installed-dist-',
                              dir=os.environ.get('TMPDIR', '/tmp')))
project = work / 'project'
(project / 'app/Resources').mkdir(parents=True)
dist = project / 'dist'
dist.mkdir()
entry = project / 'app/retain-dmgs.sh'
shutil.copy2(root / 'app/retain-dmgs.sh', entry)
env = {**os.environ, 'PRINTER_STUDIO_RELEASE_DIST_HELPER': str(helper)}
files, receipts = {}, {}
for n in (1, 2, 3, 4):
    files[n] = work / f'build-{n}.dmg'
    files[n].write_bytes(f'verified mock installer {n}'.encode())
    receipts[n] = work / f'installed-{n}.json'
    receipts[n].write_text(json.dumps({'version': f'1.0.{n}',
        'launchHealthVerified': True, 'exactMainBuiltHashes': True}))

def pins(versions):
    return {'schema': 1, 'apps': [{'app': 'Printer Studio KH',
        'project': str(project), 'releases': [{'version': f'1.0.{n}',
            'source': str(files[n]), 'sha256': hashlib.sha256(files[n].read_bytes()).hexdigest(),
            'bytes': files[n].stat().st_size, 'evidence': str(receipts[n])} for n in versions]}]}

pinfile = work / 'pins.json'
calls = 0

def run(receipt, document, succeeds):
    global calls
    calls += 1
    pinfile.write_text(json.dumps(document))
    result = subprocess.run([str(entry), str(receipt), str(pinfile)], env=env,
        capture_output=True, text=True)
    (work / f'call-{calls}.txt').write_text(result.stdout + result.stderr)
    assert (result.returncode == 0) == succeeds, result.stdout + result.stderr
    return result

def snapshot():
    return {str(p.relative_to(dist)): p.read_bytes() for p in dist.rglob('*') if p.is_file()}

run(receipts[2], pins([2, 1]), True)
assert (dist / 'Printer Studio KH-1.0.1.dmg').read_bytes() == files[1].read_bytes()
assert (dist / 'Printer Studio KH-1.0.2.dmg').read_bytes() == files[2].read_bytes()
# A new build candidate and unrelated/unmanaged images cannot retire the accepted pair.
shutil.copy2(files[3], dist / 'Printer Studio KH-1.0.3.dmg')
(dist / 'Other App-9.0.0.dmg').write_bytes(b'other app')
(dist / 'Printer Studio KH-0.9.0.dmg').write_bytes(b'unknown provenance')
before = snapshot()
failed = work / 'failed-install.json'
failed.write_text(json.dumps({'version': '1.0.3', 'launchHealthVerified': False,
    'exactMainBuiltHashes': True}))
assert 'launch health' in run(failed, pins([3, 2]), False).stderr
assert snapshot() == before
run(work / 'missing.json', pins([3, 2]), False)
assert snapshot() == before
run(receipts[2], pins([3, 2]), False)
assert snapshot() == before
mismatch = pins([3, 2])
mismatch['apps'][0]['releases'][0]['evidence'] = str(receipts[2])
run(receipts[3], mismatch, False)
assert snapshot() == before
bad_hash = pins([3, 2])
bad_hash['apps'][0]['releases'][0]['sha256'] = '0' * 64
run(receipts[3], bad_hash, False)
assert snapshot() == before
print('PASS: failed/missing/wrong receipt and hash mismatch preserve accepted pair and ledger')

run(receipts[3], pins([3, 2]), True)
assert not (dist / 'Printer Studio KH-1.0.1.dmg').exists()
assert (dist / 'Printer Studio KH-1.0.2.dmg').read_bytes() == files[2].read_bytes()
assert (dist / 'Printer Studio KH-1.0.3.dmg').read_bytes() == files[3].read_bytes()
assert (dist / 'Other App-9.0.0.dmg').read_bytes() == b'other app'
assert (dist / 'Printer Studio KH-0.9.0.dmg').read_bytes() == b'unknown provenance'
assert any(p.read_bytes() == files[1].read_bytes() for p in (project / '_trash/dist').rglob('*.dmg'))
accepted = snapshot()
run(receipts[3], pins([3, 2]), True)
assert snapshot() == accepted
bad_next = pins([4, 3])
bad_next['apps'][0]['releases'][0]['sha256'] = '0' * 64
run(receipts[4], bad_next, False)
assert snapshot() == accepted
print('PASS: shared helper keeps accepted pair, recoverable previous image and unmanaged files; repeat is unchanged')

# Existing installer collision must stop before signing or moving the app bundle.
shutil.copy2(root / 'app/build.sh', project / 'app/build.sh')
# build.sh checks the vendored shim and sources the toolchain pin (1.0.46) before
# it reaches the installer-collision check, so the fixture needs both beside it.
shutil.copy2(root / 'app/toolchain.sh', project / 'app/toolchain.sh')
shutil.copytree(root / 'vendor' / 'khsparkle', project / 'vendor' / 'khsparkle')
shutil.copy2(root / 'app/signing.sh', project / 'app/signing.sh')
shutil.copytree(root / 'app/Resources', project / 'app/Resources', dirs_exist_ok=True)
(project / 'app/Resources/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.0.3'}))
app = dist / 'Printer Studio KH.app'
app.mkdir()
(app / 'marker').write_text('working app')
result = subprocess.run(['/bin/bash', str(project / 'app/build.sh'), '--dmg'], capture_output=True, text=True)
assert result.returncode != 0 and 'Installer already exists' in result.stderr, result.stderr
assert snapshot() == {**accepted, 'Printer Studio KH.app/marker': b'working app'}
build_source = (root / 'app/build.sh').read_text()
assert 'retain-dmgs.sh' not in build_source
assert '-ov -format' not in build_source
assert 'mv "$DMG"' not in build_source
print('PASS: build cannot replace an existing installer and has no retention call')
print(f'Fixtures retained: {work}')
PY
