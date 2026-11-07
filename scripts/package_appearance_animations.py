"""Package the 392 additional PNG frames with an offline, self-contained viewer."""
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/'apps/devcat_flutter/assets/mascot'
TEMPLATE=r'''<!doctype html>
<html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DevCat · 14 образов, 84 анимации</title>
<style>
:root{font:16px system-ui,sans-serif;color:#241934;background:#f6f1fc}*{box-sizing:border-box}body{margin:0;padding:28px}main{max-width:1100px;margin:auto}h1{font-size:28px;margin:0 0 8px}.note{line-height:1.6;color:#5f526c}.card{background:white;border:1px solid #e0d6eb;border-radius:24px;padding:24px;margin-top:20px}.layout{display:grid;grid-template-columns:minmax(250px,1fr) minmax(300px,1fr);gap:24px}label{display:block;margin:14px 0 8px;font-weight:600}select,button,input{font:inherit}select{width:100%;padding:12px;border:1px solid #cabbd9;border-radius:12px;background:white}button{border:1px solid #cabbd9;background:#f6f0ff;color:#432761;padding:11px 16px;border-radius:99px;cursor:pointer}button.primary{background:#6f43a1;color:white}.buttons{display:flex;gap:8px;flex-wrap:wrap;margin:16px 0}.stage{min-height:390px;display:grid;place-items:center;border-radius:18px;overflow:hidden;background-color:#e6e0ed;background-image:linear-gradient(45deg,#c9c2d3 25%,transparent 25%),linear-gradient(-45deg,#c9c2d3 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#c9c2d3 75%),linear-gradient(-45deg,transparent 75%,#c9c2d3 75%);background-size:24px 24px;background-position:0 0,0 12px,12px -12px,-12px 0}img{width:384px;height:384px;max-width:100%;object-fit:contain;image-rendering:pixelated}.count{font-variant-numeric:tabular-nums;line-height:1.6}input[type=range]{width:100%}.badge{background:#eee3ff;padding:6px 12px;border-radius:99px;display:inline-block}code{font-size:12px;overflow-wrap:anywhere}@media(max-width:700px){body{padding:14px}.card{padding:16px}.layout{grid-template-columns:1fr}.stage{min-height:300px;order:-1}img{width:300px;height:300px}}
</style><main><h1>DevCat · покадровые анимации</h1><div class="badge">14 образов · 84 клипа · 392 PNG · 128×128</div>
<p class="note">Шесть базовых действий для каждого образа. Внешность и аксессуары сохраняются во всех фазах. Кадры созданы генератором и проверены; тонкая ручная пиксельная доводка остаётся отдельным этапом.</p>
<section class="card layout"><div><label for="appearance">Образ</label><select id="appearance"></select><label for="state">Анимация</label><select id="state"></select>
<div class="buttons"><button class="primary" id="play">Пауза</button><button id="previous">← Кадр</button><button id="next">Кадр →</button><button id="reset">Сначала</button></div>
<label><input id="repeat" type="checkbox" checked> Повторять для просмотра</label><label for="scrub">Кадр</label><input id="scrub" type="range" min="0" step="1"><p id="counter" class="count"></p><code id="path"></code>
<div class="buttons"><button data-background="checker">Шахматный</button><button data-background="white">Белый</button><button data-background="black">Чёрный</button><button data-background="#455b68">Цветной</button></div><p id="error" role="alert"></p></div>
<div class="stage" id="stage"><img id="cat" alt="Кот DevCat"></div></section>
<p class="note">В приложении одноразовые реакции возвращаются в idle. Здесь можно повторять их и листать кадры. SHA-256 каждого PNG находится в manifest.json и SHA256SUMS.txt. Для просмотра достаточно распаковать весь архив и открыть index.html; интернет не нужен.</p></main>
<script>
const data=__MANIFEST__,names=__NAMES__;
const appearance=document.querySelector('#appearance'),state=document.querySelector('#state'),cat=document.querySelector('#cat'),scrub=document.querySelector('#scrub');
let index=0,playing=true,timer;
for(const id of Object.keys(data.appearances)){const item=document.createElement('option');item.value=id;item.textContent=names[id];appearance.append(item)}
for(const [id,clip] of Object.entries(data.appearances.beginner)){const item=document.createElement('option');item.value=id;item.textContent=clip.title;state.append(item)}
const query=new URLSearchParams(location.search);if(query.get('autoplay')==='0')playing=false;if(data.appearances[query.get('appearance')])appearance.value=query.get('appearance');if(data.appearances[appearance.value][query.get('state')])state.value=query.get('state');
function clip(){return data.appearances[appearance.value][state.value]}
function show(){const c=clip();scrub.max=c.frames.length-1;scrub.value=index;cat.src=c.frames[index];cat.alt=names[appearance.value]+' · '+c.title+' · кадр '+(index+1);document.querySelector('#counter').textContent='Кадр '+(index+1)+' / '+c.frames.length+' · '+c.durationsMs[index]+' мс · клип '+c.durationsMs.reduce((a,b)=>a+b,0)+' мс';document.querySelector('#path').textContent=c.frames[index];document.body.dataset.appearance=appearance.value;document.body.dataset.state=state.value;document.body.dataset.frame=index;document.querySelector('#play').textContent=playing?'Пауза':'Играть'}
function schedule(){clearTimeout(timer);if(!playing)return;timer=setTimeout(()=>{if(index+1===clip().frames.length&&!document.querySelector('#repeat').checked){playing=false;show();return}index=(index+1)%clip().frames.length;show();schedule()},clip().durationsMs[index])}
function choose(){index=0;show();schedule()}
appearance.onchange=choose;state.onchange=choose;document.querySelector('#play').onclick=()=>{playing=!playing;show();schedule()};document.querySelector('#previous').onclick=()=>step(-1);document.querySelector('#next').onclick=()=>step(1);document.querySelector('#reset').onclick=choose;function step(delta){playing=false;index=(index+delta+clip().frames.length)%clip().frames.length;show();schedule()}scrub.oninput=()=>{playing=false;index=Number(scrub.value);show();schedule()};
for(const button of document.querySelectorAll('[data-background]'))button.onclick=()=>{const value=button.dataset.background,stage=document.querySelector('#stage');stage.style.backgroundImage=value==='checker'?'':'none';stage.style.backgroundColor=value==='checker'?'#e6e0ed':value};
cat.onload=()=>{document.body.dataset.ready='true'};cat.onerror=()=>{document.querySelector('#error').textContent='Не найден кадр. Распакуй весь архив, сохранив папки.';document.body.dataset.error='true'};
document.addEventListener('visibilitychange',()=>{if(document.hidden){playing=false;show();schedule()}});choose();
</script></html>'''


