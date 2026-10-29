import 'course.dart';

class TutorReply {
  final String text, lessonId, title;
  final bool found;
  const TutorReply(this.text, this.lessonId, this.title, {this.found = true});
}

/// Grounded offline explanations, always taken from the shipped course.
/// This is a course navigator with authored answers, not a generative model.
class CourseTutor {
  final List<Course> courses;
  CourseTutor(this.courses);
  static List<String> words(String text) => RegExp(r'[a-zа-яё0-9_]+')
      .allMatches(text.toLowerCase())
      .map((m) => m[0]!)
      .where(
        (s) =>
            s.length > 2 &&
            !const {
              'что',
              'такое',
              'как',
              'почему',
              'какой',
              'какая',
              'это',
              'мне',
              'нужно',
              'объясни',
              'пожалуйста',
              'такой',
              'делает',
              'работает',
              'понял',
              'непонятно',
              'вообще',
            }.contains(s),
      )
      .map((s) => s.length > 6 ? s.substring(0, s.length - 2) : s)
      .toList();
  TutorReply explain(String question, {String? language, String? lessonId}) {
    final q = question.trim().toLowerCase();
    if (q.isEmpty) {
      return const TutorReply(
        'Напиши, что непонятно, или выбери: «сначала», «по строкам», «пример», «ошибка».',
        '',
        '',
        found: false,
      );
    }
    final selected = courses
        .where((c) => language == null || c.id == language)
        .toList();
    final lessons = selected.expand((c) => c.lessons).toList();
    if (lessons.isEmpty) {
      return const TutorReply(
        'Выбери курс, чтобы я нашёл объяснение в его материалах.',
        '',
        '',
        found: false,
      );
    }
    Lesson? current;
    for (final l in lessons) {
      if (l.id == lessonId) current = l;
    }
    final followup = [
      'сначала',
      'проще',
      'по строкам',
      'каждую строку',
      'пример',
      'ошибка',
      'не понял',
      'повтори',
      'как проверить',
    ].any((s) => q == s || q == '$s пожалуйста');
    Lesson? best = followup ? current : null;
    var score = 0;
    final terms = words(q).toSet();
    for (final lesson in lessons) {
      final heading = words(lesson.title).toSet();
      final body = words(lesson.theory).toSet();
      final code = words(
        lesson.sections.map((s) => s['code'] ?? '').join('\n'),
      ).toSet();
      final value = terms.fold<int>(
        0,
        (n, t) =>
            n +
            (heading.contains(t)
                ? 12
                : code.contains(t)
                ? 3
                : body.contains(t)
                ? 1
                : 0),
      );
      if (value > score && !followup) {
        score = value;
        best = lesson;
      }
    }
    best ??= followup ? (current ?? lessons.first) : null;
    if (best == null || (!followup && score < 2)) {
      return const TutorReply(
        'Я не нашёл точного объяснения в курсе. Напиши название конструкции, вставь непонятную строку или выбери тему. Не хочу подменять ответ случайным советом. Если речь о текущем уроке, нажми «сначала» или «по строкам».',
        '',
        '',
        found: false,
      );
    }
    final sections = best.sections;
    final matching = sections.where((s) {
      final heading = (s['heading'] as String).toLowerCase();
      if (q.contains('строк')) {
        return heading.contains('запись') ||
            heading.contains('программа') ||
            heading.contains('маленькие');
      }
      if (q.contains('ошиб')) {
        return heading.contains('ошиб') || heading.contains('затруд');
      }
      if (q.contains('пример')) return s['code'] != null;
      if (q.contains('провер')) {
        return heading.contains('эксперимент') ||
            heading.contains('самостоятель');
      }
      return false;
    }).toList();
    final chosen = matching.isNotEmpty ? matching.take(2) : sections.take(3);
    final text = StringBuffer('Разберём спокойно: ${best.title}.\n\n');
    for (final section in chosen) {
      text.writeln('${section['heading']}\n${section['text']}\n');
      if (section['code'] != null) text.writeln('${section['code']}\n');
      if (section['table'] != null) {
        final table = section['table'] as Map;
        text.writeln((table['columns'] as List).join(' | '));
        for (final row in table['rows'] as List) {
          text.writeln((row as List).join(' | '));
        }
        text.writeln();
      }
    }
    text.write(
      'Теперь попробуй назвать первое действие своими словами. Можно спросить «по строкам», «пример», «ошибка» или указать другое понятие.\n\nИсточник: урок «${best.title}».',
    );
    return TutorReply(text.toString(), best.id, best.title);
  }
}
