"""Replace every lecture's prose with the new book-based teaching sequence.

Stable IDs, lab contracts and verified program/table data survive. No old section
paragraph is used as the new explanation. Generation fails for an uncovered topic.
"""
import json
import hashlib
import re
from pathlib import Path
from plain_core import CORE, ZERO_KEYS
from plain_specialized import SPECIAL_TEXT
from plain_sql import SQL_TEXT, SQL_ZERO, SQL_ZERO_TEXT, SQL_ZERO_OUTPUT
from plain_web import HTML_TEXT, CSS_TEXT
from plain_experiments import ZERO_TEXT, ALGORITHM_TEXT
from plain_git import GIT_TEXT
from plain_web_reading import focused as focused_web
from plain_programs import BODY as COMPLETE_TOPICS, program as complete_program
from plain_syntax import notes as syntax_notes
from plain_practice import explain as explain_practice
import sqlite3
from lecture_depth import sql_fixture

ROOT = Path(__file__).resolve().parents[1]
SOURCES = json.loads((ROOT / 'content/reference_sources.json').read_text())
FILES = dict(c='main.c', cpp='main.cpp', csharp='Program.cs', python='main.py',
             java='Main.java', javascript='main.js', go='main.go', sql='query.sql',
             html='index.html', css='style.css', git='README.md')
LANGUAGE = {
'c':'В C17 действия программы начинаются в main. #include подключает объявления стандартных средств. Точка с запятой заканчивает многие команды; фигурные скобки ограничивают блок. Файл этого примера называется main.c.',
'cpp':'В C++20 выполнение начинается в main. #include предоставляет объявления библиотечных средств. std:: указывает стандартное пространство имён. Скобки группируют действия. Файл называется main.cpp.',
'csharp':'C# — язык, а .NET 8 — среда подготовки и выполнения этих программ. using подключает доступ к именам, Console предоставляет консольные действия. Файл называется Program.cs.',
'python':'В Python 3 обычные команды файла выполняются сверху вниз. Отступы определяют вложенные блоки, поэтому их нельзя удалять как украшение. Определение функции описывает действие, а вызов запускает его. Файл называется main.py.',
'java':'В Java 21 исходник Main.java содержит public class Main и вход main. Класс объединяет объявленные части, а System.out.println выводит значение. Фигурные скобки помогают увидеть границы классов, методов и других блоков.',
'javascript':'Эти консольные примеры JavaScript работают в Node.js 22. console.log показывает результат. Браузерного document здесь нет. Имя исходника main.js; для веб-страниц используется отдельный режим HTML/CSS.',
'go':'Go-программа использует package main и func main. import подключает пакеты; неиспользуемое подключение мешает сборке. fmt предоставляет консольные операции. Имя исходника main.go; go.mod является отдельным файлом проекта.',
'sql':'Запрос выполняет встроенная SQLite. Примеры чтения не меняют базу. Для команд изменения используй учебные данные и проверяй состояние до и после. Текст запроса вводится в query.sql, а не в поле входных данных обычной программы.',
'html':'HTML записывается в index.html. Сохрани файл и открой браузерный предпросмотр. Браузер показывает результат разметки, а не исходные угловые скобки. Локальные файлы доступны, пока открыт DevCat.',
'css':'Правила оформления записываются в style.css, подключённый из head файла index.html. Сохрани изменённый файл и обнови браузерный предпросмотр. Проверяй оба файла: селектор действует только на существующий подходящий элемент.',
'git':'Практика команд Git выполняется на ПК в отдельной учебной папке. Действия GitHub выполняются в своём репозитории через браузер ПК или телефона. Чтение локальной теории не требует сети; сам сервис GitHub требует подключения.',
}
WORDS = {
'импорт':'подключение доступных имён из другой части программы',
'параметр':'имя входного значения в определении функции',
'аргумент':'конкретное значение, переданное при вызове',
'тип':'вид данных и правила допустимых действий с ними',
'объект':'отдельное значение или сущность в памяти по модели выбранного языка',
'ссылка':'способ обратиться к существующему объекту без обещания независимой копии',
'указатель':'значение адреса объекта; использовать его можно только при соблюдении условий языка',
'массив':'набор элементов, доступных по позициям',
'индекс':'номер позиции; обычно первая позиция имеет номер ноль',
'итератор':'средство последовательно получать элементы или обозначать позицию в диапазоне',
'инвариант':'правило, которое сохраняется после каждого допустимого шага',
'контракт':'договор о допустимых входах, результате и поведении при отказе',
'предусловие':'требование, которое должно выполняться до операции',
'исключение':'средство передачи отказа от текущей операции к обработчику',
'интерфейс':'набор операций, доступных вызывающему коду',
'композиция':'связь, при которой одна часть использует другую для отдельной ответственности',
'сериализация':'превращение структурированных данных в оговорённый формат хранения',
'транзакция':'группа изменений, которую подтверждают или отменяют как согласованную работу',
'агрегат':'показатель, полученный по нескольким строкам, например сумма',
'ключ':'значение, по которому различают или находят запись',
'селектор':'правило CSS, выбирающее элементы HTML',
'атрибут':'именованное дополнительное сведение в открывающем теге HTML',
'каскад':'правила выбора применённого CSS-объявления среди подходящих',
'репозиторий':'хранилище истории проекта и связанных сведений',
'коммит':'снимок подготовленного содержимого с записью в истории Git',
}


