"""Own introductory material. Sources are links, not copied manuals."""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
meta={
 'c':('C','C17','Управляй памятью. Понимай основу.','https://en.cppreference.com/w/c',
 'Программа начинается с main. int хранит целое число; переменную объявляют до использования. printf печатает, scanf читает и требует адрес &n. Проверяй результат scanf: это число успешно прочитанных значений.',
 ['int age = 20;','printf("%d\\n", age);'],['Пропущенная ; завершает не все операторы: читай первую ошибку компилятора.','scanf("%d", n) вместо &n передаёт значение как адрес: это неопределённое поведение.']),
 'cpp':('C++','C++20','От первых строк к уверенным решениям.','https://en.cppreference.com/w/cpp',
 'Тип определяет допустимые значения и операции. int age = 20 объявляет целое. Подключи <iostream>, чтобы использовать std::cin и std::cout. Оператор >> извлекает число, << выводит значение. std:: — пространство имён стандартной библиотеки. Для имени с пробелами используй std::string из <string> и std::getline(std::cin, name); затем прочитай возраст через std::cin >> age.',
 ['int age = 20;','std::cout << age << "\\n";'],['Без #include <iostream> имена потоков неизвестны.','Забытый std:: приводит к ошибке поиска имени; это не ошибка типа.']),
 'csharp':('C#','.NET 8','Чёткие типы, выразительный код.','https://learn.microsoft.com/dotnet/csharp/',
 'В .NET 8 можно писать top-level statements без явного класса Main. Console.ReadLine возвращает строку или null. int.Parse преобразует строку в целое, а Console.WriteLine выводит значение. Учебный контракт гарантирует корректный ввод; в приложении используй TryParse.',
 ['int age = 20;','Console.WriteLine(age);'],['Console без using System требует полного имени System.Console.','int.Parse может выбросить FormatException: неверный ввод нужно обработать отдельно.']),
 'python':('Python','Python 3','Маленькие шаги. Большие возможности.','https://docs.python.org/3/tutorial/',
 'Python использует отступы для блоков. input() возвращает строку, int(input()) читает целое число. Переменные связывают имена с объектами; объявлять тип заранее не нужно. print выводит результат и перевод строки.',
 ['age = 20','print(age)'],['input() + 3 вызывает TypeError, потому что input возвращает строку.','Непоследовательные отступы вызывают IndentationError или меняют смысл программы.']),
 'java':('Java','Java 21','Надёжные программы, шаг за шагом.','https://dev.java/learn/',
 'Точка входа — public static void main(String[] args). Публичный класс Main хранится в Main.java. Scanner(System.in).nextInt() читает число. System.out.println выводит значение и перевод строки. JDK включает javac, JVM выполняет байткод.',
 ['int age = 20;','System.out.println(age);'],['Имя публичного класса должно совпадать с именем файла.','Scanner требует import java.util.Scanner; импорт не устанавливает сторонний пакет.']),
 'javascript':('JavaScript','ECMAScript / Node.js','От выражений к живым программам.','https://nodejs.org/api/fs.html',
 'Этот трек использует Node.js, а не браузер. let задаёт изменяемую переменную, const — неизменяемую привязку. Ввод: Number(require("fs").readFileSync(0, "utf8").trim()). Преобразование в Number важно: + со строкой может склеить текст.',
 ['let age = 20;','console.log(age);'],['prompt не определён в Node.js: это API браузера.','"2" + 3 даёт "23", а не 5: проверь преобразование строки.']),
 'go':('Go','Go 1.22+','Простота, которая растёт вместе с тобой.','https://go.dev/tour/',
 'Файл начинается с package main. Импорт fmt даёт Scan и Println. func main() — точка входа. var n int объявляет целое, fmt.Scan(&n) заполняет переменную. Короткая форма total := 0 объявляет переменную внутри функции.',
 ['age := 20','fmt.Println(age)'],['Неиспользуемая переменная или импорт — ошибка компиляции.','Scan(n) вместо Scan(&n) не передаёт указатель на переменную.']),
 'sql':('SQL','SQLite 3','Задавай данным правильные вопросы.','https://www.sqlite.org/lang_select.html',
 'SQL описывает желаемый результат. SELECT выбирает столбцы, FROM задаёт таблицу, WHERE фильтрует строки. LEFT JOIN сохраняет строки левой таблицы без совпадений справа. GROUP BY объединяет строки для агрегатов. COUNT(o.id) не считает NULL, COUNT(*) считает строки.',
 ['SELECT id, name FROM customers ORDER BY id;','SELECT COUNT(*) FROM orders WHERE amount >= 25;'],['INNER JOIN теряет покупателей без заказов.','COUNT(*) после LEFT JOIN даёт 1 для строки без заказа; считай непустой ключ справа.'])}
courses=[]
for key,(name,version,subtitle,source,theory,examples,mistakes) in meta.items():
 lessons=[dict(id=f'{key}.basics',title='Первая программа' if key!='sql' else 'Таблицы и LEFT JOIN',theory=theory,examples=examples,mistakes=mistakes,kind='arithmetic' if key!='sql' else 'join')]
 if key!='sql':
  loops={'python':('for i in range(1, n + 1):\n    total += i','range не включает правую границу. Используй n + 1, чтобы обработать N.'),'go':('for i := 1; i <= n; i++ {\n    total += i\n}','В Go единственная конструкция цикла — for; условие включительно: i <= n.')}
  example,explanation=loops.get(key,('for (int i = 1; i <= n; i++) {\n    total += i;\n}','Цикл выполняет тело, пока условие истинно; i++ увеличивает счётчик после шага.'))
  if key=='javascript': example=example.replace('int i','let i')
  lessons.append(dict(id=f'{key}.loops',title='Циклы и накопитель',kind='loop',theory='Чтобы сложить последовательность, начни с total = 0. '+explanation+' При N = 0 цикл не выполняется, накопитель остаётся нулевым. Для заданного диапазона N ≤ 1000 достаточно обычного целого; для больших данных учитывай переполнение.',examples=[example,'N = 10 → 1 + 2 + … + 10 = 55'],mistakes=['Условие i < n пропускает N: это off-by-one.','Необнулённый накопитель или сброс total внутри цикла дают неверный результат.']))
 else:
  lessons.append(dict(id='sql.filters',title='Фильтры и порядок',kind='filter',theory='WHERE фильтрует отдельные строки до группировки. >= включает границу. ORDER BY нужен, если порядок результата является частью контракта. Без ORDER BY порядок SQL не гарантирован.',examples=['SELECT id, amount FROM orders WHERE amount >= 25 ORDER BY id;','SELECT SUM(amount) FROM orders;'],mistakes=['> вместо >= теряет строку на границе.','Без ORDER BY движок не обязан возвращать строки по id.']))
 course=dict(id=key,name=name,version=version,subtitle=subtitle,source=source,lessons=lessons,revision=1,review_status='automated_examples_only',author='DevCat',last_verified='2026-10-26')
 courses.append(course)
 target=root/'content'/key;target.mkdir(parents=True,exist_ok=True)
 (target/'intro.json').write_text(json.dumps(course,ensure_ascii=False,indent=2)+'\n')
(root/'apps/devcat_flutter/assets/content/courses.json').write_text(json.dumps(courses,ensure_ascii=False,indent=2)+'\n')
