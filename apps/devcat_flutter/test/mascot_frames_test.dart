import 'package:devcat/core/mascot.dart';
import 'package:devcat/ui/mascot_frames.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget scene({
  bool enabled = true,
  bool reduced = false,
  bool playing = true,
  String state = 'talk',
  String appearance = 'student',
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: TickerMode(
      enabled: enabled,
      child: MascotFrames(
        appearance: appearance,
        state: state,
        size: 96,
        playing: playing,
      ),
    ),
  ),
);

String displayedFrame(WidgetTester tester) =>
    (tester.widget<Image>(find.byType(Image).first).image as AssetImage)
        .assetName;

void main() {
  testWidgets('A completed gallery clip can be played again', (tester) async {
    await tester.runAsync(MascotCatalog.load);
    await tester.pumpWidget(scene(state: 'happy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(displayedFrame(tester), contains('happy-003.png'));
    await tester.pumpWidget(scene(state: 'happy', playing: false));
    await tester.pumpWidget(scene(state: 'happy'));
    await tester.pump();
    expect(displayedFrame(tester), contains('happy-000.png'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(displayedFrame(tester), contains('happy-001.png'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A hidden screen preserves its frame across a long pause', (
    tester,
  ) async {
    await tester.runAsync(MascotCatalog.load);
    await tester.pumpWidget(scene());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final before = displayedFrame(tester);
    await tester.pumpWidget(scene(enabled: false));
    await tester.pump(const Duration(seconds: 13));
    expect(displayedFrame(tester), before);
    await tester.pumpWidget(scene());
    await tester.pump();
    expect(displayedFrame(tester), before);
    await tester.pump(const Duration(milliseconds: 150));
    expect(displayedFrame(tester), isNot(before));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Background time does not become animation elapsed time', (
    tester,
  ) async {
    await tester.runAsync(MascotCatalog.load);
    await tester.pumpWidget(scene());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final before = displayedFrame(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 12));
    expect(displayedFrame(tester), before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(displayedFrame(tester), before);
    await tester.pump(const Duration(milliseconds: 150));
    expect(displayedFrame(tester), isNot(before));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Reduced motion holds a static frame and a missing clip preserves the costume',
    (tester) async {
      await tester.runAsync(MascotCatalog.load);
      await tester.pumpWidget(scene(reduced: true));
      await tester.pump();
      final before = displayedFrame(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(displayedFrame(tester), before);
      await tester.pumpWidget(scene(appearance: 'pirate', state: 'reading'));
      await tester.pump();
      final pirate = displayedFrame(tester);
      expect(pirate, contains('pirate'));
      expect(pirate, isNot(contains('student')));
      await tester.pump(const Duration(seconds: 10));
      expect(displayedFrame(tester), pirate);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
