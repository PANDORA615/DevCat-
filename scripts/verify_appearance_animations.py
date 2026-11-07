"""Validate the additional 14x6 clips, actual decoded PNGs and their provenance."""
import hashlib
import json
import zipfile
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT/'apps/devcat_flutter/assets/mascot'
MASTERS = ROOT/'assets_source/mascot_v5/appearance_animation_masters'
REQUIRED = {'idle':4,'blink':4,'talk':8,'happy':4,'thinking':4,'error':4}


def verify():
    catalog=json.loads((ASSETS/'manifests/appearance_catalog.json').read_text())['appearances']
    expected={item['id'] for item in catalog}-{'student'}
    data=json.loads((ASSETS/'manifests/appearance_animations.json').read_text())
    reports=json.loads((MASTERS/'export_report.json').read_text())
    assert data['schemaVersion']==1 and data['frameSize']==[128,128]
    assert set(data['appearances'])==expected
    count=0
    for appearance,clips in data['appearances'].items():
        assert set(clips)==set(REQUIRED),appearance
        report=reports[appearance]
        master=MASTERS/f'{appearance}.png'
        assert hashlib.sha256(master.read_bytes()).hexdigest()==report['masterSha256'],appearance
        for state,expected_count in REQUIRED.items():
            clip=clips[state]
            assert clip['appearance']==appearance
            assert clip['frameSize']==[128,128] and clip['pivot']==[64,112]
            assert len(clip['frames'])==len(clip['durationsMs'])==len(clip['frameSha256'])==expected_count
            assert all(isinstance(t,int) and t>0 for t in clip['durationsMs'])
            assert clip['next']=='idle'
            pixels=set()
            for i,(relative,sha) in enumerate(zip(clip['frames'],clip['frameSha256'])):
                assert relative==f'animations/{appearance}/{state}/{i:03}.png'
                path=ASSETS/relative
                assert hashlib.sha256(path.read_bytes()).hexdigest()==sha,relative
                with Image.open(path) as raw:
                    assert raw.mode=='RGBA' and raw.size==(128,128),relative
                    alpha=raw.getchannel('A');hist=alpha.histogram()
                    assert sum(hist[1:255])==0,relative
                    assert hist[0]>0 and hist[255]>0,relative
                    box=alpha.getbbox()
                    assert min(box[0],box[1],128-box[2],128-box[3])>=4,(relative,box)
                    pixel_hash=hashlib.sha256(raw.tobytes()).hexdigest()
                    pixels.add(pixel_hash)
                    recorded=next(f for f in report['frames'] if f['state']==state and f['frame']==i)
                    assert recorded['pixelSha256']==pixel_hash,relative
                count+=1
            assert len(pixels)>=2,f'{appearance}/{state} is a duplicated static image'
    assert count==392,count
    archive = ROOT/'docs/DevCat-0.9.2-appearance-animations.zip'
    with zipfile.ZipFile(archive) as packaged:
        assert json.loads(packaged.read('manifest.json')) == data
        pngs = [name for name in packaged.namelist() if name.endswith('.png')]
        assert len(pngs) == 392 and len(set(pngs)) == 392
        for line in packaged.read('SHA256SUMS.txt').decode().splitlines():
            sha, name = line.split('  ', 1)
            assert hashlib.sha256(packaged.read(name)).hexdigest() == sha, name
        for name in pngs:
            assert packaged.read(name) == (ASSETS/name).read_bytes(), name

    print('OK: 14 appearances, 84 real clips, 392 distinct files; 128x128 RGBA, binary alpha, clear margins, hashes and changing phases verified.')


if __name__=='__main__':verify()
