import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/sound.dart';
import 'package:devcat/core/store.dart';
import 'package:devcat/core/study.dart';
import 'package:devcat/ui/study_session.dart';
import 'package:devcat/ui/study_hub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class StudyWidgetStore extends AppStore {
  StudyWidgetStore() : super(Directory('/tmp/devcat-study-ui')) {
    device = 'study-ui';
    settings = {'onboarded': true, 'cat': false, 'catChatter': false};
  }
  @override
  Future<void> save() async {}
}

Map<String, dynamic> unitData() => {
  'id': 'python.zero.start:0',
  'title': 'Знакомство',
  'level': 0,
  'steps': [
    {
      'id': 'learn',
      'kind': 'learn',
      'prompt': 'Одна понятная идея',
      'text': 'print показывает текст.',
    },
    {
      'id': 'choice',
      'kind': 'choice',
      'prompt': 'Выбери верный ответ',
      'options': ['YES', 'NO', 'LATER'],
      'answer': 'YES',
      'why': 'Верный ответ объяснён здесь.',
    },
    {
      'id': 'write',
      'kind': 'write',
      'prompt': 'Напиши команду вывода',
      'answer': 'print',
      'why': 'print показывает текст.',
    },
    {
      'id': 'order',
      'kind': 'order',
      'prompt': 'Собери команду',
      'pieces': ['print', '(', '"Hello"', ')'],
      'why': 'Восстанови порядок команды.',
    },
  ],
};

void main() {
  final courses =
      (jsonDecode(File('assets/content/courses.json').readAsStringSync())
              as List)
          .map((j) => Course(j))
          .toList();
  final course = courses.firstWhere((c) => c.id == 'python');
  final topic = StudyTopic({
    'id': course.lessons.first.id,
    'course': 'python',
    'title': 'Первая тема',
    'chapter': 'С нуля',
    'index': 0,
    'rounds': [unitData()],
  });

  for (final size in [
    const Size(1280, 900),
    const Size(390, 844),
    const Size(390, 640),
    const Size(844, 390),
  ]) {
    testWidgets(
      'Short session corrects an error, checks typed and assembled answers, and awards XP at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final store = StudyWidgetStore();
        final sounds = SoftSounds()..enabled = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const ValueKey('open-session'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StudySessionPage(
                        topic: topic,
                        unit: StudyUnit(unitData()),
                        course: course,
                        lesson: course.lessons.first,
                        store: store,
                        sounds: sounds,
                        onPractice: () {},
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('open-session')));
        await tester.pumpAndSettle();
        expect(find.text('Одна понятная идея'), findsOneWidget);
        await tester.tap(find.text('ПРОДОЛЖИТЬ'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('NO'));
        await tester.tap(find.text('NO'));
        await tester.pump();
        await tester.tap(find.text('ПРОВЕРИТЬ'));
        await tester.pumpAndSettle();
        expect(find.text('Разберём и попробуем ещё раз'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('choice:option:1')),
            matching: find.byIcon(Icons.close_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('choice:option:0')),
            matching: find.byIcon(Icons.check_rounded),
          ),
          findsOneWidget,
        );
        expect(StudyLedger(store.progress).xp, 0);
        await tester.tap(find.text('ПРОДОЛЖИТЬ'));
        await tester.pumpAndSettle();
        expect(find.text('Напиши команду вывода'), findsOneWidget);
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'print');
        await tester.pump();
        if (size.height > 600 && size.width < 600) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('ПРОВЕРИТЬ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ПРОДОЛЖИТЬ'));
        await tester.pumpAndSettle();
        for (var i = 0; i < 4; i++) {
          final piece = find.byKey(ValueKey('order:piece:$i'));
          await tester.ensureVisible(piece);
          await tester.tap(piece);
          await tester.pump();
        }
        await tester.tap(find.text('ПРОВЕРИТЬ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ПРОДОЛЖИТЬ'));
        await tester.pumpAndSettle();
        expect(
          find.text('Выбери верный ответ'),
          findsOneWidget,
        ); // The missed question returned.
        await tester.ensureVisible(find.text('YES'));
        await tester.tap(find.text('YES'));
        await tester.pump();
        await tester.tap(find.text('ПРОВЕРИТЬ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ПРОДОЛЖИТЬ'));
        await tester.pumpAndSettle();
        expect(find.text('Ещё один шаг сделан!'), findsOneWidget);
        expect(StudyLedger(store.progress).xp, 20);
        expect(
          store.progress.solved,
          isEmpty,
        ); // Quiz completion does not invent an IDE lab pass.
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await sounds.dispose();
      },
    );
  }

  testWidgets(
    'The route keeps future lessons locked while allowing their theory',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = StudyWidgetStore();
      final sounds = SoftSounds()..enabled = false;
      await tester.runAsync(() async {
        await StudyCatalog.load();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyHub(
              course: course,
              courses: courses,
              store: store,
              sounds: sounds,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final locked = find.text(course.lessons[1].title);
      await tester.scrollUntilVisible(
        locked,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(locked);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Пройди открытый шаг маршрута'),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('study-round:${course.lessons[1].id}:0')),
        findsNothing,
      );
      expect(find.text('Подробная теория и примеры'), findsOneWidget);
      expect(StudyLedger(store.progress).xp, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await sounds.dispose();
    },
  );
}
