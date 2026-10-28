import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'course.dart';
import 'project.dart';
import 'android_runtime.dart';

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
  void Function()? _interruptSql;
  bool _cancelled = false;
  bool get desktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  bool get supported => desktop || Platform.isAndroid;
  void cancel() {
    _cancelled = true;
    _active?.kill(ProcessSignal.sigkill);
    _interruptSql?.call();
  }

  Future<RunResult?> _ready() async {
    if (!Platform.isAndroid) return null;
    try {
      await AndroidRuntime.ensureInstalled();
      return _cancelled ? const RunResult('', 'Отменено', 130) : null;
    } catch (e) {
      return RunResult(
        '',
        'Не удалось подготовить встроенные компиляторы: $e',
        127,
      );
    }
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
      proc = Platform.isAndroid
          ? await AndroidRuntime.start(executable, args, cwd: cwd)
          : await Process.start(
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
    } catch (e) {
      return RunResult(
        '',
        Platform.isAndroid
            ? 'Не удалось подготовить локальную среду Android: $e'
            : 'Не удалось запустить $executable. Установи toolchain и добавь его в PATH; перезапусти DevCat.',
        127,
      );
    }
    _active = proc;
    if (_cancelled) proc.kill(ProcessSignal.sigkill);
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
        if (Platform.isAndroid) {
          final dir = await Directory.systemTemp.createTemp('devcat-probe-');
          try {
            final result = await process(
              exe,
              p.basenameWithoutExtension(exe) == 'go'
                  ? ['version']
                  : ['--version'],
              cwd: dir.path,
              timeout: const Duration(seconds: 15),
            );
            if (result.ok) return exe;
          } finally {
            await dir.delete(recursive: true);
          }
          continue;
        }
        final result = await Process.run(
          exe,
          p.basenameWithoutExtension(exe) == 'go' ? ['version'] : ['--version'],
        ).timeout(const Duration(seconds: 15));
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
    if (!supported) return result;
    final unavailable = await _ready();
    if (unavailable != null) {
      result['Среды Android'] = unavailable.error;
      return result;
    }
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
      if (Platform.isAndroid && entry.key == 'Git') continue;
      final exe = await _find(entry.value);
      if (exe == null) {
        result[entry.key] = 'Не установлен / отсутствует в PATH';
        continue;
      }
      if (Platform.isAndroid) {
        final dir = await Directory.systemTemp.createTemp('devcat-version-');
        try {
          final r = await process(
            exe,
            exe == 'go' ? ['version'] : ['--version'],
            cwd: dir.path,
            timeout: const Duration(seconds: 15),
          );
          result[entry.key] = '${r.output}${r.error}'.trim().split('\n').first;
        } finally {
          await dir.delete(recursive: true);
        }
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
    Directory dir, {
    Map<String, String>? files,
    String? entry,
  }) async {
    final filename = entry ?? fileNames[lang]!;
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
        timeout: Duration(seconds: Platform.isAndroid ? 120 : 45),
      );
      return (command: command, error: r.ok ? null : r);
    }

    final buildDirectory = files == null
        ? dir
        : Directory(p.join(dir.path, '.devcat-build'));
    await buildDirectory.create(recursive: true);
    final binary = p.join(
      buildDirectory.path,
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
            ...?files?.keys.where(
              (name) => name.endsWith(lang == 'c' ? '.c' : '.cpp'),
            ),
            if (files == null) filename,
            '-o',
            binary,
          ],
          [binary],
        );
      case 'java':
        final classes = files == null
            ? dir.path
            : p.join(buildDirectory.path, 'classes');
        if (files != null) {
          final target = Directory(classes);
          if (await target.exists()) await target.delete(recursive: true);
          await target.create(recursive: true);
        }
        return compiled(
          'javac',
          [
            if (Platform.isAndroid) ...[
              '-J-Xmx256m',
              '-J-XX:ActiveProcessorCount=2',
              '-J-XX:-UsePerfData',
            ],
            if (files != null) ...['-d', classes],
            if (files == null)
              filename
            else
              ...files.keys.where((name) => name.endsWith('.java')),
          ],
          [
            'java',
            if (Platform.isAndroid) ...[
              '-Xms16m',
              '-Xmx256m',
              '-XX:ActiveProcessorCount=2',
              '-XX:-UsePerfData',
            ],
            '-cp',
            classes,
            'Main',
          ],
        );
      case 'go':
        if (files == null || !files.containsKey('go.mod')) {
          await File(
            p.join(dir.path, 'go.mod'),
          ).writeAsString('module devcat.local/exercise\n\ngo 1.22\n');
        }
        return compiled(
          'go',
          [
            'build',
            '-o',
            binary,
            if (files == null)
              filename
            else
              ...files.keys.where(
                (name) => name.endsWith('.go') && !name.endsWith('_test.go'),
              ),
          ],
          [binary],
        );
      case 'csharp':
        if (Platform.isAndroid) {
          // Compile with the bundled Roslyn and reference assemblies directly.
          // MSBuild/NuGet and their IPC/build servers are unnecessary for these
          // self-contained source projects and can stall under Android tracing.
          final installed = await AndroidRuntime.ensureInstalled();
          final dotnet = p.join(installed['root']!, 'opt/dotnet');
          Future<Directory> versionDirectory(String name) async {
            final versions = await Directory(p.join(dotnet, name))
                .list()
                .where(
                  (entry) =>
                      entry is Directory &&
                      p.basename(entry.path).startsWith('8.0.'),
                )
                .cast<Directory>()
                .toList();
            versions.sort((a, b) => a.path.compareTo(b.path));
            return versions.last;
          }

          final sdk = await versionDirectory('sdk');
          final references = await versionDirectory(
            'packs/Microsoft.NETCore.App.Ref',
          );
          String guest(String path) =>
              '/opt/dotnet/${p.relative(path, from: dotnet)}';
          final assemblies =
              await Directory(p.join(references.path, 'ref/net8.0'))
                  .list()
                  .where(
                    (entry) => entry is File && entry.path.endsWith('.dll'),
                  )
                  .toList();
          assemblies.sort((a, b) => a.path.compareTo(b.path));
          final output = Directory(p.join(buildDirectory.path, 'out'));
          await output.create(recursive: true);
          final dll = p.join(output.path, 'App.dll');
          await File(
            p.join(output.path, 'App.runtimeconfig.json'),
          ).writeAsString(
            jsonEncode({
              'runtimeOptions': {
                'tfm': 'net8.0',
                'framework': {
                  'name': 'Microsoft.NETCore.App',
                  'version': '8.0.0',
                },
              },
            }),
          );
          return compiled(
            'dotnet',
            [
              guest(p.join(sdk.path, 'Roslyn/bincore/csc.dll')),
              '-nologo',
              '-noconfig',
              '-nostdlib+',
              '-target:exe',
              '-langversion:12',
              '-nullable:enable',
              '-parallel-',
              '-out:${AndroidRuntime.guestPath(dll, dir.path)}',
              ...assemblies.map((assembly) => '-r:${guest(assembly.path)}'),
              if (files == null)
                filename
              else
                ...files.keys.where((name) => name.endsWith('.cs')),
            ],
            ['dotnet', dll],
          );
        }
        final csproj = p.join(buildDirectory.path, 'App.csproj');
        final include = files == null
            ? ''
            : '<EnableDefaultCompileItems>false</EnableDefaultCompileItems>';
        final sources = files == null
            ? ''
            : '<ItemGroup>${files.keys.where((name) => name.endsWith('.cs')).map((name) => '<Compile Include="../${const HtmlEscape(HtmlEscapeMode.attribute).convert(name)}" />').join()}</ItemGroup>';
        await File(csproj).writeAsString(
          '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework><Nullable>enable</Nullable>$include</PropertyGroup>$sources</Project>',
        );
        await File(p.join(buildDirectory.path, 'NuGet.Config')).writeAsString(
          '<configuration><packageSources><clear /></packageSources></configuration>',
        );
        final output = p.join(buildDirectory.path, 'out');
        return compiled(
          'dotnet',
          ['build', csproj, '-o', output, '--nologo'],
          ['dotnet', p.join(output, 'App.dll')],
        );
      case 'python':
        final exe = await _find(
          Platform.isWindows ? ['python', 'python3'] : ['python3', 'python'],
        );
        return (
          command: files == null
              ? [exe ?? 'python3', '-I', filename]
              : [
                  exe ?? 'python3',
                  '-I',
                  '-c',
                  'import runpy,sys; sys.path.insert(0, sys.argv[1]); runpy.run_path(sys.argv[2], run_name="__main__")',
                  dir.path,
                  filename,
                ],
          error: null,
        );
      case 'javascript':
        return (command: ['node', filename], error: null);
      default:
        throw ArgumentError('Unsupported language');
    }
  }

  Future<RunResult> run(String lang, String code, String input) async {
    _cancelled = false;
    if (lang == 'sql') return _sqlRun(code);
    if (!supported) {
      return const RunResult(
        '',
        'Локальное исполнение не поддерживается на этой платформе.',
        126,
      );
    }
    final unavailable = await _ready();
    if (unavailable != null) return unavailable;
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

  Future<RunResult> runProject(
    DevProject project,
    Directory root,
    String input,
  ) async {
    _cancelled = false;
    final directory = await project.materialize(root);
    if (project.language == 'sql') {
      final result = await _sqlJob(_projectSqlWorker, [
        p.join(directory.path, 'project.sqlite'),
        project.files[project.entry]!,
      ]);
      return RunResult(
        result.$1,
        result.$2,
        _cancelled
            ? 130
            : result.$2.isEmpty
            ? 0
            : 1,
      );
    }
    if (!supported) {
      return const RunResult(
        '',
        'Локальное исполнение не поддерживается на этой платформе.',
        126,
      );
    }
    final unavailable = await _ready();
    if (unavailable != null) return unavailable;
    final prepared = await _prepare(
      project.language,
      project.files[project.entry]!,
      directory,
      files: project.files,
      entry: project.entry,
    );
    if (prepared.error != null) return prepared.error!;
    return process(
      prepared.command.first,
      prepared.command.skip(1).toList(),
      cwd: directory.path,
      input: input,
    );
  }

  Future<CheckResult> check(Challenge task, String code) async {
    _cancelled = false;
    if (task.language == 'sql') return _checkSql(task, code);
    if (!supported) {
      return const CheckResult(
        false,
        'Проверка кода не поддерживается на этой платформе.',
        evaluated: false,
      );
    }
    final unavailable = await _ready();
    if (unavailable != null) {
      return CheckResult(false, unavailable.error, evaluated: false);
    }
    final dir = await Directory.systemTemp.createTemp('devcat-test-');
    try {
      final prepared = await _prepare(task.language, code, dir);
      if (prepared.error != null) {
        return CheckResult(
          false,
          '${prepared.error!.output}\n${prepared.error!.error}',
          evaluated: ![127, 130].contains(prepared.error!.exitCode),
        );
      }
      final report = <String>[];
      var passed = true;
      for (var i = 0; i < task.tests.length; i++) {
        if (_cancelled) {
          return const CheckResult(
            false,
            'Проверка отменена.',
            evaluated: false,
          );
        }
        final test = task.tests[i];
        final r = await process(
          prepared.command.first,
          prepared.command.skip(1).toList(),
          cwd: dir.path,
          input: test.input,
        );
        if (_cancelled) {
          return const CheckResult(
            false,
            'Проверка отменена.',
            evaluated: false,
          );
        }
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
    final timedOut = message.$2.contains('превышен лимит');
    return RunResult(
      message.$1,
      message.$2,
      _cancelled
          ? 130
          : timedOut
          ? 124
          : message.$2.isEmpty
          ? 0
          : 1,
      timedOut: timedOut,
    );
  }

  Future<CheckResult> _checkSql(Challenge task, String code) async {
    final report = <String>[];
    for (final alternate in [false, true]) {
      final actual = await _sqlIsolate(code, true, alternate);
      if (_cancelled) {
        return const CheckResult(false, 'Проверка отменена.', evaluated: false);
      }
      final expected = await _sqlIsolate(task.solution, true, alternate);
      if (_cancelled) {
        return const CheckResult(false, 'Проверка отменена.', evaluated: false);
      }
      if (actual.$2.isNotEmpty) return CheckResult(false, actual.$2);
      final ok = actual.$1 == expected.$1;
      report.add(
        '${ok ? '✓' : '×'} ${alternate ? 'Независимые данные' : 'Основные данные'}\nОжидалось: ${expected.$1}\nПолучено: ${actual.$1}',
      );
      if (!ok) return CheckResult(false, report.join('\n\n'));
    }
    return CheckResult(true, report.join('\n\n'));
  }

  /// SQL runs on another thread. sqlite3_interrupt is thread-safe and remains
  /// available in mobile builds which omit sqlite3_progress_handler. A handshake
  /// keeps the connection alive until the parent detaches its interrupt timer.
  Future<(String, String)> _sqlIsolate(
    String code,
    bool rowsOnly,
    bool alternate,
  ) => _sqlJob(_sqlWorker, [code, rowsOnly, alternate]);

  Future<(String, String)> _sqlJob(
    void Function(List) worker,
    List args,
  ) async {
    final port = ReceivePort();
    final result = Completer<(String, String)>();
    final closed = Completer<void>();
    SendPort? release;
    int? address;
    Timer? deadline;
    String? interrupted;
    void interrupt(String reason) {
      if (address == null || result.isCompleted) return;
      interrupted = reason;
      sqlite_open.open
          .openSqlite()
          .lookupFunction<_SqlInterruptNative, _SqlInterruptDart>(
            'sqlite3_interrupt',
          )(Pointer<Void>.fromAddress(address!));
    }

    final subscription = port.listen((dynamic message) {
      final data = message as List;
      switch (data[0]) {
        case 'ready':
          address = data[1] as int;
          release = data[2] as SendPort;
          deadline = Timer(
            const Duration(seconds: 2),
            () => interrupt('SQLite: превышен лимит 2 секунды.'),
          );
          if (_cancelled) interrupt('Отменено.');
        case 'result':
          deadline?.cancel();
          if (!result.isCompleted) {
            result.complete((
              data[1] as String,
              interrupted ?? data[2] as String,
            ));
          }
        case 'closed':
          if (!closed.isCompleted) closed.complete();
      }
    });
    final isolate = await Isolate.spawn(worker, [port.sendPort, ...args]);
    _interruptSql = () => interrupt('Отменено.');
    try {
      return await result.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      return ('', 'SQLite: превышен лимит 3 секунды.');
    } finally {
      deadline?.cancel();
      _interruptSql = null;
      if (!result.isCompleted && address != null) {
        interrupt('SQLite: проверка прервана.');
        try {
          await result.future.timeout(const Duration(seconds: 1));
        } on TimeoutException {
          /* Kill below. */
        }
      }
      // Only now may the worker close its connection: no timer or cancel hook
      // can call sqlite3_interrupt with a freed sqlite3*.
      release?.send(null);
      try {
        await closed.future.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        /* Kill below. */
      }
      isolate.kill(priority: Isolate.immediate);
      await subscription.cancel();
      port.close();
    }
  }
}

typedef _SqlInterruptNative = Void Function(Pointer<Void>);
typedef _SqlInterruptDart = void Function(Pointer<Void>);
typedef _SqlLimitNative = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _SqlLimitDart = int Function(Pointer<Void>, int, int);

void _sqlWorker(List args) async {
  final port = args[0] as SendPort;
  final db = sqlite3.openInMemory();
  final release = ReceivePort();
  port.send(['ready', db.handle.address, release.sendPort]);
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
      port.send(['result', output, '']);
    } finally {
      statement.dispose();
    }
  } catch (e) {
    port.send(['result', '', 'SQLite: $e']);
  } finally {
    await release.first;
    db.dispose();
    release.close();
    port.send(['closed']);
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

void _projectSqlWorker(List args) async {
  final port = args[0] as SendPort;
  final db = sqlite3.open(args[1] as String);
  final release = ReceivePort();
  port.send(['ready', db.handle.address, release.sendPort]);
  try {
    final code = args[2] as String;
    if (RegExp(
      r'\b(ATTACH|DETACH|load_extension|readfile|writefile)\b',
      caseSensitive: false,
    ).hasMatch(code)) {
      throw const FormatException(
        'В проекте не поддерживаются файловые расширения и ATTACH.',
      );
    }
    final library = sqlite_open.open.openSqlite();
    final limit = library.lookupFunction<_SqlLimitNative, _SqlLimitDart>(
      'sqlite3_limit',
    );
    limit(db.handle.cast<Void>(), 0, 65536);
    limit(db.handle.cast<Void>(), 1, 200000);
    limit(db.handle.cast<Void>(), 7, 0);
    db.execute('PRAGMA foreign_keys = ON');
    var remaining = code;
    final results = <String>[];
    var statements = 0, rowCount = 0, outputSize = 0;
    while ((remaining = _withoutSqlTrivia(remaining)).isNotEmpty) {
      if (++statements > 100) {
        throw const FormatException(
          'В одном запуске разрешено до 100 SQL-команд.',
        );
      }
      // SQLite itself identifies the first complete statement, including
      // strings, comments and trigger bodies. Preparing lazily allows DDL to
      // create a table before the following statement refers to that table.
      final statement = db.prepare(remaining, checkNoTail: false);
      try {
        if (statement.sql.isEmpty || !remaining.startsWith(statement.sql)) {
          throw const FormatException(
            'Не удалось определить границу SQL-команды.',
          );
        }
        remaining = remaining.substring(statement.sql.length);
        final cursor = statement.selectCursor();
        final rows = <String>[];
        while (cursor.moveNext()) {
          final row = cursor.current.values.join(' | ');
          outputSize += row.length;
          if (++rowCount > 1000 || outputSize > 65536) {
            throw const FormatException(
              'Результат превышает 1000 строк или 64 КиБ.',
            );
          }
          rows.add(row);
        }
        final output = cursor.columnNames.isNotEmpty
            ? '${cursor.columnNames.join(" | ")}\n${rows.join("\n")}'
            : 'Готово. Данные сохраняются в project.sqlite согласно границам транзакции.';
        outputSize +=
            output.length - rows.fold<int>(0, (sum, row) => sum + row.length);
        if (outputSize > 65536) {
          throw const FormatException('Вывод превышает 64 КиБ.');
        }
        results.add(output);
      } finally {
        statement.dispose();
      }
    }
    if (!db.autocommit) {
      db.execute('ROLLBACK');
      throw const FormatException(
        'Сценарий оставил открытую транзакцию. Изменения откачены: добавь COMMIT или ROLLBACK в тот же запуск.',
      );
    }
    port.send(['result', results.join('\n\n'), '']);
  } catch (e) {
    if (!db.autocommit) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {
        /* Closing also rolls back. */
      }
    }
    port.send([
      'result',
      '',
      'SQLite: $e\nКоманды вне явной транзакции могли сохраниться. Для атомарного сценария используй BEGIN … COMMIT.',
    ]);
  } finally {
    await release.first;
    db.dispose();
    release.close();
    port.send(['closed']);
  }
}

String _withoutSqlTrivia(String source) {
  var rest = source.trimLeft();
  while (true) {
    if (rest.startsWith('--')) {
      final end = rest.indexOf('\n');
      if (end < 0) return '';
      rest = rest.substring(end + 1).trimLeft();
    } else if (rest.startsWith('/*')) {
      final end = rest.indexOf('*/', 2);
      if (end < 0) return '';
      rest = rest.substring(end + 2).trimLeft();
    } else {
      return rest;
    }
  }
}
