import 'dart:io';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/git_lab.dart';
import 'package:devcat/core/runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Generator is deterministic, parameterized, excludes Git', () {
    for (final lang in languageNames.keys) {
      final a = generateChallenge(lang, seed: 426);
      final b = generateChallenge(lang, seed: 426);
      expect(a.prompt, b.prompt);
      expect(a.solution, b.solution);
      expect(a.hints.length, 3);
      expect(
        {
          for (var seed = 0; seed < 24; seed++)
            generateChallenge(lang, seed: seed).prompt,
        }.length,
        greaterThan(1),
      );
    }
    expect(() => generateChallenge('git'), throwsArgumentError);
  });
  test(
    'SQLite JOIN checks independent data and rejects hardcoded answer',
    () async {
      final task = generateChallenge('sql');
      final runner = LocalRunner();
      expect((await runner.check(task, task.solution)).passed, true);
      expect(
        (await runner.check(
          task,
          "SELECT 'Аня', 2 UNION ALL SELECT 'Борис', 1 UNION ALL SELECT 'Вера', 0",
        )).passed,
        false,
      );
      expect(
        (await runner.run('sql', "ATTACH '/tmp/escape.db' AS x", '')).ok,
        false,
      );
      expect(
        (await runner.run('sql', 'SELECT 1; DELETE FROM orders;', '')).ok,
        false,
      );
    },
  );
  test('SQLite recursive query is terminated by isolate deadline', () async {
    final watch = Stopwatch()..start();
    final result = await LocalRunner().run(
      'sql',
      'WITH RECURSIVE x(a) AS (VALUES(1) UNION ALL SELECT a+1 FROM x) SELECT sum(a) FROM x;',
      '',
    );
    expect(result.ok, false);
    expect(result.timedOut, isTrue);
    expect(result.error, contains('превышен лимит 2 секунды'));
    expect(watch.elapsed.inSeconds, lessThan(8));
    final next = await LocalRunner().run('sql', 'SELECT 42 AS answer;', '');
    expect(next.ok, isTrue);
    expect(next.output, contains('42'));
  });
  test(
    'SQL cancellation interrupts native work and a new run still succeeds',
    () async {
      final runner = LocalRunner();
      final pending = runner.run(
        'sql',
        'WITH RECURSIVE x(a) AS (VALUES(1) UNION ALL SELECT a+1 FROM x) SELECT sum(a) FROM x;',
        '',
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      runner.cancel();
      final cancelled = await pending;
      expect(cancelled.exitCode, 130);
      final next = await runner.run('sql', 'SELECT 7 AS answer;', '');
      expect(next.ok, isTrue);
      expect(next.output, contains('7'));
    },
  );
  test(
    'Real toolchains grade reference solutions and reject wrong output',
    () async {
      final runner = LocalRunner();
      final chains = await runner.toolchains();
      for (final entry in languageNames.entries.where((e) => e.key != 'sql')) {
        if (chains[entry.value]!.startsWith('Не установлен')) {
          expect(
            Platform.environment['DEVCAT_REQUIRE_ALL_TOOLCHAINS'],
            isNot('true'),
            reason: 'Required toolchain missing: ${entry.value}',
          );
          continue;
        }
        for (final kind in ['arithmetic', 'loop']) {
          final task = generateChallenge(entry.key, seed: 37, kind: kind);
          final result = await runner.check(task, task.solution);
          expect(
            result.passed,
            true,
            reason: '${entry.key}/$kind: ${result.report}',
          );
        }
      }
      if (!chains['C++']!.startsWith('Не установлен')) {
        final cpp = generateChallenge('cpp', lessonId: 'cpp.basics');
        expect((await runner.check(cpp, cpp.solution)).passed, true);
      }
      if (!chains['Python']!.startsWith('Не установлен')) {
        expect(
          (await runner.check(generateChallenge('python'), 'print(55)')).passed,
          false,
        );
        final loop = await runner.run('python', 'while True: pass', '');
        expect(loop.timedOut, true);
        final flood = await runner.run('python', 'print("x" * 100000)', '');
        expect(flood.ok, false);
        expect(flood.output.length, lessThanOrEqualTo(65536));
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test('Git exercise checks committed README, not command text', () async {
    final dir = await Directory.systemTemp.createTemp('devcat-git-test');
    addTearDown(() => dir.delete(recursive: true));
    final lab = GitLab(dir);
    await lab.initialize();
    expect((await lab.execute('git init')).ok, true);
    expect(await lab.verify(), false);
    expect((await lab.execute('git add README.md')).ok, true);
    expect((await lab.execute('git commit -m "Initial commit"')).ok, true);
    expect(await lab.verify(), true);
    expect((await lab.execute('git add ../secret')).ok, false);
    expect((await lab.execute('git init /tmp/outside')).ok, false);
    expect((await lab.execute('git push origin main')).ok, false);
  });
}
