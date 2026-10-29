import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/store.dart';
import 'package:devcat/ui/lecture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class LectureMemoryStore extends AppStore {
  LectureMemoryStore() : super(Directory('/tmp/devcat-lecture-test')) {
    device = 'lecture-test';
  }
  @override
  Future<void> save() async {}
}

void main() {
  test(
    'Rewritten questions keep old answer drafts separate and intact',
    () async {
      final store = LectureMemoryStore();
      final lesson = Lesson({
        'id': 'python.types',
        'title': 'Types',
        'theory': '',
        'questions': ['New question'],
        'questionRevision': 3,
        'kind': 'review',
        'examples': [],
        'mistakes': [],
      });
      final oldKey = 'answer.${lesson.id}.0';
      await store.draft(oldKey, 'Old answer');
      expect(store.progress.draftsFor(lesson.answerDraftKey(0)), isEmpty);
      await store.draft(lesson.answerDraftKey(0), 'New answer');
      expect(store.progress.draftsFor(oldKey).first['text'], 'Old answer');
      expect(
        store.progress.draftsFor(lesson.answerDraftKey(0)).first['text'],
        'New answer',
      );
      final legacy = Lesson({
        'id': 'sql.select',
        'title': 'Select',
        'theory': '',
        'kind': 'review',
        'examples': [],
        'mistakes': [],
      });
      expect(legacy.answerDraftKey(0), 'answer.sql.select.0');
    },
  );
  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets(
      'Long lecture navigation, data tables and real answers at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final course = Course(
          (jsonDecode(File('assets/content/courses.json').readAsStringSync())
                  as List)
              .firstWhere((c) => c['id'] == 'sql'),
        );
        final lesson = course.lessons.firstWhere((l) => l.id == 'sql.basics');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LectureView(
                lesson: lesson,
                course: course,
                store: LectureMemoryStore(),
                onPractice: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('План занятия'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('План занятия'));
        await tester.pumpAndSettle();
        final contents = find.widgetWithText(
          TextButton,
          '${lesson.sections.indexWhere((s) => s['heading'] == 'Реальный результат приведённого запроса') + 1}. Реальный результат приведённого запроса',
        );
        await tester.ensureVisible(contents);
        await tester.pumpAndSettle();
        await tester.tap(contents);
        await tester.pumpAndSettle();
        final heading = find.text('Реальный результат приведённого запроса');
        expect(tester.getRect(heading).top, inInclusiveRange(0, size.height));
        expect(find.byType(DataTable), findsWidgets);
        expect(tester.takeException(), isNull);
        final reveal = find
            .widgetWithText(TextButton, 'Показать разбор ответа')
            .first;
        await tester.ensureVisible(reveal);
        await tester.pumpAndSettle();
        await tester.tap(reveal);
        await tester.pumpAndSettle();
        expect(find.text(lesson.answers.first), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
