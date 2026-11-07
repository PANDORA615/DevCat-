import 'dart:math';
import 'package:devcat/core/cat_chatter.dart';
import 'package:devcat/core/sound.dart';
import 'package:devcat/ui/companion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingVoice extends SoftSounds {
  final spoken = <CatMood>[];
  @override
  bool get voiceBusy => false;
  @override
  void speak(CatMood mood) {
    if (enabled && voiceEnabled) spoken.add(mood);
  }

  @override
  Future<void> stopVoice() async {}
}

void main() {
  test('Conversation varies and includes the current lesson and language', () {
    final deck = CatChatter(random: Random(42));
    const topic = CompanionContext(
      CompanionPlace.lesson,
      title: 'Условия',
      language: 'python',
    );
    final lines = List.generate(23, (_) => deck.next(topic));
    expect(lines.map((l) => l.text).toSet().length, 23);
    expect(lines.any((l) => l.text.contains('«Условия»')), isTrue);
    expect(lines.any((l) => l.text.contains('Python')), isTrue);
    expect(lines.map((l) => l.mood).toSet().length, greaterThan(3));
    final ide = List.generate(
      22,
      (_) => deck.next(const CompanionContext(CompanionPlace.ide)),
    );
    expect(ide.any((l) => l.text.contains('проект')), isTrue);
    expect(ide.any((l) => l.text.contains('Условия')), isFalse);
  });

  testWidgets(
    'Cat keeps talking, pauses in background and obeys mute and frequency',
    (tester) async {
      final voice = RecordingVoice();
      Widget app({bool automatic = true, int seconds = 20}) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: CompanionBar(
              conversation: const CompanionContext(CompanionPlace.home),
              sounds: voice,
              autoTalk: automatic,
              interval: Duration(seconds: seconds),
            ),
          ),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      Future<void> reveal() async {
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 35));
        }
      }

      await tester.pumpWidget(app());
      await tester.pump(const Duration(seconds: 20));
      await reveal();
      expect(voice.spoken, isNotEmpty);
      var before = voice.spoken.length;
      await tester.pump(const Duration(seconds: 20));
      await reveal();
      expect(voice.spoken.length, greaterThan(before));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      before = voice.spoken.length;
      await tester.pump(const Duration(seconds: 60));
      expect(voice.spoken.length, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      voice.voiceEnabled = false;
      await tester.pump(const Duration(seconds: 20));
      await reveal();
      expect(voice.spoken.length, before);
      voice.voiceEnabled = true;
      await tester.pumpWidget(app(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      await reveal();
      expect(voice.spoken.length, greaterThan(before));
      await tester.pumpWidget(app(automatic: false));
      await tester.pump(const Duration(seconds: 5));
      before = voice.spoken.length;
      await tester.pump(const Duration(seconds: 90));
      expect(voice.spoken.length, before);
      await tester.tap(find.byTooltip('Ещё реплика'));
      await tester.pump();
      await reveal();
      expect(voice.spoken.length, greaterThan(before));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'History remains readable and automatic speech waits for a dialog',
    (tester) async {
      final voice = RecordingVoice();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: CompanionBar(
                conversation: const CompanionContext(CompanionPlace.practice),
                sounds: voice,
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.bySemanticsLabel(RegExp('Открыть историю разговора')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Разговор с котом'), findsOneWidget);
      await tester.pump(const Duration(seconds: 40));
      expect(voice.spoken, isEmpty);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 20));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 35));
      }
      expect(voice.spoken, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
