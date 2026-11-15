#!/usr/bin/env python3
"""Prove the packaged app serves the update hold: the contract's two requests, the reply shape,
the loopback-only bind, and a restart that resumes with no manual step.

Launches through the app's own signing-smoke entry, so nothing touches printer services, login
items or the owner's window. The hold takes a free port in that entry, so a copy the owner is
using is never disturbed.
"""
import argparse
import http.client
import json
import os
import plistlib
import select
import socket
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

DOMAIN = 'gui/' + str(os.getuid())


def run(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=30)


def launch(app, work):
    work.mkdir(parents=True, exist_ok=True)
    ready = work / 'ready.json'
    if ready.exists():
        ready.unlink()
    label = 'com.theng12.printerstudio.hold-test.' + uuid.uuid4().hex
    job = DOMAIN + '/' + label
    plist = work / 'job.plist'
    plist.write_bytes(plistlib.dumps({
        'Label': label,
        'ProgramArguments': [str(app / 'Contents/MacOS/PrinterStudio')],
        # The app's own hidden-run entry: no window, no printer services, a free hold port.
        'EnvironmentVariables': {'PRINTER_STUDIO_SIGNING_SMOKE': str(ready)},
        'RunAtLoad': True,
        'StandardOutPath': str(work / 'stdout'),
        'StandardErrorPath': str(work / 'stderr'),
    }))
    run(['/bin/launchctl', 'bootstrap', DOMAIN, str(plist)])
    deadline = time.monotonic() + 30
    while not ready.exists():
        if time.monotonic() > deadline:
            raise RuntimeError('packaged app did not become ready; see ' + str(work))
        time.sleep(0.1)
    health = json.loads(ready.read_text())
    return job, health


def stop(job):
    run(['/bin/launchctl', 'bootout', job])
    deadline = time.monotonic() + 10
    while run(['/bin/launchctl', 'print', job]).returncode != 113:
        if time.monotonic() > deadline:
            raise RuntimeError('the test launchd job stayed loaded')
        time.sleep(0.1)


def request(port, method, path, timeout=35):
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=timeout)
    try:
        connection.request(method, path, body=b'' if method == 'POST' else None)
        response = connection.getresponse()
        body = response.read()
        return response.status, json.loads(body or b'{}')
    finally:
        connection.close()


def lan_address():
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(('192.0.2.1', 9))
        return probe.getsockname()[0]
    except OSError:
        return None
    finally:
        probe.close()


def check(name, condition, failures):
    print(('PASS: ' if condition else 'FAIL: ') + name)
    if not condition:
        failures.append(name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('app', type=Path)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--expect-version', required=True)
    args = parser.parse_args()

    failures = []
    work = Path(tempfile.mkdtemp(prefix='hold-live-', dir=args.receipt.parent))
    record = {'app': str(args.app), 'checks': [], 'notChecked': [
        'a person clicking an action while paused (no desktop is driven)',
        'the fixed port 8642 bound by a normally-launched app: the smoke entry takes a free port',
    ]}

    job, health = launch(args.app.resolve(), work / 'run1')
    try:
        port = health.get('holdPort', -1)
        check('the packaged app started its hold listener', port > 0, failures)
        check('the packaged app reports its version', health.get('version') == args.expect_version, failures)
        record['holdPort'] = port
        base = '/api/maintenance/hold'

        status, reply = request(port, 'POST', base + '?timeout_s=0&pause_s=120')
        check('POST answers 200', status == 200, failures)
        check('the reply is exactly the contract shape',
              set(reply) == {'safe', 'unsettled', 'dispatch_paused_s', 'in_flight'}, failures)
        check('an idle app is safe to replace', reply.get('safe') is True and reply.get('unsettled') == [], failures)
        check('the pause is the one asked for', reply.get('dispatch_paused_s') == 120, failures)
        check('in_flight is real', reply.get('in_flight') == 0, failures)

        status, reply = request(port, 'DELETE', base)
        check('DELETE answers 200', status == 200, failures)
        check('DELETE resumes at once', reply.get('dispatch_paused_s') == 0, failures)

        status, reply = request(port, 'POST', base + '?timeout_s=0&pause_s=1')
        check('a one-second pause is taken as asked', status == 200 and reply.get('dispatch_paused_s') == 1, failures)

        status, _ = request(port, 'GET', base)
        check('another request is not the hold', status == 404, failures)

        address = lan_address()
        if address:
            probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            probe.settimeout(2)
            try:
                reachable = probe.connect_ex((address, port)) == 0
            finally:
                probe.close()
            check('the hold is not reachable from ' + address, not reachable, failures)
            record['loopbackOnlyCheckedFrom'] = address
        else:
            print('SKIP: no non-loopback address to try')

        record['checks'] = failures or ['all passed']
        record['firstRun'] = health
    finally:
        stop(job)

    # A restart is a fresh process with nothing remembered: it must serve a hold again with no
    # operator step, which is how an aborted install resumes by itself.
    job, health = launch(args.app.resolve(), work / 'run2')
    try:
        port = health.get('holdPort', -1)
        check('the restarted app serves the hold again', port > 0, failures)
        check('the restart is a different process', health.get('pid') != record['firstRun'].get('pid'), failures)
        status, reply = request(port, 'POST', '/api/maintenance/hold?timeout_s=0&pause_s=120')
        check('a restart answers the hold with no manual step',
              status == 200 and reply.get('safe') is True and reply.get('dispatch_paused_s') == 120, failures)
        record['checks'] = failures or ['all passed']
        record['secondRun'] = health
        record['restartedWithoutOperatorStep'] = True
    finally:
        stop(job)

    args.receipt.write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    if failures:
        print('FAILED: ' + '; '.join(failures))
        raise SystemExit(1)
    print('PASS: the packaged app serves the update hold, resumes on DELETE, and restarts open')


if __name__ == '__main__':
    main()
