import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

class SoftSounds {
  AudioPlayer? _tap, _result;
  bool enabled = true;
  double volume = .22;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  void tap() {
    if (!enabled || DateTime.now().difference(_last).inMilliseconds < 90) {
      return;
    }
    _last = DateTime.now();
    unawaited(_play(_tap ??= AudioPlayer(), 'tap'));
  }

  Future<void> result(bool success) => enabled
      ? _play(_result ??= AudioPlayer(), success ? 'success' : 'error')
      : Future.value();
  Future<void> _play(AudioPlayer player, String name) async {
    try {
      await player.play(AssetSource('audio/$name.wav'), volume: volume);
    } catch (_) {
      /* Sound is never required for navigation. */
    }
  }

  Future<void> dispose() async {
    await _tap?.dispose();
    await _result?.dispose();
  }
}
