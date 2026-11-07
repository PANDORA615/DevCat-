import 'package:devcat/core/mascot.dart';
import 'package:devcat/ui/cat_actor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Speech pulses preserve the gesture frame and selected costume', (
    tester,
  ) async {
    await tester.runAsync(MascotCatalog.load);
    Widget scene(bool talking, int shape) => MaterialApp(
      home: MascotScope(
        appearance: 'pirate',
        child: CatActor(
          size: 128,
          action: 'happy',
          talking: talking,
          mouthShape: shape,
        ),
      ),
    );
    String body() =>
        (tester.widget<Image>(find.byType(Image).first).image as AssetImage)
            .assetName;
    await tester.pumpWidget(scene(true, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final frame = body();
    expect(frame, contains('pirate-happy-001.png'));
    await tester.pumpWidget(scene(false, 0));
    expect(body(), frame, reason: 'A punctuation pause closes only the mouth');
    await tester.pumpWidget(scene(true, 2));
    expect(
      body(),
      frame,
      reason: 'The next syllable does not restart the gesture',
    );
    await tester.pump(const Duration(milliseconds: 130));
    expect(body(), contains('pirate-happy-002.png'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