def section(heading, text, **fields):
    return dict(heading=heading, text=text, **fields)


def source_notes(lang):
    if lang == 'git':
        return [dict(id='git.progit', title='Pro Git: основы Git', url='https://git-scm.com/book/ru/v2'),
                dict(id='git.github', title='GitHub Docs: начало работы', url='https://docs.github.com/ru/get-started')]
    return [x for x in SOURCES[lang] if 'url' in x]


def manuscript(lang, lesson):
    parts = lesson['id'].split('.')
    if lang == 'git':
        return GIT_TEXT[parts[1]], None
    if lang in ('html', 'css'):
        return (HTML_TEXT if lang == 'html' else CSS_TEXT)[parts[1]], None
    if lang == 'sql':
        if parts[1] == 'zero':
            return SQL_ZERO_TEXT[parts[2]], None
        slug = SQL_ZERO[parts[2]] if parts[1] == 'zero' else parts[-1]
        return SQL_TEXT[slug], None
    if parts[1] == 'zero':
        return ZERO_TEXT[parts[2]], CORE[ZERO_KEYS[parts[2]]]
    if parts[1] == 'advanced':
        return SPECIAL_TEXT[lang][int(parts[2])-1], None
    if parts[1] == 'workshop':
        return ALGORITHM_TEXT[parts[2]], None
    unit = CORE[parts[1]]
    return unit[2], unit


def vocabulary(text, core, lang):
    result = []
    if core:
        result += [tuple(x.split('=', 1)) for x in core[1].split('; ')]
    scoped = dict(WORDS)
    if lang == 'html':
        scoped['ссылка'] = 'элемент HTML с адресом перехода, обычно a с атрибутом href'
    if lang == 'sql':
        scoped['индекс'] = 'структура базы данных, ускоряющая некоторые выборки и требующая места и обновления'
    for word, definition in scoped.items():
        if word in text.lower() and all(word != x[0] for x in result):
            result.append((word, definition))
    return result[:7]


