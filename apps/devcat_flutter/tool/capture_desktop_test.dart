// Render the real desktop widgets with bundled fonts and fresh local progress.
// Run explicitly: flutter test tool/capture_desktop_test.dart --reporter expanded
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:devcat/core/course.dart';
import 'package:devcat/core/mascot.dart';
import 'package:devcat/core/learning_assets.dart';
import 'package:devcat/core/store.dart';
import 'package:devcat/core/study.dart';
import 'package:devcat/main.dart';
import 'package:devcat/ui/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class PreviewStore extends AppStore {
  PreviewStore() : super(Directory('/tmp/devcat-desktop-preview')) {
    device = 'desktop-preview';
    settings = {
      'onboarded': true,
      'sound': false,
      'cat': true,
      'catChatter': false,
      'reducedMotion': false,
      'theme': 'dark',
      'seedColor': 0xff8b5368,
    };
  }
  @override
  Future<void> save() async {}
}

void main() {
  testWidgets('Capture current desktop screens without changing user data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late List<Course> courses;
    late BuildContext cacheContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            cacheContext = value;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.runAsync(() async {
      for (final name in ['Nunito', 'JetBrainsMono']) {
        await (FontLoader(
          name,
        )..addFont(rootBundle.load('assets/fonts/$name.ttf'))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await MascotCatalog.load();
      final frames = await LearningAssets.bundled.frameFiles();
      for (final path in [
        ...frames.keys,
        'assets/branding/logo_ink.png',
        'assets/branding/logo_primary.png',
        'assets/branding/logo_secondary.png',
        'assets/branding/devcat_book.png',
      ]) {
        if (!cacheContext.mounted) return;
        await precacheImage(
          AssetImage(path, bundle: LearningAssets.bundle),
          cacheContext,
        );
      }
      await StudyCatalog.load();
      courses =
          (jsonDecode(
                    await rootBundle.loadString('assets/content/courses.json'),
                  )
                  as List)
              .map((data) => Course(data))
              .toList();
    });
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: DefaultAssetBundle(
          bundle: LearningAssets.bundle,
          child: DevCatApp(store: PreviewStore(), courses: courses),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        for (final widget
            in tester.widgetList<Image>(find.byType(Image)).toList()) {
          await precacheImage(widget.image, key.currentContext!);
        }
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../../docs/screenshots/0.9.1/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.tap(find.text('Главная').first);
    await tester.pump();
    await tester.pumpAndSettle();
    await capture('home');
    await tester.tap(find.text('Учиться').first);
    await tester.pump();
    await tester.pumpAndSettle();
    await capture('learning-path');
    await tester.tap(find.text('Настройки').first);
    await tester.pump();
    await tester.pumpAndSettle();
    await capture('settings');
    await tester.scrollUntilVisible(
      find.text('Образы и анимации кота'),
      350,
      scrollable: find
          .descendant(
            of: find.byType(SettingsPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Образы и анимации кота'));
    await tester.pumpAndSettle();
    await capture('mascot-gallery');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
