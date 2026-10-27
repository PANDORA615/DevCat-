import 'dart:math';

class Course {
  final String id, name, version, subtitle, source;
  final List<Lesson> lessons;
  Course(Map<String, dynamic> j)
    : id = j['id'],
      name = j['name'],
      version = j['version'],
      subtitle = j['subtitle'],
      source = j['source'],
      lessons = (j['lessons'] as List).map((x) => Lesson(x)).toList() {
    final seen = <String>{};
    coursePracticeBank[id] = lessons
        .map((l) => l.challenge)
        .whereType<Challenge>()
        .where((task) => seen.add(task.solution))
        .toList();
  }
}

class Lesson {
  final String id,
      title,
      theory,
      kind,
      chapter,
      assignment,
      photo,
      photoCaption;
  final List<Map<String, dynamic>> sections;
  final List<String> questions, checklist;
  final Challenge? challenge;
  final int minutes;
  final List<String> examples, mistakes;
  Lesson(Map<String, dynamic> j)
    : id = j['id'],
      title = j['title'],
      theory = j['theory'],
      kind = j['kind'],
      chapter = j['chapter'] ?? 'Основы',
      assignment = j['assignment'] ?? '',
      photo = j['photo'] ?? '',
      photoCaption = j['photoCaption'] ?? '',
      sections = (j['sections'] as List? ?? [])
          .map((x) => Map<String, dynamic>.from(x))
          .toList(),
      questions = List<String>.from(j['questions'] ?? []),
      checklist = List<String>.from(j['checklist'] ?? []),
      challenge = j['challenge'] == null
          ? null
          : Challenge.fromJson(Map<String, dynamic>.from(j['challenge'])),
      minutes = j['minutes'] ?? 25,
      examples = List<String>.from(j['examples']),
      mistakes = List<String>.from(j['mistakes']);
}

class Case {
  final String input, expected;
  const Case(this.input, this.expected);
}

class Challenge {
  final String id, language, title, prompt, starter, solution;
  final List<String> hints;
  final List<Case> tests;
  final int seed;
  factory Challenge.fromJson(Map<String, dynamic> j) => Challenge(
    id: j['id'],
    language: j['language'],
    title: j['title'],
    prompt: j['prompt'],
    starter: j['starter'],
    solution: j['solution'],
    hints: List<String>.from(j['hints']),
    tests: (j['tests'] as List)
        .map((x) => Case(x['input'], x['expected']))
        .toList(),
  );
  const Challenge({
    required this.id,
    required this.language,
    required this.title,
    required this.prompt,
    required this.starter,
    required this.solution,
    required this.hints,
    required this.tests,
    this.seed = 0,
  });
}

final Map<String, List<Challenge>> coursePracticeBank = {};

const languageNames = {
  'c': 'C',
  'cpp': 'C++',
  'csharp': 'C#',
  'python': 'Python',
  'java': 'Java',
  'javascript': 'JavaScript',
  'go': 'Go',
  'sql': 'SQL',
};
const fileNames = {
  'c': 'main.c',
  'cpp': 'main.cpp',
  'csharp': 'Program.cs',
  'python': 'main.py',
  'java': 'Main.java',
  'javascript': 'main.js',
  'go': 'main.go',
  'sql': 'query.sql',
};

