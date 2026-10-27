import base64
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
from apk_release_patch import create, apply


class SigningPatchTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = self.root / 'app-release.apk'
        self.signed = self.root / 'signed.apk'
        self.patch = self.root / 'patch.json'
        self.result = self.root / 'result' / self.signed.name
        payload = bytes(range(256)) * 2048
        with zipfile.ZipFile(self.base, 'w') as archive:
            archive.writestr('runtime.zip', payload)
            archive.writestr('app.so', payload, compress_type=zipfile.ZIP_DEFLATED)
            archive.writestr('META-INF/DEBUG.RSA', b'old certificate')
        with zipfile.ZipFile(self.signed, 'w') as archive:
            header = zipfile.ZipInfo('app.so')
            header.extra = struct.pack('<HH', 0xcafe, 64) + b'\0' * 64
            header.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(header, payload)
            archive.writestr('META-INF/OWNER.RSA', b'public signature and certificate')
            archive.writestr('runtime.zip', payload)
            archive.comment = b'public signing metadata'

    def test_exact_bytes_with_changed_offsets_metadata_order_and_compression(self):
        stats = create(self.base, self.signed, self.patch)
        self.assertGreater(stats['copiedBytes'], 512 * 1024)
        self.assertLess(stats['patchBytes'], 4096)
        apply(self.base, self.patch, self.result)
        self.assertEqual(self.result.read_bytes(), self.signed.read_bytes())
        with zipfile.ZipFile(self.result) as archive:
            self.assertIsNone(archive.testzip())

    def test_wrong_base_cannot_be_published(self):
        create(self.base, self.signed, self.patch)
        with self.base.open('ab') as stream:
            stream.write(b'corrupt')
        with self.assertRaisesRegex(AssertionError, 'Base APK checksum'):
            apply(self.base, self.patch, self.result)
        self.assertFalse(self.result.exists())

    def test_corrupt_public_signature_does_not_leave_a_release_file(self):
        create(self.base, self.signed, self.patch)
        data = json.loads(self.patch.read_text())
        segment = next(segment for segment in data['segments'] if 'data' in segment)
        literal = base64.b64decode(segment['data'])
        segment['data'] = base64.b64encode(bytes([literal[0] ^ 1]) + literal[1:]).decode()
        self.patch.write_text(json.dumps(data))
        with self.assertRaisesRegex(AssertionError, 'Reconstructed APK checksum'):
            apply(self.base, self.patch, self.result)
        self.assertFalse(self.result.exists())
        self.assertFalse(self.result.with_name(self.result.name + '.part').exists())


if __name__ == '__main__':
    unittest.main()
