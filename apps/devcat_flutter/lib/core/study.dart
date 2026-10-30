import 'dart:convert';
import 'package:flutter/services.dart';
import 'course.dart';
import 'progress.dart';

class StudyExercise {
  final Map<String, dynamic> data;
  StudyExercise(this.data);
  String get id => data['id'];
  String get kind => data['kind'];
  String get prompt => data['prompt'];
  String get text => data['text'] ?? '';
  String get code => data['code'] ?? '';
  String get answer => data['answer'] ?? '';
  String get why => data['why'] ?? '';
  List<String> get options => List<String>.from(data['options'] ?? []);
  List<String> get pieces => List<String>.from(data['pieces'] ?? []);
  bool get informational => kind == 'learn';

  bool accepts(String value) {
    String normalize(String s) {
      var result = s.trim();
      if (kind == 'write' ||
          (kind == 'fill' && data['caseSensitive'] == false)) {
        result = result.replaceAll(RegExp(r'\s+'), ' ');
      }
      if (data['caseSensitive'] == false) {
        result = result.toLowerCase();
        if (kind == 'write') result = result.replaceAll('ё', 'е');
      }
      return result;
    }

    final expected = kind == 'order' ? pieces.join() : answer;
    final actual = normalize(value);
    final accepted = [expected, ...List<String>.from(data['accepted'] ?? [])];
    return accepted.any((answer) => actual == normalize(answer));
  }
}

class StudyUnit {
  final String id, title;
  final int level;
  final List<StudyExercise> steps;
  StudyUnit(Map<String, dynamic> data)
    : id = data['id'],
      title = data['title'],
      level = data['level'],
      steps = (data['steps'] as List)
          .map((s) => StudyExercise(Map<String, dynamic>.from(s)))
          .toList();
  StudyUnit._(this.id, this.title, this.level, this.steps);
  StudyUnit forReview() => StudyUnit._(
    id,
    title,
    level,
    steps.where((s) => !s.informational).toList(),
  );
}

class StudyTopic {
  final String id, course, title, chapter;
  final int index;
  final List<StudyUnit> rounds;
  StudyTopic(Map<String, dynamic> data)
    : id = data['id'],
      course = data['course'],
      title = data['title'],
      chapter = data['chapter'],
      index = data['index'],
      rounds = (data['rounds'] as List)
          .map((r) => StudyUnit(Map<String, dynamic>.from(r)))
          .toList();
}

class StudyCatalog {
  static Future<StudyCatalog>? _loading;
  static StudyCatalog? cached;
  final Map<String, StudyTopic> topics;
  StudyCatalog(this.topics);
  factory StudyCatalog.decode(String text) {
    final raw = jsonDecode(text);
    if (raw['schema'] != 1 || raw['revision'] != 1) {
      throw const FormatException('Неподдерживаемая программа занятий.');
    }
    final topics = <String, StudyTopic>{};
    for (final item in raw['topics'] as List) {
      final topic = StudyTopic(Map<String, dynamic>.from(item));
      if (topics.containsKey(topic.id) || topic.rounds.length != 3) {
        throw const FormatException('Неверная структура учебного маршрута.');
      }
      topics[topic.id] = topic;
    }
    return StudyCatalog(topics);
  }
  static Future<StudyCatalog> load() => _loading ??= rootBundle
      .loadString('assets/content/study_path.json')
      .then((text) => cached = StudyCatalog.decode(text))
      .catchError((Object e) {
        _loading = null;
        throw e;
      });
  List<StudyTopic> forCourse(Course course) => [
    for (final lesson in course.lessons) topics[lesson.id]!,
  ];
}

