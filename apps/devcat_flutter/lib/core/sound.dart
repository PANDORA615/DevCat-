import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

enum SoundCue {
  tap,
  navigation,
  open,
  toggle,
  save,
  hint,
  success,
  error,
  back,
  close,
  achievement,
  notification,
  update,
}

enum CatMood {
  greeting,
  explaining,
  thinking,
  encouragement,
  celebration,
  warning,
}

/// One voice channel, independently controlled UI and achievement channels.
class SoftSounds {
  final AudioPlayer Function() _createPlayer;
  SoftSounds({AudioPlayer Function()? createPlayer})
    : _createPlayer = createPlayer ?? AudioPlayer.new;
  final Map<String, AudioPlayer> _players = {};
  bool enabled = true, voiceEnabled = true;
  bool _disposed = false, _voicePlaying = false;
  int generation = 0, _voiceEpoch = 0, _voiceVariant = 0;
  double volume = .15, voiceVolume = .20, achievementVolume = .15;
  String voiceStyle = 'auto';
  Future<void> _voiceOperations = Future.value();
  StreamSubscription<void>? _voiceCompletion;
  final Map<String, DateTime> _events = {};
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  bool get voiceBusy => _voicePlaying;
  static const cues = {
    SoundCue.tap: 'ui_soft_tap',
    SoundCue.navigation: 'ui_soft_switch',
    SoundCue.open: 'ui_soft_open',
    SoundCue.error: 'ui_soft_error',
    SoundCue.save: 'ui_soft_tap',
    SoundCue.toggle: 'ui_soft_switch',
    SoundCue.success: 'ui_soft_success',
    SoundCue.hint: 'ui_soft_hint',
    SoundCue.back: 'ui_soft_back',
    SoundCue.close: 'ui_soft_close',
    SoundCue.achievement: 'ui_soft_achievement',
    SoundCue.notification: 'ui_soft_notification',
    SoundCue.update: 'ui_soft_update',
  };
  static const voices = {
    CatMood.greeting: 'cat_voice_soft_01',
    CatMood.explaining: 'cat_voice_soft_02',
    CatMood.encouragement: 'cat_voice_soft_03',
    CatMood.thinking: 'cat_voice_thinking',
    CatMood.warning: 'cat_voice_concern',
    CatMood.celebration: 'cat_voice_happy',
  };
  static const voiceDurations = {
    'cat_voice_soft_01': 269,
    'cat_voice_soft_02': 241,
    'cat_voice_soft_03': 327,
    'cat_voice_question': 284,
    'cat_voice_happy': 314,
    'cat_voice_thinking': 330,
    'cat_voice_concern': 240,
  };
  void tap() => cue(SoundCue.tap);
  void cue(SoundCue cue, {String? eventId}) {
    generation++;
    if (!enabled || _disposed) return;
    final now = DateTime.now();
    _events.removeWhere((_, time) => now.difference(time).inMinutes >= 5);
    if (eventId != null && _events.containsKey(eventId)) return;
    if (eventId != null) _events[eventId] = now;
    _last = now;
    unawaited(
      _play(
        cue == SoundCue.achievement ? 'achievement' : 'effect',
        cues[cue]!,
        cue == SoundCue.achievement ? achievementVolume : volume,
      ),
    );
  }

  Future<void> result(bool success) async =>
      cue(success ? SoundCue.success : SoundCue.error);

  /// A token prevents a discarded widget from stopping a newer dialogue.
  int claimSpeech() {
    final token = ++_voiceEpoch;
    _voicePlaying = false;
    _queueStop(token);
    return token;
  }

  void finishSpeech(int token) {
    if (token != _voiceEpoch) return;
    final next = ++_voiceEpoch;
    _voicePlaying = false;
    _queueStop(next);
  }

