import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from compact_android_image import compact, PROFILE


class CompactImageTest(unittest.TestCase):
    def test_replaces_readonly_metadata_and_keeps_execution_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / 'x86_64.zip'
            required = [
                'opt/dotnet/sdk/8.0/Roslyn/bincore/csc.dll',
                'opt/dotnet/packs/Microsoft.NETCore.App.Ref/8.0/ref/net8.0/System.Runtime.dll',
                'opt/java/bin/javac', 'opt/java/lib/modules',
                'opt/node/bin/node', 'usr/local/go/bin/go',
            ]
            with zipfile.ZipFile(image, 'w') as archive:
                for name in required:
                    archive.writestr(name, b'execution-payload')
                archive.writestr('opt/java/lib/src.zip', b'optional-source' * 1000)
                archive.writestr('_devcat_links.json', json.dumps({
                    'opt/java/bin/java': 'javac',
                    'opt/node/include/optional-link': '../include/node.h',
                }))
            metadata = root / 'x86_64.json'
            metadata.write_text(json.dumps({
                'abi': 'x86_64', 'bytes': image.stat().st_size,
                'sha256': hashlib.sha256(image.read_bytes()).hexdigest(),
            }))
            metadata.chmod(0o444)
            compact(root)
            result = json.loads(metadata.read_text())
            self.assertEqual(result['imageProfile'], PROFILE)
            self.assertEqual(result['sha256'], hashlib.sha256(image.read_bytes()).hexdigest())
            with zipfile.ZipFile(image) as archive:
                for name in required:
                    self.assertEqual(archive.read(name), b'execution-payload')
                self.assertNotIn('opt/java/lib/src.zip', archive.namelist())
                self.assertEqual(json.loads(archive.read('_devcat_links.json')),
                                 {'opt/java/bin/java': 'javac'})
            compact(root)  # The verified profile is safely reusable.


if __name__ == '__main__':
    unittest.main()
