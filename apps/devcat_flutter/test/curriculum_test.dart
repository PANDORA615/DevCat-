import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final data =
      jsonDecode(File('assets/content/courses.json').readAsStringSync())
          as List;
  final courses = data.map((j) => Course(j)).toList();
  test(
    'Offline curriculum has full lectures, relevant labs and real images',
    () {
      expect(courses.length, 8);
      final ids = <String>{};
      for (final course in courses) {
        expect(course.lessons.length, 40, reason: course.id);
        for (final lesson in course.lessons) {
          expect(ids.add(lesson.id), isTrue);
          expect(
            lesson.theory.split(RegExp(r'\s+')).length,
            greaterThanOrEqualTo(250),
            reason: lesson.id,
          );
          expect(lesson.sections.length, greaterThanOrEqualTo(5));
          expect(lesson.questions.length, 3);
          expect(
            File('assets/content/${lesson.photo}').existsSync(),
            isTrue,
            reason: lesson.photo,
          );
          if (lesson.kind == 'review') expect(lesson.challenge, isNull);
          if (lesson.challenge != null) {
            expect(lesson.challenge!.language, course.id);
          }
        }
      }
    },
  );
  test(
    'Every unique authored reference passes real independent input checks',
    () async {
      final runner = LocalRunner(), seen = <String>{};
      final tools = await runner.toolchains();
      final required =
          Platform.environment['DEVCAT_REQUIRE_ALL_TOOLCHAINS'] == 'true';
      for (final course in courses) {
        if (course.id != 'sql' &&
            tools[course.name]!.contains('Не установлен')) {
          if (required) fail('Missing ${course.name}');
          continue;
        }
        for (final lesson in course.lessons) {
          final task = lesson.challenge;
          if (task == null || !seen.add('${task.language}:${task.solution}')) {
            continue;
          }
          final result = await runner.check(task, task.solution);
          expect(result.passed, isTrue, reason: '${task.id}: ${result.report}');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
  test(
    'Generated variants keep the executable contract across parameters',
    () async {
      final runner = LocalRunner();
      for (final language in ['python', 'sql']) {
        final prompts = <String>{};
        for (var seed = 1; seed <= 40; seed++) {
          final task = generateChallenge(language, seed: seed);
          prompts.add(task.prompt);
          final result = await runner.check(task, task.solution);
          expect(
            result.passed,
            isTrue,
            reason: '$language/$seed: ${result.report}',
          );
        }
        expect(prompts.length, greaterThan(10));
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
