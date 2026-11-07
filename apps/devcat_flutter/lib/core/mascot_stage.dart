import 'dart:math';
import 'mascot_playback.dart';

/// The mascot may move only inside its own preview stage, never over an editor.
class MascotStage {
  final MascotPlayback playback;
  final double spriteSize;
  double width, x = 0;
  double _speed = 36;
  double get speed => _speed;
  set speed(double value) {
    _speed = value.clamp(20, 100);
    _retime();
  }

  void _retime() {
    final current = playback.clips[playback.state];
    final fraction = current == null
        ? 0.0
        : playback.elapsedMs / current.duration;
    for (final action in ['walk', 'run']) {
      final old = playback.clips[action];
      if (old == null) continue;
      // One authored gait step is one logical pixel: match its travel time.
      final stepMs =
          (1000 * spriteSize / 32 / (_speed * (action == 'run' ? 2 : 1)))
              .round();
      playback.clips[action] = MascotClip(
        durations: List.filled(old.durations.length, stepMs),
        loop: old.loop,
        next: old.next,
        priority: old.priority,
      );
    }
    if (playback.state == 'walk' || playback.state == 'run') {
      final duration = playback.clips[playback.state]!.duration;
      playback.elapsedMs = (fraction * duration).round().clamp(0, duration - 1);
    }
  }

  int direction = 1;
  MascotStage(
    Map<String, MascotClip> clips, {
    this.width = 400,
    this.spriteSize = 96,
  }) : playback = MascotPlayback(Map.of(clips), ambient: false) {
    _retime();
  }
  double get maximumX => max(0, width - spriteSize);
  void resize(double value) {
    width = max(spriteSize, value);
    x = x.clamp(0, maximumX);
  }

  bool move(int sign, {bool running = false}) {
    direction = sign < 0 ? -1 : 1;
    return playback.play(running ? 'run' : 'walk');
  }

  bool jump() => playback.play('jump');
  void stop() => playback.play('idle');
  void advance(int milliseconds) {
    if (playback.paused || playback.disposed) return;
    var remaining = milliseconds;
    while (remaining > 0) {
      final step = min(16, remaining);
      if (playback.state == 'walk' || playback.state == 'run') {
        final factor = playback.state == 'run' ? 2 : 1;
        final next = x + direction * speed * factor * step / 1000;
        x = next.clamp(0, maximumX);
        if (next != x) playback.play('idle', force: true);
      }
      playback.advance(step);
      remaining -= step;
    }
  }

  void dispose() => playback.dispose();
}
