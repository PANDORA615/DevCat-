import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'course.dart';
import 'web_sample_assets.dart';
import 'progress.dart';

class DevProject {
  final String id;
  String name, language, entry;
  final Map<String, String> files;
  DevProject({
    required this.id,
    required this.name,
    required this.language,
    required this.entry,
    required this.files,
  });
  factory DevProject.forLesson(String language, Lesson lesson) {
    final id = lesson.learning['projectId'];
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        lesson.webExample.isEmpty) {
      throw const FormatException('У урока нет подготовленного веб-проекта.');
    }
    return DevProject(
      id: id,
      name: 'Урок · ${lesson.title}',
      language: language,
      entry: 'index.html',
      files: {
        ...lesson.webExample,
        'README.md': '# ${lesson.title}\n\n${lesson.assignment}\n',
      },
    );
  }
  factory DevProject.create(String language, String name) => DevProject(
    id: newId(),
    name: name,
    language: language,
    entry: fileNames[language]!,
    files: {
      if (language == 'html' || language == 'css') 'cat.svg': webSampleCat,
      if (language == 'html' || language == 'css')
        'style.css':
            'body { font-family: system-ui; line-height: 1.7; padding: 24px; }\n.card { background: #ddf3e5; padding: 20px; border-radius: 16px; }\n',
      fileNames[language]!: language == 'html' || language == 'css'
          ? '<!doctype html>\n<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="style.css"><title>Моя страница</title></head><body><main class="card"><h1>Привет!</h1><p>Моя первая страница.</p></main></body></html>'
          : language == 'sql'
          ? '-- Своя SQLite-база проекта, данные сохраняются между запусками.\nCREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY, text TEXT NOT NULL);\n'
          : generateChallenge(language, kind: 'arithmetic').starter,
      'README.md':
          '# $name\n\nЛокальный проект DevCat. Опиши запуск и проверки.\n',
    },
  );
  static bool validPath(String path) {
    if (path.isEmpty ||
        path.length > 180 ||
        path.contains('\\') ||
        path.startsWith('/') ||
        path.contains(':') ||
        path.contains(RegExp(r'[\x00-\x1f<>"|?*]'))) {
      return false;
    }
    final parts = path.split('/');
    return parts.length <= 8 &&
        parts.every(
          (part) =>
              part.isNotEmpty &&
              part != '.' &&
              part != '..' &&
              !part.startsWith('.') &&
              !part.endsWith('.') &&
              !part.endsWith(' ') &&
              !RegExp(
                r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
                caseSensitive: false,
              ).hasMatch(part),
        );
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'id': id,
    'name': name,
    'language': language,
    'entry': entry,
    'files': files,
  };
  String encode() => jsonEncode(toJson());
  factory DevProject.decode(String text) {
    if (utf8.encode(text).length > 180000) {
      throw const FormatException('Проект превышает 180 КБ.');
    }
    final j = jsonDecode(text);
    if (j is! Map ||
        j['schema'] != 1 ||
        j['id'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(j['id']) ||
        j['name'] is! String ||
        j['name'].length > 100 ||
        !languageNames.containsKey(j['language']) ||
        j['entry'] is! String ||
        j['files'] is! Map ||
        j['files'].isEmpty ||
        j['files'].length > 40) {
      throw const FormatException('Неверный формат проекта DevCat.');
    }
    final files = <String, String>{};
    for (final e in (j['files'] as Map).entries) {
      if (e.key is! String || !validPath(e.key) || e.value is! String) {
        throw const FormatException('Небезопасный путь или содержимое файла.');
      }
      // Reject case-insensitive aliases and file/directory collisions on every OS.
      final lower = (e.key as String).toLowerCase();
      if (files.keys.any(
        (k) =>
            k.toLowerCase() == lower ||
            k.toLowerCase().startsWith('$lower/') ||
            lower.startsWith('${k.toLowerCase()}/'),
      )) {
        throw const FormatException('Конфликт путей проекта.');
      }
      files[e.key] = e.value;
    }
    if (!files.containsKey(j['entry'])) {
      throw const FormatException('Точка входа не найдена.');
    }
    return DevProject(
      id: j['id'],
      name: j['name'],
      language: j['language'],
      entry: j['entry'],
      files: files,
    );
  }
  Future<Directory> materialize(Directory root) async {
    // Revalidate even projects assembled through the editor before touching disk.
    DevProject.decode(encode());
    final projectsRoot = Directory(p.join(root.path, 'projects'));
    final directory = Directory(p.join(projectsRoot.path, id));
    for (final path in [projectsRoot.path, directory.path]) {
      if (await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException(
          'Каталог проекта не должен быть символической ссылкой.',
        );
      }
    }
    await directory.create(recursive: true);
    final manifest = File(p.join(directory.path, '.devcat-managed.json'));
    if (await FileSystemEntity.type(manifest.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('Неверный манифест файлов проекта.');
    }
    if (await manifest.exists()) {
      if (await manifest.length() > 20000) {
        throw const FormatException('Неверный манифест файлов.');
      }
      final previous = jsonDecode(await manifest.readAsString());
      if (previous is! List || previous.length > 40) {
        throw const FormatException('Неверный манифест файлов.');
      }
      for (final name in previous) {
        if (name is! String || !validPath(name)) {
          throw const FormatException('Неверный путь в манифесте.');
        }
        if (!files.containsKey(name)) {
          final old = File(p.joinAll([directory.path, ...name.split('/')]));
          var current = directory.path;
          for (final part in name.split('/')) {
            current = p.join(current, part);
            if (await FileSystemEntity.type(current, followLinks: false) ==
                FileSystemEntityType.link) {
              throw const FileSystemException(
                'Символические ссылки в проекте не поддерживаются.',
              );
            }
          }
          if (await old.exists()) await old.delete();
        }
      }
    }
    for (final e in files.entries) {
      final parts = e.key.split('/');
      var current = directory.path;
      for (final part in parts) {
        current = p.join(current, part);
        if (await FileSystemEntity.type(current, followLinks: false) ==
            FileSystemEntityType.link) {
          throw const FileSystemException(
            'Символические ссылки в проекте не поддерживаются.',
          );
        }
      }
      final file = File(p.joinAll([directory.path, ...parts]));
      await file.parent.create(recursive: true);
      await file.writeAsString(e.value);
    }
    await manifest.writeAsString(jsonEncode(files.keys.toList()), flush: true);
    return directory;
  }
}
