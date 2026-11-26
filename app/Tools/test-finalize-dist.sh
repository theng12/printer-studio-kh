#!/bin/bash
# Focused check: app/finalize-dist.sh pins the newest two installers (this
# release and the one before it) from one receipt, and refuses a receipt the
# release rules reject. Mock DMG bytes, the real scripts and the real shared
# helper. Scratch lives under TMPDIR: a checkout never gets a _trash.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
/usr/bin/python3 -I -B - "$ROOT" <<'PY'
from pathlib import Path
import hashlib, json, os, shutil, subprocess, sys, tempfile

root = Path(sys.argv[1])
helper = Path(os.environ.get('PRINTER_STUDIO_RELEASE_DIST_HELPER',
    str(Path.home() / 'Developer/Shared Tools/portfolio/tools/release-dist.py')))
assert helper.is_file(), f'shared helper unavailable: {helper}'
work = Path(tempfile.mkdtemp(prefix='test-finalize-dist-')).resolve()
project = work / 'project'
(project / 'app').mkdir(parents=True)
for name in ('finalize-dist.sh', 'retain-dmgs.sh'):
    shutil.copy2(root / 'app' / name, project / 'app' / name)
dist = project / 'dist'
dist.mkdir()
(work / 'home/Desktop/_trash').mkdir(parents=True)
# The scripts retire into ~/Desktop/_trash, so the fixture gets its own HOME and
# a test run can never move a real installer. TMPDIR is the fixture's too, so
# finalize-dist's own pins scratch lands here and can be proved cleaned up.
(work / 'tmp').mkdir()
env = {**os.environ, 'PRINTER_STUDIO_RELEASE_DIST_HELPER': str(helper),
       'HOME': str(work / 'home'), 'TMPDIR': str(work / 'tmp')}

# 1.0.11 is never recorded in the ledger: the helper will not touch it, so the
# automatic sweep has to move it out of dist on its own. 1.0.10 is named by a
# release manifest, so the guard must keep it exactly where it is.
(dist / 'Printer Studio KH-1.0.11.dmg').write_bytes(b'mock installer 1.0.11')
(dist / 'Printer Studio KH-1.0.10.dmg').write_bytes(b'mock installer 1.0.10')
(dist / 'release.json').write_text(json.dumps({'version': '1.0.10'}))

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

# The kept depth is a validator, not only a counter: the installer retained as
# the previous one must still be evidence-checked. Withdraw 1.0.13's evidence and
# a run that still retains it has to refuse by name. A test that only counts the
# kept files passes with the validator silently narrowed — this is that trap.
saved_ledger = (dist / '.release-dist.json').read_text()
no_evidence = json.loads(saved_ledger)
del no_evidence['apps']['Printer Studio KH']['files']['Printer Studio KH-1.0.13.dmg']['evidence']
(dist / '.release-dist.json').write_text(json.dumps(no_evidence))
refused = run(new_receipt)
assert refused.returncode != 0 and '1.0.13' in refused.stderr, refused.stderr
assert snapshot() == before, 'a refused receipt must not touch dist'
(dist / '.release-dist.json').write_text(saved_ledger)

result = run(new_receipt)
assert result.returncode == 0, result.stdout + result.stderr
kept = sorted(p.name for p in dist.glob('Printer Studio KH-*.dmg'))
assert kept == ['Printer Studio KH-1.0.10.dmg', 'Printer Studio KH-1.0.13.dmg', 'Printer Studio KH-1.0.14.dmg'], kept
# The third installer is gone from dist and is recoverable in the one trash shape:
# ~/Desktop/_trash/<app>/<date> <what>/, never a mixed folder directly under _trash.
app_trash = work / 'home/Desktop/_trash/printer-studio-kh'
assert app_trash.is_dir(), 'the retirement folder is the app-and-date one, not the trash root'
folders = list(app_trash.iterdir())
assert len(folders) == 1, folders
assert folders[0].name.endswith('installers retired at 1.0.14'), folders[0].name
retired = list(folders[0].rglob('Printer Studio KH-1.0.12.dmg'))
assert retired and retired[0].read_bytes() == b'mock installer 1.0.12', 'the third installer is retired recoverably'
# The helper retires into <pin>/dist/ and the sweep into <pin>/: both must land in
# the one folder, never two layouts inside one trash.
assert all(folders[0] in p.parents for p in (work / 'home/Desktop/_trash').rglob('*.dmg')), 'both retirements share one folder'
swept = list((work / 'home/Desktop/_trash').rglob('Printer Studio KH-1.0.11.dmg'))
assert swept and swept[0].read_bytes() == b'mock installer 1.0.11', 'unmanaged older installer swept to the trash'
assert not (dist / 'Printer Studio KH-1.0.11.dmg').exists(), 'the sweep must leave dist'
assert (dist / 'Printer Studio KH-1.0.10.dmg').is_file(), 'a version named by release.json is never moved'
recorded = json.loads(new_receipt.read_text()).get('retiredInstallers') or []
moved = [entry for entry in recorded if entry['version'] == '1.0.11']
assert moved, 'every move is written into the receipt'
assert len(moved[0]['sha256']) == 64 and moved[0]['destination'].endswith('Printer Studio KH-1.0.11.dmg')
assert files['1.0.13'].read_bytes() == (dist / 'Printer Studio KH-1.0.13.dmg').read_bytes()
# What the pins document asked for is what the ledger now holds: this release
# and the one before it, with the previous installer's evidence carried across.
ledger = json.loads((dist / '.release-dist.json').read_text())['apps']['Printer Studio KH']['files']
assert sorted(ledger) == ['Printer Studio KH-1.0.13.dmg', 'Printer Studio KH-1.0.14.dmg'], ledger
assert ledger['Printer Studio KH-1.0.13.dmg']['evidence'] == files_manifest['Printer Studio KH-1.0.13.dmg']['evidence']
# Its own pins scratch is under the fixture's TMPDIR and must not survive the run,
# and nothing may have created a _trash inside the fixture project.
assert not list((work / 'tmp').glob('printer-finalize-dist.*')), 'finalize-dist left its pins scratch behind'
assert not (project / '_trash').exists(), 'finalize-dist must not write a _trash into the checkout'
repeat = sorted(p.name for p in dist.iterdir())
assert run(new_receipt).returncode == 0
assert sorted(p.name for p in dist.iterdir()) == repeat, 'a repeat run must change nothing'
print('PASS: finalize-dist pins the newest two (this release and the previous), sweeps the third into the trash without a hand step, still evidence-checks the one it retains, and refuses an unverified install or a receipt whose gate is missing, failed or covers other bytes')
print(f'Fixtures retained: {work}')
PY
