"""Export nearest-neighbour desktop icons; Android can remain frozen separately."""
import argparse
import io
from pathlib import Path
import struct
from PIL import Image

root = Path(__file__).resolve().parents[1]
app = root / 'apps/devcat_flutter'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--desktop-only', action='store_true')
args = parser.parse_args()
icon = Image.open(app / 'assets/branding/icon.png').convert('RGBA')
if not args.desktop_only:
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        icon.resize((size, size), Image.Resampling.NEAREST).save(app / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
for size in [16, 32, 64, 128, 256, 512, 1024]:
    icon.resize((size, size), Image.Resampling.NEAREST).save(app / f'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png')
# Pillow's ICO writer resizes additional entries internally. Embed our own crisp
# PNG entries instead, so every launcher size uses nearest-neighbour sampling.
sizes = [16, 32, 48, 64, 128, 256]
entries, images = [], []
offset = 6 + 16 * len(sizes)
for size in sizes:
    stream = io.BytesIO()
    icon.resize((size, size), Image.Resampling.NEAREST).save(stream, format='PNG')
    data = stream.getvalue()
    entries.append(struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(data), offset))
    images.append(data)
    offset += len(data)
(app / 'windows/runner/resources/app_icon.ico').write_bytes(struct.pack('<HHH', 0, 1, len(sizes)) + b''.join(entries + images))
icon.resize((512, 512), Image.Resampling.NEAREST).save(root / 'packages/cat_assets/devcat.png')
