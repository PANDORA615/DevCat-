import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/sound.dart';
import 'package:devcat/core/store.dart';
import 'package:devcat/core/study.dart';
import 'package:devcat/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Main navigation moves in the selected direction', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryStore();
    store.settings['cat'] = false;
    final sounds = SoftSounds()..enabled = false;
    await tester.runAsync(() async {
      await StudyCatalog.load();
    });
    final courses =
        (jsonDecode(File('assets/content/courses.json').readAsStringSync())
                as List)
            .map((item) => Course(item))
            .toList();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: DevCatShell(store: store, courses: courses, sounds: sounds),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Настройки'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final settingsTransition = tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.byKey(const ValueKey(6)),
            matching: find.byType(SlideTransition),
          )
          .first,
    );
    expect(settingsTransition.position.value.dx, greaterThan(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Главная'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final homeTransition = tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.byKey(const ValueKey(0)),
            matching: find.byType(SlideTransition),
          )
          .first,
    );
    expect(homeTransition.position.value.dx, lessThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await sounds.dispose();
  });

  testWidgets('Reduced motion disables shell and sidebar transitions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(
          disableAnimations: true,
          reduceMotion: true,
        );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final store = MemoryStore();
    store.settings['cat'] = false;
    final sounds = SoftSounds()..enabled = false;
    await tester.runAsync(() async {
      await StudyCatalog.load();
    });
    final courses =
        (jsonDecode(File('assets/content/courses.json').readAsStringSync())
                as List)
            .map((item) => Course(item))
            .toList();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: DevCatShell(store: store, courses: courses, sounds: sounds),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher).first)
          .duration,
      Duration.zero,
    );
    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Устройся поудобнее.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await sounds.dispose();
  });

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
        await StudyCatalog.load();
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
      expect(find.text('Твоя цель на сегодня'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('study-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('study-start')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Знакомство'), findsWidgets);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
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
