import 'package:devcat/core/mascot_playback.dart';
import 'package:devcat/core/mascot_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, MascotClip> clips() => {
    'idle': MascotClip(durations: [350], loop: true),
    'walk': MascotClip(durations: [100, 100], loop: true, priority: 30),
    'run': MascotClip(durations: [70, 70], loop: true, priority: 30),
    'jump': MascotClip(durations: [100, 100], priority: 40),
    'land': MascotClip(durations: [100, 100], priority: 40),
  };
  test('Movement stays in its stage at either boundary and after resize', () {
    final stage = MascotStage(clips(), width: 200);
    stage.move(1);
    stage.advance(5000);
    expect(stage.x, 104);
    expect(stage.playback.state, 'idle');
    stage.resize(120);
    expect(stage.x, 24);
    stage.move(-1, running: true);
    stage.advance(5000);
    expect(stage.x, 0);
    expect(stage.playback.state, 'idle');
  });
  test('Queued walking starts only after landing; paused time never moves', () {
    final stage = MascotStage(clips());
    stage.jump();
    expect(stage.move(1), isFalse);
    stage.advance(200);
    expect(stage.playback.state, 'land');
    expect(stage.x, 0);
    stage.advance(300);
    expect(stage.playback.state, 'walk');
    expect(stage.x, greaterThan(0));
    final x = stage.x;
    stage.playback.pause();
    stage.advance(50000);
    expect(stage.x, x);
    stage.dispose();
    stage.advance(1000);
    expect(stage.x, x);
  });
}
