"""Diagrams of concrete lesson data; these are diagrams, never interface photos.

Every displayed output comes from the lesson's executable reference cases.
The small introductory traces are authored against the literal source contract.
"""
import hashlib
import json
from pathlib import Path
import textwrap

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'apps/devcat_flutter/assets/content'


def diagram(lesson, language):
    example = lesson.get('runnableExample') or lesson.get('challenge')
    if not example or not example.get('tests'):
        return None
    source = example.get('code') or example.get('solution', '')
    tests = example['tests']
    key = lesson['id'].split('.')[-1]
    kind = 'cases'
    if '.zero.' in lesson['id'] and key == 'variable' and 'balance' in source:
        kind = 'memory'
        panels = [('Создание', 'balance = 10'), ('Изменение', '10 + 5 => 15'), ('После изменения', 'balance = 15')]
    elif '.zero.' in lesson['id'] and key == 'repeat' and 'total' in source:
        kind = 'trace'
        panels = [('До цикла', 'total = 0'), ('number = 1', '0 + 1 => 1'), ('number = 2', '1 + 2 => 3'), ('number = 3', '3 + 3 => 6')]
    elif '.zero.' in lesson['id'] and key == 'choice' and 'age >= 18' in source:
        kind = 'branch'
        panels = [('Данные', 'age = 16'), ('Проверяем', '16 >= 18 => нет'), ('Выбранная ветка', 'minor')]
    elif '.zero.' in lesson['id'] and key == 'arithmetic' and 'price * count' in source:
        kind = 'calculation'
        panels = [('Цена', '7'), ('Количество', '3'), ('Стоимость', '7 × 3 = 21')]
    else:
        panels = [(f'Проверка {i+1}', 'Вход:\n' + (t['input'].strip() or 'Ввод не требуется') + '\n\nРезультат:\n' + t['expected']) for i, t in enumerate(tests[:4])]
    payload = json.dumps([3, lesson['id'], lesson['title'], kind, panels], ensure_ascii=False)
    name = 'diagram-' + hashlib.sha256(payload.encode()).hexdigest()[:18] + '.png'
    path = OUT / name
    if not path.exists():
        from PIL import Image, ImageDraw, ImageFont
        font = ImageFont.truetype(str(ROOT/'apps/devcat_flutter/assets/fonts/Nunito.ttf'), 25)
        bold = ImageFont.truetype(str(ROOT/'apps/devcat_flutter/assets/fonts/Nunito.ttf'), 30)
        font.set_variation_by_axes([650])
        bold.set_variation_by_axes([800])
        title_lines = textwrap.wrap(lesson['title'], 55)
        wrapped = []
        columns = 2 if kind == 'cases' and len(panels) > 1 else 1
        width = 1000
        pw = 450 if columns == 2 else 900
        for title, text in panels:
            lines = [part for line in text.splitlines() for part in (textwrap.wrap(line, 28 if columns == 2 else 60) or [''])]
            wrapped.append((title, lines))
        cellh = max(130, max(100 + len(lines)*33 for _, lines in wrapped))
        top = 40 + len(title_lines)*38
        rows = (len(panels)+columns-1)//columns
        height = top + rows*(cellh+36) + 70
        img = Image.new('RGB', (width,height), '#f6f4fd');d=ImageDraw.Draw(img)
        for i,line in enumerate(title_lines):d.text((40,20+i*38), line, font=bold, fill='#28223d')
        palette = {'memory': '#e4d8fb', 'trace': '#d8ecf5', 'branch': '#fff0cc', 'calculation': '#e2efda', 'cases': '#e3e5fb'}
        for i,(title,lines) in enumerate(wrapped):
            x = 40 + (i%columns)*480;y = top + (i//columns)*(cellh+36)
            if kind == 'memory':
                d.rectangle((x,y,x+pw,y+cellh),fill='white',outline='#765099',width=3)
                d.rectangle((x,y,x+pw,y+48),fill=palette[kind])
            elif kind == 'branch':
                d.rounded_rectangle((x,y,x+pw,y+cellh),radius=36,fill=palette[kind],outline='#a77922',width=3)
            else:
                d.rounded_rectangle((x,y,x+pw,y+cellh),radius=14,fill=palette[kind],outline='#6a6593',width=2)
            d.text((x+18,y+10), title,font=bold,fill='#29243d')
            for j,line in enumerate(lines):d.text((x+18,y+65+j*33),line,font=font,fill='#29243d')
            if columns == 1 and i<len(wrapped)-1:
                d.line((500,y+cellh+4,500,y+cellh+25),fill='#68558c',width=3)
                d.polygon([(494,y+cellh+20),(506,y+cellh+20),(500,y+cellh+28)],fill='#68558c')
        d.text((40,height-50), 'Конкретный опыт · '+language+' · '+lesson['id'],font=font,fill='#554b67')
        img.save(path,optimize=True)
    return {'heading': 'Наблюдаем результат на конкретных данных', 'text': 'Сначала предскажи результат, затем запусти приведённый исходник и сравни. Эта схема относится к примеру данного урока. Результат другого исходника или другого ввода может отличаться.', 'image': name, 'imageCaption': 'Схема изменения данных.' if kind != 'cases' else 'Вход и ожидаемый результат конкретных проверок; не снимок интерфейса.', 'diagramKind': kind}
