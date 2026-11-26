#!/usr/bin/env python3
"""Exercise qualification failures without signing code or launching any app."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('printer_signing', Path(__file__).with_name('TestSigning.py'))
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningVerifierTests(unittest.TestCase):
    def setUp(self):
        self.app = Path(tempfile.mkdtemp(prefix='signing-verifier-')) / 'Fixture.app'
        contents = self.app / 'Contents'
        contents.mkdir(parents=True)
        (contents / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.theng12.printerstudio',
            'CFBundleShortVersionString': 'fixture', 'CFBundleVersion': '1',
        }))

    def inspect_output(self, output):
        def codesign(args):
            return subprocess.CompletedProcess(args, 0, stdout=output if '-d' in args else '', stderr='')
        with patch.object(signing, 'run', side_effect=codesign):
            return signing.inspect(self.app)

    def test_accepts_certificate_requirement(self):
        requirement = 'designated => identifier "fixture" and certificate leaf = H"abc123"'
        result = self.inspect_output('Authority=Fixture signer\n' + requirement + '\n')
        self.assertEqual(len(result['requirements']), 5)
        self.assertEqual(set(result['requirements'].values()), {requirement})

    def test_rejects_ad_hoc_cdhash_requirement(self):
        with self.assertRaises(AssertionError):
            self.inspect_output('Signature=adhoc\ndesignated => cdhash H"abc123"\n')

    def test_rejects_missing_authority(self):
        with self.assertRaises(AssertionError):
            self.inspect_output('designated => identifier "fixture" and certificate leaf = H"abc123"\n')

    def test_propagates_signature_verification_failure(self):
        failure = subprocess.CalledProcessError(1, ['codesign', '--verify'], stderr='resource envelope is obsolete')
        with patch.object(signing, 'run', side_effect=failure), self.assertRaises(subprocess.CalledProcessError):
            signing.inspect(self.app)


if __name__ == '__main__':
    unittest.main()
