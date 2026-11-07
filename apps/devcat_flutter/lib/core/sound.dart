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

/// Independent UI/voice channels using the owner's 18 unchanged Soft8Bit WAVs.
class SoftSounds {
  final Map<String, AudioPlayer> _players = {};
  final Set<String> _events = {};
  bool enabled = true, voiceEnabled = true;
  int generation = 0, _voiceVariant = 0, _voiceEpoch = 0;
  double volume = .15, voiceVolume = .20, achievementVolume = .15;
  String voiceStyle = 'auto';
  bool _voicePlaying = false, _disposed = false;
  DateTime _voiceUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool get voiceBusy => _voicePlaying;
  static const cues = {
    SoundCue.tap: 'ui_soft_tap',
    SoundCue.navigation: 'ui_soft_switch',
    SoundCue.open: 'ui_soft_open',
    SoundCue.toggle: 'ui_soft_switch',
    SoundCue.save: 'ui_soft_success',
    SoundCue.hint: 'ui_soft_hint',
    SoundCue.success: 'ui_soft_success',
    SoundCue.error: 'ui_soft_error',
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
    CatMood.celebration: 'cat_voice_happy',
    CatMood.warning: 'cat_voice_concern',
  };
  static const voiceDurations = {
    'cat_voice_soft_01': 269,
    'cat_voice_soft_02': 241,
    'cat_voice_soft_03': 327,
    'cat_voice_thinking': 330,
    'cat_voice_happy': 314,
    'cat_voice_concern': 240,
    'cat_voice_question': 284,
  };
  void tap() => cue(SoundCue.tap);
  void cue(SoundCue cue, {String? eventId, String? correlationId}) {
    if (!enabled || _disposed) return;
    if (eventId != null) {
      final key = '$eventId:${correlationId ?? ''}';
      if (!_events.add(key)) return;
      if (_events.length > 256) _events.remove(_events.first);
    }
    generation++;
    unawaited(
      _play(
        'effect',
        cues[cue]!,
        cue == SoundCue.achievement ? achievementVolume : volume,
      ),
    );
  }

  Future<void> result(bool success) async =>
      cue(success ? SoundCue.success : SoundCue.error);

  /// A request is dropped while a WAV is playing; syllables are never queued.
  void speak(CatMood mood) {
    if (!enabled ||
        !voiceEnabled ||
        _disposed ||
        _voicePlaying ||
        DateTime.now().isBefore(_voiceUntil)) {
      return;
    }
    final standard =
        mood == CatMood.greeting ||
        mood == CatMood.explaining ||
        mood == CatMood.encouragement;
    final selected = voiceDurations.containsKey(voiceStyle)
        ? voiceStyle
        : standard
        ? 'cat_voice_soft_0${1 + _voiceVariant++ % 3}'
        : voices[mood]!;
    _voicePlaying = true;
    final epoch = _voiceEpoch;
    _voiceUntil = DateTime.now().add(
      Duration(milliseconds: voiceDurations[selected]!),
    );
    unawaited(_playVoice(selected, epoch));
  }

  Future<void> _playVoice(String name, int epoch) async {
    try {
      final player = _players.putIfAbsent('voice', AudioPlayer.new);
      await player.stop();
      if (epoch != _voiceEpoch || _disposed || !enabled || !voiceEnabled) {
        return;
      }
      await player.play(
        AssetSource('audio/$name.wav'),
        volume: voiceVolume.clamp(0, 1),
      );
      await player.onPlayerComplete.first.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Optional audio must not interrupt learning.
    } finally {
      if (epoch == _voiceEpoch) _voicePlaying = false;
    }
  }

  Future<void> stopVoice() async {
    _voiceEpoch++;
    _voicePlaying = false;
    _voiceUntil = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await _players['voice']?.stop();
    } catch (_) {
      /* Optional audio. */
    }
  }

  Future<void> preview(String name) async {
    if (voiceDurations.containsKey(name)) {
      await stopVoice();
      final old = voiceStyle;
      voiceStyle = name;
      speak(CatMood.greeting);
      voiceStyle = old;
    } else if (cues.containsValue(name)) {
      if (enabled) await _play('effect', name, volume);
    }
  }

  Future<void> _play(String channel, String name, double level) async {
    try {
      final player = _players.putIfAbsent(channel, AudioPlayer.new);
      await player.stop();
      if (_disposed || !enabled) return;
      await player.play(
        AssetSource('audio/$name.wav'),
        volume: level.clamp(0, 1),
      );
    } catch (_) {
      /* UI remains available without audio. */
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await stopVoice();
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }
}

/// Bounds syllable requests for one visible utterance, independently of FPS.
class SpeechBudget {
  int syllables = 0, lastCharacters = 0;
  bool request(String visibleText, int elapsedMs) {
    final letters = visibleText.runes
        .where(
          (r) => RegExp(
            r'[\p{L}\p{N}]',
            unicode: true,
          ).hasMatch(String.fromCharCode(r)),
        )
        .length;
    if (syllables >= 24 || elapsedMs >= 4000 || letters - lastCharacters < 3) {
      return false;
    }
    lastCharacters = letters;
    syllables++;
    return true;
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

/// Use at accepted UI actions, so editor pointer events never trigger taps.
void soundAction(BuildContext context, VoidCallback action) {
  final sounds = SoundScope.of(context);
  final before = sounds?.generation;
  action();
  if (sounds != null && sounds.generation == before) sounds.tap();
}

class SoundNavigationObserver extends NavigatorObserver {
  final SoftSounds sounds;
  SoundNavigationObserver(this.sounds);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) sounds.stopVoice();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    sounds.stopVoice();
    sounds.cue(route is PopupRoute ? SoundCue.close : SoundCue.back);
  }
}
