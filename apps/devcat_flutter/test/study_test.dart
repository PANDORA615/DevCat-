import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/progress.dart';
import 'package:devcat/core/runner.dart';
import 'package:devcat/core/study.dart';
import 'package:devcat/core/study_runner.dart';
import 'package:devcat/core/store.dart';
import 'package:flutter_test/flutter_test.dart';

StudyUnit sampleUnit() => StudyUnit({
  'id': 'python.example:0',
  'title': 'Знакомство',
  'level': 0,
  'steps': [
    for (final id in ['a', 'b', 'c', 'd'])
      {'id': id, 'kind': 'write', 'prompt': id, 'answer': id, 'why': id},
  ],
});

class FailingStudyStore extends AppStore {
  FailingStudyStore() : super(Directory('/tmp/study-failed-save')) {
    device = 'failure-test';
  }
  @override
  Future<void> save() async =>
      throw const FileSystemException('read-only test storage');
}

void main() {
  test(
    'A fresh review generation does not inherit the completed answers of an earlier review',
    () {
      final older = StudySessionState(sampleUnit());
      while (!older.complete) {
        older.checked(true);
        older.advance();
      }
      final newer = StudySessionState(sampleUnit(), generation: 2);
      newer.checked(true);
      newer.advance();
      final merged = StudySessionState(
        sampleUnit(),
        snapshots: [older.toJson(), newer.toJson()],
      );
      expect(merged.generation, 2);
      expect(merged.resolved, {'a'});
      expect(merged.current.id, 'b');
      expect(merged.complete, isFalse);
    },
  );
  test(
    'Term aliases are accepted while whitespace inside code literals remains significant',
    () {
      final word = StudyExercise({
        'id': 'w',
        'kind': 'write',
        'prompt': 'p',
        'answer': 'исходник',
        'accepted': ['исходный код'],
        'caseSensitive': false,
      });
      expect(word.accepts('  ИСХОДНЫЙ   КОД '), isTrue);
      final code = StudyExercise({
        'id': 'c',
        'kind': 'fill',
        'prompt': 'p',
        'answer': '"a  b"',
        'caseSensitive': true,
      });
      expect(code.accepts('"a b"'), isFalse);
      expect(code.accepts('"a  b"'), isTrue);
    },
  );
  test('A failed disk save cannot award study XP in memory', () async {
    final store = FailingStudyStore();
    final unit = sampleUnit();
    final now = DateTime(2026, 10, 30);
    await expectLater(
      store.studyRecords({
        StudyLedger.eventKey(unit, now): StudyLedger.event(unit, {}, now),
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(StudyLedger(store.progress).xp, 0);
    expect(store.progress.drafts, isEmpty);
  });
  test(
    'Wrong answers return after two other cards and must be corrected to finish',
    () {
      final state = StudySessionState(sampleUnit());
      state.checked(false);
      state.advance();
      expect(state.queue, ['b', 'c', 'a', 'd']);
      state.checked(true);
      state.advance();
      state.checked(true);
      state.advance();
      expect(state.current.id, 'a');
      state.checked(true);
      state.advance();
      state.checked(true);
      state.advance();
      expect(state.complete, isTrue);
      expect(state.wrong, {'a'});
      expect(state.resolved.length, 4);
    },
  );

  test(
    'An unfinished answer and feedback resume and offline checkpoints merge monotonically',
    () {
      final a = StudySessionState(sampleUnit());
      a.checked(true);
      a.advance();
      a.entry = 'unfinished';
      a.checked(false);
      final restored = StudySessionState(sampleUnit(), snapshots: [a.toJson()]);
      expect(restored.current.id, 'b');
      expect(restored.entry, 'unfinished');
      expect(restored.feedback, isFalse);
      final b = StudySessionState(sampleUnit());
      b.resolved.add('b');
      b.queue.remove('b');
      final merged = StudySessionState(
        sampleUnit(),
        snapshots: [a.toJson(), b.toJson()],
      );
      expect(merged.resolved, {'a', 'b'});
      expect(merged.queue, ['c', 'd']);
      expect(merged.feedback, isNull);
    },
  );

  test(
    'XP and daily activity are not duplicated by two offline devices or repeat completion',
    () {
      final unit = sampleUnit();
      final first = DateTime(2026, 10, 30, 12);
      final a = ProgressData(), b = ProgressData();
      final key = StudyLedger.eventKey(unit, first);
      a.draft(key, StudyLedger.event(unit, {}, first), 'computer');
      b.draft(
        key,
        StudyLedger.event(unit, {'a'}, first.add(const Duration(minutes: 5))),
        'phone',
      );
      final merged = a.merge(b);
      var ledger = StudyLedger(merged, now: first);
      expect(ledger.xp, 20);
      expect(ledger.today, 1);
      expect(ledger.streak, 1);
      expect(ledger.events.single['wrong'], ['a']);
      final next = first.add(const Duration(days: 1));
      merged.draft(
        StudyLedger.eventKey(unit, next),
        StudyLedger.event(unit, {}, next),
        'phone',
      );
      ledger = StudyLedger(merged, now: next);
      expect(ledger.xp, 25);
      expect(ledger.today, 1);
      expect(ledger.streak, 2);
      expect(
        StudyLedger(ProgressData.decode(merged.encode()), now: next).xp,
        25,
      );
      expect(
        StudyLedger(merged, now: next.add(const Duration(days: 2))).streak,
        0,
      );
    },
  );

  test(
    'Review removes teaching cards, and the scheduler returns the level with mistakes',
    () {
      final data = jsonDecode(
        File('assets/content/study_path.json').readAsStringSync(),
      );
      final catalog = StudyCatalog.decode(jsonEncode(data));
      final topic = catalog.topics['python.zero.start']!;
      final progress = ProgressData();
      final date = DateTime(2026, 10, 30);
      final unit = topic.rounds[1];
      progress.draft(
        StudyLedger.eventKey(unit, date),
        StudyLedger.event(unit, {'bad-step'}, date),
        'pc',
      );
      final ledger = StudyLedger(
        progress,
        now: date.add(const Duration(days: 1)),
      );
      expect(ledger.due(topic), isTrue);
      expect(ledger.reviewUnit(topic).id, unit.id);
      expect(unit.forReview().steps.every((s) => !s.informational), isTrue);
      expect(unit.forReview().steps.isNotEmpty, isTrue);
      expect(ledger.xp, 20);
    },
  );

  test(
    'Actual SQL and Python execution validates the study gap, and rejects a wrong program',
    () async {
      final catalog = StudyCatalog.decode(
        File('assets/content/study_path.json').readAsStringSync(),
      );
      final courses =
          (jsonDecode(File('assets/content/courses.json').readAsStringSync())
                  as List)
              .map((j) => Course(j))
              .toList();
      final runner = LocalRunner();
      for (final lang in ['sql', 'python']) {
        final course = courses.firstWhere((c) => c.id == lang);
        final lesson = course.lessons.first;
        final code = catalog.topics[lesson.id]!.rounds.last.steps.firstWhere(
          (s) => s.kind == 'code',
        );
        final result = await evaluateStudyCode(
          runner,
          course,
          lesson,
          code,
          code.answer,
        );
        expect(result.passed, isTrue, reason: '$lang: ${result.report}');
        final wrong = await evaluateStudyCode(
          runner,
          course,
          lesson,
          code,
          'definitely_invalid_token',
        );
        expect(wrong.passed, isFalse, reason: lang);
      }
    },
  );
}