def reading_aid(lang, code):
    """Describe visible syntax only; do not pretend this is an execution trace."""
    if lang in ('html', 'css', 'sql', 'git'):
        return ''
    notes = []
    for number, raw in enumerate(code.splitlines(), 1):
        line = raw.strip()
        if not line or line in ('{', '}', '};'):
            continue
        if line.startswith(('# ', '//', '/*', '* ')):
            meaning = 'Комментарий для читающего человека; эта запись не является исполняемой командой.'
        elif line.startswith(('#include', 'import ', 'from ', 'using System', 'package ')):
            meaning = 'Подготовка имён и структуры файла. Подключение даёт доступ к указанным средствам, но само не печатает результат.'
        elif re.search(r'\b(class|struct|record|interface|enum)\b', line):
            meaning = 'Объявление формы типа. Поля описывают данные, методы — разрешённые действия. Само объявление не означает создание каждого будущего объекта.'
        elif re.search(r'\b(for|foreach|while)\b', line):
            meaning = 'Здесь задано повторение. Найди начало, условие продолжения и переход к следующему элементу; затем проследи один маленький вход.'
        elif re.search(r'\b(if|elif|else)\b', line):
            meaning = 'Здесь задан выбор пути. Вычисли условие для одного конкретного входа и отметь выбранный блок; остальные ветки этого выбора не выполняются автоматически.'
        elif re.search(r'\b(return|yield)\b', line):
            meaning = 'Здесь передаётся результат или управление по правилам указанной конструкции. Передача значения вызывающему коду отличается от печати текста на экран.'
        elif re.search(r'\b(print|printf|puts|WriteLine|println|Println|Print|log)\s*\(|std::cout|System.out', line):
            meaning = 'В строке есть вывод. Сначала получаются значения выражений, затем средство вывода показывает их. Кавычки исходника обычно не являются частью напечатанного текста.'
        elif re.search(r'\b(def|func)\s|\b(main|Main|cost|Cost|add|Add)\s*\(', line):
            meaning = 'Найди, является ли запись определением функции или её вызовом. Определение задаёт действия и параметры; вызов выполняет их с конкретными аргументами.'
        elif re.search(r'(?<![=!<>])=(?!=)|:=|\+=|\-=|\+\+|\-\-', line):
            meaning = 'Здесь создаётся или изменяется значение по правилам языка. Пройди вычисление правой части и изменение цели отдельно; присваивание не является проверкой равенства.'
        else:
            meaning = 'Найди имена используемых операций в объяснении темы. Отдельно установи получаемый результат и возможный отказ; расположение строки само по себе не показывает, сколько раз она выполнится.'
        notes.append(f'Строка {number}: {line}\n{meaning}')
    return '\n\n'.join(notes)


def example_cases(lesson):
    example = lesson.get('runnableExample')
    if example:
        return example['tests']
    lab = lesson.get('challenge')
    return lab['tests'] if lab else []


