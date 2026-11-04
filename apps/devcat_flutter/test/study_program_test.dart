import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/runner.dart';
import 'package:devcat/core/study.dart';
import 'package:devcat/core/study_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'All 56 authored programme changes pass real toolchains; unchanged starters fail',
    () async {
      final assets = Directory('assets/content');
      final courses =
          (jsonDecode(File('${assets.path}/courses.json').readAsStringSync())
                  as List)
              .map((j) => Course(j))
              .toList();
      final topics =
          (jsonDecode(
                File('${assets.path}/study_path.json').readAsStringSync(),
              )['topics']
              as List);
      final runner = LocalRunner();
      final toolchains = await runner.toolchains();
      var checked = 0;
      for (final raw in topics) {
        final topic = Map<String, dynamic>.from(raw);
        final variants = (topic['rounds'] as List)
            .expand((r) => r['steps'] as List)
            .where((s) => s['task'] == 'modify');
        if (variants.isEmpty) continue;
        final course = courses.firstWhere((c) => c.id == topic['course']);
        if (toolchains[course.name]!.startsWith('Не установлен')) {
          expect(
            Platform.environment['DEVCAT_REQUIRE_ALL_TOOLCHAINS'],
            isNot('true'),
            reason: 'Missing ${course.name}',
          );
          continue;
        }
        final lesson = course.lessons.firstWhere((l) => l.id == topic['id']);
        for (final item in variants) {
          final exercise = StudyExercise(Map<String, dynamic>.from(item));
          final correct = await evaluateStudyCode(
            runner,
            course,
            lesson,
            exercise,
            item['solution'],
          );
          expect(correct.evaluated, true, reason: exercise.id);
          expect(
            correct.passed,
            true,
            reason: '${exercise.id}: ${correct.report}',
          );
          final unchanged = await evaluateStudyCode(
            runner,
            course,
            lesson,
            exercise,
            item['starter'],
          );
          expect(
            unchanged.passed,
            false,
            reason:
                'Original programme must not satisfy changed condition: ${exercise.id}',
          );
          checked++;
        }
      }
      if (Platform.environment['DEVCAT_REQUIRE_ALL_TOOLCHAINS'] == 'true') {
        expect(checked, 56);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
