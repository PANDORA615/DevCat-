from pathlib import Path
import subprocess
import tempfile
import unittest
from stage_android_baseline import stage


class FrozenAndroidSource(unittest.TestCase):
    def test_new_desktop_files_never_leak_into_android(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / 'repo'
            repo.mkdir()
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=repo, stderr=subprocess.DEVNULL).decode().strip()
            git('init')
            git('config', 'user.name', 'Test')
            git('config', 'user.email', 'test@example.invalid')
            app = repo / 'apps/devcat_flutter'
            app.mkdir(parents=True)
            (app / 'pubspec.yaml').write_text('name: devcat\nversion: 0.8.0+9\n')
            (app / 'shared.dart').write_bytes(b'original sync protocol\n')
            git('add', '.')
            git('commit', '-m', 'Android baseline')
            commit = git('rev-parse', 'HEAD')
            (app / 'shared.dart').write_text('desktop changes')
            (app / 'desktop_only.dart').write_text('new feature')
            target = root / 'android'
            stage(repo, commit, target, '0.9.0+10')
            self.assertEqual((target / 'shared.dart').read_bytes(), b'original sync protocol\n')
            self.assertFalse((target / 'desktop_only.dart').exists())
            self.assertEqual((target / 'pubspec.yaml').read_text(), 'name: devcat\nversion: 0.9.0+10\n')
            self.assertEqual((app / 'shared.dart').read_text(), 'desktop changes')
            with self.assertRaises(ValueError):
                stage(repo, commit, target, '0.9.0+10')

    def test_only_exact_commit_and_semantic_version_are_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'android'
            with self.assertRaises(ValueError):
                stage(directory, 'main', target, '0.9.0+10')
            with self.assertRaises(ValueError):
                stage(directory, 'a' * 40, target, 'invalid')
