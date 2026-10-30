import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/android_runtime.dart';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/project.dart';
import 'package:devcat/core/runner.dart';
import 'package:devcat/core/web_preview.dart';
import 'package:devcat/core/study.dart';
import 'package:devcat/core/study_runner.dart';
import 'package:devcat/core/progress.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android serves HTML and CSS locally without a compiler or network',
    (tester) async {
      final project = DevProject.create('css', 'Offline web');
      final preview = WebPreview();
      final client = HttpClient();
      try {
        final uri = await preview.open(project);
        final response = await (await client.getUrl(uri)).close();
        expect(response.statusCode, 200);
        expect(
          await utf8.decoder.bind(response).join(),
          contains('Моя первая страница'),
        );
        final css = await (await client.getUrl(
          uri.resolve('style.css'),
        )).close();
        expect(css.statusCode, 200);
        expect(css.headers.contentType!.mimeType, 'text/css');
        await css.drain<void>();
        debugPrint('ANDROID_WEB_PREVIEW_PASS');
      } finally {
        client.close(force: true);
        await preview.close();
      }
    },
  );
  testWidgets(
    'All bundled Android toolchains are available without downloads',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      final installation = await AndroidRuntime.ensureInstalled();
      expect(installation['root'], isNotEmpty);
      final runner = LocalRunner();
      final versions = await runner.toolchains();
      for (final name in executableLanguages.map((id) => languageNames[id]!)) {
        expect(versions[name], isNotNull, reason: name);
        expect(
          versions[name],
          isNot(contains('Не установлен')),
          reason: '$name: ${versions[name]}',
        );
        // Each language's version must come from its real local executable.
        debugPrint('ANDROID_TOOLCHAIN $name: ${versions[name]}');
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  for (final language in executableLanguages) {
    testWidgets('Android offline references and generated task: $language', (
      tester,
    ) async {
      final courses =
          (jsonDecode(
                    await rootBundle.loadString('assets/content/courses.json'),
                  )
                  as List)
              .map((data) => Course(data))
              .toList();
      final course = courses.firstWhere((course) => course.id == language);
      final runner = LocalRunner();
      final seen = <String>{};
      for (final lesson in course.lessons) {
        final task = lesson.challenge;
        if (task == null || !seen.add(task.solution)) continue;
        final result = await runner.check(task, task.solution);
        expect(result.evaluated, isTrue, reason: task.id);
        expect(result.passed, isTrue, reason: '${task.id}: ${result.report}');
        debugPrint('ANDROID_REFERENCE_PASS ${task.id}');
      }
      for (final lesson in course.lessons) {
        final example = lesson.runnableExample;
        if (example == null) continue;
        for (final raw in example['tests'] as List) {
          final sample = Map<String, dynamic>.from(raw);
          final result = await runner.run(
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
        debugPrint('ANDROID_WORKSHOP_PASS ${lesson.id}');
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
    }, timeout: const Timeout(Duration(minutes: 12)));
  }

  testWidgets(
    'Android handles diagnostics, timeouts, cancellation, Unicode and Java 21',
    (tester) async {
      final runner = LocalRunner();
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
        'print("Привет, Android")',
        '',
      );
      expect(after.ok, isTrue, reason: after.error);
      expect(after.output.trim(), 'Привет, Android');
      final virtualThread = await LocalRunner().run(
        'java',
        'public class Main { public static void main(String[] args) throws Exception { Thread worker = Thread.ofVirtual().start(() -> System.out.println("virtual")); worker.join(); } }',
        '',
      );
      expect(virtualThread.ok, isTrue, reason: virtualThread.error);
      expect(virtualThread.output.trim(), 'virtual');
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );

  testWidgets('Android SQLite interrupts native queries and remains usable', (
    tester,
  ) async {
    const forever =
        'WITH RECURSIVE x(a) AS (VALUES(1) UNION ALL SELECT a+1 FROM x) SELECT sum(a) FROM x;';
    final limited = await LocalRunner().run('sql', forever, '');
    expect(limited.timedOut, isTrue, reason: limited.error);
    final runner = LocalRunner();
    final pending = runner.run('sql', forever, '');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    runner.cancel();
    expect((await pending).exitCode, 130);
    final next = await runner.run('sql', 'SELECT 7 AS answer;', '');
    expect(next.ok, isTrue, reason: next.error);
    expect(next.output, contains('7'));
  });

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
            'from helper import add\nfrom pathlib import Path\nprint(add(2,3))\nPath("saved.txt").write_text("saved")\n',
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
      final database = DevProject.create('sql', 'Transaction lecture');
      database.files[database.entry] = '''
CREATE TABLE parent(id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE child(parent_id INTEGER REFERENCES parent(id));
BEGIN;
INSERT INTO parent VALUES(1, 'Кот; книга');
INSERT INTO child VALUES(1);
COMMIT;
SELECT name FROM parent;
''';
      final script = await LocalRunner().runProject(database, root, '');
      expect(script.ok, isTrue, reason: script.error);
      expect(script.output, contains('Кот; книга'));
      database.files[database.entry] = '''
BEGIN;
INSERT INTO parent VALUES(2, 'rollback');
INSERT INTO child VALUES(99);
COMMIT;
''';
      expect((await LocalRunner().runProject(database, root, '')).ok, isFalse);
      database.files[database.entry] = 'SELECT COUNT(*) AS count FROM parent;';
      final after = await LocalRunner().runProject(database, root, '');
      expect(after.ok, isTrue, reason: after.error);
      expect(after.output.trim().split('\n').last, '1');
      debugPrint('ANDROID_SQL_TRANSACTION_PASS');
    } finally {
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets(
    'Android short lessons bundle the complete path and check actual code offline',
    (tester) async {
      final catalog = StudyCatalog.decode(
        await rootBundle.loadString('assets/content/study_path.json'),
      );
      expect(catalog.topics.length, 516);
      expect(
        catalog.topics.values.fold<int>(
          0,
          (count, topic) => count + topic.rounds.length,
        ),
        1548,
      );
      expect(catalog.topics.values.map((t) => t.course).toSet(), {
        ...languageNames.keys,
        'git',
      });
      final courses =
          (jsonDecode(
                    await rootBundle.loadString('assets/content/courses.json'),
                  )
                  as List)
              .map((j) => Course(j))
              .toList();
      final runner = LocalRunner();
      for (final language in ['python', 'sql']) {
        final course = courses.firstWhere((c) => c.id == language);
        final lesson = course.lessons.first;
        final exercise = catalog.topics[lesson.id]!.rounds.last.steps
            .firstWhere((s) => s.kind == 'code');
        final result = await evaluateStudyCode(
          runner,
          course,
          lesson,
          exercise,
          exercise.answer,
        );
        expect(result.passed, isTrue, reason: '$language: ${result.report}');
        final invalid = await evaluateStudyCode(
          runner,
          course,
          lesson,
          exercise,
          'definitely_invalid_token',
        );
        expect(invalid.passed, isFalse);
      }
      final unit = catalog.topics['python.zero.start']!.rounds.first;
      final date = DateTime.now();
      final key = StudyLedger.eventKey(unit, date);
      final pc = ProgressData()
        ..draft(key, StudyLedger.event(unit, {}, date), 'pc');
      final phone = ProgressData()
        ..draft(key, StudyLedger.event(unit, {}, date), 'phone');
      final restored = ProgressData.decode(pc.merge(phone).encode());
      expect(StudyLedger(restored).xp, 20);
      expect(restored.solved, isEmpty);
      debugPrint(
        'ANDROID_STUDY_FORMAT_PASS 1548 sessions; actual Python/SQL; deduplicated progress',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
