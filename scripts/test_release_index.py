import base64
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from release_index import build, sign, verify_index


class ReleaseIndexTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='devcat-index-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.key = self.root / 'private.pem'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(self.key)], check=True, capture_output=True)
        public = subprocess.check_output(['openssl', 'pkey', '-in', str(self.key), '-pubout', '-outform', 'DER'])[-32:]
        self.keys = {'test': base64.b64encode(public).decode()}
        self.assets = []
        for name in ['DevCat-0.9.1-windows-x64-setup.exe', 'DevCat-0.9.1-linux-amd64.deb', 'DevCat-0.9.1-linux-fedora-x86_64.rpm', 'DevCat-0.9.1-linux-opensuse-x86_64.rpm', 'DevCat-0.9.1-linux-x86_64.AppImage', 'DevCat-0.9.1-linux-x86_64.pkg.tar.zst', 'DevCat-0.9.1-linux-x86_64.tar.gz', 'DevCat-0.9.1-macos-universal.dmg', 'DevCat-0.9.1-content.json']:
            data = name.encode()
            (self.root / name).write_bytes(data)
            self.assets.append({'name': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
        self.data = build('0.9.1', 11, 'beta', 'Release notes', self.assets[-1], 1, 11, self.assets)

    def test_signature_binds_real_platform_packages_and_content(self):
        envelope = sign(self.data, 'test', self.key, self.keys)
        self.assertEqual(len(self.data['platforms']['linux-x64']), 6)
        self.assertEqual(verify_index(envelope, self.keys, 'v0.9.1', self.root), self.data)
        (self.root / self.assets[0]['name']).write_bytes(b'changed')
        with self.assertRaises(ValueError):
            verify_index(envelope, self.keys, 'v0.9.1', self.root)

    def test_tag_substitution_and_modified_signature_are_rejected(self):
        envelope = sign(self.data, 'test', self.key, self.keys)
        with self.assertRaises(ValueError):
            verify_index(envelope, self.keys, 'v9.9.9')
        modified = json.loads(envelope)
        modified['signature'] = base64.b64encode(b'x' * 64).decode()
        with self.assertRaises(ValueError):
            verify_index(json.dumps(modified).encode(), self.keys, 'v0.9.1')

    def test_wrong_platform_or_incomplete_native_inventory_is_rejected(self):
        bad = [dict(item) for item in self.assets]
        bad[0]['name'] = 'DevCat-0.9.1-linux-x64.exe'
        with self.assertRaises(ValueError):
            build('0.9.1', 11, 'beta', '', bad[-1], 1, 11, bad)
        envelope = sign(self.data, 'test', self.key, self.keys)
        (self.root / self.assets[1]['name']).unlink()
        with self.assertRaises(ValueError):
            verify_index(envelope, self.keys, 'v0.9.1', self.root)


if __name__ == '__main__':
    unittest.main()
