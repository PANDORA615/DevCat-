import 'package:devcat/core/mascot_playback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, MascotClip> clips() => {
    'idle': MascotClip(durations: [350, 350, 350, 350], loop: true),
    'blink': MascotClip(durations: [100, 60, 70, 60]),
    'sleeping': MascotClip(durations: [450, 450], loop: true),
    'success': MascotClip(durations: [120, 120], priority: 80),
  };
  test('Ambient cat rests after a minute despite intermediate blinks', () {
    final playback = MascotPlayback(clips(), seed: 17);
    playback.advance(59999);
    expect(playback.state, isNot('sleeping'));
    playback.advance(1);
    expect(playback.state, 'sleeping');
    expect(playback.wake(), isTrue);
    expect(playback.state, 'idle');
    playback.advance(59000);
    expect(playback.state, isNot('sleeping'));
    playback
        .wake(); // Real input postpones rest even before the cat falls asleep.
    playback.advance(2000);
    expect(playback.state, isNot('sleeping'));
  });
  test(
    'Paused time does not count toward rest and results interrupt sleep',
    () {
      final playback = MascotPlayback(clips());
      playback.advance(59000);
      playback.pause();
      playback.advance(120000);
      expect(playback.state, isNot('sleeping'));
      playback.resume();
      playback.advance(1000);
      expect(playback.state, 'sleeping');
      expect(playback.play('success'), isTrue);
      expect(playback.state, 'success');
      playback.dispose();
      expect(playback.wake(), isFalse);
    },
  );
  test('Gallery mode never adds unsolicited resting poses', () {
    final playback = MascotPlayback(clips(), ambient: false);
    playback.advance(120000);
    expect(playback.state, 'idle');
  });
}
