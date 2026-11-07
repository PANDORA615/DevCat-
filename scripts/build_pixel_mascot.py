"""Author DevCat poses on a shared 32-pixel grid; export 128px PNG and editable SVG.

This is a new geometric pixel master, not a downscaled/cropped review poster.
The original review artwork remains untouched in packages/cat_assets/v5_review.
"""
import json
import argparse
import base64
import zipfile
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'packages/cat_assets/pixel_v6'
INK = '#151220'
OUTLINE = '#fff3df'
PURPLE = '#9064ed'
DEEP = '#58398d'
TEAL = '#42c7aa'
DARK_TEAL = '#206f72'
BLUE = '#8fd5ff'
GOLD = '#ffd36d'
PINK = '#f59ac4'


def sprite(appearance, state='idle', phase=0, count=4, view=None):
    """All accessories attach to the same head/body coordinates in every pose."""
    on_book = appearance == 'book'
    if on_book:
        appearance = 'student'
    image = Image.new('RGBA', (32, 32))
    draw = ImageDraw.Draw(image)
    airborne = [0, -1, -2, -3, -3, -2, -1, 0]
    dy = airborne[phase * 8 // count] if state == 'jump' else 0
    if state == 'land':
        dy = [-1, 0, 1, 0][phase * 4 // count]
    bob = [0, 0, -1, 0][phase * 4 // count]
    if state not in ('idle', 'walk', 'run', 'happy', 'excited', 'celebrating', 'success'):
        bob = 0
    if state in ('sleepy', 'sleeping'):
        bob = 1
    head_y = dy + bob + (1 if view == 'front_sitting' else 0)

    def rect(box, color, shift=0):
        x, y, right, bottom = box
        draw.rectangle((x, y + shift, right - 1, bottom + shift - 1), fill=color)

    def poly(points, color, outline=None, shift=0):
        points = [(x, y + shift) for x, y in points]
        draw.polygon(points, fill=color)
        if outline:
            draw.line(points + points[:1], fill=outline, width=1, joint='curve')

    # Tail, body and grounded feet. A logical pixel is always exactly 4px at export.
    tail_tip = [0, -1, 0, 1][phase * 4 // count]
    poly([(9, 25), (6, 25), (4, 23), (4, 20 + tail_tip), (5, 19 + tail_tip),
          (7, 20 + tail_tip), (7, 22), (11, 23), (12, 26), (9, 27)], INK, OUTLINE, dy)
    if appearance == 'architect':
        poly([(11, 19), (24, 19), (27, 27), (23, 26), (21, 28), (8, 28)], DEEP, OUTLINE, dy)
    body_color = DEEP if appearance in ('developer', 'middle', 'hacker', 'cyberpunk', 'mage') else INK
    poly([(12, 18), (23, 18), (25, 21), (25, 26), (23, 28), (12, 28),
          (10, 26), (10, 21)], body_color, OUTLINE, dy)
    if appearance == 'space':
        rect((11, 21, 24, 27), OUTLINE, dy)
        rect((15, 23, 21, 26), DEEP, dy)
        rect((17, 23, 19, 24), BLUE, dy)
    if appearance == 'senior':
        poly([(11, 20), (15, 20), (16, 26), (13, 27), (11, 26)], OUTLINE, shift=dy)
        poly([(21, 20), (24, 21), (24, 27), (20, 27)], OUTLINE, shift=dy)
        rect((21, 23, 23, 24), PURPLE, dy)
    gait = (phase % 2) if state in ('walk', 'run') else 0
    rect((12 + gait, 26, 16 + gait, 28), INK, dy)
    rect((20 - gait, 26, 24 - gait, 28), INK, dy)
    rect((12 + gait, 28, 16 + gait, 29), OUTLINE, dy)
    rect((20 - gait, 28, 24 - gait, 29), OUTLINE, dy)
    if appearance != 'beginner':
        rect((11, 19, 24, 22), PURPLE, head_y)
        rect((13, 21, 16, 25), DEEP, head_y)
        rect((12, 21, 15, 24), PURPLE, head_y)
        if appearance == 'student':
            rect((11, 21, 18, 26), PURPLE, head_y)
            for x, y in [(12, 23), (13, 22), (13, 24), (16, 23), (15, 22), (15, 24)]:
                rect((x, y, x + 1, y + 1), OUTLINE, head_y)
        if appearance in ('developer', 'middle', 'senior'):
            rect((17, 23, 18, 24), OUTLINE, dy)
            rect((16, 24, 17, 25), OUTLINE, dy)
            rect((17, 25, 18, 26), OUTLINE, dy)
            rect((20, 23, 21, 24), OUTLINE, dy)
            rect((21, 24, 22, 25), OUTLINE, dy)
            rect((20, 25, 21, 26), OUTLINE, dy)
    # Head silhouette is shared; only explicit integer poses move it.
    head = [(9, 11), (9, 7), (11, 5), (14, 8), (20, 8), (23, 5),
          (25, 7), (25, 11), (27, 13), (27, 18), (25, 20),
          (10, 20), (8, 18), (8, 13)]
    if view == 'right':
        head = [(15, 12), (15, 7), (18, 5), (20, 8), (23, 6), (25, 8),
                (25, 12), (28, 14), (28, 17), (25, 20), (16, 20), (13, 18), (13, 14)]
    elif view == 'left':
        head = [(8, 12), (8, 8), (10, 6), (13, 8), (15, 5), (18, 7),
                (18, 12), (20, 14), (20, 18), (18, 20), (9, 20), (6, 17), (6, 14)]
    elif view == 'back_three_quarter':
        head = [(10, 12), (11, 7), (13, 5), (16, 8), (21, 8), (24, 6),
                (25, 8), (26, 13), (26, 18), (24, 20), (11, 20), (9, 18), (9, 14)]
    poly(head, INK, OUTLINE, head_y)
    rear = view in ('back', 'back_left', 'back_right', 'back_three_quarter')
    eye_shift = -1 if view in ('left', 'front_left') else 1 if view in ('right', 'front_right') else 0
    eyes = [11] if view == 'left' else [23] if view == 'right' else [13 + eye_shift, 21 + eye_shift]
    if rear:
        rect((11, 21, 24, 26), INK, dy)
        rect((11, 21, 24, 22), PURPLE, dy)
    mouth_x = 8 if view == 'left' else 25 if view == 'right' else 17
    if not rear:
        for x in eyes:
            if state in ('sleeping', 'sleepy') or (state == 'blink' and phase in (1, 2)):
                rect((x - 1, 15, x + 2, 16), OUTLINE, head_y)
            elif state in ('happy', 'celebrating', 'success', 'excited'):
                rect((x, 13, x + 1, 14), OUTLINE, head_y)
                rect((x - 1, 14, x, 15), OUTLINE, head_y)
                rect((x + 1, 14, x + 2, 15), OUTLINE, head_y)
            else:
                rect((x, 13, x + 2, 16), TEAL if appearance == 'hacker' else OUTLINE, head_y)
                if state in ('sad', 'failure', 'error'):
                    rect((x, 13, x + 1, 14), INK, head_y)
                if state == 'angry':
                    rect((x, 13, x + 2, 14), INK, head_y)
        if state in ('talk', 'explaining', 'text_typing') and phase % 4:
            mouth = [(17, 18, 19, 19), (17, 17, 19, 19), (16, 18, 20, 19)][phase % 3]
            rect(mouth, PINK, head_y)
        elif state in ('surprised', 'new', 'notification'):
            rect((17, 17, 19, 19), PINK, head_y)
        else:
            rect((mouth_x, 18, mouth_x + 2, 19), DEEP, head_y)
    if not rear and state == 'angry':
        draw.line([(12, 11 + head_y), (15, 12 + head_y)], fill=OUTLINE, width=1)
        draw.line([(20, 12 + head_y), (23, 11 + head_y)], fill=OUTLINE, width=1)
    if not rear and state == 'shy':
        rect((11, 16, 13, 17), PINK, head_y)
        rect((23, 16, 25, 17), PINK, head_y)
    # Costumes are authored on the shared anchors; no mirrored eye patches/tools.
    if appearance == 'middle':
        rect((7, 12, 10, 17), PURPLE, head_y)
        rect((25, 12, 28, 17), PURPLE, head_y)
        rect((11, 12, 25, 13), DEEP, head_y)
        rect((12, 13, 16, 16), BLUE, head_y)
        rect((20, 13, 24, 16), BLUE, head_y)
    elif appearance == 'senior':
        for left in (11, 19):
            poly([(left, 12), (left + 5, 12), (left + 5, 16), (left, 16)], INK, OUTLINE, head_y)
            rect((left + 2, 13, left + 3, 15), OUTLINE, head_y)
        rect((16, 13, 20, 14), OUTLINE, head_y)
    elif appearance == 'architect':
        poly([(12, 7), (11, 3), (14, 5), (17, 2), (20, 5), (23, 3), (22, 7)], GOLD, shift=head_y)
        rect((16, 4, 18, 5), PURPLE, head_y)
        rect((22, 21, 24, 23), GOLD, dy)
    elif appearance == 'space':
        draw.line([(8, 10 + head_y), (8, 7 + head_y), (11, 4 + head_y), (23, 4 + head_y), (27, 8 + head_y), (28, 17 + head_y), (25, 20 + head_y)], fill=BLUE, width=1)
        rect((7, 12, 10, 17), PURPLE, head_y)
    elif appearance == 'hacker':
        poly([(9, 12), (10, 7), (17, 3), (24, 7), (27, 12)], None, DEEP, head_y)
    elif appearance == 'samurai':
        poly([(7, 11), (17, 3), (28, 11)], GOLD, DARK_TEAL, head_y)
        rect((10, 10, 26, 11), OUTLINE, head_y)
        poly([(26, 24), (29, 18), (30, 18), (28, 25)], OUTLINE)
        rect((25, 24, 29, 25), GOLD)
    elif appearance == 'winter':
        poly([(8, 11), (10, 6), (14, 4), (22, 5), (26, 11)], PURPLE, DEEP, head_y)
        rect((8, 10, 27, 12), PURPLE, head_y)
        rect((13, 2, 16, 5), OUTLINE, head_y)
        for x in range(11, 25, 3):
            rect((x, 7, x + 1, 10), DEEP, head_y)
    elif appearance == 'mage':
        poly([(7, 11), (12, 9), (15, 2), (21, 4), (19, 8), (27, 11)], DEEP, PURPLE, head_y)
        rect((16, 5, 18, 7), GOLD, head_y)
        rect((28, 15, 29, 28), GOLD)
        poly([(27, 12), (30, 12), (30, 15), (27, 15)], BLUE, OUTLINE)
    elif appearance == 'engineer':
        poly([(7, 12), (10, 6), (14, 4), (22, 4), (26, 8), (27, 12)], GOLD, DARK_TEAL, head_y)
        rect((16, 4, 18, 11), OUTLINE, head_y)
        rect((7, 11, 28, 13), GOLD, head_y)
        rect((27, 20, 29, 27), OUTLINE)
        rect((26, 18, 27, 21), OUTLINE)
        rect((29, 18, 30, 21), OUTLINE)
        rect((27, 20, 29, 22), OUTLINE)
    elif appearance == 'pirate':
        poly([(8, 10), (10, 5), (14, 6), (17, 4), (21, 6), (25, 5), (27, 10)], INK, GOLD, head_y)
        rect((16, 6, 19, 8), OUTLINE, head_y)
        rect((19, 12, 25, 16), INK, head_y)
        rect((19, 12, 24, 13), GOLD, head_y)
    elif appearance == 'cyberpunk':
        rect((10, 12, 26, 16), PURPLE, head_y)
        rect((12, 13, 24, 15), BLUE, head_y)
        rect((14, 13, 15, 15), OUTLINE, head_y)
        rect((21, 13, 22, 15), OUTLINE, head_y)
    elif appearance == 'scientist':
        poly([(7, 7), (17, 3), (28, 7), (17, 11)], INK, PURPLE, head_y)
        rect((26, 7, 27, 12), GOLD, head_y)
    # Gesture arms stay in front of the costume and never erase head accessories.
    if state in ('greeting', 'explaining', 'excited', 'celebrating', 'happy'):
        arm_y = 18 - phase % 2
        poly([(23, 23), (24, arm_y), (27, arm_y), (27, arm_y + 3), (25, 24)], INK, OUTLINE, dy)
    elif state in ('thinking', 'thoughtful', 'idea', 'shy'):
        poly([(22, 24), (21, 20), (23, 18), (25, 19), (24, 23)], INK, OUTLINE, dy)
    if state in ('typing', 'text_typing', 'loading') or appearance == 'hacker':
        poly([(10, 24), (24, 24), (23, 29), (11, 29)], DARK_TEAL, OUTLINE)
        rect((12, 25, 22, 28), TEAL)
        rect((15 + phase % 3, 26, 18 + phase % 3, 27), OUTLINE)
    if state == 'reading' or appearance == 'scientist':
        poly([(11, 23), (17, 24), (24, 23), (24, 28), (17, 29), (11, 28)], DEEP, OUTLINE)
        rect((17, 24, 18, 29), GOLD)
    if state in ('idea', 'new', 'notification'):
        rect((28, 8 + phase % 2, 29, 11 + phase % 2), GOLD)
        rect((27, 9 + phase % 2, 30, 10 + phase % 2), GOLD)
    if on_book:
        # The front paws rest over the edge of a closed textbook.
        poly([(7, 25), (27, 25), (29, 27), (29, 29), (8, 30), (6, 28)], TEAL, DARK_TEAL)
        rect((9, 27, 28, 29), OUTLINE)
        rect((8, 26, 10, 29), DARK_TEAL)
        for left in (12, 22):
            poly([(left, 24), (left + 3, 24), (left + 3, 27), (left + 2, 28), (left, 27)], INK, OUTLINE)
    centered = Image.new('RGBA', (32, 32))
    centered.alpha_composite(image, (-2, 0))
    return centered


def export(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((128, 128), Image.Resampling.NEAREST).save(path, optimize=True)
    rows = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="128" height="128" shape-rendering="crispEdges">']
    for y in range(32):
        x = 0
        while x < 32:
            color = image.getpixel((x, y))
            end = x + 1
            while end < 32 and image.getpixel((end, y)) == color:
                end += 1
            if color[3]:
                rgb = '#%02x%02x%02x' % color[:3]
                rows.append(f'<rect x="{x}" y="{y}" width="{end-x}" height="1" fill="{rgb}"/>')
            x = end
    rows.append('</svg>')
    path.with_suffix('.svg').write_text('\n'.join(rows) + '\n')


def install_runtime(manifest):
    runtime = ROOT / 'apps/devcat_flutter/assets/mascot_pixel'
    runtime.mkdir(exist_ok=True)
    legacy = ROOT / 'apps/devcat_flutter/assets/mascot_v5/manifests'
    original = json.loads((legacy / 'appearance_catalog.json').read_text())['appearances']
    contract = json.loads((legacy / 'animation_contract.json').read_text())['states']
    appearances, clips, packed = [], {}, {}
    for name, states in manifest['appearances'].items():
        old = next((item for item in original if item['id'] == name),
                   {'id': 'book', 'title': 'Кот на учебнике', 'kind': 'classic'})
        appearances.append({key: value for key, value in old.items()
                            if key not in ('masterSize', 'semiTransparentPixels', 'opaquePixels', 'transparentPixels')})
        appearances[-1].update(asset=f'assets/mascot_pixel/{name}-idle-000.png',
                               status='authored_pixel_grid', productionReady=True, frameSize=[128, 128])
        clips[name] = {}
        for state, clip in states.items():
            paths = []
            for source in clip['frames']:
                destination = runtime / source.replace('/', '-')
                logical_name = 'assets/mascot_pixel/' + destination.name
                packed[logical_name] = base64.b64encode((OUTPUT / source).read_bytes()).decode('ascii')
                paths.append(logical_name)
            count = len(paths)
            durations = [350 if state == 'idle' else 70 if state == 'run' else 100 if state == 'walk' else 130] * count
            if state == 'blink':
                durations = [100, 60, 70, 60]
            anchors = []
            for phase in range(count):
                dy = [0, -1, -2, -3, -3, -2, -1, 0][phase * 8 // count] if state == 'jump' else 0
                if state == 'land':
                    dy = [-1, 0, 1, 0][phase * 4 // count]
                bob = [0, 0, -1, 0][phase * 4 // count] if state in ('idle', 'walk', 'run', 'happy', 'excited', 'celebrating', 'success') else 0
                if state in ('sleepy', 'sleeping'):
                    bob = 1
                anchors.append([60, (18 + dy + bob) * 4])
            metadata = {key: value for key, value in contract[state].items() if key in ('title', 'next', 'priority', 'trigger', 'sound', 'audioPolicy', 'kind', 'viewNames')}
            clips[name][state] = {**metadata, 'frames': paths, 'durationsMs': durations,
                'loop': clip['loop'], 'frameSize': [128, 128], 'requiredFrameCount': count,
                'mouthAnchors': anchors, 'status': 'authored_pixel_grid', 'productionReady': True,
                'pivotStatus': 'fixed_grid', 'pivotNormalized': [.5, .875]}
    states = dict(clips['student'])
    (runtime / 'catalog.json').write_text(json.dumps({'schema': 1, 'appearances': appearances,
        'states': states, 'clips': clips}, ensure_ascii=False, indent=2) + '\n')

    (runtime / 'frames.json').write_text(json.dumps({'schema': 1, 'files': packed}, sort_keys=True, separators=(',', ':')) + '\n')
    for file in runtime.glob('*.png'):
        file.unlink()
    branding = ROOT / 'apps/devcat_flutter/assets/branding'
    foreground = Image.open(OUTPUT / 'book/idle/000.png').convert('RGBA')
    foreground.save(branding / 'icon_foreground.png')
    foreground.save(branding / 'devcat_book.png')
    icon = Image.new('RGBA', foreground.size, '#6c479b')
    icon.alpha_composite(foreground)
    icon.resize((1024, 1024), Image.Resampling.NEAREST).save(branding / 'icon.png')
    ink = {INK, OUTLINE}
    bright = {PURPLE, TEAL}
    def rgba(color):
        return tuple(bytes.fromhex(color[1:])) + (255,)
    for label, colors in [('ink', ink), ('primary', bright), ('secondary', {DEEP, DARK_TEAL})]:
        accepted = {rgba(color) for color in colors}
        layer = Image.new('RGBA', foreground.size)
        pixels = getattr(foreground, 'get_flattened_data', foreground.getdata)()
        layer.putdata([pixel if pixel in accepted else (0, 0, 0, 0) for pixel in pixels])
        layer.save(branding / f'logo_{label}.png')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install-runtime', action='store_true')
    args = parser.parse_args()
    catalog = json.loads((ROOT / 'packages/cat_assets/v5_review/manifests/appearance_catalog.json').read_text())
    poses = ['idle', 'blink', 'talk', 'happy', 'thinking', 'error', 'sleepy', 'sleeping']
    manifest = {'schema': 1, 'grid': 32, 'canvas': [128, 128], 'pivot': [64, 112],
                'status': 'authored_grid_reviewed', 'appearances': {}}
    for appearance in [*catalog['appearances'], {'id': 'book'}]:
        name = appearance['id']
        states = json.loads((ROOT / 'apps/devcat_flutter/assets/mascot_v5/manifests/animation_contract.json').read_text())['states'] if name in ('student', 'book') else {pose: {} for pose in poses}
        manifest['appearances'][name] = {}
        for state in states:
            if state == 'orientations' or (name == 'book' and state in ('walk', 'run', 'jump', 'land')):
                continue
            count = 8 if state in ('talk', 'walk', 'run', 'jump') else 4
            frames = []
            for phase in range(count):
                path = OUTPUT / name / state / f'{phase:03}.png'
                export(sprite(name, state, phase, count), path)
                frames.append(str(path.relative_to(OUTPUT)))
            manifest['appearances'][name][state] = {'frames': frames,
                'durationsMs': [120 if state != 'idle' else 350] * count,
                'loop': state in ('idle', 'talk', 'walk', 'run', 'typing', 'loading', 'sleeping')}
    views = ['front', 'front_right', 'right', 'back_three_quarter', 'back', 'front_left', 'left', 'front_sitting']
    view_frames = []
    for index, view in enumerate(views):
        path = OUTPUT / 'student/orientations' / f'{index:03}.png'
        export(sprite('student', view=view), path)
        view_frames.append(str(path.relative_to(OUTPUT)))
    manifest['appearances']['student']['orientations'] = {
        'frames': view_frames, 'durationsMs': [500] * 8, 'loop': False,
    }
    (OUTPUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    if args.install_runtime:
        install_runtime(manifest)
    # Review sheets are separate from runtime art, never used as frame atlases.
    for background, color in [('light', '#fff8ed'), ('dark', '#211a2b')]:
        sheet = Image.new('RGB', (5 * 180, 4 * 176), color)
        draw = ImageDraw.Draw(sheet)
        for index, name in enumerate(manifest['appearances']):
            image = Image.open(OUTPUT / name / 'idle/000.png')
            x, y = index % 5 * 180 + 26, index // 5 * 176 + 8
            sheet.paste(image, (x, y), image)
            draw.text((x, y + 136), name, fill=OUTLINE if background == 'dark' else INK)
        sheet.save(OUTPUT / f'review-{background}.png')
    with zipfile.ZipFile(ROOT / 'docs/DevCat-pixel-masters.zip', 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(OUTPUT.rglob('*')):
            if path.is_file():
                info = zipfile.ZipInfo(str(path.relative_to(OUTPUT)), date_time=(2026, 11, 6, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, path.read_bytes())
    print(f'Authored {len(manifest["appearances"])} pixel appearances; runtime exported: {args.install_runtime}.')


if __name__ == '__main__':
    main()