def rewrite(course):
    lang = course['id']
    course.update(revision=5, teachingRevision=1, references=source_notes(lang), last_verified='2026-10-29')
    previous = None
    for index, lesson in enumerate(course['lessons']):
        concept, core = manuscript(lang, lesson)  # Deliberately no generic fallback.
        lab = lesson.get('challenge')
        parts = lesson['id'].split('.')
        if lang == 'sql' and parts[1] == 'zero':
            lesson['runnableExample'] = dict(code=lesson['examples'][0], tests=[dict(input='', expected=SQL_ZERO_OUTPUT[parts[2]])])
        if len(parts) == 2 and parts[1] in COMPLETE_TOPICS and lang in COMPLETE_TOPICS[parts[1]] and not lab:
            lesson['runnableExample'] = complete_program(lang, parts[1])
            lesson['examples'] = [lesson['runnableExample']['code']]
        old_sections = lesson['sections']
        complete = lesson.get('runnableExample')
        code = complete['code'] if complete else lab['solution'] if lab else next(
            (s['code'] for s in old_sections if s.get('code')), lesson['examples'][0] if lesson['examples'] else '')
        terms = vocabulary(concept, core, lang)
        goal = core[0] if core else 'Разобрать тему «'+lesson['title']+'» и выполнить связанный опыт с объяснением результата.'
        experiment = core[3] if core else 'Повтори показанный пример, затем измени один относящийся к теме параметр. До обновления результата запиши, какие значения или видимые части должны измениться. Сравни фактический результат с этим ожиданием.'
        if lang == 'git':
            experiment = lesson['assignment']
        mistake = core[4] if core else next((s for s in reversed(re.split(r'(?<=[.!?])\s+',concept)) if 'не ' in s.lower()),'Проверяй условия применения именно этого средства, прежде чем переносить его в другую задачу.')
        cases = example_cases(lesson)
        assessment = 'tests' if lab else 'experiment' if '.zero.' in lesson['id'] or lang in ('html', 'css') and index < 23 else 'project'
        lesson['learning'] = dict(goal=goal, prerequisites=[] if previous is None else [previous],
            projectId=hashlib.sha256(('DevCat lesson:'+lesson['id']).encode()).hexdigest()[:32],
            vocabulary=[dict(term=k, meaning=v) for k, v in terms],
            assessment=assessment, steps=['Прочитать объяснение', 'Разобрать пример', 'Повторить опыт', 'Решить самостоятельно'],
            experiment=experiment, codeIsComplete=bool(complete or lab), references=source_notes(lang))
        practice = explain_practice(lesson, lang)
        if practice:
            lesson['learning']['practiceExplanation'] = practice
        if lang == 'sql' and lab:
            with sqlite3.connect(':memory:') as db:
                db.executescript(sql_fixture())
                cursor = db.execute(lab['solution'])
                lesson['learning']['practicePreview'] = dict(columns=[c[0] for c in cursor.description], rows=[['NULL' if value is None else str(value) for value in row] for row in cursor.fetchall()])
        new = [section('Что сейчас научимся делать', goal+'\n\n'+LANGUAGE[lang])]
        if terms:
            new.append(section('Новые слова без догадок', '\n\n'.join(k+' — '+v+'.' for k, v in terms)))
        new.append(section('Объяснение с самого начала', concept))
        syntax = syntax_notes(lang, lesson['id'])
        if syntax:
            new.append(section('Что означают служебные слова в этом языке', syntax))
        if lang in ('html', 'css'):
            files = lesson['webExample']
            focus, explanation, exercise = focused_web(lang, lesson['id'].split('.')[1])
            new.append(section('Один изучаемый фрагмент', explanation, code=focus))
            lesson['learning']['experiment'] = exercise
            new.append(section('Файл index.html: что читает браузер', 'Открой в проекте index.html. Это полный документ данного опыта. Найди изучаемый элемент среди каркаса; сведения head и видимое содержимое body имеют разные задачи.', code=files['index.html']))
            if 'style.css' in files:
                new.append(section('Файл style.css: что меняет оформление', 'Открой отдельный style.css. Подключение находится в head документа. Изучаемый селектор должен соответствовать реальному элементу HTML. Файл cat.svg уже входит в учебный проект; создавать его содержимое по памяти не требуется.', code=files['style.css']))
            for s in old_sections:
                if s.get('image') and any(k in s['image'] for k in ('-desktop.', '-phone.')):
                    new.append(section('Сравнение с браузером', 'Это реальный результат того же примера при '+('узкой ширине 390px.' if '-phone.' in s['image'] else 'широкой ширине 1080px.')+' Сопоставь конкретный изучаемый элемент с HTML и CSS. Сохранение файла и обновление страницы — отдельные действия.', image=s['image'], imageCaption='Снимок Chromium для приведённого набора файлов.'))
        elif lang == 'sql':
            for s in old_sections:
                if s.get('code'):
                    description = ('Это полный запрос опыта. Его маленькие исходные данные заданы прямо в записи; отдельно создавать базу для этого запуска не требуется. Сначала выполни без изменений и сопоставь столбцы с результатом, затем проведи один описанный опыт.' if '.zero.' in lesson['id'] else 'Прочитай этот SQL как отдельный этап. Назови источник, правило отбора или изменения и смысл одной выходной строки. Если есть WITH, его имена действуют в пределах данной команды.')
                    if '?' in s['code']:
                        description += ' Места параметров заполняются отдельно через API, то есть средство вызова базы из программы; знак ? не является готовыми данными для ручного запроса.'
                    new.append(section(s['heading'], description, code=s['code']))
                if s.get('table'):
                    t=s['table'];columns=', '.join(t['columns'])
                    new.append(section(s['heading'], f'В этом наборе {len(t["rows"])} строк. Столбцы: {columns}. Каждая строка — отдельный факт текущего этапа. Сначала сопоставь первую строку с запросом, затем проверь остальные. Надпись NULL обозначает отсутствие известного значения, а не текст для арифметики.', table=t))
        elif lang == 'git' and code:
            if any(line.lstrip().startswith('git ') for line in code.splitlines()):
                instruction = 'Это команды терминала на ПК в своей учебной папке. Выполняй по одной строке и сравнивай состояние перед следующим действием. YOUR_NAME в адресе заменяется своим именем GitHub; чужой адрес не даёт права менять чужой проект.'
            elif code.startswith('https://'):
                instruction = 'Это адрес для браузера ПК или телефона, а не команда Git и не текст README. Открой страницу и найди элементы, описанные в объяснении. Для изменений используй свой учебный репозиторий.'
            else:
                instruction = 'Это последовательность действий или образец текста для текущего шага. Стрелки показывают порядок; их не нужно вводить как команды терминала. Сначала найди указанный файл или раздел интерфейса.'
            new.append(section('Действия именно этого шага', instruction, code=code))
        elif code:
            new.append(section('Полный пример' if complete or lab else 'Разбираемый фрагмент и место его применения',
                ('Ниже приведён полный исходник. Открой '+FILES[lang]+', сохрани код и используй показанный вход. ' if complete or lab else 'Это часть программы, а не обещание самостоятельного запуска без окружения. Сначала найди её назначение в объяснении; типы и функции размещаются по правилам языка. В самостоятельном проекте добавь точку входа и необходимые подключения. ')+
                'Вначале прочитай данные и операции, затем переходи к деталям записи. Не перепутай строку исходника с готовым результатом.', code=code))
            aid=reading_aid(lang, code)
            if aid:new.append(section('Как прочитать запись по строкам', aid))
            if '.workshop.' in lesson['id']:
                for s in old_sections:
                    if s.get('table'):
                        new.append(section(s['heading'], 'Это значения конкретного маленького опыта. Сопоставь начальное состояние, каждый переход и полученный итог с объяснённым правилом. Таблица показывает состояние алгоритма; номера её строк не являются номерами строк исходника.', table=s['table']))
        if lang == 'git':
            for s in old_sections:
                if s.get('image'):
                    new.append(section('Сверка шага с изображением', 'Найди на изображении действие этого урока и сравни выбранные репозиторий, ветку и файл. На телефоне часть элементов находится в меню. Перед изменением проверь, что работаешь в своём учебном репозитории.', image=s['image'], imageCaption=s.get('imageCaption','Учебный шаг Git/GitHub.')))
        if cases:
            rows=[]
            for c in cases[:3]:rows.append([c['input'] if c['input'] else 'Без входных данных',c['expected'] if c['expected'] else 'Пустой вывод'])
            new.append(section('Вход и ожидаемый результат',
                'Каждая строка таблицы описывает отдельный запуск одного исходника. Левую часть передай в поле данных программы, правую сравни с её выводом. Переводы строк являются частью формата. Не добавляй подписи, которых нет в условии. После разбора первого запуска проверь границу или пустой случай из следующих примеров.',
                table=dict(columns=['Данные для запуска','Ожидаемый вывод'],rows=rows)))
        if practice:
            new.append(section('Как понять именно это упражнение', practice))
        new += [section('Небольшой опыт перед самостоятельной работой',experiment),
                section('Если результат не совпал',mistake+'\n\nСначала убедись, что открыт и сохранён нужный файл. Затем проверь конкретный вход и первое место расхождения с ожидаемым результатом. Ошибка подготовки среды, ошибка записи языка и неверный ответ программы имеют разные причины. Сохрани маленький пример, на котором видно расхождение, и попроси кота разобрать именно текущую тему.'),
                section('Самостоятельная работа',lab['prompt'] if lab else lesson['assignment']),
                section('Материалы, по которым построен урок','\n\n'.join(x['title']+'\n'+x['url'] for x in source_notes(lang))+ '\n\nОбъяснения DevCat написаны самостоятельно на русском. Ссылки нужны для дополнительного чтения; текст, примеры и иллюстрации этого урока уже доступны без интернета.')]
        # The screenshot/diagram is a work route, not a fabricated execution trace.
        new[0]['visual']=dict(title='Путь через этот урок',boxes=['Файл: '+FILES[lang],goal,'Пример → небольшой опыт → самостоятельная работа'])
        first_question = 'Что означает «'+terms[0][0]+'» в этом уроке?' if terms else 'Какую проблему решает изучаемое средство?'
        first_answer = ('«'+terms[0][0]+'» означает: '+terms[0][1]+'.\n\n'+goal) if terms else 'Главная мысль: '+concept.split('\n\n')[0]
        lesson.update(sections=new, theory='\n\n'.join(s['text'] for s in new),
            questionRevision=5, questions=[first_question,
                'Какие данные и результат показаны в примере?','Какой небольшой опыт проверит понимание темы?'],
            answers=[first_answer,('Данные для первого запуска:\n'+(cases[0]['input'] or 'Ввод не требуется.')+'\n\nОжидаемый вывод:\n'+cases[0]['expected']+'\n\nЭто вход и результат одного исходника. Исходник остаётся программой, которую нужно выполнить.' if cases else 'Сначала укажи, является ли код полным исходником, фрагментом или браузерным проектом. '+concept),experiment+'\n\n'+mistake],
            mistakes=[mistake], checklist=['Я могу объяснить новые слова.', 'Я сопоставил пример с его результатом.', 'Я выполнил небольшой опыт и объяснил изменение.'])
        lesson['readingWords']=len(lesson['theory'].split())
        previous=lesson['id']
    return course
