import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/android_runtime.dart';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/project.dart';
import 'package:devcat/core/runner.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'All bundled Android languages execute and check real programs offline',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      final installation = await AndroidRuntime.ensureInstalled();
      expect(installation['root'], isNotEmpty);
      final courses =
          (jsonDecode(
                    await rootBundle.loadString('assets/content/courses.json'),
                  )
                  as List)
              .map((data) => Course(data))
              .toList();
      final runner = LocalRunner();
      final versions = await runner.toolchains();
      for (final name in languageNames.values) {
        expect(versions[name], isNotNull, reason: name);
        expect(
          versions[name],
          isNot(contains('Не установлен')),
          reason: '$name: ${versions[name]}',
        );
        // Each language's version must come from its real local executable.
        debugPrint('ANDROID_TOOLCHAIN $name: ${versions[name]}');
      }
      for (final course in courses) {
        final seen = <String>{};
        for (final lesson in course.lessons) {
          final task = lesson.challenge;
          if (task == null || !seen.add(task.solution)) continue;
          final result = await runner.check(task, task.solution);
          expect(result.evaluated, isTrue, reason: task.id);
          expect(result.passed, isTrue, reason: '${task.id}: ${result.report}');
          debugPrint('ANDROID_REFERENCE_PASS ${task.id}');
        }
        final generated = generateChallenge(course.id, seed: 73);
        expect(
          (await runner.check(generated, generated.solution)).passed,
          isTrue,
          reason: course.id,
        );
        if (course.id != 'sql') {
          final reference = course.lessons
              .map((l) => l.challenge)
              .whereType<Challenge>()
              .first;
          final run = await runner.run(
            course.id,
            reference.solution,
            reference.tests.first.input,
          );
          expect(run.ok, isTrue, reason: '${course.id}: ${run.error}');
          expect(
            LocalRunner.normalize(run.output),
            LocalRunner.normalize(reference.tests.first.expected),
          );
        }
      }
      final failure = await runner.run(
        'python',
        'this is invalid python !',
        '',
      );
      expect(failure.ok, isFalse);
      expect(failure.error, contains('SyntaxError'));
      final infinite = await runner.run('python', 'while True: pass', '');
      expect(infinite.timedOut, isTrue);
      final cancellable = LocalRunner();
      final running = cancellable.run('python', 'while True: pass', '');
      await Future<void>.delayed(const Duration(seconds: 1));
      cancellable.cancel();
      expect((await running).exitCode, 130);
      final after = await LocalRunner().run(
        'python',
        'debugPrint("Привет, Android")',
        '',
      );
      expect(after.ok, isTrue, reason: after.error);
      expect(after.output.trim(), 'Привет, Android');
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );

  testWidgets('Android IDE compiles multi-file projects and persists generated files', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('devcat-android-ide-');
    final programs = <String, Map<String, String>>{
      'c': {
        'main.c':
            '#include <stdio.h>\nint add(int,int);int main(void){printf("%d\\n",add(2,3));return 0;}',
        'helper.c': 'int add(int a,int b){return a+b;}',
      },
      'cpp': {
        'main.cpp':
            '#include <iostream>\nint add(int,int);int main(){std::cout<<add(2,3)<<"\\n";}',
        'helper.cpp': 'int add(int a,int b){return a+b;}',
      },
      'csharp': {
        'Program.cs': 'using System; Console.WriteLine(Helper.Add(2,3));',
        'Helper.cs':
            'public static class Helper {public static int Add(int a,int b)=>a+b;}',
      },
      'java': {
        'Main.java':
            'public class Main {public static void main(String[] args){System.out.println(Helper.add(2,3));}}',
        'Helper.java':
            'class Helper {static int add(int a,int b){return a+b;}}',
      },
      'go': {
        'main.go':
            'package main\nimport "fmt"\nfunc main(){fmt.Println(add(2,3))}',
        'helper.go': 'package main\nfunc add(a,b int) int{return a+b}',
      },
      'javascript': {
        'main.js': 'console.log(require("./helper.js").add(2,3));',
        'helper.js': 'exports.add=(a,b)=>a+b;',
      },
      'python': {
        'main.py':
            'from helper import add\nfrom pathlib import Path\ndebugPrint(add(2,3))\nPath("saved.txt").write_text("saved")\n',
        'helper.py': 'def add(a,b):\n    return a+b\n',
      },
    };
    try {
      for (final item in programs.entries) {
        final project = DevProject.create(item.key, 'Android ${item.key}');
        project.files.clear();
        project.files.addAll(item.value);
        final result = await LocalRunner().runProject(project, root, '');
        expect(result.ok, isTrue, reason: '${item.key}: ${result.error}');
        expect(result.output.trim(), '5', reason: item.key);
        if (item.key == 'python') {
          expect(
            await File(
              '${root.path}/projects/${project.id}/saved.txt',
            ).readAsString(),
            'saved',
          );
        }
        debugPrint('ANDROID_IDE_PASS ${item.key}');
      }
    } finally {
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
