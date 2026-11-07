"""Sign and verify the desktop update index, bound to actual release artifacts."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from content_package import canonical, verify

PLATFORMS = {
    'windows-x64': ('windows-x64-setup.exe', 'windows-x64.zip'),
    'linux-x64': ('linux-amd64.deb', 'linux-fedora-x86_64.rpm',
                  'linux-opensuse-x86_64.rpm', 'linux-x86_64.AppImage',
                  'linux-x86_64.tar.gz', 'linux-x86_64.pkg.tar.zst'),
    'macos-universal': ('macos-universal.dmg', 'macos-universal.zip'),
}


def installer_names(version, platform):
    return {f'DevCat-{version}-{suffix}' for suffix in PLATFORMS[platform]}



def descriptor(value):
    name = value['name']
    size = value.get('bytes', value.get('size'))
    digest = value['sha256']
    if (not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,149}', name)
            or '..' in name or type(size) is not int or not 0 < size < 2 * 1024 ** 3
            or not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest)):
        raise ValueError('Invalid update artifact descriptor')
    return {'name': name, 'bytes': size, 'sha256': digest}


def validate(data, tag):
    version = data['version']
    if (data.get('schemaVersion') != 1 or data.get('kind') != 'devcat-update-index'
            or not isinstance(version, str) or not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', version)
            or tag != f'v{version}' or type(data['appBuild']) is not int or data['appBuild'] <= 0
            or data['channel'] not in ('stable', 'beta') or not isinstance(data['notes'], str)
            or len(data['notes']) > 12000):
        raise ValueError('Invalid signed release identity')
    content = data['content']
    package = descriptor(content)
    if (package['name'] != f'DevCat-{version}-content.json' or package['bytes'] > 192 * 1024 ** 2
            or type(content['revision']) is not int or content['revision'] <= 0
            or type(content['minAppBuild']) is not int or not 0 <= content['minAppBuild'] <= data['appBuild']):
        raise ValueError('Invalid course package identity')
    platforms = data['platforms']
    if set(platforms) != set(PLATFORMS):
        raise ValueError('Missing desktop platform')
    names = set()
    for platform, files in platforms.items():
        if not 1 <= len(files) <= 6:
            raise ValueError('Invalid platform file count')
        for item in files:
            item = descriptor(item)
            if (item['name'] not in installer_names(version, platform) or item['name'] in names):
                raise ValueError('Invalid or duplicate platform installer')
            names.add(item['name'])
    return data


def build(version, build_number, channel, notes, content, revision, minimum, artifacts):
    platforms = {platform: [] for platform in PLATFORMS}
    for item in artifacts:
        for platform in platforms:
            if item['name'] in installer_names(version, platform):
                platforms[platform].append(descriptor(item))
    data = {'schemaVersion': 1, 'kind': 'devcat-update-index', 'version': version,
            'appBuild': build_number, 'channel': channel, 'notes': notes,
            'content': {**descriptor(content), 'revision': revision, 'minAppBuild': minimum},
            'platforms': platforms}
    return validate(data, f'v{version}')


def sign(data, key_id, private_key, keys):
    payload = canonical(data)
    with tempfile.TemporaryDirectory(prefix='devcat-sign-index-') as folder:
        source, destination = Path(folder) / 'payload', Path(folder) / 'signature'
        source.write_bytes(payload)
        subprocess.run(['openssl', 'pkeyutl', '-sign', '-rawin', '-inkey', str(private_key),
                        '-in', str(source), '-out', str(destination)], check=True, capture_output=True)
        signature = destination.read_bytes()
    verify(payload, signature, base64.b64decode(keys[key_id], validate=True))
    return canonical({'keyId': key_id, 'payload': base64.b64encode(payload).decode('ascii'),
                      'signature': base64.b64encode(signature).decode('ascii')})


def verify_index(envelope, keys, tag, directory=None):
    if len(envelope) > 65536:
        raise ValueError('Update index exceeds client limit')
    outer = json.loads(envelope)
    payload = base64.b64decode(outer['payload'], validate=True)
    signature = base64.b64decode(outer['signature'], validate=True)
    verify(payload, signature, base64.b64decode(keys[outer['keyId']], validate=True))
    data = validate(json.loads(payload), tag)
    if directory is not None:
        native = [item for files in data['platforms'].values() for item in files]
        expected_native = {path.name for path in directory.iterdir()
                           if any(path.name in installer_names(data['version'], platform) for platform in PLATFORMS)}
        if {item['name'] for item in native} != expected_native:
            raise ValueError('Index does not cover every native package')
        for item in [data['content'], *native]:
            path = directory / item['name']
            digest = hashlib.sha256()
            with path.open('rb') as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b''):
                    digest.update(chunk)
            if path.stat().st_size != item['bytes'] or digest.hexdigest() != item['sha256']:
                raise ValueError(f'Update index does not match {path.name}')
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', type=int, required=True)
    parser.add_argument('--channel', choices=['stable', 'beta'], required=True)
    parser.add_argument('--notes', type=Path, required=True)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--content', type=Path, required=True)
    parser.add_argument('--content-revision', type=int, required=True)
    parser.add_argument('--min-app-build', type=int, required=True)
    parser.add_argument('--private-key', type=Path, required=True)
    parser.add_argument('--key-id', required=True)
    parser.add_argument('--keys', type=Path, default=Path('apps/devcat_flutter/assets/branding/desktop_update_keys.json'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    data = build(args.version, args.build, args.channel, args.notes.read_text(),
                 json.loads(args.content.read_text()), args.content_revision, args.min_app_build,
                 json.loads(args.assets.read_text()))
    keys = json.loads(args.keys.read_text())['keys']
    envelope = sign(data, args.key_id, args.private_key, keys)
    verify_index(envelope, keys, f'v{args.version}')
    args.output.write_bytes(envelope)
    print(json.dumps({'name': 'content-index.json', 'bytes': len(envelope),
                      'sha256': hashlib.sha256(envelope).hexdigest()}))


if __name__ == '__main__':
    main()
