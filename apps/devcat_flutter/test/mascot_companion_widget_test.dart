import 'package:devcat/core/cat_chatter.dart';
import 'package:devcat/core/sound.dart';
import 'package:devcat/ui/companion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class SilentVoice extends SoftSounds {
  int stops = 0;
  @override
  bool get voiceBusy => false;
  @override
  void speak(CatMood mood) {}
  @override
  Future<void> stopVoice() async {
    stops++;
  }
}

Widget harness(SilentVoice sounds, {bool reducedMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Scaffold(
      body: CompanionBar(
        sounds: sounds,
        autoTalk: false,
        conversation: const CompanionContext(CompanionPlace.practice),
      ),
    ),
  ),
);

void main() {
  testWidgets('visible dialogue can be skipped without leaving speech active', (
    tester,
  ) async {
    final sounds = SilentVoice();
    await tester.pumpWidget(harness(sounds));
    await tester.tap(find.byTooltip('Ещё реплика'));
    await tester.pump();
    expect(find.byTooltip('Показать реплику целиком'), findsOneWidget);
    await tester.tap(find.byTooltip('Показать реплику целиком'));
    await tester.pump();
    expect(find.byTooltip('Показать реплику целиком'), findsNothing);
    expect(sounds.stops, greaterThanOrEqualTo(1));
    await tester.pump(const Duration(seconds: 10));
    expect(find.byTooltip('Показать реплику целиком'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion shows complete dialogue immediately', (
    tester,
  ) async {
    final sounds = SilentVoice();
    await tester.pumpWidget(harness(sounds, reducedMotion: true));
    await tester.tap(find.byTooltip('Ещё реплика'));
    await tester.pump();
    expect(find.byTooltip('Показать реплику целиком'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('background pauses reveal and does not resume old dialogue', (
    tester,
  ) async {
    final sounds = SilentVoice();
    await tester.pumpWidget(harness(sounds));
    await tester.tap(find.byTooltip('Ещё реплика'));
    await tester.pump();
    expect(find.byTooltip('Показать реплику целиком'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.byTooltip('Показать реплику целиком'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byTooltip('Показать реплику целиком'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
