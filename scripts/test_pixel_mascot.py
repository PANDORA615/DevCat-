import json
import base64
import io
from pathlib import Path
import unittest
import zipfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'apps/devcat_flutter'


class PixelMascotTest(unittest.TestCase):
    def test_every_costume_has_six_clips_on_the_same_opaque_pixel_grid(self):
        catalog = json.loads((ASSETS / 'assets/mascot_pixel/catalog.json').read_text())
        packed = json.loads((ASSETS / 'assets/mascot_pixel/frames.json').read_text())['files']
        required = {'idle', 'blink', 'talk', 'happy', 'thinking', 'error'}
        self.assertEqual(len(catalog['appearances']), 16)  # 15 skins plus the book cat.
        for appearance in catalog['appearances']:
            clips = catalog['clips'][appearance['id']]
            self.assertTrue(required <= clips.keys(), appearance['id'])
            self.assertIn(appearance['asset'], packed)
            for state, clip in clips.items():
                if clip.get('kind') == 'views':
                    self.assertEqual(len(clip['frames']), 8)
                self.assertEqual(len(clip['frames']), len(clip['durationsMs']))
                self.assertEqual(len(clip['frames']), len(clip['mouthAnchors']))
                self.assertTrue(all(duration > 0 for duration in clip['durationsMs']))
                self.assertEqual(clip['pivotNormalized'], [.5, .875])
                for path in clip['frames']:
                    image = Image.open(io.BytesIO(base64.b64decode(packed[path]))).convert('RGBA')
                    self.assertEqual(image.size, (128, 128), path)
                    self.assertTrue(set(image.getchannel('A').tobytes()) <= {0, 255}, path)
                    bounds = image.getbbox()
                    self.assertIsNotNone(bounds, path)
                    self.assertTrue(bounds[0] >= 4 and bounds[1] >= 4 and bounds[2] <= 124 and bounds[3] <= 124, path)
                    # An exported pixel is a solid 4x4 square; no resampling halo.
                    rebuilt = image.resize((32, 32), Image.Resampling.NEAREST).resize((128, 128), Image.Resampling.NEAREST)
                    self.assertEqual(image.tobytes(), rebuilt.tobytes(), path)

    def test_pixel_masters_are_editable_and_original_reference_stays_separate(self):
        with zipfile.ZipFile(ROOT / 'docs/DevCat-pixel-masters.zip') as masters:
            manifest = json.loads(masters.read('manifest.json'))
            for states in manifest['appearances'].values():
                for clip in states.values():
                    for frame in clip['frames']:
                        self.assertIn(str(Path(frame).with_suffix('.svg')), masters.namelist())


if __name__ == '__main__':
    unittest.main()
