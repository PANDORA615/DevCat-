import 'dart:math';
import 'sound.dart';

enum CompanionPlace {
  home,
  lesson,
  practice,
  ide,
  git,
  reference,
  progress,
  settings,
}

class CompanionContext {
  final CompanionPlace place;
  final String title, language;
  const CompanionContext(this.place, {this.title = '', this.language = ''});
  String get key => '${place.name}:$language:$title';
}

class CatLine {
  final String text;
  final CatMood mood;
  const CatLine(this.text, [this.mood = CatMood.encouragement]);
}

/// Shuffled offline conversation. It never pretends to have inspected user code.
class CatChatter {
  final Random random;
  final List<CatLine> _bag = [];
  String _context = '', _last = '';
  CatChatter({Random? random}) : random = random ?? Random();

  CatLine next(CompanionContext context) {
    if (_context != context.key) {
      _context = context.key;
      _bag.clear();
    }
    if (_bag.isEmpty) {
      _bag.addAll(_lines(context)..shuffle(random));
      final priority = _bag
          .where(
            (l) =>
                (context.title.isNotEmpty &&
                    l.text.contains('«${context.title}»')) ||
                (context.language.isNotEmpty &&
                    l.text.contains(switch (context.language) {
                      'python' => 'Python',
                      'go' => 'Go',
                      'java' => 'Java',
                      'csharp' => 'C#',
                      'cpp' => 'C++',
                      'sql' => 'SQL',
                      'javascript' => 'JavaScript',
                      'html' => 'HTML',
                      'css' => 'CSS',
                      _ => 'В C ',
                    })) ||
                (context.place == CompanionPlace.ide &&
                    l.text.contains('сохрани проект')),
          )
          .toList();
      for (final item in priority) {
        _bag.remove(item);
      }
      _bag.addAll(priority);
      if (_bag.length > 1 && _bag.last.text == _last) {
        final first = _bag.first;
        _bag[0] = _bag.last;
        _bag[_bag.length - 1] = first;
      }
    }
    final line = _bag.removeLast();
    _last = line.text;
    return line;
  }

