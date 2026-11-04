"""Small authored changes with observable results, using already introduced syntax."""
import re


def first_program_variation(lesson, lang):
    if '.zero.' not in lesson['id'] or lang in ('sql', 'html', 'css', 'git'):
        return None
    key = lesson['id'].split('.')[-1]
    source = lesson['runnableExample']['code']
    result = source
    cases = [{'input': '', 'expected': ''}]
    if key == 'start':
        prompt = 'Поздоровайся по-своему: вместо Hello программа должна показать Mew. Кавычки в результат не входят.'
        result = source.replace('"Hello"', '"Mew"')
        cases[0]['expected'] = 'Mew'
    elif key == 'output':
        prompt = 'Поменяй порядок приветствий: сначала Cat, на следующей строке Hello. Сохрани два отдельных действия вывода.'
        result = source.replace('"Hello"', '"__TEMP__"').replace('"Cat"', '"Hello"').replace('"__TEMP__"', '"Cat"')
        cases[0]['expected'] = 'Cat\nHello'
    elif key == 'values':
        prompt = 'Покажи сумму 4 и 3, а затем текст 23. Измени только число в вычислении: текстовая строка должна остаться прежней.'
        result = source.replace('2 + 3', '4 + 3')
        cases[0]['expected'] = '7\n23'
    elif key == 'variable':
        prompt = 'На счёте теперь 20 монет. Пополнение остаётся 5. Измени начальный баланс, сохрани вычисление и покажи новый итог.'
        result = re.sub(r'(balance\s*(?::=|=)\s*)10\b', r'\g<1>20', source, count=1)
        cases[0]['expected'] = '25'
    elif key == 'arithmetic':
        prompt = 'Одна тетрадь стоит 9 монет, нужно 4 тетради. Измени исходные данные покупки. Сохрани умножение и выведи общую стоимость.'
        result = re.sub(r'(price\s*(?::=|=)\s*)7\b', r'\g<1>9', source, count=1)
        result = re.sub(r'(count\s*(?::=|=)\s*)3\b', r'\g<1>4', result, count=1)
        cases[0]['expected'] = '36'
    elif key == 'input':
        prompt = 'Программа должна читать число и прибавлять 2. Проверь её на положительном числе, нуле и отрицательном числе. Ответ нельзя привязать к одному входу.'
        result = source.replace('count + 1', 'count + 2')
        cases = [{'input': f'{n}\n', 'expected': str(n+2)} for n in (4, 0, -2, 17)]
    elif key == 'choice':
        prompt = 'В учебном клубе взрослый тариф начинается с 16 лет включительно. Измени границу условия. Для возраста 16 программа должна показать adult.'
        result = source.replace('age >= 18', 'age >= 16')
        cases[0]['expected'] = 'adult'
    elif key == 'repeat':
        prompt = 'Сложи числа от 1 до 5 включительно с помощью имеющегося цикла. Измени его границу; не заменяй вычисление готовым ответом. Ожидается 15.'
        result = source.replace('number <= 3', 'number <= 5').replace('range(1, 4)', 'range(1, 6)')
        cases[0]['expected'] = '15'
    else:
        return None
    assert result != source, lesson['id']
    assert all(c['expected'] for c in cases)
    return dict(mode='program', task='modify', prompt=prompt, starter=source, solution=result, tests=cases,
                why='Сначала предскажи результат нового условия. Измени данные или действие в полном исходнике, затем запусти программу. Сравнение выполняется по настоящему выводу.')


def restore_statement(lesson, lang, line, syntax):
    source = lesson['runnableExample']['code']
    if not line or line not in source:
        return None
    comment = '# Восстанови действие по условию ниже' if lang == 'python' else '-- Восстанови запрос' if lang == 'sql' else '// Восстанови действие по условию ниже'
    starter = source.replace(line, re.match(r'\s*', line)[0] + comment, 1)
    return dict(mode='program', task='restore', prompt='В программе пропущено действие. Восстанови его в редакторе так, чтобы все примеры входа давали указанный результат.',
                starter=starter, solution=source, tests=lesson['runnableExample']['tests'], why=syntax)
