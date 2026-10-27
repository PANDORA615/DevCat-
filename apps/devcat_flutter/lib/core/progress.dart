import 'dart:convert';
import 'dart:math';

String newId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class ProgressData {
  final Map<String, Map<String, dynamic>> attempts, drafts, cursors;
  ProgressData({
    Map<String, Map<String, dynamic>>? attempts,
    Map<String, Map<String, dynamic>>? drafts,
    Map<String, Map<String, dynamic>>? cursors,
  }) : attempts = attempts ?? {},
       drafts = drafts ?? {},
       cursors = cursors ?? {};
  Set<String> get solved => attempts.values
      .where((a) => a['passed'] == true)
      .map((a) => a['task'] as String)
      .toSet();
  Map<String, dynamic> toJson() => {
    'schema': 1,
    'attempts': attempts,
    'drafts': drafts,
    'cursors': cursors,
  };
  String encode() => jsonEncode(toJson());
  factory ProgressData.decode(String text) {
    if (utf8.encode(text).length > 5 * 1024 * 1024) {
      throw const FormatException('Импорт больше 5 МиБ.');
    }
    final j = jsonDecode(text);
    if (j is! Map || j['schema'] != 1) {
      throw const FormatException('Неподдерживаемая версия прогресса.');
    }
    Map<String, Map<String, dynamic>> records(String key) {
      final raw = j[key];
      if (raw is! Map || raw.length > 50000) {
        throw FormatException('Неверный раздел $key.');
      }
      final out = <String, Map<String, dynamic>>{};
      for (final e in raw.entries) {
        if (e.key is! String ||
            (e.key as String).length > 256 ||
            e.value is! Map) {
          throw const FormatException('Неверная запись.');
        }
        final value = Map<String, dynamic>.from(e.value);
        if (value['updated'] is! int ||
            value['updated'] < 0 ||
            value['revision'] is! int ||
            value['revision'] < 0) {
          throw const FormatException('Неверная ревизия.');
        }
        if (key == 'attempts' &&
            (value['task'] is! String ||
                value['passed'] is! bool ||
                value['language'] is! String)) {
          throw const FormatException('Неверная попытка.');
        }
        if (key == 'drafts' &&
            (value['task'] is! String ||
                value['text'] is! String ||
                (value['text'] as String).length > 200000 ||
                value['device'] is! String)) {
          throw const FormatException('Неверный черновик.');
        }
        if (key == 'cursors' &&
            (value['language'] is! String ||
                value['lesson'] is! int ||
                value['seed'] is! int)) {
          throw const FormatException('Неверная позиция.');
        }
        if (key == 'cursors' && value['contentRevision'] == null) {
          final oldIndex = value['lesson'] as int;
          if (oldIndex == 0 || oldIndex == 1) {
            value['lesson'] = value['language'] == 'sql'
                ? (oldIndex == 0 ? 15 : 2)
                : (oldIndex == 0 ? 0 : 7);
            value['revision'] = (value['revision'] as int) + 1;
          }
          value['contentRevision'] = 2;
        }
        out[e.key] = value;
      }
      return out;
    }

    return ProgressData(
      attempts: records('attempts'),
      drafts: records('drafts'),
      cursors: records('cursors'),
    );
  }
  ProgressData merge(ProgressData other) {
    Map<String, Map<String, dynamic>> union(
      Map<String, Map<String, dynamic>> a,
      Map<String, Map<String, dynamic>> b,
    ) {
      final out = {...a};
      for (final e in b.entries) {
        final previous = out[e.key];
        if (previous == null || compare(e.value, previous) > 0) {
          out[e.key] = Map.of(e.value);
        }
      }
      return out;
    }

    return ProgressData(
      attempts: union(attempts, other.attempts),
      drafts: union(drafts, other.drafts),
      cursors: union(cursors, other.cursors),
    );
  }

  static int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final revision = (a['revision'] as int).compareTo(b['revision'] as int);
    if (revision != 0) return revision;
    final timestamp = (a['updated'] as int).compareTo(b['updated'] as int);
    return timestamp != 0 ? timestamp : jsonEncode(a).compareTo(jsonEncode(b));
  }

  List<Map<String, dynamic>> draftsFor(String task) =>
      drafts.values.where((d) => d['task'] == task).toList()
        ..sort((a, b) => (b['updated'] as int).compareTo(a['updated'] as int));
  Map<String, dynamic>? get latestCursor {
    if (cursors.isEmpty) return null;
    return (cursors.values.toList()..sort(
          (a, b) => (b['updated'] as int).compareTo(a['updated'] as int),
        ))
        .first;
  }

  void draft(String task, String text, String device) {
    final key = '$task:$device';
    drafts[key] = {
      'task': task,
      'text': text,
      'device': device,
      'updated': DateTime.now().millisecondsSinceEpoch,
      'revision': (drafts[key]?['revision'] as int? ?? 0) + 1,
    };
  }

  void attempt(String task, String language, bool passed) {
    attempts[newId()] = {
      'task': task,
      'language': language,
      'passed': passed,
      'updated': DateTime.now().millisecondsSinceEpoch,
      'revision': 1,
    };
  }

  void cursor(String language, int lesson, int seed, String device) {
    cursors[device] = {
      'language': language,
      'contentRevision': 2,
      'lesson': lesson,
      'seed': seed,
      'updated': DateTime.now().millisecondsSinceEpoch,
      'revision': (cursors[device]?['revision'] as int? ?? 0) + 1,
    };
  }
}
