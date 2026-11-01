"""Smoke tests for the local mascot v5 review gallery (standard library)."""
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import urlopen
from http.server import ThreadingHTTPServer
import zipfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('gallery', HERE / 'mascot_review_gallery.py')
gallery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gallery)


def fixtures():
    state = {'states': {'idle': {
        'title': 'Покой',
        'frames': ['animations/student/idle/000.png'],
        'durationsMs': [350],
        'loop': True,
    }}}
    appearance = {'appearances': [{
        'id': 'student', 'title': 'Ученик', 'kind': 'evolution',
        'asset': 'models/evolution/student.png', 'details': 'Шарф',
        'productionReady': False,
    }]}
    sounds = {'audio': [{
        'id': 'ui_soft_tap', 'file': 'audio/ui_soft_tap.wav',
        'channels': 1, 'sampleRate': 32000, 'bits': 16, 'durationMs': 80,
    }]}
    return {
        'manifests/animation_contract.json': json.dumps(state).encode(),
        'manifests/appearance_catalog.json': json.dumps(appearance).encode(),
        'manifests/audio_catalog.json': json.dumps(sounds).encode(),
        'animations/student/idle/000.png': b'\x89PNGdata',
        'models/evolution/student.png': b'\x89PNGother',
        'audio/ui_soft_tap.wav': b'RIFFtest',
    }


class GalleryTests(unittest.TestCase):
    def test_extracted_and_zipped_catalogs_match(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            for name, payload in fixtures().items():
                path = base / 'folder' / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(payload)
            pkg_folder = gallery.ReviewPackage(base / 'folder')
            archive_path = base / 'review.zip'
            with zipfile.ZipFile(archive_path, 'w') as archive:
                for name, payload in fixtures().items():
                    archive.writestr('DevCat_Review_v5/' + name, payload)
            pkg_zip = gallery.ReviewPackage(archive_path)
            self.assertEqual(pkg_zip.catalog, pkg_folder.catalog)
            self.assertEqual(len(pkg_zip.catalog['clips']), 1)
            self.assertEqual(pkg_zip.read('audio/ui_soft_tap.wav'), b'RIFFtest')

    def test_gallery_serves_only_manifest_package_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            for name, payload in fixtures().items():
                p = Path(directory) / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(payload)
            pkg = gallery.ReviewPackage(directory)
            server = ThreadingHTTPServer(('127.0.0.1', 0), gallery.make_handler(pkg))
            runner = threading.Thread(target=server.serve_forever, daemon=True)
            runner.start()
            base = f'http://127.0.0.1:{server.server_port}'
            try:
                with urlopen(base + '/', timeout=3) as response:
                    self.assertIn(b'DevCat v5', response.read())
                with urlopen(base + '/api/catalog', timeout=3) as response:
                    data = json.load(response)
                    self.assertEqual(len(data['appearances']), 1)
                    self.assertEqual(response.headers['Content-Type'], 'application/json; charset=utf-8')
                with urlopen(base + '/asset/animations%2Fstudent%2Fidle%2F000.png', timeout=3) as response:
                    self.assertEqual(response.read(), b'\x89PNGdata')
                for path in ['/asset/../secret.txt', '/asset/README.md', '/unknown']:
                    with self.assertRaises(HTTPError) as ctx:
                        urlopen(base + path, timeout=3)
                    self.assertEqual(ctx.exception.code, 404)
            finally:
                server.shutdown()
                server.server_close()
                runner.join(timeout=3)

    def test_path_traversal_and_duplicate_names_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            archive_path = Path(directory) / 'invalid.zip'
            with zipfile.ZipFile(archive_path, 'w') as archive:
                archive.writestr('../bad', 'no')
            with self.assertRaises(ValueError):
                gallery.ReviewPackage(archive_path)


if __name__ == '__main__':
    unittest.main()
