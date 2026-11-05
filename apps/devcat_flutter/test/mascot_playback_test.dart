import 'package:devcat/core/mascot_playback.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, MascotClip> clips() => {
  'idle': MascotClip(durations: [100, 100], loop: true),
  'blink': MascotClip(durations: [20, 30], priority: 15),
  'jump': MascotClip(durations: [50, 50], next: 'land', priority: 35),
  'land': MascotClip(durations: [40, 60], priority: 35),
  'talk': MascotClip(durations: [70, 30], loop: true, priority: 70),
  'happy': MascotClip(durations: [100, 100], priority: 60),
  'error': MascotClip(durations: [40, 60], priority: 90),
};

void main() {
  test('Pause preserves time within a frame; resume continues that frame', () {
    final actor = MascotPlayback(clips(), ambient: false);
    actor.play('talk');
    actor.advance(63);
    actor.pause();
    actor.advance(900);
    expect(actor.elapsedMs, 63);
    actor.resume();
    actor.advance(8);
    expect(actor.frame, 1);
    expect(actor.elapsedMs, 71);
  });

  test('A repeated command does not restart the same reaction', () {
    final actor = MascotPlayback(clips(), ambient: false);
    actor.play('happy', correlation: 'answer-1');
    actor.advance(150);
    actor.play('happy', correlation: 'answer-1');
    expect(actor.elapsedMs, 150);
    actor.play('happy', correlation: 'answer-2');
    expect(actor.elapsedMs, 0);
  });

  test(
    'Jump finishes land before a normal reaction, preserving spare time',
    () {
      final actor = MascotPlayback(clips(), ambient: false);
      actor.play('jump');
      actor.advance(90);
      expect(actor.play('talk', correlation: 'speech'), isFalse);
      actor.advance(10);
      expect(actor.state, 'land');
      actor.advance(125);
      expect(actor.state, 'talk');
      expect(actor.elapsedMs, 25);
      expect(actor.correlationId, 'speech');
    },
  );

  test('Critical result interrupts movement and discards queued speech', () {
    final actor = MascotPlayback(clips(), ambient: false);
    actor.play('jump');
    actor.play('talk', correlation: 'speech');
    expect(actor.play('error', correlation: 'result'), isTrue);
    expect(actor.state, 'error');
    expect(actor.play('happy'), isFalse);
    actor.advance(500);
    expect(actor.state, 'idle');
  });

  test('Cancel from an old owner does not cancel a newer speech', () {
    final actor = MascotPlayback(clips(), ambient: false);
    actor.play('talk', correlation: 'new');
    actor.advance(20);
    actor.cancel(correlation: 'old');
    expect(actor.state, 'talk');
    expect(actor.elapsedMs, 20);
    actor.cancel(correlation: 'new');
    expect(actor.state, 'idle');
    actor.advance(300);
    expect(actor.state, 'idle');
  });

  test(
    'Cancelling queued speech preserves the jump and prevents stale speech',
    () {
      final actor = MascotPlayback(clips(), ambient: false);
      actor.play('jump', correlation: 'move');
      actor.play('talk', correlation: 'speech');
      actor.cancel(correlation: 'speech');
      expect(actor.state, 'jump');
      actor.advance(200);
      expect(actor.state, 'idle');
    },
  );

  test('Ambient blink occurs after 3–7 seconds and returns to idle', () {
    final actor = MascotPlayback(clips(), seed: 5);
    var firstBlink = 0;
    for (var ms = 1; ms <= 7000; ms++) {
      actor.advance(1);
      if (actor.state == 'blink') {
        firstBlink = ms;
        break;
      }
    }
    expect(firstBlink, inInclusiveRange(3000, 7000));
    actor.advance(50);
    expect(actor.state, 'idle');
    actor.play('talk');
    actor.advance(10000);
    expect(actor.state, 'talk');
  });

  test('Timing is independent of refresh rate', () {
    final sixty = MascotPlayback(clips(), ambient: false)..play('jump');
    final high = MascotPlayback(clips(), ambient: false)..play('jump');
    for (final ms in [17, 16, 17, 17, 16, 17, 17, 16, 17]) {
      sixty.advance(ms);
    }
    for (var i = 0; i < 30; i++) {
      high.advance(5);
    }
    expect(sixty.state, high.state);
    expect(sixty.elapsedMs, high.elapsedMs);
    expect(sixty.frame, high.frame);
  });

  test('Gallery holds a non-looping last frame and allows seeking', () {
    final actor = MascotPlayback(
      clips(),
      ambient: false,
      followTransitions: false,
    );
    actor.play('happy');
    actor.advance(300);
    expect(actor.state, 'happy');
    expect(actor.frame, 1);
    actor.seek(0);
    expect(actor.frame, 0);
    expect(actor.completed, isFalse);
  });

  test('An unavailable action falls back without changing appearance data', () {
    final actor = MascotPlayback(clips(), ambient: false)..play('talk');
    expect(actor.play('unprepared'), isFalse);
    expect(actor.state, 'idle');
    final empty = MascotPlayback({}, ambient: false);
    expect(empty.play('talk'), isFalse);
    empty.advance(10000);
    expect(empty.frame, 0);
  });

  test('Disposal makes late completion and commands inert', () {
    final actor = MascotPlayback(clips(), ambient: false)..play('jump');
    actor.advance(20);
    actor.dispose();
    actor.advance(5000);
    actor.cancel();
    actor.resume();
    expect(actor.play('error'), isFalse);
    expect(actor.elapsedMs, 20);
  });

  test('Invalid frame durations are rejected', () {
    expect(() => MascotClip(durations: []), throwsArgumentError);
    expect(() => MascotClip(durations: [10, 0]), throwsArgumentError);
  });
}
