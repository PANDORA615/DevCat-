"""Export the same bundled lessons as accessible offline HTML and Markdown."""
from html import escape
from pathlib import Path
import json
import re
import zipfile

ROOT=Path(__file__).resolve().parents[1]
CSS='''@font-face{font-family:Nunito;src:url(assets/Nunito.ttf)}@font-face{font-family:Code;src:url(assets/JetBrainsMono.ttf)}*{box-sizing:border-box}body{margin:0;background:#f5f7f4;color:#202b25;font:600 18px/1.8 Nunito,system-ui,sans-serif}main{max-width:920px;margin:auto;padding:38px 24px}h1,h2,h3{line-height:1.3;scroll-margin-top:24px}h1{font-size:42px}h2{font-size:32px;margin-top:70px}h3{font-size:24px;margin-top:32px}a{color:#32654c}p{white-space:pre-wrap}pre{font:14px/1.65 Code,monospace;background:#e9eee9;border-radius:14px;padding:18px;overflow:auto;white-space:pre}table{border-collapse:collapse;min-width:60%;font-size:15px}th,td{border:1px solid #bdcdbf;padding:10px;text-align:left;vertical-align:top}td pre{margin:0;padding:4px;background:none;border-radius:0}.table{overflow:auto}details{border:1px solid #bdcdbf;border-radius:12px;padding:12px 16px;margin:10px 0}summary{cursor:pointer;font-weight:800}img{max-width:100%;height:auto;border-radius:18px}small{font-size:13px}nav{border:1px solid #bdcdbf;padding:18px;border-radius:18px}nav a{display:block}.meta{font-size:14px;color:#506656}section{border-top:1px solid #bdcdbf;margin-top:50px;padding-top:10px}@media print{body{background:white;font-size:11pt}main{max-width:none;padding:0}nav{break-after:page}section{break-before:page}pre{white-space:pre-wrap;overflow-wrap:anywhere}details>*{display:block!important}summary{list-style:none}a{color:inherit}h2,h3{break-after:avoid}.table{overflow:visible}img{max-height:200px;width:auto}}'''


def paragraphs(text):
    return ''.join('<p>'+escape(part)+'</p>' for part in text.split('\n\n') if part)


