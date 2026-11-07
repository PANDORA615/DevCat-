"""Check v5 asset integrity/coverage without claiming visual production readiness."""
from pathlib import Path
import hashlib, json, wave
root = Path(__file__).resolve().parents[1]
assets = root / 'apps/devcat_flutter/assets'
mascot = assets / 'mascot'
contract = json.loads((mascot / 'manifests/animation_contract.json').read_text())
appearances = json.loads((mascot / 'manifests/appearance_catalog.json').read_text())['appearances']
assert len(appearances) == 15
assert len([c for c in contract['states'].values() if c.get('kind') != 'views']) == 31
for item in appearances:
    assert (mascot / item['asset']).is_file(), item['asset']
for name, clip in contract['states'].items():
    assert len(clip['frames']) == clip['requiredFrameCount'] == len(clip['durationsMs']), name
    assert all(isinstance(t, int) and t > 0 for t in clip['durationsMs']), name
    assert clip['next'] in contract['states'], name
    assert all((mascot / p).is_file() for p in clip['frames']), name
assert len(list((mascot / 'views/student').glob('*.png'))) == 8
for path in (assets / 'audio').glob('*_*.wav'):
    if not path.name.startswith(('cat_voice_', 'ui_soft_')):
        continue
    with wave.open(str(path)) as audio:
        assert (audio.getnchannels(), audio.getframerate(), audio.getsampwidth()) == (1, 32000, 2), path
# Verify bytes against the archive's original checksums wherever bundled.
checked = 0
for line in (root / 'assets_source/mascot_v5/SHA256SUMS.original.txt').read_text().splitlines():
    digest, relative = line.split(maxsplit=1)
    relative = relative.lstrip('*')
    path = mascot / relative
    if relative.startswith('audio/'):
        path = assets / relative
    elif relative == 'icons/app_icon.png':
        path = assets / 'branding/icon.png'
    elif relative.startswith(('animation_masters/', 'references/', 'docs/')):
        path = root / 'assets_source/mascot_v5' / relative
    if path.is_file():
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, relative
        checked += 1
assert checked > 200, checked
print(f'OK: 15 appearances, 31 clips, 8 views, 18 WAVs; {checked} original SHA-256 checksums verified.')
