#!/usr/bin/env python3
"""Exercise the exact worker with stand-in system tools; never touch a real printer."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import shlex

root = Path(__file__).resolve().parents[2]
source = (root / "app/Resources/keep-usb-printer-ready.sh").read_text()
trash = root / "_trash"
trash.mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(dir=trash))
stub = work / "tool.py"
stub.write_text('''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
f=json.loads(os.environ['USB_FIXTURE'])
name=Path(sys.argv[0]).name
if name=='lpstat': print(f.get('queues','')); sys.exit(f.get('lpstat_status',0))
if name=='pgrep': print('123'); sys.exit(f.get('pgrep_status',0))
if name=='ps':
    key='executable' if 'comm=' in sys.argv else 'command'
    print(f[key]); sys.exit(0)
if name=='kill':
    Path(os.environ['USB_KILL_LOG']).write_text(' '.join(sys.argv[1:])); sys.exit(f.get('kill_status',0))
''')
stub.chmod(0o755)
for name in ("lpstat", "pgrep", "ps", "kill"):
    (work / name).symlink_to(stub)
    for prefix in ("/usr/bin/", "/bin/"):
        source = source.replace(prefix + name, shlex.quote(str(work / name)))
worker = work / "worker.sh"
worker.write_text(source)
base = dict(queues="device for HPLaser107a: usb://HP/HP%20Laser%20103%20107%20108?serial=ABC123",
            executable="/usr/libexec/ippusbd",
            command="/usr/libexec/ippusbd usb://HP%20Inc./HP%20Laser%20107a?serial=ABC123")
cases = [
    ("configured printer", {}, True, 0),
    ("no queue", {"queues": ""}, False, 0),
    ("different serial", {"command": base["command"].replace("ABC123", "ABC1234")}, False, 0),
    ("other model", {"command": base["command"].replace("107a", "109a")}, False, 0),
    ("other executable", {"executable": "/tmp/ippusbd"}, False, 0),
    ("extra arguments", {"command": base["command"] + " --other"}, False, 0),
    ("unsafe serial", {"command": base["command"].replace("ABC123", "ABC;touch_BAD")}, False, 0),
    ("different CUPS model", {"queues": base["queues"].replace("103%20107%20108", "109")}, False, 0),
    ("no daemon", {"pgrep_status": 1}, False, 0),
    ("CUPS unavailable", {"lpstat_status": 1}, False, 1),
    ("permission failure", {"kill_status": 1}, True, 1),
]
for name, changes, killed, status in cases:
    log = work / (name.replace(" ", "-") + ".log")
    env = dict(os.environ, USB_FIXTURE=json.dumps(base | changes), USB_KILL_LOG=str(log))
    result = subprocess.run(["/bin/bash", str(worker)], env=env, capture_output=True, text=True)
    assert result.returncode == status, (name, result.returncode, result.stderr)
    assert log.exists() == killed, name
    if killed:
        assert log.read_text() == "-TERM 123", name
    print("PASS:", name)
print("11 automatic USB checks passed; no real process was signalled.")
