import hashlib
import json
from pathlib import Path
import unittest
import wave

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'packages/cat_assets/v5_review'
ASSETS=ROOT/'apps/devcat_flutter/assets'

class MascotAssetContracts(unittest.TestCase):
    def test_review_archive_integrity_is_preserved(self):
        for line in (SOURCE/'SHA256SUMS.txt').read_text().splitlines():
            if not line.strip():continue
            expected,name=line.split(maxsplit=1)
            path=SOURCE/name.lstrip('* ')
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),expected,name)
    def test_runtime_manifest_paths_and_exact_audio(self):
        path=ASSETS/'mascot_v5'
        catalog=json.loads((path/'manifests/appearance_catalog.json').read_text())
        self.assertEqual(len(catalog['appearances']),15)
        for a in catalog['appearances']:
            self.assertTrue((path/a['asset']).is_file())
            self.assertFalse(a['productionReady'])
        states=json.loads((path/'manifests/animation_contract.json').read_text())['states']
        self.assertEqual(len(states),32)
        self.assertEqual(len(states['orientations']['frames']),8)
        for state in states.values():
            self.assertEqual(len(state['frames']),len(state['durationsMs']))
            self.assertTrue(all(t>0 for t in state['durationsMs']))
            self.assertFalse(state.get('productionReady',False))
            self.assertEqual(len({hashlib.sha256((path/f).read_bytes()).digest() for f in state['frames']}),len(state['frames']))
        audio=json.loads((path/'manifests/audio_catalog.json').read_text())['audio']
        self.assertEqual(len(audio),18)
        for a in audio:
            f=ASSETS/a['file']
            self.assertEqual(hashlib.sha256(f.read_bytes()).hexdigest(),a['sha256'])
            with wave.open(str(f)) as wav:
                self.assertEqual((wav.getnchannels(),wav.getframerate(),wav.getsampwidth()),(1,32000,2))
