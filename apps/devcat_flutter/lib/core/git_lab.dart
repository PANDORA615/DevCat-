import 'dart:io';
import 'package:path/path.dart' as p;
import 'runner.dart';

class GitLab {
  final Directory directory;
  final LocalRunner runner = LocalRunner();
  GitLab(this.directory);
  Future<void> initialize() async {
    await directory.create(recursive: true);
    final readme = File(p.join(directory.path, 'README.md'));
    if (!await readme.exists()) {
      await readme.writeAsString(
        '# Мой первый проект\n\nУчусь вместе с DevCat.\n',
      );
    }
  }

  static List<String> parse(String line) {
    final tokens = <String>[];
    final token = StringBuffer();
    String? quote;
    var active = false;
    for (final rune in line.runes) {
      final c = String.fromCharCode(rune);
      if (quote != null) {
        if (c == quote) {
          quote = null;
        } else {
          token.write(c);
        }
        active = true;
      } else if (c == '"' || c == "'") {
        quote = c;
        active = true;
      } else if (c.trim().isEmpty) {
        if (active) {
          tokens.add(token.toString());
          token.clear();
          active = false;
        }
      } else {
        token.write(c);
        active = true;
      }
    }
    if (quote != null) throw const FormatException('Закрой кавычки.');
    if (active) tokens.add(token.toString());
    return tokens;
  }

  Future<RunResult> execute(String command) async {
    final args = parse(command);
    if (args.length < 2 || args.first != 'git') {
      return const RunResult(
        '',
        'В лаборатории принимаются только команды git.',
        1,
      );
    }
    const allowed = {
      'init',
      'status',
      'add',
      'commit',
      'log',
      'diff',
      'branch',
      'switch',
      'merge',
      'show',
    };
    if (!allowed.contains(args[1])) {
      return const RunResult(
        '',
        'Доступны init/status/add/commit/log/diff/branch/switch/merge/show. Лаборатория работает без сети.',
        1,
      );
    }
    if (args
        .skip(2)
        .any(
          (a) =>
              a.startsWith('-c') ||
              a.startsWith('--exec') ||
              a.startsWith('--upload') ||
              a.startsWith('--output') ||
              a.startsWith('--git-dir') ||
              a.startsWith('--work-tree') ||
              a == '-C' ||
              p.isAbsolute(a) ||
              a.split(RegExp(r'[/\\]')).contains('..'),
        )) {
      return const RunResult(
        '',
        'Путь или опция недоступны в учебном репозитории.',
        1,
      );
    }
    // init is pinned to this directory; no custom template or external path.
    if (args[1] == 'init' && args.length != 2) {
      return const RunResult(
        '',
        'Используй git init без дополнительных аргументов.',
        1,
      );
    }
    // All paths are generated locally, no external repositories are imported.
    return runner.process(
      'git',
      [
        '-c',
        'user.name=DevCat Student',
        '-c',
        'user.email=student@devcat.local',
        '-c',
        'core.hooksPath=${p.join(directory.path, '.disabled-hooks')}',
        '-c',
        'commit.gpgsign=false',
        ...args.skip(1),
      ],
      cwd: directory.path,
      timeout: const Duration(seconds: 10),
    );
  }

  Future<bool> verify() async {
    final commit = await runner.process('git', [
      'rev-parse',
      '--verify',
      'HEAD',
    ], cwd: directory.path);
    final file = await runner.process('git', [
      'cat-file',
      '-e',
      'HEAD:README.md',
    ], cwd: directory.path);
    return commit.ok && file.ok;
  }
}