def html_book(course):
    parts=['<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+escape(course['name'])+' — подробный курс DevCat</title><style>'+CSS+'</style><main>', '<h1>'+escape(course['name'])+' · '+escape(course['version'])+'</h1>', '<p>'+str(len(course['lessons']))+' занятий: основы, особенности языка, проекты и подробные разборы сложных задач. Материалы доступны без интернета. Код примеров и таблицы совпадают с содержимым приложения DevCat.</p>', '<nav aria-label="Оглавление">']
    for i,lesson in enumerate(course['lessons'],1):parts.append(f'<a href="#lesson-{i}">{i}. {escape(lesson["title"])}</a>')
    parts.append('</nav>')
    for i,lesson in enumerate(course['lessons'],1):
        parts += [f'<section aria-labelledby="lesson-{i}"><h2 id="lesson-{i}">{i}. {escape(lesson["title"])}</h2>', '<p class="meta">'+escape(lesson['chapter']+' · '+lesson['difficulty'])+'</p>']
        if i == 1 or course['lessons'][i-2]['chapter'] != lesson['chapter']:
            parts.append('<figure><img loading=\"lazy\" src=\"assets/'+escape(lesson['photo'],quote=True)+'\" alt=\"Учебная фотография DevCat\"><figcaption><small>'+escape(lesson['photoCaption'])+'</small></figcaption></figure>')
        for section in lesson['sections']:
            parts += ['<h3>'+escape(section['heading'])+'</h3>', paragraphs(section.get('text',''))]
            if section.get('image'):parts.append('<figure><img loading="lazy" src="assets/'+escape(section['image'],quote=True)+'" alt="'+escape(section.get('imageCaption','Пошаговая схема'),quote=True)+'"><figcaption>'+escape(section.get('imageCaption',''))+'</figcaption></figure>')
            if section.get('code'):parts.append('<pre><code>'+escape(section['code'])+'</code></pre>')
            if section.get('table'):
                table=section['table'];parts.append('<div class="table"><table><thead><tr>'+''.join('<th scope="col">'+escape(c)+'</th>' for c in table['columns'])+'</tr></thead><tbody>')
                for row in table['rows']:parts.append('<tr>'+''.join('<td><pre><code>'+escape(str(value))+'</code></pre></td>' for value in row)+'</tr>')
                parts.append('</tbody></table></div>')
        parts.append('<h3>Вопросы и разбор ответов</h3>')
        for question,answer in zip(lesson['questions'],lesson['answers']):parts.append('<details><summary>'+escape(question)+'</summary>'+paragraphs(answer)+'</details>')
        parts += ['<h3>Самостоятельная работа</h3>',paragraphs(lesson['assignment']),'<p><a href="#">К оглавлению</a></p></section>']
    parts += ['<p>Официальная документация: <a href="'+escape(course['source'],quote=True)+'">'+escape(course['source'])+'</a>. Это дополнительная внешняя ссылка; для чтения учебника соединение не требуется.</p>', '</main></html>']
    return '\n'.join(parts)+'\n'


def markdown_book(course):
    lines=['# '+course['name']+' · подробный курс DevCat', '',course['version'], '', str(len(course['lessons']))+' занятий. Код, результаты и разборы совпадают с офлайн-приложением.', '']
    for i,lesson in enumerate(course['lessons'],1):lines.append(f'{i}. [{lesson["title"]}](#lesson-{i})')
    for i,lesson in enumerate(course['lessons'],1):
        lines += ['',f'<a id="lesson-{i}"></a>','',f'## {i}. {lesson["title"]}','',lesson['chapter']+' · '+lesson['difficulty'],'']
        for section in lesson['sections']:
            lines += ['### '+section['heading'],'',section.get('text',''),'']
            if section.get('code'):lines += ['```'+({'cpp':'cpp','csharp':'csharp','javascript':'javascript'}.get(course['id'],course['id'])),section['code'].rstrip(),'```','']
            if section.get('table'):
                table=section['table'];cell=lambda v:str(v).replace('|','\\|').replace('\n','<br>')
                lines += ['| '+' | '.join(map(cell,table['columns']))+' |','| '+' | '.join('---' for _ in table['columns'])+' |']
                lines += ['| '+' | '.join(map(cell,row))+' |' for row in table['rows']];lines.append('')
        lines += ['### Вопросы и разборы','']
        for question,answer in zip(lesson['questions'],lesson['answers']):lines += ['**'+question+'**','',answer,'']
        lines += ['### Самостоятельная работа','',lesson['assignment'],'']
    return '\n'.join(lines).rstrip()+'\n'


def export(courses):
    folder=ROOT/'docs/textbooks';folder.mkdir(parents=True,exist_ok=True)
    archive=ROOT/'docs/DevCat-lectures.zip'
    files={}
    for course in courses:
        md=markdown_book(course);html=html_book(course)
        (folder/(course['id']+'.md')).write_text(md)
        # HTML in the ZIP is self-contained with its accompanying assets.
        files[course['id']+'.html']=html.encode()
        files[course['id']+'.md']=md.encode()
    index='<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Учебники DevCat</title><style>'+CSS+'</style><main><h1>Подробные курсы DevCat</h1><p>Открой любой курс. Интернет для чтения не нужен. Печать в PDF доступна через браузер. Контрольные ответы раскрываются нажатием.</p><nav>'+''.join('<a href="'+c['id']+'.html">'+escape(c['name'])+' — '+str(len(c['lessons']))+' занятий</a>' for c in courses)+'</nav><p>Учебные фотографии созданы для DevCat и служат контекстом; реальные данные и вычисления приведены в таблицах.</p></main></html>'
    files['index.html']=index.encode()
    files['LICENSE.txt']=(ROOT/'LICENSE').read_bytes()
    files['README.txt']='Распакуй весь архив в одну папку и открой index.html. Внутри 11 HTML-учебников и 11 Markdown-версий. Файлы assets должны оставаться рядом. Можно печатать HTML в PDF. Практические проекты требуют самостоятельной реализации; количество прочитанных страниц не является автоматической оценкой навыка.\n'.encode()
    for name in ['Nunito.ttf','Nunito-OFL.txt','JetBrainsMono.ttf','JetBrainsMono-OFL.txt']:
        files['assets/'+name]=(ROOT/'apps/devcat_flutter/assets/fonts'/name).read_bytes()
    for name in ['memory.png','data.png','debug.png','workbench.png']:
        files['assets/'+name]=(ROOT/'apps/devcat_flutter/assets/content'/name).read_bytes()
    for course in courses:
        for lesson in course['lessons']:
            for section in lesson['sections']:
                if section.get('image'):
                    files['assets/'+section['image']]=(ROOT/'apps/devcat_flutter/assets/content'/section['image']).read_bytes()
    # Fixed entry timestamps and order make regeneration byte-reproducible.
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as target:
        for name,data in sorted(files.items()):
            entry=zipfile.ZipInfo(name,date_time=(2026,10,29,0,0,0));entry.compress_type=zipfile.ZIP_DEFLATED;entry.external_attr=0o100644<<16
            target.writestr(entry,data,compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
    (folder/'README.md').write_text('# Подробные учебники DevCat\n\n[Скачать HTML и Markdown одним архивом](../DevCat-lectures.zip). После распаковки открой index.html.\n\n'+'\n'.join('- ['+c['name']+']('+c['id']+'.md) — '+str(len(c['lessons']))+' занятий.' for c in courses)+'\n')
    print('Exported offline HTML and Markdown textbooks:',archive.stat().st_size,'archive bytes')