/// Durable short-session state. Wrong answers return after two other cards;
/// finishing requires a correct answer to every question, including retries.
class StudySessionState {
  final StudyUnit unit;
  final Set<String> resolved = {}, wrong = {};
  final List<String> queue = [];
  bool? feedback;
  String entry = '', detail = '';
  List<int> selectedPieces = [];
  final Map<String, String> codeEntries = {};
  String? selectedOption;
  late final int generation;
  StudySessionState(
    this.unit, {
    List<Map<String, dynamic>> snapshots = const [],
    int? generation,
  }) {
    final valid = unit.steps.map((s) => s.id).toSet();
    final candidates = snapshots
        .where((s) => s['unit'] == unit.id && s['schema'] == 1)
        .toList();
    int version(Map<String, dynamic> value) => value['generation'] is int
        ? (value['generation'] as int).clamp(1, 1000000)
        : 1;
    this.generation =
        generation ??
        candidates.fold<int>(
          1,
          (latest, s) => version(s) > latest ? version(s) : latest,
        );
    final compatible = candidates
        .where((s) => version(s) == this.generation)
        .toList();
    for (final state in compatible) {
      resolved.addAll(_strings(state['resolved']).where(valid.contains));
      wrong.addAll(_strings(state['wrong']).where(valid.contains));
    }
    final latest = compatible.isEmpty ? null : compatible.first;
    if (latest?['codeEntries'] is Map) {
      for (final entry in (latest!['codeEntries'] as Map).entries) {
        if (valid.contains(entry.key) &&
            entry.value is String &&
            (entry.value as String).length < 50000) {
          codeEntries[entry.key] = entry.value;
        }
      }
    }
    queue.addAll(
      _strings(
        latest?['queue'],
      ).where((id) => valid.contains(id) && !resolved.contains(id)).toSet(),
    );
    queue.addAll(
      valid.where((id) => !resolved.contains(id) && !queue.contains(id)),
    );
    if (latest != null &&
        queue.isNotEmpty &&
        latest['current'] == queue.first) {
      feedback = latest['feedback'] is bool ? latest['feedback'] : null;
      entry = latest['entry'] is String ? latest['entry'] : '';
      detail = latest['detail'] is String ? latest['detail'] : '';
      selectedOption = latest['selected'] is String ? latest['selected'] : null;
      final pieces = current.pieces;
      selectedPieces =
          (latest['pieces'] is List ? latest['pieces'] as List : [])
              .whereType<int>()
              .where((i) => i >= 0 && i < pieces.length)
              .toSet()
              .toList();
    }
  }
  static List<String> _strings(dynamic raw) =>
      raw is List ? raw.whereType<String>().take(100).toList() : [];
  bool get complete => queue.isEmpty;
  StudyExercise get current =>
      unit.steps.firstWhere((s) => s.id == queue.first);
  int get answered => unit.steps
      .where((s) => !s.informational && resolved.contains(s.id))
      .length;
  int get questionCount => unit.steps.where((s) => !s.informational).length;
  double get fraction => resolved.length / unit.steps.length;
  void checked(bool correct, {String explanation = ''}) {
    if (feedback != null || complete || current.informational) return;
    feedback = correct;
    detail = explanation;
    if (!correct) wrong.add(current.id);
  }

  void advance() {
    if (complete || (!current.informational && feedback == null)) return;
    final exercise = current;
    final id = queue.removeAt(0);
    if (feedback == false) {
      if (exercise.kind == 'code') codeEntries[id] = entry;
      queue.insert(queue.length.clamp(0, 2), id);
    } else {
      resolved.add(id);
      codeEntries.remove(id);
    }
    feedback = null;
    entry = '';
    detail = '';
    selectedPieces = [];
    selectedOption = null;
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'generation': generation,
    'codeEntries': codeEntries,
    'unit': unit.id,
    'resolved': resolved.toList(),
    'wrong': wrong.toList(),
    'queue': queue,
    'current': complete ? null : queue.first,
    'feedback': feedback,
    'entry': entry,
    'detail': detail,
    'pieces': selectedPieces,
    'selected': selectedOption,
  };
}