/// Детерминированные задания: эталон и тесты создаются из одной спецификации,
/// однако проверяется вывод реальной программы, а не текст решения.
Challenge generateChallenge(
  String language, {
  int seed = 0,
  String kind = 'loop',
  String? lessonId,
}) {
  if (!languageNames.containsKey(language)) {
    throw ArgumentError('Генератор доступен только для восьми языков, не Git.');
  }
  final bank = coursePracticeBank[language];
  if (seed > 0 && bank != null && bank.isNotEmpty) {
    return _libraryChallenge(language, seed, bank);
  }
  if (language == 'cpp' && lessonId == 'cpp.basics') {
    return const Challenge(
      id: 'cpp.basics',
      language: 'cpp',
      title: 'Имя и возраст',
      prompt:
          'Прочитай имя целой первой строкой (включая пробелы; пустое имя разрешено), затем возраст 0–150 во второй строке. Выведи: Имя: <имя>; возраст: <число>. Без приглашений ввода.',
      starter:
          '#include <iostream>\n#include <string>\nint main() {\n    std::string name;\n    int age;\n    // Прочитай данные и выведи результат\n}\n',
      solution:
          '#include <iostream>\n#include <string>\nint main() { std::string name; int age; std::getline(std::cin, name); std::cin >> age; std::cout << "Имя: " << name << "; возраст: " << age << "\\n"; }\n',
      hints: [
        'Имя может содержать пробелы: читай всю строку.',
        'Используй std::getline(std::cin, name), затем std::cin >> age.',
        'std::cout связывает строковые фрагменты и значения оператором <<.',
      ],
      tests: [
        Case('Анна\n20\n', 'Имя: Анна; возраст: 20'),
        Case('\n0\n', 'Имя: ; возраст: 0'),
        Case('Аня Петрова\n150\n', 'Имя: Аня Петрова; возраст: 150'),
      ],
    );
  }
  final rng = Random(seed);
  final factor = 2 + rng.nextInt(7);
  final variant = seed == 0 ? 0 : rng.nextInt(3);
  if (language == 'sql') return _sql(seed, factor, lessonId);
  final arithmetic = kind == 'arithmetic';
  final description = arithmetic
      ? 'Прочитай целое N (0 ≤ N ≤ 1000) из stdin. Выведи N × $factor + 3. Только число, без приглашений.'
      : switch (variant) {
          0 =>
            'Прочитай N (0 ≤ N ≤ 1000). Найди сумму целых чисел от 1 до N включительно. При N = 0 ответ 0.',
          1 =>
            'Прочитай N (0 ≤ N ≤ 1000). Найди сумму чисел от 1 до N включительно, кратных $factor. При отсутствии таких чисел ответ 0.',
          _ =>
            'Прочитай N (0 ≤ N ≤ 1000). Посчитай, сколько чисел от 1 до N включительно кратны $factor. При N = 0 ответ 0.',
        };
  int expected(int n) {
    if (arithmetic) return n * factor + 3;
    var result = 0;
    for (var i = 1; i <= n; i++) {
      if (variant == 0 || i % factor == 0) result += variant == 2 ? 1 : i;
    }
    return result;
  }

  final condition = variant == 0 ? null : 'i % $factor == 0';
  final expression = arithmetic ? 'n * $factor + 3' : 'total';
  final body = arithmetic
      ? ''
      : 'for (int i = 1; i <= n; i++) { ${condition == null ? '' : 'if ($condition) '}total += ${variant == 2 ? '1' : 'i'}; }';
  final starters = <String, String>{
    'c':
        '#include <stdio.h>\nint main(void) {\n    int n;\n    scanf("%d", &n);\n    // Твоё решение\n    return 0;\n}\n',
    'cpp':
        '#include <iostream>\nint main() {\n    int n;\n    std::cin >> n;\n    // Твоё решение\n}\n',
    'csharp':
        'using System;\nint n = int.Parse(Console.ReadLine()!);\n// Твоё решение\n',
    'python': 'n = int(input())\n# Твоё решение\n',
    'java':
        'import java.util.Scanner;\npublic class Main {\n    public static void main(String[] args) {\n        int n = new Scanner(System.in).nextInt();\n        // Твоё решение\n    }\n}\n',
    'javascript':
        "const fs = require('fs');\nconst n = Number(fs.readFileSync(0, 'utf8').trim());\n// Твоё решение\n",
    'go':
        'package main\nimport "fmt"\nfunc main() {\n    var n int\n    fmt.Scan(&n)\n    // Твоё решение\n}\n',
  };
  final solutions = <String, String>{
    'c':
        '#include <stdio.h>\nint main(void) { int n, total = 0; if (scanf("%d", &n) != 1) return 1; $body printf("%d\\n", $expression); return 0; }\n',
    'cpp':
        '#include <iostream>\nint main() { int n, total = 0; std::cin >> n; $body std::cout << $expression << "\\n"; }\n',
    'csharp':
        'using System;\nint n = int.Parse(Console.ReadLine()!);\nint total = 0;\n$body\nConsole.WriteLine($expression);\n',
    'java':
        'import java.util.Scanner;\npublic class Main { public static void main(String[] args) { int n = new Scanner(System.in).nextInt(); int total = 0; $body System.out.println($expression); } }\n',
    'python':
        'n = int(input())\n${arithmetic ? '' : 'total = 0\nfor i in range(1, n + 1):\n${condition == null ? '    total += i' : '    if $condition:\n        total += ${variant == 2 ? '1' : 'i'}'}\n'}print($expression)\n',
    'javascript':
        "const n = Number(require('fs').readFileSync(0, 'utf8').trim());\nlet total = 0;\n${body.replaceAll('int i', 'let i')}\nconsole.log($expression);\n",
    'go':
        'package main\nimport "fmt"\nfunc main() { var n int; fmt.Scan(&n); total := 0; ${arithmetic ? '' : 'for i := 1; i <= n; i++ { ${condition == null ? '' : 'if $condition { '}total += ${variant == 2 ? '1' : 'i'}${condition == null ? '' : ' }'} };'} ${arithmetic ? '_ = total;' : ''} fmt.Println($expression) }\n',
  };
  return Challenge(
    id: lessonId ?? '$language.generated.$seed',
    language: language,
    seed: seed,
    title: arithmetic
        ? 'Выражение и результат'
        : [
            'Сумма последовательности',
            'Сумма кратных',
            'Счётчик кратных',
          ][variant],
    prompt:
        '$description\nВыводи только ответ и перевод строки. Проверяются в том числе граничные значения.',
    starter: starters[language]!,
    solution: solutions[language]!,
    hints: arithmetic
        ? [
            'Сначала умножение, затем сложение.',
            'Сохрани результат n * $factor + 3.',
            'Выведи выражение n * $factor + 3 через стандартный вывод.',
          ]
        : [
            'Начни с нулевого накопителя.',
            'Включи N в диапазон: i <= n или range(1, n + 1).',
            condition == null
                ? 'На каждом шаге прибавляй i к total.'
                : 'Условие кратности: $condition; ${variant == 2 ? 'увеличивай счётчик на 1' : 'прибавляй i'}.',
          ],
    tests: {
      0,
      1,
      10,
      factor,
      50 + rng.nextInt(950),
    }.map((n) => Case('$n\n', '${expected(n)}')).toList(),
  );
}

