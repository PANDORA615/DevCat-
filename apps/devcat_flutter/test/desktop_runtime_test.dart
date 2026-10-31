import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/desktop_runtime.dart';
import 'package:devcat/core/runner.dart';
import 'package:devcat/core/study.dart';
import 'package:devcat/core/study_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final enabled = Platform.environment['DEVCAT_REQUIRE_BUNDLED'] == 'true';
  test(
    'Packaged desktop tools are absolute, relocatable and execute without system SDKs',
    () async {
      final root = DesktopRuntime.root!;
      for (final name in [
        'clang',
        'clang++',
        'dotnet',
        'python3',
        'java',
        'javac',
        'node',
        'go',
      ]) {
        final resolved = DesktopRuntime.command(
          name,
          [],
          cwd: Directory.systemTemp.path,
        );
        expect(p.isWithin(root, resolved.executable), isTrue, reason: name);
        expect(File(resolved.executable).existsSync(), isTrue, reason: name);
      }
      final courses =
          (jsonDecode(File('assets/content/courses.json').readAsStringSync())
                  as List)
              .map((j) => Course(j))
              .toList();
      final catalog = StudyCatalog.decode(
        File('assets/content/study_path.json').readAsStringSync(),
      );
      for (final language in executableLanguages) {
        final course = courses.firstWhere((c) => c.id == language);
        final lesson = course.lessons.first;
        final exercise = catalog.topics[lesson.id]!.rounds.last.steps
            .firstWhere((s) => s.kind == 'code');
        final result = await evaluateStudyCode(
          LocalRunner(),
          course,
          lesson,
          exercise,
          exercise.answer,
        );
        expect(result.passed, isTrue, reason: '$language: ${result.report}');
        // A visible marker makes a missing SDK distinguishable from compilation
        // of the standard library on a fresh machine.
        // ignore: avoid_print
        print('BUNDLED_DESKTOP_PASS $language');
        final invalid = await evaluateStudyCode(
          LocalRunner(),
          course,
          lesson,
          exercise,
          'invalid_token',
        );
        expect(invalid.passed, isFalse, reason: language);
      }
      // Regression for the screenshot: a valid C++ answer must run, rather than
      // asking a child to install a compiler or configure PATH.
      final cpp = await LocalRunner().run(
        'cpp',
        '#include <iostream>\nint main(){std::cout << "Study" << "\\n";return 0;}',
        '',
      );
      expect(cpp.ok, isTrue, reason: cpp.error);
      expect(cpp.output.trim(), 'Study');
      final unicode = await LocalRunner().run(
        'csharp',
        'using System; class Program { static void Main() { Console.WriteLine(Console.ReadLine()); } }',
        'Привет, кот!\n',
      );
      expect(unicode.ok, isTrue, reason: unicode.error);
      expect(unicode.output.trim(), 'Привет, кот!');
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