String studyDay(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Completion events are deduplicated by unit + calendar day across devices.
/// XP is derived, never merged as an incrementable counter.
class StudyLedger {
  final List<Map<String, dynamic>> events;
  final DateTime now;
  StudyLedger(ProgressData progress, {DateTime? now})
    : now = now ?? DateTime.now(),
      events = _events(progress);
  static List<Map<String, dynamic>> _events(ProgressData progress) {
    final records = <String, Map<String, dynamic>>{};
    for (final draft in progress.drafts.values) {
      final task = draft['task'];
      if (task is! String || !task.startsWith('study.done.v1:')) continue;
      try {
        final event = jsonDecode(draft['text']);
        if (event is! Map ||
            event['unit'] is! String ||
            event['day'] is! String ||
            event['time'] is! int) {
          continue;
        }
        if (!RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(event['day'])) continue;
        final day = DateTime.tryParse(event['day']);
        if (day == null || studyDay(day) != event['day']) continue;
        if (task != 'study.done.v1:${event['unit']}:${event['day']}') continue;
        final previous = records[task];
        final combinedWrong = <String>{
          ...StudySessionState._strings(previous?['wrong']),
          ...StudySessionState._strings(event['wrong']),
        };
        if (previous == null || event['time'] < previous['time']) {
          records[task] = Map<String, dynamic>.from(event);
        }
        records[task]!['wrong'] = combinedWrong.toList();
      } catch (_) {
        /* A broken optional study record must not discard projects. */
      }
    }
    return records.values.toList();
  }

  bool done(StudyUnit unit) => events.any((e) => e['unit'] == unit.id);
  int levels(StudyTopic topic) => topic.rounds.where(done).length;
  int get xp {
    final units = events.map((e) => e['unit']).toSet().length;
    return units * 20 + (events.length - units) * 5;
  }

  int get today => events.where((e) => e['day'] == studyDay(now)).length;
  int get streak {
    final days = events.map((e) => e['day']).toSet();
    var date = DateTime.utc(now.year, now.month, now.day);
    if (!days.contains(studyDay(date))) {
      date = date.subtract(const Duration(days: 1));
    }
    var result = 0;
    while (days.contains(studyDay(date))) {
      result++;
      date = date.subtract(const Duration(days: 1));
    }
    return result;
  }

  int firstIncomplete(List<StudyTopic> topics) {
    final index = topics.indexWhere((t) => levels(t) < 3);
    return index < 0 ? topics.length - 1 : index;
  }

  bool due(StudyTopic topic) {
    final ids = topic.rounds.map((r) => r.id).toSet();
    final records = events.where((e) => ids.contains(e['unit'])).toList()
      ..sort((a, b) => (b['time'] as int).compareTo(a['time'] as int));
    if (records.isEmpty) return false;
    final days = records.map((e) => e['day']).toSet().length;
    final latest = records.first;
    final mistakes = topic.rounds.where(done).any((unit) {
      final last = records.firstWhere((e) => e['unit'] == unit.id);
      return last['wrong'] is List && (last['wrong'] as List).isNotEmpty;
    });
    final interval = mistakes ? 1 : [1, 3, 7, 14, 30][(days - 1).clamp(0, 4)];
    final last = DateTime.parse('${latest['day']}T00:00:00Z');
    final today = DateTime.utc(now.year, now.month, now.day);
    return today.difference(last).inDays >= interval;
  }

  StudyUnit reviewUnit(StudyTopic topic) {
    final completed = topic.rounds.where(done).toList();
    for (final unit in completed.reversed) {
      final records = events.where((e) => e['unit'] == unit.id).toList()
        ..sort((a, b) => (b['time'] as int).compareTo(a['time'] as int));
      if (StudySessionState._strings(records.first['wrong']).isNotEmpty) {
        return unit;
      }
    }
    return completed.last;
  }

  static String eventKey(StudyUnit unit, DateTime date) =>
      'study.done.v1:${unit.id}:${studyDay(date)}';
  static String event(StudyUnit unit, Set<String> wrong, DateTime date) =>
      jsonEncode({
        'unit': unit.id,
        'day': studyDay(date),
        'time': date.millisecondsSinceEpoch,
        'wrong': wrong.toList(),
      });
  static List<Map<String, dynamic>> snapshots(
    ProgressData progress,
    String key,
  ) {
    final result = <Map<String, dynamic>>[];
    for (final record in progress.draftsFor(key)) {
      try {
        final parsed = jsonDecode(record['text']);
        if (parsed is Map) result.add(Map<String, dynamic>.from(parsed));
      } catch (_) {
        /* Ignore a malformed optional checkpoint. */
      }
    }
    return result;
  }
}
