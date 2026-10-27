import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

enum SoundCue { tap, navigation, open, toggle, save, hint, success, error }

enum CatMood {
  greeting,
  explaining,
  thinking,
  encouragement,
  celebration,
  warning,
}

/// All fourteen samples supplied by the owner are bundled for offline playback.
class SoftSounds {
  final Map<String, AudioPlayer> _players = {};
  bool enabled = true, voiceEnabled = true;
  int generation = 0;
  double volume = .22, voiceVolume = .18;
  String voiceStyle = 'auto';
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static const cues = {
    SoundCue.tap: '01_Soft_Click',
    SoundCue.navigation: '02_Bubble',
    SoundCue.open: '03_Glass',
    SoundCue.error: '04_Digital',
    SoundCue.save: '05_Wood',
    SoundCue.toggle: '06_Pop',
    SoundCue.success: '07_Crystal',
    SoundCue.hint: '08_Retro_Select',
  };
  static const voices = {
    CatMood.greeting: '09_Voice_Classic_8bit',
    CatMood.encouragement: '10_Voice_Cute',
    CatMood.thinking: '11_Voice_Robot',
    CatMood.warning: '12_Voice_Monster',
    CatMood.celebration: '13_Voice_Magic_NPC',
    CatMood.explaining: '14_Voice_Retro_Radio',
  };
  void tap() => cue(SoundCue.tap);
  void cue(SoundCue cue) {
    if (!enabled) return;
    generation++;
    final now = DateTime.now();
    if (cue == SoundCue.tap && now.difference(_last).inMilliseconds < 90) {
      return;
    }
    _last = now;
    unawaited(_play('effect', cues[cue]!, volume));
  }

  Future<void> result(bool success) async =>
      cue(success ? SoundCue.success : SoundCue.error);
  void speak(CatMood mood) {
    if (!enabled || !voiceEnabled) return;
    final selected = voiceStyle == 'auto'
        ? voices[mood]!
        : voices.values.firstWhere(
            (v) => v == voiceStyle,
            orElse: () => voices[mood]!,
          );
    unawaited(_play('voice', selected, voiceVolume));
  }

  Future<void> stopVoice() async {
    try {
      await _players['voice']?.stop();
    } catch (_) {
      /* Optional audio. */
    }
  }

  Future<void> _play(String channel, String name, double level) async {
    try {
      final player = _players.putIfAbsent(channel, AudioPlayer.new);
      await player.stop();
      await player.play(
        AssetSource('audio/$name.wav'),
        volume: level.clamp(0, 1),
      );
    } catch (_) {
      /* Navigation and lessons remain available without audio. */
    }
  }

  Future<void> dispose() async {
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
