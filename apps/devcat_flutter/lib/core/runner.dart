import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'course.dart';

class RunResult {
  final String output, error;
  final int exitCode;
  final bool timedOut;
  const RunResult(
    this.output,
    this.error,
    this.exitCode, {
    this.timedOut = false,
  });
  bool get ok => exitCode == 0 && !timedOut;
}

class CheckResult {
  final bool passed;
  final String report;
  final bool evaluated;
  const CheckResult(this.passed, this.report, {this.evaluated = true});
}

/// Executes the owner's code with the owner's privileges. Not a security sandbox.
class LocalRunner {
  Process? _active;
  bool _cancelled = false;
  bool get desktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  void cancel() {
    _cancelled = true;
    _active?.kill(ProcessSignal.sigkill);
  }

  Future<RunResult> process(
    String executable,
    List<String> args, {
    required String cwd,
    String input = '',
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_cancelled) return const RunResult('', 'Отменено', 130);
    Process proc;
    try {
      proc = await Process.start(
        executable,
        args,
        workingDirectory: cwd,
        environment: {
          'DOTNET_CLI_TELEMETRY_OPTOUT': '1',
          'GOTOOLCHAIN': 'local',
          'GOPROXY': 'off',
          'GOSUMDB': 'off',
        },
      );
    } on ProcessException {
      return RunResult(
        '',
        'Не удалось запустить $executable. Установи toolchain и добавь его в PATH; перезапусти DevCat.',
        127,
      );
    }
    _active = proc;
    final out = <int>[], err = <int>[];
    var limited = false, expired = false;
    void collect(List<int> chunk, List<int> buffer) {
      final remaining = 65536 - out.length - err.length;
      if (remaining > 0) buffer.addAll(chunk.take(remaining));
      if (chunk.length >= remaining) {
        limited = true;
        proc.kill(ProcessSignal.sigkill);
      }
    }

    final a = proc.stdout.listen((v) => collect(v, out));
    final b = proc.stderr.listen((v) => collect(v, err));
    final drained = Future.wait([a.asFuture<void>(), b.asFuture<void>()]);
    // Some programs close stdin before accepting all input.
    unawaited(() async {
      try {
        proc.stdin.write(input);
        await proc.stdin.close();
      } catch (_) {
        /* Process already exited. */
      }
    }());
    final timer = Timer(timeout, () {
      expired = true;
      proc.kill(ProcessSignal.sigkill);
    });
    int code;
    try {
      code = await proc.exitCode;
      // Descendants can keep inherited pipes open: never wait forever on them.
      await drained.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      code = 124;
    } finally {
      timer.cancel();
      await a.cancel();
      await b.cancel();
      _active = null;
    }
    return RunResult(
      utf8.decode(out, allowMalformed: true),
      '${utf8.decode(err, allowMalformed: true)}${expired ? '\nПревышен лимит времени.' : ''}${limited ? '\nВывод превысил 64 КиБ.' : ''}${_cancelled ? '\nОтменено.' : ''}',
      expired || limited
          ? 124
          : _cancelled
          ? 130
          : code,
      timedOut: expired,
    );
  }

  Future<String?> _find(List<String> candidates) async {
    for (final exe in candidates) {
      try {
        final result = await Process.run(exe, [
          '--version',
        ]).timeout(const Duration(seconds: 4));
        if (result.exitCode == 0) return exe;
      } catch (_) {
        /* Try the next official toolchain. */
      }
    }
    return null;
  }

