import 'dart:ui' as ui;
import 'package:devcat/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Logo follows palette and brightness while preserving the black cat',
    (tester) async {
      final key = GlobalKey();
      Future<List<int>> pixel(Color seed, Brightness brightness) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: seed,
                brightness: brightness,
              ),
            ),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: key,
                  child: const DevCatLogo(size: 64),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/branding/icon.png'),
            key.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
        late List<int> result;
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final bytes = data!.buffer.asUint8List();
          final background = (46 * image.width + 24) * 4;
          final cat = (29 * image.width + 42) * 4;
          result = [
            ...bytes.sublist(background, background + 4),
            ...bytes.sublist(cat, cat + 4),
          ];
          image.dispose();
        });
        return result;
      }

      final green = await pixel(Colors.green, Brightness.light);
      final blue = await pixel(Colors.blue, Brightness.light);
      final dark = await pixel(Colors.blue, Brightness.dark);
      expect(green.take(3).toList(), isNot(blue.take(3).toList()));
      expect(blue.take(3).toList(), isNot(dark.take(3).toList()));
      for (final colors in [green, blue, dark]) {
        expect(colors.sublist(4), [0, 0, 0, 255]);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
