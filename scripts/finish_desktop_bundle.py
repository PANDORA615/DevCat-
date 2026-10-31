"""Place toolchains beside the application; preserve upstream license files."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

repo = Path(__file__).resolve().parents[1]
target = sys.argv[1]
bundle = repo / {
    'windows': 'apps/devcat_flutter/build/windows/x64/runner/Release',
    'linux': 'apps/devcat_flutter/build/linux/x64/release/bundle',
    'macos': 'apps/devcat_flutter/build/macos/Build/Products/Release/DevCat.app/Contents/Resources',
}[target]
source = repo / 'build/desktop-runtime'
metadata = json.loads((source / 'manifest.json').read_text())
assert metadata['schema'] == 1 and len(metadata['platforms']) == (2 if target == 'macos' else 1)
destination = bundle / 'runtime'
assert not destination.exists()
if target == 'windows':
    # A test process or antivirus may briefly hold an SDK DLL open. Reading
    # the verified files is safe; deleting or renaming the source is unnecessary.
    shutil.copytree(source, destination, symlinks=True)
else:
    shutil.move(str(source), destination)
if target != 'windows':
    # Extraction staging directories can be 0700 (notably the .NET archive
    # root). A root-owned DEB/RPM or AppImage must remain readable/executable
    # by the learner, rather than only by the CI account that tested it.
    for path in [destination, *destination.rglob('*')]:
        if path.is_symlink():
            continue
        mode = path.stat().st_mode
        path.chmod(0o755 if path.is_dir() or mode & 0o111 else 0o644)
if target == 'windows':
    # App-local Microsoft runtime: the Flutter app itself must launch on a PC
    # without Visual Studio or a separately installed VC++ redistributable.
    base = Path(os.environ['ProgramFiles']) / 'Microsoft Visual Studio/2022/Enterprise/VC/Redist/MSVC'
    if not base.exists():
        base = Path(os.environ['ProgramFiles']) / 'Microsoft Visual Studio/2022/Professional/VC/Redist/MSVC'
    versions = sorted(base.glob('*/x64/Microsoft.VC143.CRT'))
    assert versions, 'Official Visual C++ app-local redistributable was not found'
    for dll in versions[-1].glob('*.dll'):
        shutil.copy2(dll, bundle / dll.name)
if target == 'linux':
    # .NET's Unicode and crypto dependencies must also be available on a fresh
    # GTK desktop. Keep them private; never replace distribution libraries.
    native = destination / 'linux-x64/native'
    native.mkdir()
    system = Path('/usr/lib/x86_64-linux-gnu')
    major = max(int(p.name.split('.so.')[1].split('.')[0]) for p in system.glob('libicuuc.so.[0-9]*'))
    (native / 'icu-version.txt').write_text(str(major))
    for name in [f'libicudata.so.{major}', f'libicuuc.so.{major}', f'libicui18n.so.{major}', 'libssl.so.3', 'libcrypto.so.3']:
        source = system / name
        assert source.exists(), f'Missing Linux runtime dependency: {name}'
        shutil.copy2(source, native / name)
    for package in [f'libicu{major}', 'libssl3']:
        shutil.copy2(Path('/usr/share/doc') / package / 'copyright', native / f'{package}-copyright.txt')
    for path in destination.rglob('*'):
        if not path.is_symlink():
            path.chmod(path.stat().st_mode & ~0o222)
    destination.chmod(destination.stat().st_mode & ~0o222)
print('Bundled runtime platforms:', metadata['platforms'], flush=True)
