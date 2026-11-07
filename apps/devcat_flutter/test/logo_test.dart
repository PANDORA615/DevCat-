import 'dart:ui' as ui;
import 'package:devcat/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Supplied v5 brand colors stay intact in every theme', (
    tester,
  ) async {
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
          tester.widget<Image>(find.byType(Image)).image,
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
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
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
    expect(green, blue);
    expect(blue, dark);
    for (final colors in [green, blue, dark]) {
      expect(colors[3], 255);
      expect(colors[7], 255);
    }
    expect(tester.takeException(), isNull);
  });
}