  Future<Map<String, String>> toolchains() async {
    final result = <String, String>{
      'SQL': 'SQLite ${sqlite3.version.libVersion} (встроен)',
    };
    if (!desktop) return result;
    for (final entry in <String, List<String>>{
      'C': ['clang', 'gcc'],
      'C++': ['clang++', 'g++'],
      'C#': ['dotnet'],
      'Python': Platform.isWindows
          ? ['python', 'python3']
          : ['python3', 'python'],
      'Java': ['java'],
      'JavaScript': ['node'],
      'Go': ['go'],
      'Git': ['git'],
    }.entries) {
      final exe = await _find(entry.value);
      if (exe == null) {
        result[entry.key] = 'Не установлен / отсутствует в PATH';
        continue;
      }
      final r = await Process.run(
        exe,
        p.basenameWithoutExtension(exe) == 'go' ? ['version'] : ['--version'],
      );
      result[entry.key] = '${r.stdout}${r.stderr}'.trim().split('\n').first;
    }
    return result;
  }

  Future<({List<String> command, RunResult? error})> _prepare(
    String lang,
    String code,
    Directory dir,
  ) async {
    final filename = fileNames[lang]!;
    await File(p.join(dir.path, filename)).writeAsString(code);
    Future<({List<String> command, RunResult? error})> compiled(
      String exe,
      List<String> args,
      List<String> command,
    ) async {
      final r = await process(
        exe,
        args,
        cwd: dir.path,
        timeout: const Duration(seconds: 45),
      );
      return (command: command, error: r.ok ? null : r);
    }

    final binary = p.join(
      dir.path,
      Platform.isWindows ? 'program.exe' : 'program',
    );
    switch (lang) {
      case 'c':
      case 'cpp':
        final exe = await _find(
          lang == 'c' ? ['clang', 'gcc'] : ['clang++', 'g++'],
        );
        if (exe == null) {
          return (
            command: <String>[],
            error: const RunResult(
              '',
              'Установи Clang или GCC и добавь в PATH.',
              127,
            ),
          );
        }
        return compiled(
          exe,
          [
            lang == 'c' ? '-std=c17' : '-std=c++20',
            '-Wall',
            '-Wextra',
            filename,
            '-o',
            binary,
          ],
          [binary],
        );
      case 'java':
        return compiled('javac', [filename], ['java', '-cp', dir.path, 'Main']);
      case 'go':
        await File(
          p.join(dir.path, 'go.mod'),
        ).writeAsString('module devcat.local/exercise\n\ngo 1.22\n');
        return compiled('go', ['build', '-o', binary, filename], [binary]);
      case 'csharp':
        await File(p.join(dir.path, 'App.csproj')).writeAsString(
          '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework><Nullable>enable</Nullable></PropertyGroup></Project>',
        );
        await File(p.join(dir.path, 'NuGet.Config')).writeAsString(
          '<configuration><packageSources><clear /></packageSources></configuration>',
        );
        return compiled(
          'dotnet',
          ['build', 'App.csproj', '-o', 'out', '--nologo'],
          ['dotnet', p.join(dir.path, 'out', 'App.dll')],
        );
      case 'python':
        final exe = await _find(
          Platform.isWindows ? ['python', 'python3'] : ['python3', 'python'],
        );
        return (command: [exe ?? 'python3', '-I', filename], error: null);
      case 'javascript':
        return (command: ['node', filename], error: null);
      default:
        throw ArgumentError('Unsupported language');
    }
  }

