"""Install verified, relocatable toolchains into the distributable app.

Only packaging downloads archives. The installed application never downloads
compilers. Original license files and standard libraries are preserved.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request
import zipfile

REPO = Path(__file__).resolve().parents[1]


def install(platforms, output, cache):
    config = json.loads((REPO / 'scripts/desktop_runtime_versions.json').read_text())
    output.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    manifest = {'schema': 1, 'platforms': platforms, 'components': {}}
    for platform in platforms:
        manifest['components'][platform] = {}
        for name, item in config['platforms'][platform].items():
            algorithm = 'sha512' if 'sha512' in item else 'sha256'
            expected = item[algorithm].lower()
            archive = cache / expected
            def valid(path):
                with path.open('rb') as f:
                    digest = hashlib.new(algorithm)
                    for block in iter(lambda: f.read(1024 * 1024), b''):
                        digest.update(block)
                    return digest.hexdigest() == expected
            if not archive.exists() or not valid(archive):
                partial = archive.with_suffix('.part')
                with urllib.request.urlopen(item['url'], timeout=120) as src, partial.open('wb') as dst:
                    shutil.copyfileobj(src, dst)
                if not valid(partial):
                    partial.unlink()
                    raise RuntimeError(f'Upstream checksum mismatch: {platform}/{name}')
                partial.replace(archive)
            target = output / platform / name
            with tempfile.TemporaryDirectory(prefix='devcat-extract-', dir=output) as folder:
                extracted = Path(folder)
                if item['url'].endswith('.zip'):
                    with zipfile.ZipFile(archive) as z:
                        for member in z.namelist():
                            if Path(member).is_absolute() or '..' in Path(member).parts:
                                raise ValueError('Unsafe archive path')
                        z.extractall(extracted)
                else:
                    with tarfile.open(archive) as t:
                        t.extractall(extracted, **({'filter': 'data'} if hasattr(tarfile, 'data_filter') else {}))
                root = extracted
                for _ in range(item['strip']):
                    entries = list(root.iterdir())
                    if len(entries) != 1 or not entries[0].is_dir():
                        raise RuntimeError(f'Unexpected archive layout: {platform}/{name}')
                    root = entries[0]
                if name == 'java' and (root / 'Contents/Home').is_dir():
                    root = root / 'Contents/Home'
                if target.exists():
                    shutil.rmtree(target)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copytree(root, target, symlinks=True)
            manifest['components'][platform][name] = item
            print(platform, name, item['version'], 'checksum verified and bundled', flush=True)
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--platform', action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cache', type=Path, default=REPO / 'build/desktop-downloads')
    args = parser.parse_args()
    install(args.platform, args.output, args.cache)
