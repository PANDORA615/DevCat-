#!/usr/bin/env python3
"""Validate DevCat v5 review assets without confusing review with production.

Run: python scripts/validate_mascot_v5.py DevCat_Review_v5.zip
     python scripts/validate_mascot_v5.py DevCat_Review_v5.zip --require-production
Only Python's standard library is required. Accepts a ZIP or extracted directory.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import struct
import sys
import wave
import zipfile
from contextlib import contextmanager
from io import BytesIO

CORE_STATES = {'idle', 'blink', 'talk', 'happy', 'thinking', 'error'}
EVOLUTION = ('beginner', 'student', 'developer', 'middle', 'senior', 'architect')
COSTUMES = ('space', 'hacker', 'samurai', 'winter', 'mage', 'engineer', 'pirate', 'cyberpunk', 'scientist')
VIEW_NAMES = ('front', 'front_left', 'left', 'back_three_quarter', 'back', 'front_right', 'right', 'front_sitting')
SHA_LINE = re.compile(r'^([0-9a-f]{64})  (.+)$')


def safe_path(path):
    p = PurePosixPath(path)
    return bool(path) and not path.startswith('/') and '\\' not in path and all(x not in ('', '..', '.') for x in path.split('/')) and p.as_posix() == path


@contextmanager
def package(source):
    path = Path(source)
    if path.is_dir():
        names = {p.relative_to(path).as_posix(): p for p in path.rglob('*') if p.is_file()}
        if any(not safe_path(n) or p.is_symlink() for n, p in names.items()):
            raise ValueError('Unsafe path in extracted package')
        yield names, lambda name: names[name].read_bytes()
    else:
        with zipfile.ZipFile(path) as z:
            all_names = [i.filename for i in z.infolist() if not i.is_dir()]
            if len(all_names) != len(set(all_names)) or any(not safe_path(n) for n in all_names):
                raise ValueError('Unsafe or duplicate ZIP entry')
            if any(((i.external_attr >> 16) & 0o170000) == 0o120000 for i in z.infolist()):
                raise ValueError('ZIP contains a symlink')
            roots = {n.split('/')[0] for n in all_names}
            prefix = next(iter(roots)) + '/' if len(roots) == 1 and all('/' in n for n in all_names) else ''
            names = {n[len(prefix):]: n for n in all_names}
            yield names, lambda name: z.read(names[name])


def inspect_png(payload):
    if payload[:8] != b'\x89PNG\r\n\x1a\n' or payload[12:16] != b'IHDR':
        raise ValueError('Invalid PNG signature/IHDR')
    width, height, depth, kind = struct.unpack('>IIBB', payload[16:26])
    if not 0 < width <= 8192 or not 0 < height <= 8192 or depth != 8 or kind != 6:
        raise ValueError(f'Expected 8-bit RGBA PNG, got {width}x{height}, {depth}/{kind}')
    return (width, height)


def inspect_wav(payload):
    with wave.open(BytesIO(payload), 'rb') as w:
        return (w.getnchannels(), w.getframerate(), w.getsampwidth(), w.getcomptype())


def validate(source, require_production=False):
    errors, warnings = [], []
    stats = {'files': 0, 'sha256Verified': 0, 'appearances': 0, 'animationClips': 0,
             'animationFrames': 0, 'views': 0, 'audio': 0, 'missingCoreClips': 0,
             'productionReady': False}
    with package(source) as (names, read):
        stats['files'] = len(names)

        def require(path):
            if not safe_path(path) or path not in names:
                errors.append(f'Missing/unsafe file: {path}')
                return None
            return read(path)

        def obj(path):
            data = require(path)
            if data is None:
                return {}
            try:
                return json.loads(data)
            except (ValueError, UnicodeError) as e:
                errors.append(f'Bad JSON {path}: {e}')
                return {}

        sums = require('SHA256SUMS.txt')
        if sums is not None:
            expected = {}
            for line in sums.decode('utf-8-sig').splitlines():
                match = SHA_LINE.fullmatch(line)
                if not match or not safe_path(match[2]) or match[2] in expected:
                    errors.append(f'Bad checksum entry: {line[:100]}')
                    continue
                expected[match[2]] = match[1]
            for path in names:
                if path == 'SHA256SUMS.txt':
                    continue
                if path not in expected:
                    errors.append(f'Checksum missing: {path}')
                elif hashlib.sha256(read(path)).hexdigest() != expected[path]:
                    errors.append(f'Checksum mismatch: {path}')
                else:
                    stats['sha256Verified'] += 1
            for path in expected.keys() - names.keys():
                errors.append(f'Checksum references missing file: {path}')

        appearance = obj('manifests/appearance_catalog.json').get('appearances', [])
        ids = set()
        for item in appearance:
            ident = item.get('id')
            if ident in ids:
                errors.append(f'Duplicate appearance: {ident}')
            ids.add(ident)
            payload = require(item.get('asset', ''))
            if payload is not None:
                try:
                    inspect_png(payload)
                except ValueError as e:
                    errors.append(f'{ident}: {e}')
        if ids != set(EVOLUTION + COSTUMES):
            errors.append(f'Appearance IDs differ: {sorted(ids ^ set(EVOLUTION + COSTUMES))}')
        stats['appearances'] = len(ids)
        tiers = sorted((a for a in appearance if a.get('kind') == 'evolution'), key=lambda a: a.get('minLevel', -1))
        if [(t.get('minLevel'), t.get('maxLevel')) for t in tiers] != [(1,10),(11,25),(26,50),(51,75),(76,100),(101,None)]:
            errors.append('Evolution level boundaries do not match v5 (architect starts at 101)')

        contract = obj('manifests/animation_contract.json').get('states', {})
        frames_present = set()
        for ident, state in contract.items():
            frames, durations = state.get('frames', []), state.get('durationsMs', [])
            if len(frames) != state.get('requiredFrameCount') or len(frames) != len(durations) or any(type(d) is not int or d <= 0 for d in durations):
                errors.append(f'Bad frame count/durations: {ident}')
            if state.get('next') not in contract:
                errors.append(f'Unknown next state: {ident}')
            for index, file in enumerate(frames):
                if file in frames_present:
                    errors.append(f'Frame reused in multiple states: {file}')
                frames_present.add(file)
                payload = require(file)
                if payload is not None:
                    try:
                        dimensions = inspect_png(payload)
                        if list(dimensions) != state.get('frameSize'):
                            errors.append(f'Wrong frame size: {file}')
                        if require_production and dimensions != (128, 128):
                            errors.append(f'Not 128x128 release frame: {file}')
                    except ValueError as e:
                        errors.append(f'{file}: {e}')
                if not file.endswith(f'/{index:03}.png'):
                    errors.append(f'Nonconsecutive frame name: {file}')
            if ident != 'orientations':
                stats['animationClips'] += 1
                stats['animationFrames'] += len(frames)
            if state.get('productionReady') is not True:
                warnings.append(f'Unapproved animation: {ident}')
        if not {'idle', 'blink', 'talk'}.issubset(contract):
            errors.append('Base idle/blink/talk missing')
        for name in VIEW_NAMES:
            if require(f'views/student/{name}.png') is not None:
                stats['views'] += 1
        coverage = obj('manifests/coverage.json').get('coverage', [])
        missing = set()
        for entry in coverage:
            appearance_id = entry.get('appearance')
            for state in CORE_STATES:
                if entry.get('states', {}).get(state) == 'missing':
                    missing.add((appearance_id, state))
        if {a.get('appearance') for a in coverage} != ids:
            errors.append('Coverage appearance set does not match catalog')
        stats['missingCoreClips'] = len(missing)
        if missing:
            warnings.append(f'Core costume/evolution clips missing: {len(missing)}')
        if any(x.get('productionReady') is not True for x in appearance):
            warnings.append('Static appearances have not passed manual visual approval')

        audio = obj('manifests/audio_catalog.json').get('audio', [])
        audio_ids = set()
        for entry in audio:
            ident, file = entry.get('id'), entry.get('file', '')
            if ident in audio_ids:
                errors.append(f'Duplicate audio ID: {ident}')
            audio_ids.add(ident)
            data = require(file)
            if data is None:
                continue
            try:
                if inspect_wav(data) != (1, 32000, 2, 'NONE'):
                    errors.append(f'Wrong WAV format: {file}')
            except (wave.Error, EOFError) as e:
                errors.append(f'Unreadable WAV {file}: {e}')
            if hashlib.sha256(data).hexdigest() != entry.get('sha256'):
                errors.append(f'Audio digest mismatch: {file}')
            stats['audio'] += 1
        if len(audio_ids) != 18:
            errors.append(f'Expected 18 audio IDs, found {len(audio_ids)}')
        bindings = obj('manifests/audio_bindings.json')
        for event, setting in bindings.get('events', {}).items():
            if setting.get('audio') not in {a.get('file') for a in audio}:
                errors.append(f'Event {event} references unknown sound')
            state = setting.get('animation')
            if state and state not in contract:
                errors.append(f'Event {event} references unknown animation {state}')
        for kind, samples in bindings.get('voice', {}).items():
            for sample in samples:
                if sample not in audio_ids:
                    errors.append(f'Voice {kind} references unknown audio {sample}')

        stats['productionReady'] = (not errors and not missing and
            all(a.get('productionReady') is True for a in appearance) and
            all(s.get('productionReady') is True for s in contract.values()) and
            all(s.get('frameSize') == [128, 128] for s in contract.values()))
        if require_production and not stats['productionReady']:
            errors.append('Not production-ready: manual acceptance and all appearance clips required')
    return {'structurallyValid': not errors, 'statistics': stats,
            'errors': errors, 'warnings': warnings}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', help='ZIP or extracted v5 review directory')
    parser.add_argument('--require-production', action='store_true', help='Fail on incomplete or unapproved release assets')
    parser.add_argument('--json-output', type=Path, help='Write machine-readable report')
    args = parser.parse_args()
    try:
        report = validate(args.package, args.require_production)
    except (OSError, ValueError, zipfile.BadZipFile, KeyError) as e:
        report = {'structurallyValid': False, 'statistics': {}, 'errors': [str(e)], 'warnings': []}
    result = json.dumps(report, ensure_ascii=False, indent=2)
    print(result)
    if args.json_output:
        args.json_output.write_text(result + '\n', encoding='utf-8')
    return 0 if report['structurallyValid'] else 1


if __name__ == '__main__':
    sys.exit(main())
