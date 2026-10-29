import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/sound.dart';
import 'package:devcat/core/store.dart';
import 'package:devcat/core/project.dart';
import 'package:devcat/ui/course_route.dart';
import 'package:devcat/ui/lecture.dart';
import 'package:devcat/ui/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class StudyMemoryStore extends AppStore {
  StudyMemoryStore() : super(Directory('/tmp/devcat-study-memory')) {
    device = 'study-test';
  }
  @override
  Future<void> save() async {}
}

void main() {
  testWidgets(
    'SQL practice shows the actual example result without asking for stdin',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sql = Course(
        (jsonDecode(File('assets/content/courses.json').readAsStringSync())
                as List)
            .firstWhere((c) => c['id'] == 'sql'),
      );
      final lesson = sql.lessons.firstWhere((l) => l.id == 'sql.basics');
      final sounds = SoftSounds()..enabled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspacePage(
              store: StudyMemoryStore(),
              language: 'sql',
              sounds: sounds,
              course: sql,
              lesson: lesson,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ожидаемый результат на учебной базе'), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await sounds.dispose();
    },
  );
  test(
    'Every HTML/CSS lesson opens its own valid project without mutating the course source',
    () {
      final courses =
          (jsonDecode(File('assets/content/courses.json').readAsStringSync())
                  as List)
              .map((c) => Course(c));
      final ids = <String>{};
      for (final course in courses.where(
        (c) => c.id == 'html' || c.id == 'css',
      )) {
        for (final lesson in course.lessons) {
          final project = DevProject.forLesson(course.id, lesson);
          expect(ids.add(project.id), isTrue);
          expect(DevProject.decode(project.encode()).files, project.files);
          expect(project.entry, 'index.html');
          expect(project.files['index.html'], lesson.webExample['index.html']);
          project.files['index.html'] = 'My own change';
          expect(lesson.webExample['index.html'], isNot('My own change'));
          expect(DevProject.forLesson(course.id, lesson).id, project.id);
        }
      }
      expect(ids.length, 48);
    },
  );
  final course = Course(
    (jsonDecode(File('assets/content/courses.json').readAsStringSync()) as List)
        .firstWhere((c) => c['id'] == 'python'),
  );
  testWidgets(
    'Read bookmark appears on course route without claiming a passed lab',
    (tester) async {
      final store = StudyMemoryStore();
      await store.draft('reading.${course.lessons.first.id}', '5000');
      var advanced = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LectureView(
              lesson: course.lessons.first,
              course: course,
              store: store,
              onPractice: () {},
              onNext: () => advanced++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text(course.lessons.first.title).first).top,
        inInclusiveRange(0, 600),
      );
      expect(
        store.progress
            .draftsFor('reading.${course.lessons.first.id}')
            .first['text'],
        '5000',
      );
      final next = find.text('Отметить прочитанным и идти дальше');
      await tester.scrollUntilVisible(
        next,
        900,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 100,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(advanced, 1);
      expect(
        store.progress
            .draftsFor('learned.${course.lessons.first.id}')
            .first['text'],
        'read',
      );
      expect(store.progress.solved, isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourseRouteSheet(course: course, store: store, current: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Прочитано 1 из 56'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Mobile lesson starts with the condition and copies its actual sample input',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = StudyMemoryStore();
      final sounds = SoftSounds()..enabled = false;
      final lesson = course.lessons.firstWhere(
        (l) => l.id == 'python.zero.input',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspacePage(
              store: store,
              language: 'python',
              sounds: sounds,
              course: course,
              lesson: lesson,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Условие'), findsOneWidget);
      expect(find.text('Запустить'), findsNothing);
      await tester.tap(find.text('Редактор'));
      await tester.pumpAndSettle();
      final input = tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere(
            (field) =>
                field.decoration?.labelText == 'Данные для программы (вход)',
          );
      expect(
        input.controller!.text,
        (lesson.runnableExample!['tests'] as List).first['input'],
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await sounds.dispose();
    },
  );
}