  void syllable(int token, CatMood mood, {bool question = false}) {
    if (token != _voiceEpoch ||
        !enabled ||
        !voiceEnabled ||
        _voicePlaying ||
        _disposed) {
      return;
    }
    final selected = voiceDurations.containsKey(voiceStyle)
        ? voiceStyle
        : question
        ? 'cat_voice_question'
        : [
            CatMood.greeting,
            CatMood.explaining,
            CatMood.encouragement,
          ].contains(mood)
        ? 'cat_voice_soft_0${1 + _voiceVariant++ % 3}'
        : voices[mood]!;
    _voicePlaying = true;
    _voiceOperations = _voiceOperations.then((_) async {
      if (token != _voiceEpoch || !enabled || !voiceEnabled || _disposed) {
        if (token == _voiceEpoch) _voicePlaying = false;
        return;
      }
      try {
        final player = _players.putIfAbsent('voice', _createPlayer);
        await _voiceCompletion?.cancel();
        await player.stop();
        if (token != _voiceEpoch || _disposed) return;
        _voiceCompletion = player.onPlayerComplete.listen((_) {
          if (token == _voiceEpoch) _voicePlaying = false;
        });
        await player.play(
          AssetSource('audio/$selected.wav'),
          volume: voiceVolume.clamp(0, 1),
        );
        // The next syllable waits for native completion, including device latency.
        // Missing completion leaves speech quiet rather than overlapping samples.
      } catch (_) {
        if (token == _voiceEpoch) _voicePlaying = false;
      }
    });
  }

  /// Manual sound preview; normal dialogue uses visible-character pulses.
  void speak(CatMood mood) => syllable(claimSpeech(), mood);
  void previewSample(String id) {
    if (voiceDurations.containsKey(id)) {
      final previous = voiceStyle;
      voiceStyle = id;
      speak(CatMood.greeting);
      voiceStyle = previous;
    } else if (cues.containsValue(id)) {
      cue(cues.entries.firstWhere((e) => e.value == id).key);
    }
  }

  void _queueStop(int token) {
    _voiceOperations = _voiceOperations.then((_) async {
      if (token != _voiceEpoch) return;
      try {
        await _players['voice']?.stop();
      } catch (_) {
        /* Audio is optional. */
      }
    });
  }

  Future<void> stopVoice() async {
    finishSpeech(_voiceEpoch);
    await _voiceOperations;
  }

  Future<void> _play(String channel, String name, double level) async {
    if (_disposed) return;
    try {
      final player = _players.putIfAbsent(channel, _createPlayer);
      await player.stop();
      if (!_disposed && enabled) {
        await player.play(
          AssetSource('audio/$name.wav'),
          volume: level.clamp(0, 1),
        );
      }
    } catch (_) {
      /* Navigation and learning work without audio. */
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await stopVoice();
    await _voiceCompletion?.cancel();
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }
}

class SoundScope extends InheritedWidget {
  final SoftSounds sounds;
  const SoundScope({super.key, required this.sounds, required super.child});
  static SoftSounds? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SoundScope>()?.sounds;
  @override
  bool updateShouldNotify(SoundScope oldWidget) => sounds != oldWidget.sounds;
}

class PointerSoundLayer extends StatefulWidget {
  final SoftSounds sounds;
  final Widget child;
  const PointerSoundLayer({
    super.key,
    required this.sounds,
    required this.child,
  });
  @override
  State<PointerSoundLayer> createState() => _PointerSoundLayerState();
}

class _PointerSoundLayerState extends State<PointerSoundLayer> {
  final Map<int, Offset> starts = {};
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => starts[event.pointer] = event.position,
    onPointerCancel: (event) => starts.remove(event.pointer),
    onPointerUp: (event) {
      final start = starts.remove(event.pointer);
      if (start == null || (event.position - start).distance > 8) return;
      final before = widget.sounds.generation;
      Timer.run(() {
        if (mounted &&
            widget.sounds.generation == before &&
            DateTime.now().difference(widget.sounds._last).inMilliseconds >
                60) {
          widget.sounds.tap();
        }
      });
    },
    child: widget.child,
  );
}
