import base64
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from content_package import assemble, payload, sign


class ContentPackageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='devcat-package-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'assets/content').mkdir(parents=True)
        (self.root / 'assets/branding').mkdir(parents=True)
        (self.root / 'assets/content/courses.json').write_text('[{"title":"Привет"}]')
        self.key = self.root / 'test-key.pem'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(self.key)], check=True, capture_output=True)
        public = subprocess.check_output(['openssl', 'pkey', '-in', str(self.key), '-pubout', '-outform', 'DER'])[-32:]
        self.config = self.root / 'assets/branding/desktop_update_keys.json'
        self.config.write_text(json.dumps({'keys': {'test': base64.b64encode(public).decode()}}))

    def test_ci_reconstructs_exact_signed_bytes_without_private_key(self):
        record = sign(self.root, 2, 11, 'test', self.key)
        self.key.unlink()
        first, second = self.root / 'first.json', self.root / 'second.json'
        assemble(self.root, record, first)
        assemble(self.root, record, second)
        self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_changed_sources_or_signature_fail_before_output(self):
        record = sign(self.root, 2, 11, 'test', self.key)
        output = self.root / 'output.json'
        bad = dict(record, signature=base64.b64encode(b'x' * 64).decode())
        with self.assertRaises(ValueError):
            assemble(self.root, bad, output)
        (self.root / 'assets/content/courses.json').write_text('[]')
        with self.assertRaises(ValueError):
            assemble(self.root, record, output)
        self.assertFalse(output.exists())

    def test_unsafe_case_collisions_and_symlinks_are_rejected(self):
        (self.root / 'assets/content/Courses.json').write_text('[]')
        with self.assertRaises(ValueError):
            payload(self.root, 2, 11)
        (self.root / 'assets/content/Courses.json').unlink()
        (self.root / 'assets/content/linked.json').symlink_to(self.key)
        with self.assertRaises(ValueError):
            payload(self.root, 2, 11)


if __name__ == '__main__':
    unittest.main()
