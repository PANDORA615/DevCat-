#!/usr/bin/env python3
"""Create a bundled, offline execution image. Run inside Debian bookworm.

The host only downloads and extracts foreign-architecture packages; it does not
execute them. No maintainer script is run and no Android-side package download
is needed. Package signatures and the SDK/toolchain hashes are verified.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request
import zipfile


def run(*args):
    subprocess.run(args, check=True)


def download(item, path, algorithm):
    def verified(candidate):
        if not candidate.exists():
            return False
        digest = hashlib.new(algorithm)
        with candidate.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        return digest.hexdigest().lower() == item[algorithm].lower()

    if verified(path):
        return
    partial = path.with_suffix(path.suffix + '.part')
    with urllib.request.urlopen(item['url']) as source, partial.open('wb') as out:
        shutil.copyfileobj(source, out)
    if not verified(partial):
        partial.unlink()
        raise RuntimeError(f'Hash mismatch: {path}')
    partial.replace(path)


def build(abi, output, work):
    repo = Path(__file__).resolve().parent.parent
    config = json.loads((repo / 'scripts/android_runtime_versions.json').read_text())
    debarch, dotnet, goarch = {
        'arm64-v8a': ('arm64', 'linux-arm64', 'arm64'),
        'armeabi-v7a': ('armhf', 'linux-arm', 'armv6l'),
        'x86_64': ('amd64', 'linux-x64', 'amd64'),
    }[abi]
    work.mkdir(parents=True, exist_ok=True)
    archives = work / 'debs'
    (archives / 'partial').mkdir(parents=True, exist_ok=True)
    # A changed toolchain selection must not silently retain packages from an
    # earlier image (for example a second, obsolete Java or Node runtime).
    for package in archives.glob('*.deb'):
        package.unlink()
    status = work / 'empty-status'
    status.touch()
    sources = work / 'sources.list'
    sources.write_text(
        f'deb [arch={debarch}] https://deb.debian.org/debian bookworm main\n'
        f'deb [arch={debarch}] https://deb.debian.org/debian bookworm-updates main\n'
        f'deb [arch={debarch}] https://security.debian.org/debian-security bookworm-security main\n'
    )
    options = [
        '-o', f'APT::Architecture={debarch}',
        '-o', f'APT::Architectures::={debarch}',
        '-o', f'Dir::Etc::sourcelist={sources}',
        '-o', 'Dir::Etc::sourceparts=-',
        '-o', f'Dir::State::status={status}',
        '-o', f'Dir::Cache::archives={archives}',
        '-o', 'Acquire::https::CaInfo=' + os.environ.get('SSL_CERT_FILE', '/etc/ssl/certs/ca-certificates.crt'),
    ]
    run('apt-get', *options, 'update')
    run('apt-get', *options, '-y', '--download-only', '--no-install-recommends', 'install',
        'bash', 'coreutils', 'findutils', 'grep', 'sed', 'gcc', 'g++',
        'python3', 'libfontconfig1', 'libfreetype6', 'libasound2',
        'libicu72', 'libssl3', 'libgssapi-krb5-2', 'zlib1g')
    root = work / 'root'
    if root.exists():
        shutil.rmtree(root)
    root.mkdir()
    packages = []
    for package in sorted(archives.glob('*.deb')):
        run('dpkg-deb', '-x', str(package), str(root))
        fields = subprocess.check_output(
            ['dpkg-deb', '-f', str(package), 'Package', 'Version', 'Source'], text=True)
        packages.append({'deb': package.name, 'metadata': fields,
                         'sha256': hashlib.file_digest(package.open('rb'), 'sha256').hexdigest()})
    for folder in ('dev', 'proc', 'sys', 'tmp', 'root', 'work', 'opt/dotnet', 'var/tmp', 'etc'):
        (root / folder).mkdir(parents=True, exist_ok=True)
    # dpkg alternatives normally come from maintainer scripts, not .deb payloads.
    java = root / 'opt/java'
    javatar = work / 'java21.tar.gz'
    javaarch = {'arm64-v8a': 'aarch64', 'armeabi-v7a': 'arm', 'x86_64': 'x64'}[abi]
    download(config['java'][javaarch], javatar, 'sha256')
    unpack = root / 'opt/java-unpack'
    unpack.mkdir()
    with tarfile.open(javatar) as archive:
        archive.extractall(unpack, **({'filter': 'data'} if hasattr(tarfile, 'data_filter') else {}))
    next(unpack.iterdir()).rename(java)
    unpack.rmdir()
    for command in ('java', 'javac'):
        link = root / 'usr/bin' / command
        link.unlink(missing_ok=True)
        link.symlink_to(os.path.relpath(java / 'bin' / command, link.parent))
    nodetar = work / 'node22.tar.xz'
    nodearch = {'arm64-v8a': 'arm64', 'armeabi-v7a': 'armv7l', 'x86_64': 'x64'}[abi]
    download(config['node'][nodearch], nodetar, 'sha256')
    unpack = root / 'opt/node-unpack'
    unpack.mkdir()
    with tarfile.open(nodetar) as archive:
        archive.extractall(unpack, **({'filter': 'data'} if hasattr(tarfile, 'data_filter') else {}))
    next(unpack.iterdir()).rename(root / 'opt/node')
    unpack.rmdir()
    (root / 'usr/bin/node').symlink_to('/opt/node/bin/node')
    for name, command in [('dotnet', '/opt/dotnet/dotnet'), ('go', '/usr/local/go/bin/go')]:
        (root / 'usr/bin' / name).symlink_to(command)
    (root / 'etc/passwd').write_text('root:x:0:0:DevCat:/root:/bin/bash\n')
    (root / 'etc/group').write_text('root:x:0:\n')
    (root / 'etc/hosts').write_text('127.0.0.1 localhost\n::1 localhost\n')
    sdk = work / 'dotnet.tar.gz'
    download(config['dotnet'][dotnet], sdk, 'sha512')
    with tarfile.open(sdk) as archive:
        archive.extractall(root / 'opt/dotnet', **({'filter': 'data'} if hasattr(tarfile, 'data_filter') else {}))
    gotar = work / 'go.tar.gz'
    download(config['go'][goarch], gotar, 'sha256')
    (root / 'usr/local').mkdir(parents=True, exist_ok=True)
    with tarfile.open(gotar) as archive:
        archive.extractall(root / 'usr/local', **({'filter': 'data'} if hasattr(tarfile, 'data_filter') else {}))
    # Remove optional payloads, preserving compilers, standard libraries, runtime
    # reference packs, package copyright texts and every required shared library.
    for folder in (root / 'usr/share/man', root / 'usr/share/locale', java / 'jmods',
                   root / 'usr/local/go/test', root / 'usr/local/go/doc'):
        if folder.exists():
            shutil.rmtree(folder)
    links = {}
    files = []
    for parent, dirs, names in os.walk(root, followlinks=False):
        for name in dirs + names:
            path = Path(parent) / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                links[relative] = os.readlink(path)
            elif path.is_file():
                files.append(path)
    output.mkdir(parents=True, exist_ok=True)
    image = output / f'{abi}.zip'
    inventory = {'schema': 1, 'abi': abi, 'dotnet': config['dotnetVersion'],
                 'java': config['javaVersion'], 'node': config['nodeVersion'],
                 'go': config['goVersion'], 'packages': packages,
                 'unpackedBytes': sum(x.stat().st_size for x in files)}
    with zipfile.ZipFile(image, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(files):
            archive.write(path, path.relative_to(root).as_posix())
        archive.writestr('_devcat_links.json', json.dumps(links))
        archive.writestr('_devcat_inventory.json', json.dumps(inventory, indent=2))
    metadata = {'sha256': hashlib.file_digest(image.open('rb'), 'sha256').hexdigest(),
                'bytes': image.stat().st_size, **inventory}
    (output / f'{abi}.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(json.dumps({k: metadata[k] for k in ('abi', 'bytes', 'unpackedBytes', 'sha256')}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('abi', choices=['arm64-v8a', 'armeabi-v7a', 'x86_64'])
    parser.add_argument('output', type=Path)
    parser.add_argument('work', type=Path)
    args = parser.parse_args()
    build(args.abi, args.output.resolve(), args.work.resolve())
