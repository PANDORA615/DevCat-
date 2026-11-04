import 'course.dart';
import 'runner.dart';
import 'study.dart';

String studySource(StudyExercise exercise, String entry) =>
    ['challenge', 'program'].contains(exercise.data['mode'])
    ? entry
    : exercise.code.replaceFirst('___', entry);

Future<CheckResult> evaluateStudyCode(
  LocalRunner runner,
  Course course,
  Lesson lesson,
  StudyExercise exercise,
  String entry,
) async {
  final source = studySource(exercise, entry);
  if (exercise.data['mode'] == 'challenge') {
    if (lesson.challenge == null) {
      return const CheckResult(
        false,
        'Не найдено условие задачи.',
        evaluated: false,
      );
    }
    return runner.check(lesson.challenge!, source);
  }
  final example = lesson.runnableExample;
  if (example == null) {
    return const CheckResult(
      false,
      'Не найден проверяемый пример.',
      evaluated: false,
    );
  }
  var count = 0;
  final tests = exercise.data['mode'] == 'program'
      ? exercise.data['tests'] as List
      : example['tests'] as List;
  for (final raw in tests) {
    final sample = Map<String, dynamic>.from(raw);
    final result = await runner.run(course.id, source, sample['input']);
    if (!result.ok) {
      return CheckResult(
        false,
        result.error.isNotEmpty ? result.error : result.output,
        evaluated: ![127, 130].contains(result.exitCode),
      );
    }
    final actual = course.id == 'sql'
        ? result.output.split('\n').skip(1).join('\n')
        : result.output;
    if (LocalRunner.normalize(actual) !=
        LocalRunner.normalize(sample['expected'])) {
      return CheckResult(
        false,
        'Для ввода:\n${(sample['input'] as String).isEmpty ? 'Ввод не требуется' : sample['input']}\n'
        'Ожидалось:\n${sample['expected']}\nПолучилось:\n$actual',
      );
    }
    count++;
  }
  return CheckResult(
    count > 0,
    'Программа действительно выполнена. Проверок: $count.',
    evaluated: count > 0,
  );
}
