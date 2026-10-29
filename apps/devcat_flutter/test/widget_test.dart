import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/sound.dart';
import 'package:devcat/core/store.dart';
import 'package:devcat/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(1280, 900),
    const Size(390, 844),
    const Size(390, 640),
    const Size(844, 390),
  ]) {
    testWidgets('Home → lesson and settings render at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final store = MemoryStore();
      late List<Course> courses;
      await tester.runAsync(() async {
        courses =
            (jsonDecode(
                      await rootBundle.loadString(
                        'assets/content/courses.json',
                      ),
                    )
                    as List)
                .map((j) => Course(j))
                .toList();
      });
      final sounds = SoftSounds()..enabled = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: DevCatShell(store: store, courses: courses, sounds: sounds),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Продолжить обучение'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продолжить обучение'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('План занятия'), findsOneWidget);
      await tester.tap(find.text('Практика'));
      await tester.pumpAndSettle();
      if (size.width < 760) {
        expect(find.text('Условие'), findsOneWidget);
        await tester.tap(find.text('Редактор'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Запустить'), findsOneWidget);
      if (size.width < 960) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
      }
      if (size.width > 960) {
        await tester.tap(find.text('Настройки'));
      } else {
        await tester.tap(find.text('Ещё'));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Устройся поудобнее.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Дополнительно: личное облако WebDAV'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Дополнительно: личное облако WebDAV').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('Дополнительно: личное облако WebDAV'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Синхронизировать'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(size.width > 960 ? 'DevCat IDE' : 'Код'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Запустить проект'), findsOneWidget);
      if (size.width < 1100) {
        await tester.tap(find.byTooltip('Файлы проекта'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('README.md'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(store.flush);
      await sounds.dispose();
    });
  }
}

class MemoryStore extends AppStore {
  MemoryStore() : super(Directory('/tmp/devcat-widget-memory')) {
    device = 'widget-device';
    settings = {'onboarded': true, 'sound': false, 'cat': true};
  }
  @override
  Future<void> save() async {}
  @override
  Future<void> flush() async {}
}