def package():
    manifest=json.loads((ASSETS/'manifests/appearance_animations.json').read_text())
    assert len(manifest['appearances'])==14
    names={a['id']:a['title'] for a in json.loads((ASSETS/'manifests/appearance_catalog.json').read_text())['appearances']}
    def inline(value):return json.dumps(value,ensure_ascii=False,separators=(',',':')).replace('</','<\\/')
    html=TEMPLATE.replace('__MANIFEST__',inline(manifest)).replace('__NAMES__',inline(names))
    files={'index.html':html.encode(),'manifest.json':json.dumps(manifest,ensure_ascii=False,indent=2).encode(),
           'README.txt':('DevCat 0.9.2 — 14 образов, 84 клипа, 392 отдельных PNG.\n'
             'Распакуй весь архив и открой index.html. Интернет не нужен.\n'
             'Набор: idle 4, blink 4, talk 8, happy 4, thinking 4, error 4 на каждый образ.\n'
             'Размер 128x128; прозрачность 0/255; pivot (64,112).\n'
             'Изображения созданы генератором по исходным образам. Это не ручная пиксельная доводка.\n'
             'Мастера и отчёт экспорта сохранены в репозитории DevCat-.\n').encode()}
    for clips in manifest['appearances'].values():
        for clip in clips.values():
            for relative in clip['frames']:files[relative]=(ASSETS/relative).read_bytes()
    assert sum(name.endswith('.png') for name in files)==392
    files['SHA256SUMS.txt']=''.join(f'{hashlib.sha256(raw).hexdigest()}  {name}\n' for name,raw in sorted(files.items())).encode()
    version=re.search(r'^version:\s*([^+\s]+)',(ROOT/'apps/devcat_flutter/pubspec.yaml').read_text(),re.M)[1]
    path=ROOT/f'docs/DevCat-{version}-appearance-animations.zip'
    with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for name,raw in sorted(files.items()):
            info=zipfile.ZipInfo(name,date_time=(2026,11,7,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o644<<16
            archive.writestr(info,raw)
    print(f'{path.name}: {path.stat().st_size} bytes; 392 PNGs, viewer, manifest and checksums')
    return path


if __name__=='__main__':package()
