import 'package:devcat/core/mascot_playback.dart';
import 'package:flutter_test/flutter_test.dart';

MascotClip clip(
  String name,
  List<int> ms, {
  bool loop = false,
  String next = 'idle',
  int priority = 40,
}) => MascotClip(
  id: name,
  frames: [
    for (var i = 0; i < ms.length; i++)
      MascotFrame(
        'animations/student/$name/${i.toString().padLeft(3, '0')}.png',
        ms[i],
      ),
  ],
  loop: loop,
  next: next,
  priority: priority,
);

MascotCatalog approvedCatalog() => MascotCatalog({
  'student': {
    'idle': clip('idle', [100, 150], loop: true, priority: 10),
    'talk': clip(
      'talk',
      [100, 90, 110, 90, 110, 100, 100, 100],
      loop: true,
      priority: 70,
    ),
    'jump': clip(
      'jump',
      [90, 80, 100, 130, 100, 80],
      next: 'land',
      priority: 45,
    ),
    'land': clip('land', [80, 90, 110, 120], priority: 45),
    'error': clip('error', [140, 180, 200, 140], priority: 90),
  },
  'pirate': {
    'idle': MascotClip(
      id: 'idle',
      frames: [const MascotFrame('animations/pirate/idle/000.png', 250)],
      loop: true,
      next: 'idle',
      priority: 10,
    ),
  },
});

void main() {
  test('per-frame elapsed time handles irregular advances and looping', () {
    final p = MascotPlaybackController(
      approvedCatalog(),
      appearance: 'student',
    );
    expect(p.state, 'idle');
    expect(p.frameIndex, 0);
    p.advance(const Duration(milliseconds: 99));
    expect(p.frameIndex, 0);
    expect(p.elapsedMs, 99);
    p.advance(const Duration(milliseconds: 1));
    expect(p.frameIndex, 1);
    p.advance(const Duration(milliseconds: 200));
    expect(p.frameIndex, 0);
    expect(p.elapsedMs, 50);
    p.pause();
    p.advance(const Duration(seconds: 1));
    expect(p.frameIndex, 0);
    expect(p.elapsedMs, 50);
    p.resume();
    p.advance(const Duration(milliseconds: 50));
    expect(p.frameIndex, 1);
  });

  test('jump always finishes through land before idle', () {
    final p = MascotPlaybackController(
      approvedCatalog(),
      appearance: 'student',
    );
    expect(p.play('jump'), isTrue);
    expect(p.play('idle'), isFalse);
    p.advance(const Duration(milliseconds: 580));
    expect(p.state, 'land');
    expect(p.frameIndex, 0);
    p.advance(const Duration(milliseconds: 400));
    expect(p.state, 'idle');
  });

  test('speech start, loop, end follow frames 0-2, 2-6, 6-7', () {
    final p = MascotPlaybackController(
      approvedCatalog(),
      appearance: 'student',
    );
    expect(p.startSpeech(correlationId: 'new'), isTrue);
    expect(p.frameIndex, 0);
    p.advance(const Duration(milliseconds: 100));
    expect(p.frameIndex, 1);
    p.advance(const Duration(milliseconds: 90));
    expect(p.frameIndex, 2);
    p.advance(const Duration(milliseconds: 110));
    expect(p.speechPhase, MascotSpeechPhase.loop);
    expect(p.frameIndex, 2);
    p.advance(const Duration(milliseconds: 110 + 90 + 110 + 100 + 100));
    expect(p.frameIndex, 2);
    p.stopSpeech(correlationId: 'old');
    expect(p.speechPhase, MascotSpeechPhase.loop);
    p.stopSpeech(correlationId: 'new');
    expect(p.speechPhase, MascotSpeechPhase.end);
    expect(p.frameIndex, 6);
    p.advance(const Duration(milliseconds: 100));
    expect(p.frameIndex, 7);
    p.advance(const Duration(milliseconds: 100));
    expect(p.state, 'idle');
  });

  test('old completion cannot cancel a newer dialogue', () {
    final p = MascotPlaybackController(
      approvedCatalog(),
      appearance: 'student',
    );
    p.startSpeech(correlationId: 'first');
    p.startSpeech(correlationId: 'second');
    p.cancel(correlationId: 'first');
    p.stopSpeech(correlationId: 'first');
    expect(p.state, 'talk');
    expect(p.speechPhase, MascotSpeechPhase.start);
    p.cancel(correlationId: 'second');
    expect(p.state, 'idle');
  });

  test('high priority result interrupts speech and deduplicates result', () {
    final p = MascotPlaybackController(
      approvedCatalog(),
      appearance: 'student',
    );
    p.startSpeech(correlationId: 'text');
    expect(p.play('jump'), isFalse);
    expect(p.play('error', correlationId: 'compile-1'), isTrue);
    expect(p.state, 'error');
    p.advance(const Duration(milliseconds: 200));
    final index = p.frameIndex;
    expect(p.play('error', correlationId: 'compile-1'), isTrue);
    expect(p.frameIndex, index);
    p.advance(const Duration(milliseconds: 460));
    expect(p.state, 'idle');
  });

  test('missing costume clips never switch the appearance to student', () {
    final p = MascotPlaybackController(
      approvedCatalog(),
      appearance: 'student',
    );
    p.setAppearance('pirate');
    expect(p.state, 'idle');
    expect(p.asset, 'animations/pirate/idle/000.png');
    expect(p.startSpeech(), isFalse);
    expect(p.appearance, 'pirate');
    expect(p.asset, 'animations/pirate/idle/000.png');
    p.setAppearance('hacker');
    expect(p.asset, isNull);
    expect(p.diagnostics.last, contains('hacker'));
  });

  test('review-only contract assets never enter playback', () {
    final json = {
      'schemaVersion': 5,
      'states': {
        'idle': {
          'appearance': 'student',
          'productionReady': false,
          'frames': ['animations/student/idle/000.png'],
          'durationsMs': [100],
          'requiredFrameCount': 1,
          'loop': true,
          'next': 'idle',
          'priority': 10,
        },
      },
    };
    final catalog = MascotCatalog.fromContract(json);
    final p = MascotPlaybackController(catalog, appearance: 'student');
    expect(p.asset, isNull);
    expect(p.diagnostics, isNotEmpty);
  });

  test('invalid durations and unsafe approved paths are rejected', () {
    expect(() => clip('idle', [0]), throwsArgumentError);
    final bad = {
      'schemaVersion': 5,
      'states': {
        'idle': {
          'appearance': 'student',
          'productionReady': true,
          'frames': ['animations/student/idle/../broken.png'],
          'durationsMs': [100],
          'requiredFrameCount': 1,
          'loop': true,
          'next': 'idle',
          'priority': 10,
        },
      },
    };
    expect(() => MascotCatalog.fromContract(bad), throwsFormatException);
    expect(
      () => MascotCatalog.fromContract({'schemaVersion': 4, 'states': {}}),
      throwsFormatException,
    );
  });

  test('disposed player rejects subsequent operations', () {
    final p = MascotPlaybackController(
      approvedCatalog(),
      appearance: 'student',
    );
    p.dispose();
    expect(p.isDisposed, true);
    expect(() => p.advance(const Duration(milliseconds: 1)), throwsStateError);
  });
}