const sqlFixture = '''
CREATE TABLE customers(id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE orders(id INTEGER PRIMARY KEY, customer_id INTEGER REFERENCES customers(id), amount INTEGER NOT NULL);
INSERT INTO customers VALUES(1,'Аня'),(2,'Борис'),(3,'Вера');
INSERT INTO orders VALUES(1,1,10),(2,1,25),(3,2,40);
''';
Challenge _sql(int seed, int factor, String? lessonId) {
  final join = seed == 0;
  return Challenge(
    id: lessonId ?? 'sql.generated.$seed',
    language: 'sql',
    seed: seed,
    title: join ? 'Покупатели без заказов' : 'Фильтр заказов',
    prompt: join
        ? 'Выведи name и число заказов каждого покупателя, включая покупателей без заказов. Сортировка по customers.id. Таблицы: customers(id, name), orders(id, customer_id, amount). COUNT(o.id) не считает NULL.'
        : 'Выведи id и amount заказов с amount ≥ ${factor * 5}. Сортировка по id. Данные в примере: 10, 25, 40. Проверка также использует другой набор данных.',
    starter: join
        ? 'SELECT c.name, COUNT(o.id)\nFROM customers AS c\n-- Добавь JOIN и группировку\n'
        : 'SELECT id, amount\nFROM orders\n-- Добавь условие и сортировку\n',
    solution: join
        ? 'SELECT c.name, COUNT(o.id) FROM customers c LEFT JOIN orders o ON c.id = o.customer_id GROUP BY c.id, c.name ORDER BY c.id;'
        : 'SELECT id, amount FROM orders WHERE amount >= ${factor * 5} ORDER BY id;',
    hints: join
        ? [
            'Нужно сохранить левую таблицу целиком.',
            'Используй LEFT JOIN и GROUP BY c.id, c.name.',
            'Считай COUNT(o.id), а не COUNT(*), чтобы получить 0.',
          ]
        : [
            'Фильтрация строк выполняется WHERE.',
            'Сравни amount с ${factor * 5}.',
            'Заверши запрос ORDER BY id.',
          ],
    tests: const <Case>[],
  );
}

