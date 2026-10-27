"""Rebuild exact owner-signed APK bytes using a verified public CI APK.

ZIP entry payloads survive zipalign/apksigner unchanged. Copy identical raw
payloads from the CI archive and transfer only headers, public signatures and
changed metadata. No private key is read or transmitted by this module.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct
import zipfile

BLOCK = 1024 * 1024


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def region_hash(stream, offset, length):
    stream.seek(offset)
    result = hashlib.sha256()
    while length:
        block = stream.read(min(BLOCK, length))
        if not block:
            raise ValueError('Truncated ZIP payload')
        result.update(block)
        length -= len(block)
    return result.hexdigest()


def payload(stream, entry):
    stream.seek(entry.header_offset)
    header = stream.read(30)
    if len(header) != 30 or header[:4] != b'PK\x03\x04' or entry.flag_bits & 1:
        raise ValueError('Unsupported ZIP entry')
    name, extra = struct.unpack_from('<HH', header, 26)
    return entry.header_offset + 30 + name + extra, entry.compress_size


def create(base, signed, output):
    base, signed, output = map(Path, (base, signed, output))
    patch = {'schema': 1, 'base': {'name': base.name, 'bytes': base.stat().st_size, 'sha256': digest(base)},
             'target': {'name': signed.name, 'bytes': signed.stat().st_size, 'sha256': digest(signed)},
             'segments': []}
    literal_bytes = 0
    copied_bytes = 0
    with base.open('rb') as original, signed.open('rb') as target, zipfile.ZipFile(base) as before, zipfile.ZipFile(signed) as after:
        entries = {entry.filename: entry for entry in before.infolist()}
        assert len(entries) == len(before.infolist()), 'Duplicate base ZIP entries'
        assert len({e.filename for e in after.infolist()}) == len(after.infolist()), 'Duplicate target ZIP entries'
        position = 0

        def literal(start, end):
            nonlocal literal_bytes
            if end <= start:
                return
            literal_bytes += end - start
            if literal_bytes > 32 * BLOCK:
                raise ValueError('APK payloads changed too much for a signing patch')
            target.seek(start)
            data = target.read(end - start)
            assert len(data) == end - start
            patch['segments'].append({'data': base64.b64encode(data).decode('ascii')})

        for entry in sorted(after.infolist(), key=lambda entry: entry.header_offset):
            start, length = payload(target, entry)
            assert start >= position and start + length <= patch['target']['bytes']
            previous = entries.get(entry.filename)
            reusable = previous is not None and previous.compress_type == entry.compress_type and previous.compress_size == length
            if reusable:
                offset, _ = payload(original, previous)
                reusable = region_hash(original, offset, length) == region_hash(target, start, length)
            if reusable and length:
                literal(position, start)
                patch['segments'].append({'copy': [offset, length]})
                copied_bytes += length
                position = start + length
        literal(position, patch['target']['bytes'])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(patch, separators=(',', ':')) + '\n')
    return {'copiedBytes': copied_bytes, 'literalBytes': literal_bytes, 'patchBytes': output.stat().st_size}


def apply(base, patch_file, output):
    base, patch_file, output = map(Path, (base, patch_file, output))
    patch = json.loads(patch_file.read_text())
    assert patch['schema'] == 1
    assert base.name == patch['base']['name']
    assert base.stat().st_size == patch['base']['bytes'] and digest(base) == patch['base']['sha256'], 'Base APK checksum mismatch'
    assert output.name == patch['target']['name']
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + '.part')
    checksum = hashlib.sha256()
    size = 0
    try:
        with base.open('rb') as original, temporary.open('wb') as target:
            for segment in patch['segments']:
                if set(segment) == {'copy'}:
                    offset, remaining = segment['copy']
                    assert type(offset) is int and type(remaining) is int
                    assert offset >= 0 and remaining >= 0 and offset + remaining <= patch['base']['bytes']
                    original.seek(offset)
                    while remaining:
                        block = original.read(min(BLOCK, remaining))
                        assert block
                        target.write(block); checksum.update(block); size += len(block)
                        assert size <= patch['target']['bytes']
                        remaining -= len(block)
                else:
                    assert set(segment) == {'data'}
                    data = base64.b64decode(segment['data'], validate=True)
                    target.write(data); checksum.update(data); size += len(data)
                    assert size <= patch['target']['bytes']
        assert size == patch['target']['bytes'] and checksum.hexdigest() == patch['target']['sha256'], 'Reconstructed APK checksum mismatch'
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    return patch['target']


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['create', 'apply'])
    parser.add_argument('base', type=Path)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(json.dumps((create if args.action == 'create' else apply)(args.base, args.input, args.output)))
