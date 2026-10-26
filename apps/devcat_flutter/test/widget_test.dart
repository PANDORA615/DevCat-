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
  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets('Home → lesson and settings render at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      await tester.tap(find.text('Продолжить обучение'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Проверить'), findsOneWidget);
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