  List<CatLine> _lines(CompanionContext context) => [
    const CatLine(
      'Мур. Я рядом — будем разбираться по одному маленькому шагу.',
    ),
    const CatLine(
      'Интересно, что получится, если изменить всего одно значение?',
      CatMood.thinking,
    ),
    const CatLine(
      'Программисты тоже перечитывают одну строку несколько раз. Это нормально.',
    ),
    const CatLine(
      'Маленький понятный пример — уже маленькая победа.',
      CatMood.celebration,
    ),
    const CatLine(
      'Можно идти медленно. Главное — понимать, почему программа делает именно так.',
    ),
    const CatLine(
      'Я бы сейчас проверил самый простой случай. Иногда он объясняет половину задачи.',
      CatMood.thinking,
    ),
    const CatLine(
      'Если устал, короткая пауза поможет вернуться со свежим взглядом.',
      CatMood.warning,
    ),
    const CatLine(
      'У каждого хорошего решения когда-то был первый неуверенный черновик.',
    ),
    const CatLine(
      'Люблю момент, когда непонятная строка вдруг становится понятной.',
      CatMood.celebration,
    ),
    const CatLine(
      'Мур-мур. Ошибка — повод задать программе ещё один хороший вопрос.',
    ),
    const CatLine(
      'Попробуй объяснить идею вслух. Я буду очень внимательным слушателем.',
      CatMood.greeting,
    ),
    const CatLine(
      'Не обязательно запоминать всё сразу. Полезнее понять, где искать ответ.',
    ),
    const CatLine(
      'Небольшие эксперименты часто учат лучше, чем долгое угадывание.',
      CatMood.explaining,
    ),
    const CatLine(
      'А что в этом примере меняется, а что остаётся неизменным?',
      CatMood.thinking,
    ),
    const CatLine(
      'Я мысленно свернулся клубочком рядом с клавиатурой. Продолжай, я здесь.',
      CatMood.greeting,
    ),
    const CatLine(
      'Удобное имя переменной иногда объясняет код лучше длинного комментария.',
      CatMood.explaining,
    ),
    const CatLine(
      'Давай начнём с самого начала: где данные, какое действие и где результат.',
      CatMood.greeting,
    ),
    const CatLine(
      'Можно спросить меня «что означает эта строка» — разберём её отдельно.',
      CatMood.explaining,
    ),
    const CatLine(
      'Не нужно знать английские термины заранее. Дадим каждому простое объяснение.',
      CatMood.thinking,
    ),
    const CatLine(
      'Я рядом. Сегодня достаточно понять одно действие и проверить его на примере.',
      CatMood.encouragement,
    ),
    const CatLine(
      'Если чтение утомило, давай попробуем маленький опыт в редакторе.',
      CatMood.celebration,
    ),
    const CatLine(
      'Новый термин — не экзамен. Сначала увидим, что он означает в работе.',
      CatMood.warning,
    ),
    const CatLine(
      'Видишь две похожие записи? Изменим одну и сравним результат.',
      CatMood.greeting,
    ),
    const CatLine(
      'Мур. Хороший вопрос — «почему именно так?».',
      CatMood.explaining,
    ),
    const CatLine(
      'Ошибки не измеряют способности. Они показывают, где проверить предположение.',
      CatMood.thinking,
    ),
    const CatLine(
      'Я могу повторить объяснение столько раз, сколько нужно.',
      CatMood.encouragement,
    ),
    const CatLine(
      'Книга большая, но идти будем маленькими шагами.',
      CatMood.celebration,
    ),
    const CatLine(
      'Попробуй сначала предсказать одну строку вывода. Потом проверим вместе.',
      CatMood.warning,
    ),
    const CatLine(
      'Пауза — тоже часть учёбы. Я подожду тебя рядом с учебником.',
      CatMood.greeting,
    ),
    const CatLine(
      'Код можно читать как историю: сначала произошло одно, потом другое.',
      CatMood.explaining,
    ),
    const CatLine(
      'Не запоминай символы вслепую. Назови действие, которое они обозначают.',
      CatMood.thinking,
    ),
    const CatLine(
      'Для HTML результат виден на странице, а для CSS важно сравнить до и после.',
      CatMood.encouragement,
    ),
    const CatLine(
      'В Go := создаёт переменную, а = меняет уже объявленную. Это разные шаги.',
      CatMood.celebration,
    ),
    const CatLine(
      'Git сохраняет историю на устройстве; GitHub помогает работать с удалённым репозиторием.',
      CatMood.warning,
    ),
    ...switch (context.place) {
      CompanionPlace.home => [
        const CatLine(
          'Выбери направление, которое сейчас интереснее всего. Мы можем начать с основ.',
          CatMood.greeting,
        ),
        const CatLine(
          'Хочешь вернуться к прошлой теме? Сохранённая позиция поможет продолжить.',
        ),
        const CatLine(
          'Сегодня можно просто разобрать один пример. Это уже полезное занятие.',
        ),
        const CatLine(
          'Я приготовил компанию для чтения, практики и маленьких экспериментов.',
          CatMood.greeting,
        ),
      ],
      CompanionPlace.lesson => [
        CatLine(
          'Разбираем «${context.title}». Попробуй сформулировать главную идею своими словами.',
          CatMood.explaining,
        ),
        const CatLine(
          'Перед запуском примера попробуй предсказать его вывод. Потом сравним.',
          CatMood.thinking,
        ),
        const CatLine(
          'Если термин новый, найди его в примере и посмотри, какую роль он играет.',
          CatMood.explaining,
        ),
        const CatLine(
          'Вопросы после лекции помогут заметить, что уже понятно, а что стоит перечитать.',
        ),
        const CatLine(
          'Схема показывает связи. Попробуй проследить их от входных данных до результата.',
          CatMood.explaining,
        ),
        const CatLine(
          'Не торопись прокручивать. Один разобранный пример полезнее нескольких бегло прочитанных.',
        ),
      ],
      CompanionPlace.practice => [
        const CatLine(
          'Сначала сверь формат ввода и вывода с условием. Он тоже часть решения.',
          CatMood.explaining,
        ),
        const CatLine(
          'Проверь границы: ноль, один элемент, отрицательное число — где это разрешено условием.',
          CatMood.thinking,
        ),
        const CatLine(
          'Если результат неожиданный, проследи значения переменных на маленьком примере.',
          CatMood.thinking,
        ),
        const CatLine(
          'Можно сначала написать шаги решения обычными словами, а потом перевести их в код.',
        ),
        const CatLine(
          'Одна осмысленная правка за раз — так легче понять причину изменения.',
        ),
        const CatLine(
          'Когда всё получится, попробуй объяснить, почему решение работает на разных входных данных.',
          CatMood.celebration,
        ),
      ],
      CompanionPlace.ide => [
        const CatLine(
          'Перед большим изменением сохрани проект. К маленьким экспериментам удобнее возвращаться.',
        ),
        const CatLine(
          'Если файл стал трудным для чтения, часть работы можно вынести в отдельный модуль.',
          CatMood.explaining,
        ),
        const CatLine(
          'Имена файлов и точка входа помогают понять, с чего начинается программа.',
          CatMood.explaining,
        ),
        const CatLine(
          'Одинаковый кусочек кода в нескольких местах — повод подумать об общей функции.',
          CatMood.thinking,
        ),
        const CatLine(
          'Начни с маленькой работающей версии проекта, затем добавляй возможности по одной.',
        ),
        const CatLine(
          'Полезно проверить проект после переименования или удаления файла.',
          CatMood.thinking,
        ),
      ],
      CompanionPlace.git => [
        const CatLine(
          'Хорошее сообщение коммита объясняет, зачем сделано изменение.',
          CatMood.explaining,
        ),
        const CatLine(
          'Перед коммитом полезно посмотреть diff и понять каждое изменение.',
          CatMood.thinking,
        ),
        const CatLine(
          'Небольшие логичные коммиты помогают читать историю проекта.',
        ),
        const CatLine(
          'Ветка удобна для эксперимента, который хочется держать отдельно от основной работы.',
          CatMood.explaining,
        ),
      ],
      CompanionPlace.reference => [
        const CatLine(
          'Справочник удобнее читать с конкретным вопросом. Что ты хочешь выяснить?',
          CatMood.thinking,
        ),
        const CatLine(
          'Найденное правило стоит проверить на маленьком собственном примере.',
          CatMood.explaining,
        ),
        const CatLine(
          'Сравнение похожих конструкций помогает заметить важные различия.',
        ),
        const CatLine(
          'Если ответ нашёлся, попробуй объяснить его без подсказки.',
        ),
      ],
      CompanionPlace.progress => [
        const CatLine(
          'Прогресс — это ещё и то, что теперь получается объяснить своими словами.',
        ),
        const CatLine(
          'Возвращаться к пройденным темам полезно. Знакомый пример часто открывается по-новому.',
          CatMood.explaining,
        ),
        const CatLine(
          'Выбери одну тему для повторения — не нужно повторять всё сразу.',
        ),
        const CatLine(
          'Попробуй решить знакомую задачу заново, не открывая прежний код.',
          CatMood.thinking,
        ),
      ],
      CompanionPlace.settings => [
        const CatLine(
          'Мою болтовню можно настроить отдельно от громкости голоса. Я подстроюсь под твой ритм.',
        ),
        const CatLine(
          'Комфортный размер текста помогает читать дольше без лишнего напряжения.',
          CatMood.explaining,
        ),
        const CatLine(
          'Мур! Цвет моей эмблемы подстраивается под выбранную тему.',
          CatMood.greeting,
        ),
        const CatLine(
          'Если хочется тишины, выключи мой голос. Текстовые реплики останутся.',
        ),
      ],
    },
    ...switch (context.language) {
      'python' => [
        const CatLine(
          'В Python отступы показывают структуру блока. Проверь, какие строки находятся внутри него.',
          CatMood.explaining,
        ),
      ],
      'c' => [
        const CatLine(
          'В C следи за границами массива и временем жизни памяти, на которую ссылается указатель.',
          CatMood.explaining,
        ),
      ],
      'cpp' => [
        const CatLine(
          'В C++ подумай, кто владеет ресурсом и когда он освобождается.',
          CatMood.thinking,
        ),
      ],
      'csharp' => [
        const CatLine(
          'В C# полезно заранее решить, может ли значение отсутствовать, и явно обработать этот случай.',
          CatMood.thinking,
        ),
      ],
      'java' => [
        const CatLine(
          'В Java equals сравнивает смысл значений так, как определено типом. Для ссылок == означает другое.',
          CatMood.explaining,
        ),
      ],
      'javascript' => [
        const CatLine(
          'В JavaScript проверь типы значений перед операцией: преобразование иногда меняет результат.',
          CatMood.thinking,
        ),
      ],
      'go' => [
        const CatLine(
          'В Go возвращённый error — часть результата. Не забудь решить, как его обработать.',
          CatMood.explaining,
        ),
      ],
      'sql' => [
        const CatLine(
          'В SQL порядок строк гарантирует ORDER BY. Без него результат может прийти в другом порядке.',
          CatMood.explaining,
        ),
      ],
      _ => <CatLine>[],
    },
  ];
}