Challenge _libraryChallenge(String language, int seed, List<Challenge> bank) {
  final rng = Random(seed);
  final chosen = bank[rng.nextInt(bank.length)];
  var solution = chosen.solution, prompt = chosen.prompt;
  var tests = [...chosen.tests];
  void scalar(Iterable<int> values, int Function(int) expected) {
    tests = values.toSet().map((n) => Case('$n\n', '${expected(n)}')).toList();
  }

  if (language != 'sql') {
    final topic = chosen.id.split('.')[1];
    if (topic == 'basics' || topic == 'variables') {
      final factor = 2 + rng.nextInt(8), offset = rng.nextInt(20);
      solution = solution.replaceAll('n * 4 + 3', 'n * $factor + $offset');
      prompt = prompt.replaceAll('N × 4 + 3', 'N × $factor + $offset');
      scalar([0, 1, 10, 1000, rng.nextInt(1001)], (n) => n * factor + offset);
    } else if (topic == 'expressions') {
      final capacity = 2 + rng.nextInt(99);
      solution = solution.replaceAll('% 60', '% $capacity');
      prompt =
          'Прочитай число предметов N (0 ≤ N ≤ 100000). В полной коробке $capacity предметов. Выведи число оставшихся предметов после заполнения всех возможных полных коробок.';
      scalar([
        0,
        capacity - 1,
        capacity,
        capacity + 1,
        100000,
      ], (n) => n % capacity);
    } else if (topic == 'booleans') {
      final lo = rng.nextInt(50), hi = 50 + rng.nextInt(50);
      solution = solution.replaceAllMapped(
        RegExp(r'\b(10|20)\b'),
        (match) => match[1] == '10' ? '$lo' : '$hi',
      );
      prompt =
          'Прочитай целое N от -1000 до 1000. Выведи 1, если $lo ≤ N ≤ $hi, иначе 0.';
      scalar([
        -1000,
        lo - 1,
        lo,
        hi,
        hi + 1,
        1000,
      ], (n) => n >= lo && n <= hi ? 1 : 0);
    } else if (topic == 'nested') {
      final divisor = 2 + rng.nextInt(8);
      solution = solution.replaceAll('% 3', '% $divisor');
      prompt = prompt.replaceAll('кратных 3', 'кратных $divisor');
      scalar([0, 1, divisor, 1000, rng.nextInt(1001)], (n) {
        final count = n ~/ divisor;
        return divisor * count * (count + 1) ~/ 2;
      });
    } else if (topic == 'loops') {
      scalar([
        0,
        1,
        1000,
        rng.nextInt(1001),
        rng.nextInt(1001),
      ], (n) => n * (n + 1) ~/ 2);
    } else if (topic == 'strings') {
      final sample = List.generate(
        40,
        (_) => 'abc XYZ0123456789'[rng.nextInt(16)],
      ).join();
      tests.add(
        Case(
          '$sample\n',
          sample.codeUnits.where((c) => c >= 48 && c <= 57).length.toString(),
        ),
      );
    }
  } else if (chosen.id == 'sql.filters.v2') {
    final threshold = 5 + rng.nextInt(70);
    solution = solution.replaceAll('>= 25', '>= $threshold');
    prompt =
        'Выведи id и amount заказов с amount ≥ $threshold. Отсортируй по id.';
  }
  tests.shuffle(rng);
  return Challenge(
    id: '$language.generated.$seed',
    language: language,
    seed: seed,
    title: chosen.title,
    prompt: prompt,
    starter: chosen.starter,
    solution: solution,
    hints: chosen.hints,
    tests: tests,
  );
}
