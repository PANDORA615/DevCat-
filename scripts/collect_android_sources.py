#!/usr/bin/env python3
"""Collect exact Debian corresponding source archives for release distribution.

Run in Debian bookworm with python3, ca-certificates and its trusted archive keys.
Pass all runtime inventory JSON files; one source archive covers all three ABIs.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
from build_android_rootfs import download


def collect(inventories, folder, output):
    folder.mkdir(parents=True, exist_ok=True)
    packages = set()
    for path in inventories:
        for package in json.loads(path.read_text())['packages']:
            fields = dict(line.split(': ', 1) for line in package['metadata'].splitlines() if ': ' in line)
            source = re.fullmatch(r'([^ ]+)(?: \(([^)]+)\))?', fields.get('Source', fields['Package']))
            version = source[2] or re.sub(r'\+b\d+$', '', fields['Version'])
            packages.add((source[1], version))
    sources = folder / 'sources.list'
    sources.write_text(
        'deb-src https://deb.debian.org/debian bookworm main\n'
        'deb-src https://deb.debian.org/debian bookworm-updates main\n'
        'deb-src https://security.debian.org/debian-security bookworm-security main\n'
    )
    options = ['-o', f'Dir::Etc::sourcelist={sources}', '-o', 'Dir::Etc::sourceparts=-',
               '-o', 'Acquire::https::CaInfo=' + os.environ.get('SSL_CERT_FILE', '/etc/ssl/certs/ca-certificates.crt')]
    subprocess.run(['apt-get', *options, 'update'], check=True)
    for name, version in sorted(packages):
        print('CORRESPONDING_SOURCE', name, version, flush=True)
        subprocess.run(['apt-get', *options, 'source', '--download-only', '--only-source', f'{name}={version}'], cwd=folder, check=True)
    selected = set()
    found = set()
    for path in folder.glob('*.dsc'):
        text = path.read_text()
        name = re.search(r'^Source: (.+)$', text, re.M)[1]
        version = re.search(r'^Version: (.+)$', text, re.M)[1]
        if (name, version) not in packages:
            continue
        found.add((name, version))
        selected.add(path.name)
        checksums = re.search(r'^Checksums-Sha256:\n((?: .+\n)+)', text, re.M)[1]
        for line in checksums.splitlines():
            digest, size, filename = line.split()
            source = folder / filename
            assert source.name == filename and source.is_file()
            with source.open('rb') as stream:
                assert hashlib.file_digest(stream, 'sha256').hexdigest() == digest
            assert source.stat().st_size == int(size)
            selected.add(filename)
    assert found == packages, sorted(packages - found)
    config = json.loads((Path(__file__).parent / 'android_runtime_versions.json').read_text())
    java_source = folder / 'Liberica-JDK21-corresponding-sources.tar.gz'
    download(config['javaSources'], java_source, 'sha256')
    selected.add(java_source.name)
    records = []
    for name in sorted(selected):
        path = folder / name
        with path.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        records.append({'name': path.name, 'bytes': path.stat().st_size, 'sha256': digest})
    manifest = folder / 'SOURCE_MANIFEST.json'
    manifest.write_text(json.dumps({'packages': sorted(packages), 'java': config['javaVersion'],
                                   'javaSource': config['javaSources'], 'files': records}, indent=2) + '\n')
    with tarfile.open(output, 'w') as archive:
        for name in [r['name'] for r in records] + ['SOURCE_MANIFEST.json']:
            archive.add(folder / name, arcname=name)
    print('SOURCE_ARCHIVE', output, output.stat().st_size, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--folder', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('inventories', type=Path, nargs='+')
    args = parser.parse_args()
    collect([p.resolve() for p in args.inventories], args.folder.resolve(), args.output.resolve())
