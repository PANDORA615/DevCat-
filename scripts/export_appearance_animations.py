"""Export generated 4x7 appearance atlases into registered standalone PNG frames.

This is deterministic atlas export, not a claim of manual pixel-art retouching.
Each clip shares one scale and ground offset. Frames are never individually re-centered.
Original supplied v5 assets/manifests remain untouched.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'apps/devcat_flutter/assets/mascot'
MASTERS = ROOT / 'assets_source/mascot_v5/appearance_animation_masters'
STATES = {'idle': (0, 4), 'blink': (4, 4), 'talk': (8, 8),
          'happy': (16, 4), 'thinking': (20, 4), 'error': (24, 4)}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def grid_cuts(alpha, divisions, axis):
    """Find transparent gutters near nominal grid lines; never cut a subject."""
    size = alpha.width if axis == 'x' else alpha.height
    result = [0]
    for line in range(1, divisions):
        nominal = round(line * size / divisions)
        radius = round(size / divisions * .18)
        candidates = []
        for at in range(nominal-radius, nominal+radius+1):
            strip = alpha.crop((at, 0, at+1, alpha.height) if axis == 'x'
                               else (0, at, alpha.width, at+1))
            candidates.append((sum(strip.histogram()[1:]), at))
        minimum = min(count for count, _ in candidates)
        if minimum != 0:
            raise ValueError(f'No transparent {axis} gutter near grid line {line}')
        # Prefer the widest contiguous run of transparent pixels.
        runs = []
        for count, at in candidates:
            if count == minimum:
                if runs and runs[-1][-1] == at-1:
                    runs[-1].append(at)
                else:
                    runs.append([at])
        best = max(runs, key=lambda run: (len(run), -abs(sum(run)/len(run)-nominal)))
        result.append(round((best[0]+best[-1])/2))
    return result + [size]


def export(index, partial=False):
    originals = json.loads((ASSETS / 'manifests/appearance_catalog.json').read_text())['appearances']
    expected = {a['id'] for a in originals} - {'student'}
    if not partial and set(index) != expected:
        raise ValueError(f'Expected all 14 appearances; missing={expected-set(index)}')
    if not set(index) <= expected:
        raise ValueError('Unknown appearance in atlas index')
    base = json.loads((ASSETS / 'manifests/animation_contract.json').read_text())['states']
    result = {'schemaVersion': 1, 'frameSize': [128, 128], 'appearances': {},
              'productionReady': False,
              'notes': ['Generated and visually reviewed phases; not a manual pixel-art final pass.']}
    MASTERS.mkdir(parents=True, exist_ok=True)
    source_index = {}
    reports = {}
    for appearance, source_path in sorted(index.items()):
        master = MASTERS / f'{appearance}.png'
        source = Path(source_path)
        if source.resolve() != master.resolve():
            shutil.copyfile(source, master)
        source_index[appearance] = str(master.relative_to(ROOT))
        image = Image.open(master).convert('RGBA')
        w, h = image.size
        if abs(w / 4 - h / 7) > 2:
            raise ValueError(f'Atlas cells must be square: {appearance}: {image.size}')
        alpha = image.getchannel('A').point(lambda a: 255 if a >= 192 else 0)
        xcuts, ycuts = grid_cuts(alpha, 4, 'x'), grid_cuts(alpha, 7, 'y')
        # Column registration is measured ONCE from the neutral idle row and
        # reused for every state. No per-frame bounding-box re-centering.
        centers = []
        for col in range(4):
            box = alpha.crop((xcuts[col], ycuts[0], xcuts[col+1], ycuts[1])).getbbox()
            centers.append(xcuts[col] + (box[0]+box[2])/2)
        cell_size = max(max(b-a for a,b in zip(xcuts,xcuts[1:])),
                        max(b-a for a,b in zip(ycuts,ycuts[1:])))
        def cell_at(col, row):
            rect = (xcuts[col], ycuts[row], xcuts[col+1], ycuts[row+1])
            cell = Image.new('RGBA', (cell_size, cell_size))
            cell.alpha_composite(image.crop(rect),
                (round(cell_size/2 + xcuts[col]-centers[col]), 0))
            return cell
        clips = {}
        frame_reports = []
        clip_origins = {}
        for state, (start, count) in STATES.items():
            col0,row0 = start % 4,start // 4
            neutral = cell_at(col0, row0)
            bounds = neutral.getchannel('A').point(lambda a: 255 if a>=192 else 0).getbbox()
            if bounds is None:
                raise ValueError(f'Empty neutral cell: {appearance}/{state}')
            # Register the sequence once against its neutral ground. Preserve ALL
            # intra-clip movement; never align frames to individual bounding boxes.
            origin = (12,112-round((bounds[3]-1)*104/neutral.height))
            clip_origins[state] = list(origin)
            folder = ASSETS / 'animations' / appearance / state
            folder.mkdir(parents=True, exist_ok=True)
            frames = []
            for number in range(count):
                i = start + number
                col, row = i % 4, i // 4
                art = cell_at(col, row).resize((104, 104), Image.Resampling.NEAREST)
                art.putalpha(art.getchannel('A').point(lambda a: 255 if a >= 192 else 0))
                frame = Image.new('RGBA', (128, 128))
                frame.alpha_composite(art, origin)
                file = folder / f'{number:03}.png'
                frame.save(file, optimize=True)
                box = frame.getchannel('A').getbbox()
                if box is None:
                    raise ValueError(f'Empty frame: {file}')
                # Use actual pixels, not just file hashes, to audit duplicate phases.
                frame_reports.append({'state': state, 'frame': number, 'bbox': list(box),
                                      'pixelSha256': hashlib.sha256(frame.tobytes()).hexdigest(),
                                      'sha256': digest(file),
                                      'clearMargin': min(box[0],box[1],128-box[2],128-box[3])})
                frames.append(str(file.relative_to(ASSETS)))
            clip = {k: base[state][k] for k in ['title', 'loop', 'next', 'priority']}
            clip.update({'frames': frames, 'frameSha256': [digest(ASSETS/p) for p in frames], 'durationsMs': base[state]['durationsMs'],
                         'appearance': appearance, 'frameSize': [128,128],
                         'pivot': [64,112], 'sourceMaster': str(master.relative_to(ROOT)),
                         'status': 'generated_review', 'productionReady': False})
            clips[state] = clip
        result['appearances'][appearance] = clips
        reports[appearance] = {'masterSize': [w,h], 'masterSha256': digest(master),
                               'layout': {'columns':4,'rows':7, 'xCuts':xcuts, 'yCuts':ycuts},
                               'columnCenters':centers, 'sourceCellSize':cell_size, 'clipOrigins':clip_origins,
                               'cellResize': [104,104], 'alphaThreshold':192,
                               'manualPixelRetouch':False,'frames':frame_reports}
    (MASTERS / 'index.json').write_text(json.dumps(source_index, indent=2)+'\n')
    (ASSETS / 'manifests/appearance_animations.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    (MASTERS / 'export_report.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2)+'\n')
    print(f'Exported {len(index)*6} clips / {len(index)*28} standalone PNGs for {len(index)} appearances')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index',type=Path,default=MASTERS/'index.json')
    parser.add_argument('--allow-partial',action='store_true')
    args = parser.parse_args()
    index = json.loads(args.index.read_text())
    export({k:str(ROOT/p) if not Path(p).is_absolute() else p for k,p in index.items()},args.allow_partial)
