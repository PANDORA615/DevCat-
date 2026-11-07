import 'dart:io';
import 'dart:ui' as ui;
import 'package:devcat/core/store.dart';
import 'package:devcat/core/sound.dart';
import 'package:devcat/ui/mascot_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:devcat/ui/cat_actor.dart';
import 'package:flutter_test/flutter_test.dart';

class GalleryStore extends AppStore {
  GalleryStore() : super(Directory('/tmp/devcat-gallery-memory')) {
    device = 'gallery';
  }
  @override
  Future<void> save() async {}
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('Gallery renders actual v5 assets and controls at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        for (final entry in {
          'Nunito': 'assets/fonts/Nunito.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final loader = FontLoader(entry.key)
            ..addFont(rootBundle.load(entry.value));
          await loader.load();
        }
      });
      final boundary = GlobalKey();
      final sounds = SoftSounds()..enabled = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Nunito',
            colorSchemeSeed: Colors.deepPurple,
          ),
          home: RepaintBoundary(
            key: boundary,
            child: MascotGallery(store: GalleryStore(), sounds: sounds),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const ResizeImage(
            AssetImage('assets/mascot/models/evolution/beginner.png'),
            width: 240,
          ),
          boundary.currentContext!,
        ),
      );
      await tester.pump();
      expect(find.text('Галерея DevCat'), findsOneWidget);
      expect(find.text('Новичок'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final capture = Platform.environment['DEVCAT_CAPTURE_DIR'];
      if (capture != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(capture).create(recursive: true);
          await File(
            '$capture/mascot-gallery-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ученик').last);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.widget<CatActor>(find.byType(CatActor)).controller!.appearanceId,
        'student',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await sounds.dispose();
    });
  }
}
