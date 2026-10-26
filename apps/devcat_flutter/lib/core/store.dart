import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'progress.dart';

class AppStore extends ChangeNotifier {
  final Directory directory;
  late String device;
  ProgressData progress = ProgressData();
  Map<String, dynamic> settings = {};
  String? storageWarning;
  Future<void> _pending = Future.value();
  AppStore(this.directory);
  File get _file => File(p.join(directory.path, 'devcat.json'));
  Future<void> load() async {
    await directory.create(recursive: true);
    // Never silently discard corrupt user data; try a complete backup first.
    for (final path in [_file.path, '${_file.path}.bak']) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final raw = await file.readAsString();
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final parsed = ProgressData.decode(jsonEncode(j['progress']));
        final id = j['device'];
        if (id is! String) throw const FormatException('No device id');
        progress = parsed;
        device = id;
        settings = Map<String, dynamic>.from(j['settings']);
        if (path.endsWith('.bak')) {
          storageWarning =
              'Основной файл повреждён. Восстановлена резервная копия; оригинал сохранён.';
        }
        return;
      } catch (_) {
        storageWarning =
            'Не удалось прочитать локальные данные. Оригинал сохранён; экспортируй файл из каталога данных перед очисткой.';
      }
    }
    device = newId();
    if (storageWarning != null && await _file.exists()) {
      await _file.copy(
        '${_file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
      );
    }
  }

  T setting<T>(String key, T fallback) =>
      settings[key] is T ? settings[key] as T : fallback;
  Future<void> set(String key, dynamic value) async {
    settings[key] = value;
    notifyListeners();
    await save();
  }

  Future<void> save() {
    final snapshot = jsonEncode({
      'device': device,
      'settings': settings,
      'progress': progress.toJson(),
    });
    final operation = _pending.then((_) async {
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(snapshot, flush: true);
      if (await _file.exists()) await _file.copy('${_file.path}.bak');
      if (Platform.isWindows && await _file.exists()) await _file.delete();
      await temp.rename(_file.path);
    });
    _pending = operation.catchError((Object e) {
      storageWarning = 'Ошибка сохранения: $e';
      notifyListeners();
    });
    return operation;
  }

  Future<void> merge(ProgressData data) async {
    progress = progress.merge(data);
    await save();
    notifyListeners();
  }

  Future<void> record(String task, String lang, bool passed) async {
    progress.attempt(task, lang, passed);
    await save();
    notifyListeners();
  }

  Future<void> draft(String task, String text) async {
    progress.draft(task, text, device);
    await save();
  }

  Future<void> cursor(String lang, int lesson, int seed) async {
    progress.cursor(lang, lesson, seed, device);
    await save();
  }

  Future<void> flush() => _pending;
}
