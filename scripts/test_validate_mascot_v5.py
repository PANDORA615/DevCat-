"""Regression tests for the v5 review-package validator (stdlib only)."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import warnings
import zipfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('validator', HERE / 'validate_mascot_v5.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class ValidatorTests(unittest.TestCase):
    def test_path_traversal_is_disallowed(self):
        for path in ['../wrong.png', '/absolute.png', 'dir/../wrong.png', 'dir\\wrong.png', 'dir//wrong.png']:
            self.assertFalse(validator.safe_path(path))
        self.assertTrue(validator.safe_path('animations/student/talk/000.png'))

    def test_png_header_requires_rgba(self):
        prefix = bytes.fromhex('89504e470d0a1a0a') + b'\x00\x00\x00\x0dIHDR'
        header = (128).to_bytes(4, 'big') * 2 + bytes([8, 6, 0, 0, 0])
        self.assertEqual(validator.inspect_png(prefix + header), (128, 128))
        with self.assertRaises(ValueError):
            validator.inspect_png(prefix + header[:9] + bytes([2]) + header[10:])
        with self.assertRaises(ValueError):
            validator.inspect_png(b'not a png')

    def test_zip_slip_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'invalid.zip'
            with zipfile.ZipFile(p, 'w') as z:
                z.writestr('DevCat_Review_v5/../secret', 'x')
            with self.assertRaises(ValueError):
                with validator.package(p):
                    pass

    def test_duplicate_zip_entry_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'invalid.zip'
            with warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                with zipfile.ZipFile(p, 'w') as z:
                    z.writestr('folder/README.md', 'x')
                    z.writestr('folder/README.md', 'y')
            with self.assertRaises(ValueError):
                with validator.package(p):
                    pass

    def test_empty_package_cannot_pass(self):
        with tempfile.TemporaryDirectory() as d:
            r = validator.validate(d)
        self.assertFalse(r['structurallyValid'])
        self.assertFalse(r['statistics']['productionReady'])
        self.assertTrue(r['errors'])


if __name__ == '__main__':
    unittest.main()
