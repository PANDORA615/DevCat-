import 'package:devcat/core/mascot.dart';
import 'package:devcat/core/speech.dart';
import 'package:devcat/core/sound.dart';
import 'package:devcat/ui/cat_dialogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class VoiceLog extends SoftSounds {
  final pulses = <int>[];
  final finished = <int>[];
  @override
  void syllable(int token, CatMood mood, {bool question = false}) =>
      pulses.add(token);
  @override
  void finishSpeech(int token) {
    finished.add(token);
    super.finishSpeech(token);
  }
}

void main() {
  test('Evolution boundary is senior at 100 and architect from 101', () {
    expect(
      [
        1,
        10,
        11,
        25,
        26,
        50,
        51,
        75,
        76,
        100,
        101,
      ].map(MascotCatalog.evolution),
      [
        'beginner',
        'beginner',
        'student',
        'student',
        'developer',
        'developer',
        'middle',
        'middle',
        'senior',
        'senior',
        'architect',
      ],
    );
  });
  test('Frame durations follow elapsed time, looping and final frame', () {
    expect(mascotFrame([100, 90, 110], 99, loop: true), 0);
    expect(mascotFrame([100, 90, 110], 100, loop: true), 1);
    expect(mascotFrame([100, 90, 110], 190, loop: true), 2);
    expect(mascotFrame([100, 90, 110], 300, loop: true), 0);
    expect(mascotFrame([100, 90, 110], 900, loop: false), 2);
    expect(() => mascotFrame([0], 0, loop: true), throwsArgumentError);
  });
  testWidgets('Whole graphemes, pauses, skip and dispose stop the timeline', (
    tester,
  ) async {
    var pulses = 0, stops = 0;
    final timeline = SpeechTimeline(
      onSyllable: () => pulses++,
      onStop: () => stops++,
    );
    timeline.start('Кот 👩‍💻, давай!');
    await tester.pump(const Duration(milliseconds: 32 * 5));
    expect(timeline.text, 'Кот 👩‍💻');
    await tester.pump(const Duration(milliseconds: 32));
    expect(timeline.text, 'Кот 👩‍💻,');
    expect(timeline.talking, false);
    final before = pulses;
    timeline.reveal();
    await tester.pump(const Duration(seconds: 1));
    expect(timeline.text, 'Кот 👩‍💻, давай!');
    expect(pulses, before);
    expect(timeline.talking, false);
    expect(stops, greaterThanOrEqualTo(2));
    timeline.dispose();
  });
  testWidgets(
    'Dialogue cancel cannot leave a voice or mouth running on a new route',
    (tester) async {
      final voice = VoiceLog();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                CatDialogue(
                  'Привет, давай разберём программу вместе.',
                  sounds: voice,
                ),
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const Scaffold(body: Text('Другой экран')),
                      ),
                    ),
                    child: const Text('Уйти'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 160));
      expect(voice.pulses, isNotEmpty);
      await tester.tap(find.text('Уйти'));
      await tester.pumpAndSettle();
      final before = voice.pulses.length;
      await tester.pump(const Duration(seconds: 1));
      expect(voice.pulses.length, before);
      expect(voice.finished, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      await voice.dispose();
    },
  );
}
