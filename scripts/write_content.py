"""Build the bundled offline book from reviewed original manuscripts.
Run without network. No lecture is created by splitting a paragraph into pages.
"""
import json
from pathlib import Path
from curriculum import FOUNDATIONS
from language_notes import SPECIAL
from sql_curriculum import SQL
from foundation_examples import EXAMPLES, LANGUAGE_CONTEXT
from practice_bank import NAMES, challenge
from lecture_depth import enrich_foundation, enrich_advanced, enrich_sql
from workshops import build_workshops
from export_books import export
from beginner_course import lessons as beginner_lessons
from web_courses import course as web_course
from git_course import course as git_course
from learning_visuals import enrich as visual_enrich
from plain_notebook import rewrite as rewrite_notebook
ROOT=Path(__file__).resolve().parents[1]
META={
'c':('C17','Память, алгоритмы и надёжные локальные программы.','https://en.cppreference.com/w/c'),
'cpp':('C++20','Современный C++: от значений до владения и проектов.','https://en.cppreference.com/w/cpp'),
'csharp':('.NET 8','Типы, коллекции, async и самостоятельные приложения.','https://learn.microsoft.com/dotnet/csharp/'),
'python':('Python 3','От первой программы до модулей, тестов и проектов.','https://docs.python.org/3/tutorial/'),
'java':('Java 21','Модели, коллекции, JVM и законченные приложения.','https://dev.java/learn/'),
'javascript':('Node.js 22','Язык, Node, асинхронность и локальные CLI-проекты.','https://developer.mozilla.org/docs/Web/JavaScript'),
'go':('Go 1.22+','Данные, ошибки, конкурентность и локальные инструменты.','https://go.dev/doc/'),
'sql':('SQLite 3','От первого SELECT до схем, транзакций и аналитики.','https://www.sqlite.org/lang.html'),
}
def section(heading,text='',**extra):return dict(heading=heading,text=text,**extra)
def diagram(topic):
    if topic in ['values','variables','scope','records']:return 'memory'
    if topic in ['booleans','branches','errors']:return 'branch'
    if topic in ['loops','nested','iteration']:return 'loop'
    if topic in ['arrays','collections','search']:return 'collection'
    if topic in ['testing','debugging','complexity']:return 'trace'
    if topic in ['files','json','modules','functions']:return 'pipeline'
    return 'flow'
def photo(topic):
    if topic in ['values','variables','scope','arrays']:return 'memory.png'
    if topic in ['collections','records','json','files']:return 'data.png'
    if topic in ['loops','nested','testing','debugging','complexity','search']:return 'debug.png'
    return 'workbench.png'
