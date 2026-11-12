#!/bin/bash
# Focused check: app/finalize-dist.sh pins the newest two installers from one
# receipt, and refuses a receipt the release rules reject. Mock DMG bytes, the
# real scripts and the real shared helper.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
/usr/bin/python3 -I -B - "$ROOT" <<'PY'
from pathlib import Path
import hashlib, json, os, shutil, subprocess, sys, tempfile

root = Path(sys.argv[1])
helper = Path(os.environ.get('PRINTER_STUDIO_RELEASE_DIST_HELPER',
    str(Path.home() / 'Developer/Shared Tools/portfolio/tools/release-dist.py')))
assert helper.is_file(), f'shared helper unavailable: {helper}'
(root / '_trash').mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix='test-finalize-dist-', dir=root / '_trash'))
project = work / 'project'
(project / 'app').mkdir(parents=True)
for name in ('finalize-dist.sh', 'retain-dmgs.sh'):
    shutil.copy2(root / 'app' / name, project / 'app' / name)
dist = project / 'dist'
dist.mkdir()
(work / 'home/Desktop/_trash').mkdir(parents=True)
# The scripts retire into ~/Desktop/_trash, so the fixture gets its own HOME and
# a test run can never move a real installer.
env = {**os.environ, 'PRINTER_STUDIO_RELEASE_DIST_HELPER': str(helper),
       'HOME': str(work / 'home')}

files, files_manifest = {}, {}
for version in ('1.0.12', '1.0.13', '1.0.14'):
    path = dist / f'Printer Studio KH-{version}.dmg'
    path.write_bytes(f'mock installer {version}'.encode())
    files[version] = path
    receipt = work / f'installed-{version}.json'
    gate_log = work / f'gate-{version}.log'
    gate_log.write_text(f'GATE-EXIT:0 %s\n' % version)
    receipt.write_text(json.dumps({'version': version, 'launchHealthVerified': True,
                                   'exactMainBuiltHashes': True,
                                   'gate': {'log': str(gate_log), 'exit': 0,
                                            'artifactSha256': hashlib.sha256(path.read_bytes()).hexdigest()}}))
    files_manifest[path.name] = {'version': version, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                                 'bytes': path.stat().st_size, 'evidence': str(receipt),
                                 'provenance': 'fixture'}
(dist / '.release-dist.json').write_text(json.dumps({
    'schema': 1, 'apps': {'Printer Studio KH': {'files': files_manifest}}}))

new_receipt = work / 'installed-1.0.14.json'

def run(receipt):
    return subprocess.run(['/bin/bash', str(project / 'app/finalize-dist.sh'), str(receipt)],
                          env=env, capture_output=True, text=True)

def snapshot():
    return sorted(p.name for p in dist.iterdir())

before = snapshot()
bad = work / 'bad.json'
bad.write_text(json.dumps({'version': '1.0.14', 'launchHealthVerified': False,
                           'exactMainBuiltHashes': True}))
assert run(bad).returncode != 0, 'an unverified install must be refused'
assert snapshot() == before, 'a rejected receipt must not touch dist'

# A receipt without the gate that produced these exact bytes proves nothing.
good = json.loads(new_receipt.read_text())
no_gate = work / 'no-gate.json'
no_gate.write_text(json.dumps({k: v for k, v in good.items() if k != 'gate'}))
refused = run(no_gate)
assert refused.returncode != 0 and 'gate evidence' in refused.stderr, refused.stderr
wrong_bytes = work / 'wrong-bytes.json'
wrong_bytes.write_text(json.dumps({**good, 'gate': {**good['gate'], 'artifactSha256': '0' * 64}}))
refused = run(wrong_bytes)
assert refused.returncode != 0 and 'not the installer in dist' in refused.stderr, refused.stderr
missing_log = work / 'missing-log.json'
missing_log.write_text(json.dumps({**good, 'gate': {**good['gate'], 'log': str(work / 'gone.log')}}))
refused = run(missing_log)
assert refused.returncode != 0 and 'missing or did not pass' in refused.stderr, refused.stderr
assert snapshot() == before, 'refused receipts must not touch dist'

result = run(new_receipt)
assert result.returncode == 0, result.stdout + result.stderr
kept = sorted(p.name for p in dist.glob('Printer Studio KH-*.dmg'))
assert kept == ['Printer Studio KH-1.0.13.dmg', 'Printer Studio KH-1.0.14.dmg'], kept
retired = list(work.rglob('Printer Studio KH-1.0.12.dmg'))
assert retired and retired[0].read_bytes() == b'mock installer 1.0.12', 'older installer retired recoverably'
assert files['1.0.13'].read_bytes() == (dist / 'Printer Studio KH-1.0.13.dmg').read_bytes()
pins = sorted((project / '_trash').glob('finalize-dist-*.json'))
assert pins, 'no pins document written'
document = json.loads(pins[-1].read_text())['apps'][0]
assert [r['version'] for r in document['releases']] == ['1.0.14', '1.0.13'], document['releases']
assert document['releases'][1]['evidence'] == files_manifest['Printer Studio KH-1.0.13.dmg']['evidence']
repeat = sorted(p.name for p in dist.iterdir())
assert run(new_receipt).returncode == 0
assert sorted(p.name for p in dist.iterdir()) == repeat, 'a repeat run must change nothing'
print('PASS: finalize-dist pins the newest two with recorded evidence, retires the older installer recoverably, and refuses an unverified install or a receipt whose gate is missing, failed or covers other bytes')
print(f'Fixtures retained: {work}')
PY