  Future<RunResult> run(String lang, String code, String input) async {
    _cancelled = false;
    if (lang == 'sql') return _sqlRun(code);
    if (!desktop) {
      return const RunResult(
        '',
        'На Android локально исполняется SQLite. Для других языков в 0.1 доступны уроки, генерация и редактор; toolchain не встроен.',
        126,
      );
    }
    final dir = await Directory.systemTemp.createTemp('devcat-run-');
    try {
      final prepared = await _prepare(lang, code, dir);
      if (prepared.error != null) return prepared.error!;
      return await process(
        prepared.command.first,
        prepared.command.skip(1).toList(),
        cwd: dir.path,
        input: input,
      );
    } finally {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }

  Future<CheckResult> check(Challenge task, String code) async {
    _cancelled = false;
    if (task.language == 'sql') return _checkSql(task, code);
    if (!desktop) {
      return const CheckResult(
        false,
        'Проверка этого языка на Android недоступна: компилятор не встроен. Черновик сохранён локально.',
      );
    }
    final dir = await Directory.systemTemp.createTemp('devcat-test-');
    try {
      final prepared = await _prepare(task.language, code, dir);
      if (prepared.error != null) {
        return CheckResult(
          false,
          '${prepared.error!.output}\n${prepared.error!.error}',
          evaluated: prepared.error!.exitCode != 127,
        );
      }
      final report = <String>[];
      var passed = true;
      for (var i = 0; i < task.tests.length; i++) {
        if (_cancelled) return const CheckResult(false, 'Проверка отменена.');
        final test = task.tests[i];
        final r = await process(
          prepared.command.first,
          prepared.command.skip(1).toList(),
          cwd: dir.path,
          input: test.input,
        );
        final correct = r.ok && normalize(r.output) == normalize(test.expected);
        passed &= correct;
        report.add(
          '${correct ? '✓' : '×'} Тест ${i + 1} · ввод ${test.input.trim()} · ожидалось ${test.expected} · получено ${r.output.trim()}${r.error.isEmpty ? '' : '\n${r.error}'}',
        );
        if (!r.ok) break;
      }
      return CheckResult(passed, report.join('\n'));
    } finally {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }

  static String normalize(String text) =>
      text.trim().split(RegExp(r'\s+')).join(' ');

  Future<RunResult> _sqlRun(String code) async {
    final message = await _sqlIsolate(code, false, false);
    return RunResult(message.$1, message.$2, message.$2.isEmpty ? 0 : 1);
  }

  Future<CheckResult> _checkSql(Challenge task, String code) async {
    final report = <String>[];
    for (final alternate in [false, true]) {
      final actual = await _sqlIsolate(code, true, alternate);
      final expected = await _sqlIsolate(task.solution, true, alternate);
      if (actual.$2.isNotEmpty) return CheckResult(false, actual.$2);
      final ok = actual.$1 == expected.$1;
      report.add(
        '${ok ? '✓' : '×'} ${alternate ? 'Независимые данные' : 'Основные данные'}\nОжидалось: ${expected.$1}\nПолучено: ${actual.$1}',
      );
      if (!ok) return CheckResult(false, report.join('\n\n'));
    }
    return CheckResult(true, report.join('\n\n'));
  }

  /// A separate isolate is killed on timeout, including recursive SQL queries.
  Future<(String, String)> _sqlIsolate(
    String code,
    bool rowsOnly,
    bool alternate,
  ) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(_sqlWorker, [
      port.sendPort,
      code,
      rowsOnly,
      alternate,
    ]);
    try {
      final result =
          await port.first.timeout(const Duration(seconds: 3)) as List;
      return (result[0] as String, result[1] as String);
    } on TimeoutException {
      return ('', 'SQLite: превышен лимит 3 секунды.');
    } finally {
      isolate.kill(priority: Isolate.immediate);
      port.close();
    }
  }
}

typedef _SqlProgress = Int32 Function(Pointer<Void>);
typedef _ProgressInstallNative =
    Void Function(
      Pointer<Void>,
      Int32,
      Pointer<NativeFunction<_SqlProgress>>,
      Pointer<Void>,
    );
typedef _ProgressInstallDart =
    void Function(
      Pointer<Void>,
      int,
      Pointer<NativeFunction<_SqlProgress>>,
      Pointer<Void>,
    );
typedef _SqlLimitNative = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _SqlLimitDart = int Function(Pointer<Void>, int, int);

void _sqlWorker(List args) {
  final port = args[0] as SendPort;
  final db = sqlite3.openInMemory();
  NativeCallable<_SqlProgress>? progress;
  try {
    db.execute(sqlFixture);
    if (args[3] as bool) {
      db.execute(
        "DELETE FROM orders; INSERT INTO orders VALUES(10,1,0),(11,3,25),(12,3,100),(13,3,35); INSERT INTO customers VALUES(4,'Глеб');",
      );
    }
    // Read-only educational DB: no ATTACH, filesystem extensions or mutations.
    db.execute('PRAGMA query_only = ON');
    final library = sqlite_open.open.openSqlite();
    final limit = library.lookupFunction<_SqlLimitNative, _SqlLimitDart>(
      'sqlite3_limit',
    );
    limit(db.handle.cast<Void>(), 0, 65536); // Maximum string/blob/row size.
    limit(db.handle.cast<Void>(), 1, 200000); // SQL text length.
    limit(db.handle.cast<Void>(), 2, 128); // Columns.
    limit(db.handle.cast<Void>(), 3, 128); // Expression depth.
    limit(db.handle.cast<Void>(), 4, 50); // Compound SELECT terms.
    limit(db.handle.cast<Void>(), 7, 0); // Attached databases.
    var operations = 0;
    final deadline = Stopwatch()..start();
    progress = NativeCallable<_SqlProgress>.isolateLocal((Pointer<Void> _) {
      operations += 1000;
      return operations > 1000000 || deadline.elapsedMilliseconds > 2000
          ? 1
          : 0;
    }, exceptionalReturn: 1);
    library.lookupFunction<_ProgressInstallNative, _ProgressInstallDart>(
      'sqlite3_progress_handler',
    )(db.handle.cast<Void>(), 1000, progress.nativeFunction, nullptr);

    final code = args[1] as String;
    if (!RegExp(r'^\s*(SELECT|WITH)\b', caseSensitive: false).hasMatch(code) ||
        RegExp(
          r'\b(ATTACH|DETACH|PRAGMA|load_extension|readfile|writefile)\b',
          caseSensitive: false,
        ).hasMatch(code)) {
      throw const FormatException(
        'В учебной базе разрешён один SELECT/WITH без файловых расширений.',
      );
    }
    final statement = db.prepare(code, checkNoTail: true);
    try {
      final rows = statement.selectCursor();
      final data = <List<Object?>>[];
      var size = 0;
      while (rows.moveNext()) {
        final row = rows.current.values.toList();
        size += row.join(' | ').length;
        if (data.length >= 5000 || size > 65536) {
          throw const FormatException(
            'Результат превышает 5000 строк или 64 КиБ.',
          );
        }
        data.add(row);
      }
      final output = args[2] as bool
          ? jsonEncode(data)
          : '${rows.columnNames.join(' | ')}\n${data.map((r) => r.join(' | ')).join('\n')}';
      if (output.length > 65536) {
        throw const FormatException('Результат превышает 64 КиБ.');
      }
      port.send([output, '']);
    } finally {
      statement.dispose();
    }
  } catch (e) {
    port.send(['', 'SQLite: $e']);
  } finally {
    db.dispose();
    progress?.close();
  }
}

String explainDiagnostic(String diagnostic) {
  if (diagnostic.contains('IndentationError')) {
    return 'Python обнаружил неверный отступ. Проверь блок цикла и одинаковое число пробелов.';
  }
  if (diagnostic.contains('SyntaxError') || diagnostic.contains('expected')) {
    return 'Возможна синтаксическая ошибка. Начни с первой строки диагностики: следующая ошибка часто является её следствием.';
  }
  if (diagnostic.contains('TypeError')) {
    return 'Операция получила несовместимые типы. Проверь преобразование ввода в число.';
  }
  if (diagnostic.contains('no such column')) {
    return 'SQLite не нашёл столбец. Сверь имена и псевдонимы с условием.';
  }
  if (diagnostic.contains('PATH') || diagnostic.contains('toolchain')) {
    return 'Проверка не состоялась: среда исполнения не найдена. Это не оценка твоего решения.';
  }
  return 'Посмотри на фактический вывод и первую диагностику. Если код выполняется, сравни границы цикла и формат вывода с контрактом задания.';
}
