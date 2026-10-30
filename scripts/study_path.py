"""Build short, interactive lessons from the reviewed DevCat manuscripts.

No LLM, network, or fabricated execution trace is used. Output questions use
the same complete programs and literal test cases exercised by runtime CI.
"""
import hashlib
import json
from pathlib import Path
import random
import re

from plain_core import CORE, ZERO_KEYS
from plain_syntax import FRAMES
from study_facts import ADVANCED, WEB, SQL, GIT, ALGORITHMS

ROOT = Path(__file__).resolve().parents[1]
NAMES = ['Знакомство', 'Тренировка', 'Самостоятельно']
ALIASES = {
    'исходник': ['исходный код', 'исходный текст', 'текст программы'],
    'тип': ['тип данных'], 'строка': ['текстовая строка'],
    'присваивание': ['операция присваивания'], 'параметр': ['формальный параметр'],
    'аргумент': ['аргумент функции'], 'область видимости': ['scope'],
    'генератор': ['функция-генератор'], 'срез': ['slice'],
    'кодировка': ['кодировка текста'], 'таблица': ['таблица данных'],
    'первичный ключ': ['primary key'], 'внешний ключ': ['foreign key'],
    'индекс': ['индекс SQL', 'индекс базы данных'],
    'ветка': ['ветка Git', 'branch'], 'коммит': ['commit'],
    'pull request': ['PR', 'пулл-реквест', 'пулл реквест'],
    'flex-контейнер': ['flex контейнер', 'контейнер flex'],
}
SYNTAX = {
    'print': 'print показывает результат в Python.',
    'input': 'input получает строку ввода в Python.',
    'return': 'return завершает текущую функцию и передаёт результат вызывающему коду.',
    'if': 'if задаёт действие, выполняемое при истинном условии.',
    'else': 'else задаёт альтернативную ветку выбора.',
    'for': 'for задаёт повторение по правилам выбранного языка.',
    'while': 'while повторяет действие, пока условие остаётся истинным.',
    'def': 'def начинает определение функции Python.',
    'func': 'func начинает объявление функции или метода Go.',
    'await': 'await ожидает результат асинхронной операции по правилам выбранной среды.',
    'SELECT': 'SELECT задаёт возвращаемые выражения запроса.',
    'WHERE': 'WHERE отбирает строки по условию.',
    'GROUP BY': 'GROUP BY объединяет строки в группы для агрегации.',
    'ORDER BY': 'ORDER BY задаёт порядок результата.',
    'JOIN': 'JOIN связывает строки источников по условию.',
    'HAVING': 'HAVING задаёт условие отбора групп.',
    'printf': 'printf выводит данные в соответствии с форматной строкой C.',
    'scanf': 'scanf читает данные по формату; результат чтения нужно проверять.',
    'std::cout': 'std::cout используется для вывода в стандартный поток C++.',
    'std::cin': 'std::cin используется для ввода из стандартного потока C++.',
    'Console.WriteLine': 'Console.WriteLine показывает значение и завершает строку в C#.',
    'System.out.println': 'System.out.println показывает значение и завершает строку в Java.',
    'console.log': 'console.log показывает значения в консоли JavaScript.',
    'fmt.Println': 'fmt.Println показывает значения и завершает строку в Go.',
    'fmt.Scan': 'fmt.Scan читает данные из стандартного ввода Go.',
    'git add': 'git add подготавливает выбранное содержимое к коммиту.',
    'git status': 'git status показывает состояние рабочей папки и индекса.',
    'git commit': 'git commit фиксирует подготовленный снимок в локальной истории.',
    'color': 'color задаёт цвет текста CSS.',
    'padding': 'padding задаёт внутренний отступ CSS.',
    'margin': 'margin задаёт внешний отступ CSS.',
    'display': 'display участвует в выборе модели расположения элемента.',
    'href': 'href задаёт адрес перехода HTML-ссылки.',
    'src': 'src задаёт адрес подключаемого ресурса HTML.',
    'alt': 'alt задаёт текстовую альтернативу изображения.',
    'class': 'Здесь нужно восстановить именно запись примера; значение class зависит от языка.',
    'h1': 'h1 обозначает заголовок первого уровня. Теги показывают структуру, а не печатаются как текст.',
    'p': 'p обозначает абзац текста HTML.',
    'img': 'img подключает изображение; src задаёт адрес, alt — текстовую альтернативу.',
    'label': 'label даёт полю понятную подпись и может связываться с ним через for и id.',
    'button': 'button создаёт кнопку действия; в форме важно явно выбрать её type.',
    'form': 'form объединяет элементы ввода; обработчик отправленных данных нужен отдельно.',
    'font-size': 'font-size задаёт размер текста CSS.',
    'line-height': 'line-height задаёт высоту строки текста CSS.',
    'flex-wrap': 'flex-wrap разрешает перенос flex-элементов.',
    'grid-template-columns': 'grid-template-columns задаёт столбцы CSS Grid.',
    'position': 'position выбирает способ позиционирования элемента.',
    'overflow': 'overflow задаёт поведение содержимого, которое не помещается в область.',
    'transition': 'transition задаёт параметры плавного изменения свойства.',
}


