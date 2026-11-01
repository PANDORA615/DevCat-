#!/usr/bin/env python3
"""Local-only DevCat v5 review gallery. No web dependencies or asset uploads.

Usage:
  python scripts/mascot_review_gallery.py /path/to/DevCat_Review_v5.zip
  python scripts/mascot_review_gallery.py /path/to/DevCat_Review_v5/
  python scripts/mascot_review_gallery.py /path/to/archive.zip --port 0

The gallery is deliberately a review tool: assets are NOT marked ready.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
from urllib.parse import unquote, urlsplit
import zipfile

HTML = r"""<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DevCat v5 — проверка ассетов</title>
<style>
:root{font-family:system-ui,-apple-system,sans-serif;color:#ebebf4;background:#10131e}
*{box-sizing:border-box}body{margin:0}header{padding:18px 24px;border-bottom:1px solid #353b51}
header h1{font-size:22px;margin:0 0 4px}header small{color:#adb3d4}
main{display:grid;grid-template-columns:minmax(240px,290px) minmax(260px,1fr);height:calc(100vh - 84px);min-height:550px}
aside{overflow:auto;border-right:1px solid #353b51;padding:16px}section{padding:18px 22px;min-width:0;overflow:auto}
label{display:block;font-size:13px;color:#d9dbeb;margin:13px 0 7px}
button,select{background:#272d43;color:#fff;border:1px solid #535c7a;border-radius:8px;padding:9px 12px;font:inherit;cursor:pointer}
button:hover{background:#424b70}button:focus-visible,select:focus-visible{outline:2px solid #c9a4ff;outline-offset:2px}
select{width:100%}button.active{background:#5a4c99;border-color:#b6a4ff}
#info{color:#ccd0e7;font-size:14px;min-height:45px;line-height:1.5}
#stage{margin-top:12px;border:1px solid #5f6172;border-radius:12px;min-height:280px;height:min(52vh,560px);display:flex;align-items:center;justify-content:center;overflow:hidden}
#stage.light{background:#fff}#stage.dark{background:#070a10}#stage.accent{background:#6b2d70}
#stage.checker{background-color:white;background-image:linear-gradient(45deg,#ccc 25%,transparent 25%),linear-gradient(-45deg,#ccc 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#ccc 75%),linear-gradient(-45deg,transparent 75%,#ccc 75%);background-size:24px 24px;background-position:0 0,0 12px,12px -12px,-12px 0}
#art{width:100%;height:100%;max-height:100%;object-fit:contain;image-rendering:pixelated}
.controls{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px;align-items:center}
#status{font-variant-numeric:tabular-nums;color:#c7cdf0;margin:12px 0}#warning{border-left:3px solid #e3ad64;background:#3b3026;padding:10px 14px;margin:12px 0;color:#ffdc9d}
#notes{white-space:pre-wrap;color:#d0d4e9;line-height:1.6;font-size:14px}
audio{width:100%;margin-top:8px}
@media(max-width:710px){main{display:block;height:auto}aside{border-right:0;border-bottom:1px solid #353b51}section{padding:12px}#stage{height:45vh}}
</style></head>
<body><header><h1>DevCat v5 · Галерея проверки</h1>
<small>Локальный просмотр PNG и WAV · материалы из review-архива, не релизные спрайты</small></header>
<main><aside>
<label for="category">Раздел</label>
<select id="category"><option value="clips">Покадровые клипы</option>
<option value="appearances">15 внешностей</option><option value="audio">18 звуков</option></select>
<label for="item">Ассет</label><select id="item"></select>
<label for="background">Фон для проверки альфы и контура</label>
<select id="background"><option value="checker">Шахматный</option>
<option value="light">Белый</option><option value="dark">Чёрный</option>
<option value="accent">Контрастный цвет</option></select>
<label for="speed">Скорость воспроизведения</label>
<select id="speed"><option value="0.5">0.5×</option><option value="1" selected>1×</option>
<option value="2">2×</option></select>
<div id="warning">⚠ Не подтверждено вручную: производственные критерии v5 не пройдены.</div>
<div id="info"></div>
</aside><section>
<div id="stage" class="checker"><img id="art" alt="Предпросмотр PNG из архива"></div>
<div class="controls"><button id="play">▶ Воспроизвести</button>
<button id="prev">← Кадр</button><button id="next">Кадр →</button>
<button id="first">В начало</button></div>
<div id="status" aria-live="polite"></div>
<div id="notes"></div>
<audio id="sound" controls preload="none"></audio>
<p style="color:#969bb5;font-size:13px">Стрелки ←/→ — покадровый просмотр; пробел — пауза/воспроизведение. Размер холста кадра не нормализован до 128×128. Для релиза нужна ручная пиксельная доводка.</p>
</section></main>
<script>
'use strict';
const $ = id => document.getElementById(id);
let catalog, current=null, index=0, playing=false, raf=null, due=0;
const asset = path => '/asset/' + encodeURIComponent(path);
function stop(){playing=false;if(raf!==null)cancelAnimationFrame(raf);raf=null;$('play').textContent='▶ Воспроизвести';}
function frame(i){
 if(!current||!current.frames||!current.frames.length)return;
 index=(i+current.frames.length)%current.frames.length;
 $('art').src=asset(current.frames[index]);
 $('status').textContent='Кадр '+(index+1)+' / '+current.frames.length+
  ' · '+current.durationsMs[index]+' мс · '+current.frames[index];
}
function animate(now){
 if(!playing||!current)return;
 const speed=Number($('speed').value);
 let safety=0;
 while(now>=due&&safety++<100){
  if(index+1>=current.frames.length&&!current.loop){stop();return;}
  index=(index+1)%current.frames.length;
  frame(index);
  due+=current.durationsMs[index]/speed;
 }
 raf=requestAnimationFrame(animate);
}
function toggle(){
 if(!current||!current.frames||current.frames.length<2)return;
 if(playing){stop();return;}
 playing=true;$('play').textContent='Ⅱ Пауза';
 due=performance.now()+current.durationsMs[index]/Number($('speed').value);
 raf=requestAnimationFrame(animate);
}
function items(){
 const category=$('category').value;
 return category==='clips'?catalog.clips:category==='appearances'?catalog.appearances:catalog.audio;
}
function choose(){
 stop();$('sound').pause();$('sound').removeAttribute('src');$('sound').load();
 const data=items();current=data[Number($('item').value)]||null;index=0;
 $('notes').textContent='';$('info').textContent='';
 $('art').hidden=false;$('sound').hidden=true;
 const isAudio=$('category').value==='audio';
 const hasFrames=Boolean(current&&current.frames&&current.frames.length);
 for(const id of ['play','prev','next','first'])$(id).disabled=!hasFrames;
 if(!current){$('art').removeAttribute('src');$('status').textContent='Нет данных';return;}
 if(isAudio){
  $('art').hidden=true;$('sound').hidden=false;$('sound').src=asset(current.file);
  $('status').textContent=current.id+' · '+current.durationMs+' мс';
  $('notes').textContent='Формат: '+current.sampleRate+' Гц · '+current.channels+' канал · '+current.bits+' бит';
 }else if(hasFrames){
  frame(0);
  $('info').textContent=current.title+' · '+(current.loop?'цикл':'однократно')+
   ' · '+(current.productionReady?'одобрено':'review only');
  $('notes').textContent=[current.phases,current.trigger,...(current.reviewNotes||[])].filter(Boolean).join('\n');
 }else{
  $('art').src=asset(current.asset);
  $('status').textContent=current.asset;
  $('info').textContent=current.title+' · '+current.kind;
  $('notes').textContent=current.details+' · '+(current.productionReady?'одобрено':'review only');
 }
}
function populate(){
 $('item').replaceChildren();
 for(const [i,entry] of items().entries()){
  const opt=document.createElement('option');opt.value=String(i);
  opt.textContent=(entry.title||entry.id)+' · '+entry.id;
  $('item').append(opt);
 }
 choose();
}
$('category').addEventListener('change',populate);
$('item').addEventListener('change',choose);
$('background').addEventListener('change',()=>{$('stage').className=$('background').value;});
$('speed').addEventListener('change',()=>{if(playing){stop();toggle();}});
$('play').addEventListener('click',toggle);
$('prev').addEventListener('click',()=>{stop();frame(index-1);});
$('next').addEventListener('click',()=>{stop();frame(index+1);});
$('first').addEventListener('click',()=>{stop();frame(0);});
document.addEventListener('keydown',event=>{
 if(['INPUT','SELECT','TEXTAREA','BUTTON'].includes(document.activeElement.tagName))return;
 if(event.key==='ArrowLeft'){event.preventDefault();stop();frame(index-1);}
 if(event.key==='ArrowRight'){event.preventDefault();stop();frame(index+1);}
 if(event.code==='Space'){event.preventDefault();toggle();}
});
fetch('/api/catalog').then(r=>{if(!r.ok)throw new Error('HTTP '+r.status);return r.json();})
 .then(data=>{catalog=data;populate();})
 .catch(e=>{$('status').textContent='Не удалось загрузить манифест: '+e.message;});
</script></body></html>
"""


class ReviewPackage:
    """Open a fixed package, exposing only files already listed in it."""

    def __init__(self, source):
        self.source = Path(source)
        self.zip_mode = self.source.is_file()
        if self.zip_mode:
            with zipfile.ZipFile(self.source) as archive:
                raw = [i.filename for i in archive.infolist() if not i.is_dir()]
            if len(set(raw)) != len(raw) or any(not self._safe(n) for n in raw):
                raise ValueError('Unsafe/duplicate archive path')
            roots = {n.split('/')[0] for n in raw}
            prefix = next(iter(roots)) + '/' if len(roots) == 1 and all('/' in n for n in raw) else ''
            self.names = {n[len(prefix):]: n for n in raw}
        else:
            if not self.source.is_dir():
                raise FileNotFoundError(self.source)
            self.names = {}
            for p in self.source.rglob('*'):
                if not p.is_file():
                    continue
                if p.is_symlink():
                    raise ValueError('Symlink not allowed in review package')
                name = p.relative_to(self.source).as_posix()
                if not self._safe(name):
                    raise ValueError(f'Unsafe path {name}')
                self.names[name] = name
        self.catalog = self._catalog()

    @staticmethod
    def _safe(name):
        return bool(name) and not name.startswith('/') and '\\' not in name and all(
            part not in ('', '.', '..') for part in name.split('/')
        )

    def read(self, name):
        if name not in self.names:
            raise KeyError(name)
        if self.zip_mode:
            with zipfile.ZipFile(self.source) as archive:
                return archive.read(self.names[name])
        return (self.source / self.names[name]).read_bytes()

    def _json(self, name):
        return json.loads(self.read(name))

    def _catalog(self):
        states = self._json('manifests/animation_contract.json')['states']
        clips = []
        for ident, state in states.items():
            if state.get('kind') == 'views':
                title = 'Ракурсы (8)'
            else:
                title = state.get('title', ident)
            clips.append({
                'id': ident, 'title': title, 'frames': state['frames'],
                'durationsMs': state['durationsMs'], 'loop': state['loop'],
                'productionReady': state.get('productionReady', False),
                'trigger': state.get('trigger'), 'phases': state.get('phases'),
                'reviewNotes': state.get('reviewNotes', []),
            })
        appearances = [
            {k: a.get(k) for k in (
                'id', 'title', 'kind', 'asset', 'details', 'productionReady'
            )}
            for a in self._json('manifests/appearance_catalog.json')['appearances']
        ]
        audio = self._json('manifests/audio_catalog.json')['audio']
        for item in [*appearances, *audio]:
            if item['file' if 'file' in item else 'asset'] not in self.names:
                raise ValueError('Missing asset in catalog')
        for clip in clips:
            if any(name not in self.names for name in clip['frames']):
                raise ValueError(f"Missing frame in {clip['id']}")
        return {'clips': clips, 'appearances': appearances, 'audio': audio}


def make_handler(package):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            target = unquote(urlsplit(self.path).path)
            if target == '/':
                self._send(200, HTML.encode('utf-8'), 'text/html; charset=utf-8')
            elif target == '/api/catalog':
                data = json.dumps(package.catalog, ensure_ascii=False).encode('utf-8')
                self._send(200, data, 'application/json; charset=utf-8')
            elif target.startswith('/asset/'):
                name = target[len('/asset/'):]
                if name not in package.names or not name.lower().endswith(('.png', '.wav')):
                    self._send(404, b'Not found', 'text/plain; charset=utf-8')
                    return
                mimetype = 'image/png' if name.lower().endswith('.png') else 'audio/wav'
                self._send(200, package.read(name), mimetype)
            else:
                self._send(404, b'Not found', 'text/plain; charset=utf-8')

        def _send(self, status, payload, content_type):
            self.send_response(status)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(payload)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Security-Policy',
                             "default-src 'none'; img-src 'self'; media-src 'self'; "
                             "connect-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'")
            self.end_headers()
            self.wfile.write(payload)

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', help='DevCat review ZIP or extracted folder')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    pkg = ReviewPackage(args.package)
    # Loopback-only: the archive and its audio must never be exposed on LAN.
    server = ThreadingHTTPServer(('127.0.0.1', args.port), make_handler(pkg))
    print(f'Local mascot gallery: http://127.0.0.1:{server.server_port}', flush=True)
    print('Ctrl+C to stop. Nothing is uploaded.', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
