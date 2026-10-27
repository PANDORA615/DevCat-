import 'dart:io';
import 'package:devcat/core/project.dart';
import 'package:devcat/core/runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Project import rejects traversal, aliases and collisions before writing',
    () {
      final p = DevProject.create('python', 'Test');
      for (final path in [
        '../evil.py',
        '/tmp/evil.py',
        'C:/evil.py',
        'folder/../evil.py',
        'folder\\evil.py',
        'CON.txt',
        'a//b',
      ]) {
        p.files[path] = 'x';
        expect(() => DevProject.decode(p.encode()), throwsFormatException);
        p.files.remove(path);
      }
      p.files['MAIN.PY'] = 'x';
      expect(() => DevProject.decode(p.encode()), throwsFormatException);
      p.files.remove('MAIN.PY');
      p.files['folder'] = 'x';
      p.files['folder/file.py'] = 'x';
      expect(() => DevProject.decode(p.encode()), throwsFormatException);
    },
  );
  test(
    'Multi-file Python project imports a local module and persists its output file',
    () async {
      final root = await Directory.systemTemp.createTemp('devcat-project-');
      final project = DevProject.create('python', 'Modules');
      project.files['main.py'] =
          'from helper import add\nfrom pathlib import Path\nprint(add(2, 3))\nPath("result.txt").write_text("saved", encoding="utf-8")\n';
      project.files['helper.py'] = 'def add(a, b):\n    return a + b\n';
      try {
        final result = await LocalRunner().runProject(project, root, '');
        expect(result.ok, isTrue, reason: result.error);
        expect(result.output.trim(), '5');
        expect(
          await File(
            '${root.path}/projects/${project.id}/result.txt',
          ).readAsString(),
          'saved',
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('IDE SQLite project supports DDL, DML and persistent queries', () async {
    final root = await Directory.systemTemp.createTemp('devcat-project-sql-');
    final project = DevProject.create('sql', 'Database');
    final runner = LocalRunner();
    try {
      for (final source in [
        'CREATE TABLE notes(id INTEGER PRIMARY KEY, text TEXT);',
        "INSERT INTO notes VALUES(1,'Привет');",
        'SELECT id, text FROM notes ORDER BY id;',
      ]) {
        project.files['query.sql'] = source;
        final result = await runner.runProject(project, root, '');
        expect(result.ok, isTrue, reason: result.error);
        if (source.startsWith('SELECT')) {
          expect(result.output, contains('1 | Привет'));
        }
      }
      project.files['query.sql'] = 'SELECT COUNT(*) FROM notes;';
      final result = await LocalRunner().runProject(project, root, '');
      expect(result.output.trim(), endsWith('1'));
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('Multi-file toolchain projects link their helper sources', () async {
    final root = await Directory.systemTemp.createTemp('devcat-link-');
    final runner = LocalRunner(), tools = await LocalRunner().toolchains();
    final programs = <String, Map<String, String>>{
      'c': {
        'main.c':
            '#include <stdio.h>\nint add(int,int);\nint main(void){printf("%d\\n",add(2,3));return 0;}',
        'helper.c': 'int add(int a,int b){return a+b;}',
      },
      'cpp': {
        'main.cpp':
            '#include <iostream>\nint add(int,int);\nint main(){std::cout<<add(2,3)<<"\\n";}',
        'helper.cpp': 'int add(int a,int b){return a+b;}',
      },
      'csharp': {
        'Program.cs': 'using System;\nConsole.WriteLine(Helper.Add(2,3));',
        'Helper.cs':
            'public static class Helper { public static int Add(int a,int b)=>a+b; }',
      },
      'java': {
        'Main.java':
            'public class Main { public static void main(String[] args){System.out.println(Helper.add(2,3));}}',
        'Helper.java':
            'class Helper { static int add(int a,int b){return a+b;}}',
      },
      'go': {
        'main.go':
            'package main\nimport "fmt"\nfunc main(){fmt.Println(add(2,3))}',
        'helper.go': 'package main\nfunc add(a,b int) int {return a+b}',
      },
      'javascript': {
        'main.js': 'console.log(require("./helper.js").add(2,3));',
        'helper.js': 'exports.add=(a,b)=>a+b;',
      },
    };
    try {
      for (final entry in programs.entries) {
        final language = {
          'c': 'C',
          'cpp': 'C++',
          'csharp': 'C#',
          'java': 'Java',
          'go': 'Go',
          'javascript': 'JavaScript',
        }[entry.key]!;
        if (tools[language]!.startsWith('Не установлен')) {
          expect(
            Platform.environment['DEVCAT_REQUIRE_ALL_TOOLCHAINS'],
            isNot('true'),
            reason: language,
          );
          continue;
        }
        final project = DevProject.create(entry.key, 'Link test');
        project.files
          ..clear()
          ..addAll(entry.value);
        final result = await runner.runProject(project, root, '');
        expect(result.ok, isTrue, reason: '$language: ${result.error}');
        expect(result.output.trim(), '5');
      }
    } finally {
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
  test(
    'Removed source files are removed on the next materialization',
    () async {
      final root = await Directory.systemTemp.createTemp('devcat-delete-');
      final project = DevProject.create('python', 'Delete test');
      try {
        project.files['helper.py'] = 'value=1';
        final directory = await project.materialize(root);
        project.files.remove('helper.py');
        await project.materialize(root);
        expect(await File('${directory.path}/helper.py').exists(), isFalse);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