def seed(value):
    return int(hashlib.sha256(value.encode()).hexdigest()[:12], 16)


def aliases(lang, term):
    if term == 'индекс' and lang != 'sql':
        return ['номер позиции', 'индекс элемента']
    if term == 'ветка' and lang != 'git':
        return ['ветка условия', 'ветка ветвления']
    return ALIASES.get(term, [])


def facts(course, lesson, index):
    lang = course['id']
    if lang in WEB:
        return [WEB[lang][index]]
    if lang == 'sql':
        return [SQL[index], *PROJECT_RULES] if lesson['id'] == 'sql.graduation' else [SQL[index]]
    if lang == 'git':
        return [GIT[index]]
    parts = lesson['id'].split('.')
    if parts[1] == 'advanced':
        number = int(parts[2])
        return [ADVANCED[lang][number - 1], *(PROJECT_RULES if number >= 13 else [])]
    if parts[1] == 'workshop':
        return [ALGORITHMS[index - 48]]
    key = ZERO_KEYS[parts[2]] if parts[1] == 'zero' else parts[1]
    return [tuple(p.split('=', 1)) for p in CORE[key][1].split('; ')]


PROJECT_RULES = [
    ('проверка входных данных', 'Отклоняет недопустимые значения до изменения состояния проекта.'),
    ('сценарий теста', 'Задаёт начальные условия, действие и наблюдаемый ожидаемый результат.'),
    ('инструкция запуска', 'Позволяет воспроизвести запуск с известными требованиями к среде.'),
]

# Early questions must not introduce terminology from later chapters as
# distractors. These ordinary starting concepts cover courses whose first
# topic has only one vocabulary item.
PRIMER = {
    'html': [
        ('браузер', 'Приложение, в котором открывают и просматривают веб-страницы.'),
        ('редактор', 'Приложение, в котором пишут и изменяют текст исходника.'),
        ('файл', 'Сохранённые данные с именем, например index.html.'),
    ],
    'css': [
        ('HTML', 'Разметка, которая описывает содержимое и структуру страницы.'),
        ('браузер', 'Приложение, которое показывает страницу с её оформлением.'),
        ('файл', 'Сохранённые данные с именем, например style.css.'),
    ],
    'sql': [
        ('строка таблицы', 'Одна запись, например данные об одной книге.'),
        ('столбец', 'Одно подписанное поле записей, например название книги.'),
        ('запрос', 'Команда, с которой обращаются к базе данных.'),
    ],
    'git': [
        ('файл', 'Сохранённые данные с именем, например README.md.'),
        ('папка', 'Место, в котором объединены файлы и другие папки.'),
        ('редактор', 'Приложение, в котором изменяют текст файла.'),
    ],
}


def paragraphs(lesson):
    section = next(s for s in lesson['sections'] if s['heading'] == 'Объяснение с самого начала')
    # Sentence boundaries preserve the actual explanation. A card never cuts
    # a sentence just to satisfy a character limit.
    sentences = re.split(r'(?<=[.!?])\s+(?=[А-ЯA-Z«])', section['text'])
    out = []
    current = ''
    for sentence in sentences:
        if current and len(current) + len(sentence) > 370:
            out.append(current.strip())
            current = ''
        current += (' ' if current else '') + sentence
    if current:
        out.append(current.strip())
    return out


