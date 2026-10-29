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
      expect(courses.length, 10);
      final ids = <String>{};
      for (final course in courses) {
        expect(
          course.lessons.length,
          course.id == 'html' || course.id == 'css' ? 24 : 56,
          reason: course.id,
        );
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
    'Every complete workshop program executes its documented examples',
    () async {
      for (final course in courses) {
        for (final lesson in course.lessons) {
          final example = lesson.runnableExample;
          if (example == null) continue;
          for (final raw in example['tests'] as List) {
            final sample = Map<String, dynamic>.from(raw);
            final result = await LocalRunner().run(
              course.id,
              example['code'] as String,
              sample['input'] as String,
            );
            expect(result.ok, isTrue, reason: '${lesson.id}: ${result.error}');
            final output = course.id == 'sql'
                ? result.output.split('\n').skip(1).join('\n')
                : result.output;
            expect(
              LocalRunner.normalize(output),
              LocalRunner.normalize(sample['expected'] as String),
              reason: lesson.id,
            );
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
  test(
    'Every unique authored reference passes real independent input checks',
    () async {
      final runner = LocalRunner(), seen = <String>{};
      final tools = await runner.toolchains();
      final required =
          Platform.environment['DEVCAT_REQUIRE_ALL_TOOLCHAINS'] == 'true';
      for (final course in courses) {
        if (!executableLanguages.contains(course.id)) continue;
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
  test(
    'Debugging starts with a reproducible defect rather than an empty task',
    () async {
      final task = courses
          .firstWhere((c) => c.id == 'python')
          .lessons
          .firstWhere((l) => l.id == 'python.debugging')
          .challenge!;
      final runner = LocalRunner();
      expect((await runner.check(task, task.starter)).passed, isFalse);
      expect((await runner.check(task, task.solution)).passed, isTrue);
    },
  );
}
