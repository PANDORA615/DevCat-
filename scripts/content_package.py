"""Reproducible, data-only desktop course packages with Ed25519 signatures.

The signing key stays on the signing machine. CI reconstructs the exact payload
from the reviewed source tree and a small public signature record, then verifies
that signature against the app's pinned public key before publishing anything.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(',', ':')).encode('utf-8')


def payload(app, revision, min_build):
    if type(revision) is not int or revision < 1 or type(min_build) is not int or min_build < 0:
        raise ValueError('Invalid content revision or minimum app build')
    files = []
    total = 0
    sources = []
    virtual = {}
    for namespace in ('content', 'mascot_pixel', 'config'):
        directory = app / 'assets' / namespace
        if not directory.exists():
            continue
        for source in sorted(directory.iterdir()):
            if namespace == 'mascot_pixel' and source.name == 'frames.json':
                if source.is_symlink() or not source.is_file():
                    raise ValueError('Unsafe packed frame source')
                pack = json.loads(source.read_text())
                if pack['schema'] != 1:
                    raise ValueError('Invalid packed frame schema')
                for name, encoded in pack['files'].items():
                    if not re.fullmatch(r'assets/mascot_pixel/[a-z0-9_-]+\.png', name):
                        raise ValueError('Invalid packed frame path')
                    virtual[name] = base64.b64decode(encoded, validate=True)
                continue
            if source.suffix not in ('.json', '.png', '.jpg', '.jpeg'):
                continue
            sources.append((source, f'assets/{namespace}/{source.name}'))
    audio_catalog = app / 'assets/mascot_v5/manifests/audio_catalog.json'
    if audio_catalog.exists():
        for item in json.loads(audio_catalog.read_text())['audio']:
            name = item['file']
            if not re.fullmatch(r'audio/[a-zA-Z0-9_-]+\.wav', name):
                raise ValueError('Invalid sound catalog path')
            sources.append((app / 'assets' / name, f'assets/{name}'))
    sources.extend((None, name) for name in virtual)
    for source, name in sorted(sources, key=lambda item: item[1]):
        if source is None:
            source_name = Path(name).name
        else:
            source_name = source.name
        if ((source is not None and (source.is_symlink() or not source.is_file())) or '..' in source_name
                or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]*\.(json|png|jpg|jpeg|wav)', source_name)):
            raise ValueError(f'Unsafe content path: {source_name}')
        if name.startswith('assets/config/') and name != 'assets/config/themes.json':
            raise ValueError('Unsupported configuration file')
        data = virtual[name] if source is None else source.read_bytes()
        if name.endswith('.json'):
            json.loads(data)
        total += len(data)
        if total > 96 * 1024 * 1024:
            raise ValueError('Decoded content exceeds the client limit')
        files.append({'path': name, 'size': len(data),
                      'sha256': hashlib.sha256(data).hexdigest(),
                      'data': base64.b64encode(data).decode('ascii')})
    if not 1 <= len(files) <= 4096:
        raise ValueError('Invalid number of course assets')
    names = {file['path'].lower() for file in files}
    if len(names) != len(files):
        raise ValueError('Case-insensitive duplicate content names')
    return canonical({'schemaVersion': 1, 'kind': 'devcat-content',
                      'revision': revision, 'minAppBuild': min_build, 'files': files})


def verify(data, signature, public_key):
    if len(signature) != 64 or len(public_key) != 32:
        raise ValueError('Invalid Ed25519 signature or public key size')
    with tempfile.TemporaryDirectory(prefix='devcat-public-content-') as folder:
        directory = Path(folder)
        (directory / 'payload').write_bytes(data)
        (directory / 'signature').write_bytes(signature)
        (directory / 'public.der').write_bytes(bytes.fromhex('302a300506032b6570032100') + public_key)
        result = subprocess.run(['openssl', 'pkeyutl', '-verify', '-rawin', '-pubin',
                                 '-keyform', 'DER', '-inkey', str(directory / 'public.der'),
                                 '-in', str(directory / 'payload'), '-sigfile', str(directory / 'signature')],
                                capture_output=True)
        if result.returncode:
            raise ValueError('Content signature verification failed')


def assemble(app, record, output):
    if record.get('schema') != 1:
        raise ValueError('Unsupported content signature record')
    data = payload(app, record['revision'], record['minAppBuild'])
    if hashlib.sha256(data).hexdigest() != record['payloadSha256']:
        raise ValueError('Content source differs from the signed payload')
    keys = json.loads((app / 'assets/branding/desktop_update_keys.json').read_text())['keys']
    signature = base64.b64decode(record['signature'], validate=True)
    public = base64.b64decode(keys[record['keyId']], validate=True)
    verify(data, signature, public)
    envelope = canonical({'keyId': record['keyId'], 'payload': base64.b64encode(data).decode('ascii'),
                          'signature': record['signature']})
    if len(envelope) > 192 * 1024 * 1024:
        raise ValueError('Content envelope exceeds the client limit')
    output.write_bytes(envelope)
    return {'name': output.name, 'bytes': len(envelope), 'sha256': hashlib.sha256(envelope).hexdigest()}


def sign(app, revision, min_build, key_id, private_key):
    data = payload(app, revision, min_build)
    with tempfile.TemporaryDirectory(prefix='devcat-sign-content-') as folder:
        source, destination = Path(folder) / 'payload', Path(folder) / 'signature'
        source.write_bytes(data)
        subprocess.run(['openssl', 'pkeyutl', '-sign', '-rawin', '-inkey', str(private_key),
                        '-in', str(source), '-out', str(destination)], check=True, capture_output=True)
        signature = destination.read_bytes()
    keys = json.loads((app / 'assets/branding/desktop_update_keys.json').read_text())['keys']
    verify(data, signature, base64.b64decode(keys[key_id], validate=True))
    return {'schema': 1, 'keyId': key_id, 'revision': revision, 'minAppBuild': min_build,
            'payloadSha256': hashlib.sha256(data).hexdigest(),
            'signature': base64.b64encode(signature).decode('ascii')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path('apps/devcat_flutter'))
    parser.add_argument('--signature-record', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--private-key', type=Path)
    parser.add_argument('--revision', type=int)
    parser.add_argument('--min-app-build', type=int)
    parser.add_argument('--key-id')
    args = parser.parse_args()
    if args.private_key:
        if args.revision is None or args.min_app_build is None or not args.key_id:
            parser.error('Signing requires --revision, --min-app-build and --key-id')
        if args.signature_record.exists():
            parser.error('Refusing to overwrite an existing signature record')
        record = sign(args.app, args.revision, args.min_app_build, args.key_id, args.private_key)
        args.signature_record.write_bytes(canonical(record) + b'\n')
    else:
        record = json.loads(args.signature_record.read_bytes())
    print(json.dumps(assemble(args.app, record, args.output), ensure_ascii=False))


if __name__ == '__main__':
    main()