def full_code(lesson, lang):
    if lesson.get('runnableExample'):
        return lesson['runnableExample']['code']
    if lesson.get('challenge'):
        return lesson['challenge']['solution']
    if lang in ('html', 'css'):
        focused = next((s['code'] for s in lesson['sections']
                        if s['heading'] == 'Один изучаемый фрагмент' and s.get('code')), None)
        if focused:
            return focused
    return next((s['code'] for s in lesson['sections'] if s.get('code')), '')


def focus(code, lang, preferred='', definition=''):
    lines = [s for s in code.splitlines() if s.strip()
             and s.strip() not in ('{', '}', '};', 'return 0;')
             and not s.strip().startswith(('#include', '# ', '//', '/*', '* ', 'import ', 'from ', 'using ', 'package '))]
    candidates = [s for s in lines if len(s) <= 160] or [s for s in lines if len(s) <= 320]
    def match_token(line, token, flags=0):
        quoted = [(m.start(), m.end()) for m in re.finditer(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|`[^`]*`', line)]
        def in_string(position):
            return any(start <= position < end for start, end in quoted)
        comments = ['#'] if lang == 'python' else ['--', '/*'] if lang == 'sql' else ['//', '/*']
        boundary = len(line)
        if lang in ADVANCED or lang == 'sql':
            for marker in comments:
                for found in re.finditer(re.escape(marker), line):
                    if not in_string(found.start()):
                        boundary = min(boundary, found.start())
        for found in re.finditer(r'(?<![\w.])' + re.escape(token) + r'(?!\w)', line, flags):
            if (lang not in ADVANCED and lang != 'sql') or (found.start() < boundary and not in_string(found.start())):
                return found
        return None
    if preferred and re.fullmatch(r'[A-Za-z][A-Za-z0-9_. -]*', preferred):
        for line in candidates:
            found = match_token(line, preferred, re.IGNORECASE if lang == 'sql' else 0)
            if found:
                return line, found[0], f'{preferred} — {definition}'
    # Prefer an observable operation over a program's boilerplate.
    common = ['return', 'if', 'else', 'for', 'while']
    keys = {
        'c': ['printf', 'scanf', *common],
        'cpp': ['std::cout', 'std::cin', *common],
        'csharp': ['Console.WriteLine', 'await', *common],
        'python': ['print', 'input', 'def', 'await', *common],
        'java': ['System.out.println', *common],
        'javascript': ['console.log', 'await', *common],
        'go': ['fmt.Println', 'fmt.Scan', 'func', *common],
        'git': ['git add', 'git status', 'git commit'],
    }.get(lang, [])
    if lang == 'sql':
        keys = ['WHERE', 'GROUP BY', 'HAVING', 'ORDER BY', 'JOIN', 'SELECT']
    elif lang == 'html':
        keys = ['href', 'src', 'alt', 'label', 'button', 'form', 'input', 'img', 'h1', 'p']
    elif lang == 'css':
        keys = ['flex-wrap', 'grid-template-columns', 'position', 'overflow', 'transition',
                'font-size', 'line-height', 'padding', 'margin', 'color', 'display']
    for line in candidates:
        for token in keys:
            if match_token(line, token):
                meaning = 'input создаёт поле ввода HTML; тип поля задаётся атрибутом type.' if lang == 'html' and token == 'input' else SYNTAX[token]
                return line, token, meaning
    line = next((s for s in candidates if len(s.strip()) > 5), '')
    if not line:
        return '', '', ''
    token = re.search(r'[A-Za-z_][A-Za-z_0-9-]*|\d+', line)
    if not token:
        return line, '', ''
    return line, token[0], 'Восстанови фрагмент в точности как в изученном примере; остальные части записи уже заданы.'


def fragments(line):
    tokens = re.findall(r'\s+|"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|[A-Za-z_][\w.-]*|\d+(?:\.\d+)?|==|!=|<=|>=|:=|=>|\S', line)
    parts = []
    prefix = ''
    for token in tokens:
        if token.isspace():
            if parts:
                parts[-1] += token
            else:
                prefix += token
        else:
            parts.append(prefix + token)
            prefix = ''
    if len(parts) > 7:
        count = min(6, len(parts))
        parts = [''.join(parts[i * len(parts) // count:(i + 1) * len(parts) // count]) for i in range(count)]
    return parts


def choice(identifier, prompt, answer, alternatives, why, **context):
    choices = list(dict.fromkeys([answer, *alternatives]))[:4]
    assert len(choices) >= 3, (identifier, choices)
    random.Random(seed(identifier)).shuffle(choices)
    return dict(id=identifier, kind='choice', prompt=prompt, options=choices,
                answer=answer, why=why, **context)


def build(courses):
    topics = []
    for course in courses:
        lang = course['id']
        vocab = [facts(course, l, i) for i, l in enumerate(course['lessons'])]
        for index, lesson in enumerate(course['lessons']):
            pool = list(dict.fromkeys(
                [pair for group in vocab[:index + 1] for pair in group] + PRIMER.get(lang, [])))
            identifier = lesson['id']
            term, meaning = vocab[index][0]
            short = paragraphs(lesson)
            source = full_code(lesson, lang)
            line, token, syntax = focus(source, lang, term, meaning)
            illustration = next((s for s in lesson['sections'] if s.get('image')
                                 and not s['image'].startswith('steps-')), lesson['sections'][0])
            rounds = []
            for level, name in enumerate(NAMES):
                prefix = f'{identifier}.r{level}'
                steps = []
                # New pieces of explanation appear throughout the three rounds.
                start = level * len(short) // 3
                end = (level + 1) * len(short) // 3
                chunks = short[start:end] or ([short[min(level, len(short) - 1)]] if level == 0 else [])
                if index == 0 and lang in FRAMES:
                    frame = re.split(r'(?<=[.!?])\s+(?=[А-ЯA-Z«#])', FRAMES[lang])
                    chunks_of_frame = [' '.join(frame[n:n+2]) for n in range(0, len(frame), 2)]
                    for n in range(level * len(chunks_of_frame) // 3, (level + 1) * len(chunks_of_frame) // 3):
                        step = dict(id=f'{prefix}.frame{n}', kind='learn',
                                    prompt='Из чего состоит первая программа', text=chunks_of_frame[n])
                        if len(source) < 1200:
                            step['code'] = source
                        steps.append(step)
                for n, text in enumerate(chunks):
                    step = dict(id=f'{prefix}.learn{n}', kind='learn', prompt=lesson['title'], text=text)
                    if level == 0 and n == 0 and illustration.get('image'):
                        step.update(image=illustration['image'], imageCaption=illustration.get('imageCaption', 'Иллюстрация к примеру'))
                    steps.append(step)
                steps.append(dict(id=f'{prefix}.word', kind='learn', prompt='Одно важное понятие',
                                  text=f'{term} — {meaning}', code=line if level == 0 else ''))
                wrong_meanings = [m for t, m in pool if t != term and m != meaning]
                wrong_terms = [t for t, m in pool if t != term and m != meaning]
                rng = random.Random(seed(prefix));rng.shuffle(wrong_meanings);rng.shuffle(wrong_terms)
                if level == 0:
                    steps.append(choice(f'{prefix}.concept', f'Что означает «{term}» в этой теме?',
                                        meaning, wrong_meanings, f'{term} — {meaning}'))
                elif level == 1:
                    steps.append(choice(f'{prefix}.recall', 'Как называется это понятие?\n\n'+meaning,
                                        term, wrong_terms, f'{term} — {meaning}'))
                else:
                    steps.append(dict(id=f'{prefix}.recall', kind='write',
                                      prompt='Напиши название понятия своими руками.', text=meaning,
                                      answer=term, why=f'{term} — {meaning}',
                                      accepted=aliases(lang, term),
                                      caseSensitive=term in ('Map', 'map', 'Set', 'set')))
                # More than one vocabulary item is taught and tested when the
                # source provides it. This is particularly useful for beginners.
                if len(vocab[index]) > 1:
                    t2, m2 = vocab[index][1 + level % (len(vocab[index]) - 1)]
                    steps.append(dict(id=f'{prefix}.word2', kind='learn', prompt=t2, text=m2))
                    alternatives = [m for t, m in pool if t != t2 and m != m2]
                    rng.shuffle(alternatives)
                    if level == 1:
                        steps.append(dict(id=f'{prefix}.concept2', kind='write', prompt='Как называется это понятие?',
                                          text=m2, answer=t2, why=f'{t2} — {m2}', caseSensitive=False))
                        steps[-1]['accepted'] = aliases(lang, t2)
                    else:
                        steps.append(choice(f'{prefix}.concept2', f'Выбери объяснение: {t2}.', m2,
                                            alternatives, f'{t2} — {m2}'))
                if line and token and level != 2:
                    steps.append(dict(id=f'{prefix}.syntax', kind='learn', prompt='Прочитаем запись',
                                      text=syntax, code=line))
                    steps.append(dict(id=f'{prefix}.fill', kind='fill',
                                      prompt='Вставь пропущенный фрагмент. Остальной код уже написан.',
                                      code=line.replace(token, '___', 1), answer=token,
                                      why=syntax, caseSensitive=lang != 'sql'))
                example = lesson.get('runnableExample')
                challenge = lesson.get('challenge')
                cases = (example or challenge or {}).get('tests', [])
                if cases and level < 2:
                    sample = cases[min(level, len(cases) - 1)]
                    expected = sample['expected']
                    if expected and len(expected) < 240:
                        alternatives = [c['expected'] for c in cases if c['expected'] != expected]
                        if re.fullmatch(r'-?\d+', expected.strip()):
                            value = int(expected.strip());alternatives += [str(value + 1), str(value - 1), str(value + 2)]
                        alternatives += ['Нет вывода', 'Ошибка компиляции или синтаксиса', 'Исходный текст программы']
                        steps.append(choice(f'{prefix}.output', 'Какой результат покажет эта программа?',
                                            expected, alternatives,
                                            'Для показанного исходника и именно этих данных ожидается:\n'+expected,
                                            code=(example or challenge)['code' if example else 'solution'], input=sample['input']))
                pieces = fragments(line)
                if level > 0 and 2 <= len(pieces) <= 7:
                    steps.append(dict(id=f'{prefix}.order', kind='order',
                                      prompt='Собери запись из блоков в том же порядке, что в изученном примере.',
                                      pieces=pieces, why=syntax or 'Порядок блоков восстанавливает изученную запись.',
                                      example=line))
                if level == 2 and (challenge or example):
                    if challenge:
                        steps.append(dict(id=f'{prefix}.code', kind='code', prompt='Теперь напиши решение.',
                                          mode='challenge', why='Решение должно пройти настоящие тесты на разных входных данных.'))
                    elif token and line in example['code']:
                        before, _, after = example['code'].partition(line)
                        template = before + line.replace(token, '___', 1) + after
                        assert template.replace('___', token, 1) == example['code']
                        steps.append(dict(id=f'{prefix}.code', kind='code', prompt='Дополни программу и проверь её запуском.',
                                          mode='example', code=template, answer=token,
                                          why=syntax or 'Восстанови изученный фрагмент и проверь результат на приведённых данных.'))
                assert any(s['kind'] not in ('learn',) for s in steps), identifier
                rounds.append(dict(id=f'{identifier}:{level}', level=level, title=name, steps=steps))
            topics.append(dict(id=identifier, course=lang, index=index, title=lesson['title'],
                               chapter=lesson['chapter'], term=term, rounds=rounds))
    assert len(topics) == 516
    return dict(schema=1, revision=1, topics=topics)


def write(courses):
    data = build(courses)
    path = ROOT / 'apps/devcat_flutter/assets/content/study_path.json'
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print(f"{len(data['topics']) * 3} interactive study sessions generated")


if __name__ == '__main__':
    folder = ROOT / 'apps/devcat_flutter/assets/content'
    courses = json.loads((folder / 'courses.json').read_text())
    courses += [json.loads((folder / 'git_course.json').read_text())]
    write(courses)
