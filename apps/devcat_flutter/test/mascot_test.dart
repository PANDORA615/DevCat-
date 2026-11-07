import 'dart:io';
import 'package:devcat/core/mascot.dart';
import 'package:devcat/core/sound.dart';
import 'package:devcat/ui/cat_actor.dart';
import 'package:devcat/ui/lesson_path_circle.dart';
import 'package:devcat/ui/speech_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class VoiceRecorder extends SoftSounds {
  int count = 0, stops = 0;
  @override
  void speak(CatMood mood) {
    if (enabled && voiceEnabled) count++;
  }

  @override
  Future<void> stopVoice() async {
    stops++;
  }
}

void main() {
  test('Evolution boundaries include senior at 100, architect at 101', () {
    final levels = {
      1: 'beginner',
      10: 'beginner',
      11: 'student',
      25: 'student',
      26: 'developer',
      50: 'developer',
      51: 'middle',
      75: 'middle',
      76: 'senior',
      100: 'senior',
      101: 'architect',
    };
    for (final e in levels.entries) {
      expect(MascotCatalog.evolution(e.key).id, e.value);
    }
  });
  test(
    'Every bundled model and animation frame exists with valid durations',
    () {
      expect(MascotCatalog.appearances.length, 15);
      expect(MascotCatalog.clips.length, 31);
      for (final a in MascotCatalog.appearances) {
        expect(File(a.asset).existsSync(), true);
      }
      for (final c in MascotCatalog.clips.values) {
        expect(c.frames.length, c.durations.length);
        expect(c.durations.every((d) => d > 0), true);
        for (final p in c.frames) {
          expect(File(p).existsSync(), true, reason: p);
        }
      }
    },
  );
  test('Timing, pause, resume, jump landing and correlation cancellation', () {
    final c = CatAnimationController(appearanceId: 'student');
    addTearDown(c.dispose);
    c.play('talk', correlation: 'old');
    c.advance(105);
    expect(c.frame, 1);
    c.pause();
    c.advance(500);
    expect(c.elapsedMs, 105);
    c.resume();
    c.advance(90);
    expect(c.frame, 2);
    c.play('jump', force: true, correlation: 'new');
    c.complete('old');
    expect(c.state, 'jump');
    c.advance(MascotCatalog.clips['jump']!.durationMs);
    expect(c.state, 'land');
    c.advance(MascotCatalog.clips['land']!.durationMs);
    expect(c.state, 'idle');
    c.play('error');
    expect(c.play('walk'), false);
    c.cancel();
    expect(c.state, 'idle');
    expect(c.elapsedMs, 0);
  });
  test('Missing costume animations never change the selected cat', () {
    final c = CatAnimationController(appearanceId: 'pirate');
    addTearDown(c.dispose);
    expect(c.play('talk'), false);
    expect(c.appearanceId, 'pirate');
    expect(c.asset, contains('costumes/pirate.png'));
    expect(c.diagnostic, isNotNull);
  });
  test('Speech budget ignores punctuation and bounds long utterances', () {
    final b = SpeechBudget();
    expect(b.request('?! …', 100), false);
    expect(b.request('кот', 200), true);
    expect(b.request('кот!', 300), false);
    for (var i = 2; i < 40; i++) {
      b.request('кот' * i, i * 50);
    }
    expect(b.syllables, 24);
    expect(SpeechBudget().request('кот', 4000), false);
  });
  testWidgets('Reveal is bounded and skip and background stop speech', (
    tester,
  ) async {
    final voice = VoiceRecorder();
    Widget app(bool instant) => MaterialApp(
      home: Scaffold(
        body: SpeechText(
          text: 'Кот помогает читать код.',
          mood: CatMood.explaining,
          sounds: voice,
          instant: instant,
        ),
      ),
    );
    await tester.pumpWidget(app(false));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 35));
    }
    expect(voice.count, 1);
    await tester.pumpWidget(app(true));
    final stopped = voice.count;
    await tester.pump(const Duration(seconds: 1));
    expect(voice.count, stopped);
    expect(find.text('Кот помогает читать код.'), findsOneWidget);
    await tester.pumpWidget(app(false));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(voice.count, stopped);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('External gallery controller retains its chosen appearance', (
    tester,
  ) async {
    final c = CatAnimationController(appearanceId: 'student');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(home: CatActor(size: 100, controller: c)),
    );
    expect(c.appearanceId, 'student');
    c.play('blink');
    await tester.pump(const Duration(milliseconds: 110));
    expect(c.state, 'blink');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('Map circle, ring and glyph align at text scale $scale', (
      tester,
    ) async {
      for (final levels in [0, 1, 2, 3]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: LessonPathCircle(
                    levels: levels,
                    active: true,
                    unlocked: levels > 0,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        final center = tester.getCenter(
          find.byKey(const ValueKey('lesson-body')),
        );
        expect(
          tester.getCenter(find.byKey(const ValueKey('lesson-ring'))),
          center,
        );
        expect(
          tester.getCenter(find.byKey(const ValueKey('lesson-icon'))),
          center,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }
}