def chapter(i):return ['01 · Первые программы','02 · Управление выполнением','03 · Данные и функции','04 · Надёжность и проекты'][min(i//6,3)]
def foundation(lang,index,t):
    slug,title,model,trace,failure,assignment,questions=t
    lesson_id=f'{lang}.{slug}'
    lab=challenge(lang,slug,lesson_id)
    code=EXAMPLES[lang][index]
    sections=[
      section('Зачем это нужно',model),
      section('Как это устроено в '+NAMES[lang],LANGUAGE_CONTEXT[lang],code=code),
      section('Разбираем выполнение по шагам',trace,diagram=diagram(slug)),
      section('Практическая работа',('Автоматически проверяемая часть: '+lab['prompt']+'\n\nДополнительная самостоятельная работа: ' if lab else '')+assignment+'\n\nПеред кодом запиши вход и ожидаемый результат словами. Подготовь обычный пример и отдельный случай на границе. В процессе решения отмечай, какое значение хранится в каждой переменной и какое условие остаётся верным. После запуска сравни результат с ручным расчётом; совпадение только с одним примером ещё не доказывает правильность.'),
      section('Диагностика и типичные ловушки',failure),
      section('Закрепление без подсказок','Вернись к задаче после перерыва и напиши решение в новом файле, не подглядывая в образец. Измени одно требование: допустимый диапазон, формат ответа или способ получения данных. Объясни, какие части алгоритма сохраняются, а какие нужно пересмотреть. Сравни два решения по ясности имён, явности проверок и числу скрытых зависимостей.\n\nДля завершения работы нужно не только получить ответ, но и объяснить его. Кратко запиши, почему выбранное начальное состояние правильно, что происходит на каждом этапе и почему работа заканчивается. Если объяснение опирается на слова «так получилось», вернись к трассировке и найди недостающую связь.'),
    ]
    return dict(id=lesson_id,title=title,chapter=chapter(index),kind='authored' if lab else 'review',theory='\n\n'.join(x['text'] for x in sections),sections=sections,examples=[code],mistakes=[failure],questions=questions,assignment=assignment,challenge=lab,photo=photo(slug),photoCaption='Учебная фотография, созданная для DevCat. Схема ниже показывает абстрактную модель; детали физического устройства могут отличаться.',checklist=['Я могу объяснить основной принцип своими словами.','Я написал решение самостоятельно и проверил границы.','Я могу изменить условие без копирования образца.'],minutes=35)
def specialized(lang,index,t):
    title,model,code,assignment=t
    sections=[
      section('Понятие и область применения',model),
      section('Пример и контракт','Прочитай пример до запуска и определи, какие значения создаются, кто ими владеет и какие условия должны выполняться. Фрагмент показывает центральную идею; при переносе в проект добавь нужные импорты, заголовки и точку входа по правилам '+NAMES[lang]+'. Комментарий с названием файла означает границу модуля, а не инструкцию вставить все файлы подряд в один.\n\nСначала предскажи наблюдаемый результат или состояние, затем проверь его. Если пример зависит от файла, создай отдельный тестовый каталог. Если требуется внешняя библиотека или инструмент, проверь его документацию и версию; встроенная среда не устанавливает зависимости незаметно.',code=code),
      section('Связь с изученными основами',LANGUAGE_CONTEXT[lang]+'\n\nСопоставь новую возможность с обычной функцией, циклом и структурой данных. Что она выражает яснее? Какой дополнительный контракт требует? Выдели ответственность вызывающего кода и ответственность самой операции. Для объектов и ресурсов отдельно проследи время жизни, для асинхронной работы — завершение и ошибку.',diagram='pipeline'),
      section('Лабораторная работа',assignment+'\n\nРаздели работу на минимальную рабочую версию, обработку отказов и улучшение структуры. Для каждого этапа сохрани пример, который показывает реальное изменение поведения. Перед рефакторингом зафиксируй проверки, чтобы изменение структуры не изменило контракт случайно. Не включай в тестовые данные пароли или реальные персональные сведения.'),
      section('Проверка и самостоятельный разбор','Подготовь обычный случай, пустые или отсутствующие данные там, где они допустимы, и неуспешную операцию. Определи ожидаемый результат до запуска. Проверь повторный вызов: не осталось ли скрытого состояния от предыдущего? Для сохранения данных обязательно перезапусти программу и восстанови экспорт в отдельном каталоге. Для конкурентного кода объясни, как заканчивается каждый участник.\n\nЭта работа оценивается по результату и объяснению, а не автоматическим сравнением одной строки. Пункты самопроверки не подтверждают профессиональную квалификацию: они помогают обнаружить темы, к которым стоит вернуться. Если не можешь объяснить поведение без образца, повтори базовый урок и сократи пример до нескольких операций.'),
    ]
    return dict(id=f'{lang}.advanced.{index+1}',title=title,chapter='05 · Особенности языка' if index<13 else '06 · Самостоятельные проекты',kind='review',sections=sections,theory='\n\n'.join(s['text'] for s in sections),examples=[code],mistakes=['Не переноси фрагмент без проверки импортов, версии среды и контракта.','Не скрывай неуспешную операцию сообщением об успехе.'],questions=['Какую проблему решает эта возможность языка?','Какие условия и ограничения есть у примера?','Как ты проверишь обычный случай и отказ?'],assignment=assignment,challenge=None,photo='memory.png' if lang in ['c','cpp'] and index<5 else 'workbench.png',photoCaption='Сгенерированная учебная фотография DevCat: контекст самостоятельной работы.',checklist=['Минимальная версия работает по описанному контракту.','Ошибки и границы проверены отдельно.','Код разделён по ответственности, я могу объяснить решение.'],minutes=50 if index<13 else 120)
def sql_lesson(index,t):
    slug,title,model,query,assignment=t
    automatic=index<27
    sections=[
      section('Модель и смысл операции',model),
      section('Запрос и ожидаемая форма результата','Прежде чем читать SQL, определи, что означает одна строка ответа. Затем назови исходные таблицы, ключи связи, фильтры и порядок. В учебной базе customers(id, name) содержит покупателей, orders(id, customer_id, amount) — заказы, сумма измеряется целыми единицами. Первичный ключ покупателя не равен номеру строки после сортировки.\n\nПроследи запрос на трёх покупателях и трёх заказах: у первого два заказа, у второго один, у третьего ни одного. Имя не обязано быть уникальным. Проверка также использует независимый набор данных, поэтому константный ответ вместо запроса не считается решением.',code=query,diagram='relation'),
      section('Разбор на бумаге','Нарисуй исходные строки и выполни логические этапы запроса вручную. Для соединения выпиши пары ключей, для фильтра — значение условия у каждой строки, для группировки — состав каждой группы. После этого вычисли итоговые выражения и порядок. Если появляется NULL, отдельно объясни его происхождение: отсутствие исходного значения и отсутствие совпадения при JOIN имеют разный контекст.\n\nИзмени данные: добавь второго покупателя с тем же именем, заказ с суммой на границе и покупателя без заказов. Сформулируй, как должен измениться ответ. Такая проверка обнаруживает случайную зависимость от демонстрационного набора.'),
      section('Практическая работа',assignment+'\n\nЗапиши контракт результата: названия и порядок столбцов, гранулярность строки, обработку пустого множества и сортировку. Для read-only задания используй встроенную проверку. Для изменения схемы и данных создай свою локальную базу: учебный runner защищает предустановленные таблицы и не выполняет DDL/DML. Не выдавай запрет runner за ограничение самого SQL.'),
      section('Самостоятельное закрепление','Перепиши решение с чистого листа и объясни, почему каждая часть нужна. Удали одну часть мысленно: какой конкретный пример перестанет работать? Сравни альтернативное выражение через JOIN, EXISTS, подзапрос или CTE там, где это осмысленно. Равенство ответа на маленьком примере не гарантирует одинаковый смысл на всех данных.\n\nПри оценке производительности сначала проверь правильность и план запроса на собственной базе реалистичного размера. Индекс, ограничения и транзакции решают разные задачи. Сохрани итоговый запрос вместе с примером данных и ожидаемым ответом: это превращает разовый эксперимент в воспроизводимую проверку.'),
    ]
    lab=dict(id='sql.'+slug+'.v2',language='sql',title=title,prompt=assignment+'\nСхема: customers(id, name), orders(id, customer_id, amount). Выводи столбцы именно в указанном порядке. Проверка выполняется на двух наборах данных.',starter='-- Напиши SELECT или WITH по условию\n',solution=query,hints=['Определи, что означает одна строка ответа.','Проследи фильтрацию, связь таблиц и обработку NULL на бумаге.','Проверь порядок столбцов и ORDER BY. Эталон доступен после самостоятельной попытки.'],tests=[]) if automatic else None
    return dict(id='sql.'+slug,title=title,chapter=f'{index//7+1:02} · '+['Основы запросов','Агрегация и связи','Подзапросы и множества','Оконные вычисления','Схема и изменения','Надёжность и проекты'][min(index//7,5)],kind='authored' if lab else 'review',sections=sections,theory='\n\n'.join(s['text'] for s in sections),examples=[query],mistakes=['Не полагайся на порядок без ORDER BY.','Проверь NULL, кратность связей и независимые данные.'],questions=['Что означает одна строка результата?','Как поведёт себя запрос на пустых данных и NULL?','Какая независимая проверка отличит верный запрос от случайного совпадения?'],assignment=assignment,challenge=lab,photo='data.png',photoCaption='Сгенерированная фотография картотеки: аналогия записей и связей, а не внутреннего хранения SQLite.',checklist=['Я объяснил контракт результата.','Я проверил запрос на независимых данных.','Я могу изменить запрос под новое требование.'],minutes=40 if index<27 else 75)
def main():
    courses=[]
    for lang,(version,subtitle,source) in META.items():
        lessons=[sql_lesson(i,t) for i,t in enumerate(SQL)] if lang=='sql' else [foundation(lang,i,t) for i,t in enumerate(FOUNDATIONS)]+[specialized(lang,i,t) for i,t in enumerate(SPECIAL[lang])]
        if lang == 'sql':
            lessons = [enrich_sql(i, SQL[i][0], lesson) for i, lesson in enumerate(lessons)]
        else:
            lessons = [enrich_foundation(lang, FOUNDATIONS[i][0], lesson) if i < len(FOUNDATIONS) else enrich_advanced(lang, i-len(FOUNDATIONS), lesson) for i, lesson in enumerate(lessons)]
        lessons += build_workshops(lang)
        lessons = beginner_lessons(lang) + lessons
        extra=[challenge(lang,'generator',f'{lang}.generator.{key}',key) for key in ['gcd','multiples']] if lang!='sql' else []
        course=dict(practiceBank=extra,id=lang,name=NAMES[lang],version=version,subtitle=subtitle,source=source,lessons=lessons,revision=4,review_status='authored_with_executable_labs_and_manual_projects',author='DevCat',last_verified='2026-10-28')
        course = visual_enrich(rewrite_notebook(course))
        courses.append(course)
        target=ROOT/'content'/lang;target.mkdir(exist_ok=True,parents=True)
        (target/'intro.json').write_text(json.dumps(course,ensure_ascii=False,indent=2)+'\n')
    courses += [visual_enrich(rewrite_notebook(web_course('html'))), visual_enrich(rewrite_notebook(web_course('css')))]
    for course in courses:
        if course['id'] in ['html','css']:
            for lesson in course['lessons']:
                for label in ['desktop','phone']:
                    image=lesson['id']+'-'+label+'.png'
                    if (ROOT/'apps/devcat_flutter/assets/content'/image).exists():
                        lesson['sections'].insert(3,dict(heading='Результат в браузере: '+label,text='Настоящий снимок Chromium при ширине '+('390px' if label=='phone' else '1080px')+'. Внешним изображениям нужны соответствующие локальные файлы.',image=image,imageCaption='Реальный браузерный рендеринг приведённого исходника.'))
    for course in courses:
        if course['id'] in ['html','css']:
            target=ROOT/'content'/course['id'];target.mkdir(exist_ok=True)
            (target/'intro.json').write_text(json.dumps(course,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'apps/devcat_flutter/assets/content/courses.json').write_text(json.dumps(courses,ensure_ascii=False,indent=2)+'\n')
    lines=['# Подробные курсы DevCat 0.5\n', 'Десять направлений с вводным маршрутом для новичка: основы, особенности языка, проекты и восемь подробных разборов сложных задач. Материалы, фотографии и схемы входят в офлайн-приложение. Заверши проекты, объясни решения и продолжай читать документацию.\n', '125 лабораторных проверяются автоматически; остальные работы — самостоятельная реализация с критериями. Проверка результата программы не оценивает автоматически качество тестов, стиль и объяснение. Для эталонов выполняется реальный запуск в CI; независимая экспертная редактура текста ещё нужна.\n']
    for course in courses:
        lines.append('\n## '+course['name']+' · '+course['version']+'\n')
        current=None
        for index,lesson in enumerate(course['lessons'],1):
            if current!=lesson['chapter']:
                current=lesson['chapter'];lines.append('\n### '+current+'\n')
            assessment={'tests':'автотесты','experiment':'опыт с образцом','project':'самостоятельный проект'}[lesson['learning']['assessment']]
            lines.append(f"{index}. {lesson['title']} — {assessment}; ориентир {lesson['minutes']} мин с практикой.")
        lines.append('\nДокументация: '+course['source']+'\n')
    git = visual_enrich(rewrite_notebook(git_course()))
    (ROOT/'apps/devcat_flutter/assets/content/git_course.json').write_text(json.dumps(git,ensure_ascii=False,indent=2)+'\n')
    used_images={s['image'] for c in courses+[git] for l in c['lessons'] for s in l['sections'] if s.get('image')}
    for image in (ROOT/'apps/devcat_flutter/assets/content').glob('steps-*.png'):
        if image.name not in used_images:
            image.unlink()
    export(courses+[git])
    (ROOT/'docs/CURRICULUM.md').write_text('\n'.join(lines).rstrip()+'\n')
    print(f'{sum(len(c["lessons"]) for c in courses)} lectures; {sum(bool(l["challenge"]) for c in courses for l in c["lessons"])} checked laboratories; '+str(sum(len(l['theory'].split()) for c in courses for l in c['lessons']))+' lecture words')
if __name__=='__main__':main()
