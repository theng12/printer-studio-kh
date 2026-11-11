#!/usr/bin/env python3
"""Compare two packaged builds and launch each without touching printer services."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import select
import subprocess
import tempfile
import time
import uuid


def run(args):
    return subprocess.run(args, capture_output=True, text=True, check=True, timeout=30)


def inspect(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.theng12.printerstudio'
    requirements, authorities, hashes = {}, {}, {}
    paths = ['.', 'Contents/MacOS/PrinterStudio',
             'Contents/Resources/label-filters/urftopdf',
             'Contents/Resources/label-filters/label-options',
             'Contents/Resources/splix/bin/rastertoqpdl']
    for relative in paths:
        path = app / relative
        run(['/usr/bin/codesign', '--verify', '--strict', str(path)])
        result = run(['/usr/bin/codesign', '-d', '-vv', '-r-', str(path)])
        text = result.stdout + result.stderr
        lines = [s.strip().removeprefix('# ') for s in text.splitlines()]
        req = [s for s in lines if s.startswith('designated =>')]
        authority = [s for s in lines if s.startswith('Authority=')]
        assert len(req) == 1 and 'cdhash ' not in req[0] and re.search(r'\b(certificate|anchor)\b', req[0]), text
        assert authority and 'Signature=adhoc' not in text, text
        requirements[relative] = req[0]
        authorities[relative] = authority[0]
        if path.is_file():
            hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    return dict(version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
                requirements=requirements, authorities=authorities, hashes=hashes)


def launch(app, expected_version, work):
    work.mkdir()
    ready = work / 'ready.json'
    label = 'com.theng12.printerstudio.signing-test.' + uuid.uuid4().hex
    domain = 'gui/' + str(os.getuid())
    job = domain + '/' + label
    plist = work / 'job.plist'
    plist.write_bytes(plistlib.dumps({
        'Label': label,
        'ProgramArguments': [str(app / 'Contents/MacOS/PrinterStudio')],
        'EnvironmentVariables': {'PRINTER_STUDIO_SIGNING_SMOKE': str(ready)},
        'RunAtLoad': True,
        'StandardOutPath': str(work / 'stdout'),
        'StandardErrorPath': str(work / 'stderr'),
    }))
    fd = os.open(work, os.O_RDONLY)
    queue = select.kqueue()
    queue.control([select.kevent(fd, filter=select.KQ_FILTER_VNODE,
        flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR, fflags=select.KQ_NOTE_WRITE)], 0)
    started = False
    try:
        run(['/bin/launchctl', 'bootstrap', domain, str(plist)])
        started = True
        deadline = time.monotonic() + 30
        while not ready.exists():
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not queue.control(None, 1, remaining):
                raise RuntimeError('Packaged app did not become ready; inspect retained test stderr')
        health = json.loads(ready.read_text())
        assert health['version'] == expected_version and health['bundleID'] == 'com.theng12.printerstudio' and health['ready'] is True
        state = run(['/bin/launchctl', 'print', job]).stdout
        pid = int(re.search(r'^\s*pid = (\d+)', state, re.M)[1])
        assert health['pid'] == pid
        queue.control(None, 10, 0)
        queue.control([select.kevent(pid, filter=select.KQ_FILTER_PROC,
            flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT, fflags=select.KQ_NOTE_EXIT)], 0)
        events = queue.control(None, 10, 2)
        assert not any(e.filter == select.KQ_FILTER_PROC for e in events), 'Packaged app exited after readiness'
        os.kill(pid, 0)
    finally:
        if started:
            run(['/bin/launchctl', 'bootout', job])
        queue.close()
        os.close(fd)
    # launchd unloads a booted-out job asynchronously (measured ~0.2 s here);
    # poll instead of racing it, or the smoke fails at random.
    deadline = time.monotonic() + 5
    while subprocess.run(['/bin/launchctl', 'print', job], capture_output=True).returncode != 113:
        assert time.monotonic() < deadline, 'Owned test launchd job remains loaded'
        time.sleep(0.1)
    return dict(health=health, survivedStartup=True, ownedJobRemoved=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('first', type=Path)
    parser.add_argument('second', type=Path)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    first, second = inspect(args.first), inspect(args.second)
    assert first['version'] != second['version'], 'Build two differing versions'
    assert first['hashes'] != second['hashes'], 'Build content must differ'
    assert first['requirements'] == second['requirements'], 'Designated requirements changed across builds'
    assert first['authorities'] == second['authorities'], 'Signing authority changed across builds'
    work = Path(tempfile.mkdtemp(prefix='signing-launch-', dir=args.receipt.parent))
    results = [launch(app.resolve(), details['version'], work / name)
               for app, details, name in [(args.first, first, 'first'), (args.second, second, 'second')]]
    args.receipt.write_text(json.dumps(dict(first=first, second=second,
        requirementsUnchangedAcrossBuilds=True, launches=results, work=str(work)), indent=2))
    print('PASS: certificate requirements stable across changed builds; both packaged apps survived isolated launchd startup')


if __name__ == '__main__':
    main()
