import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'mascot_data.dart';
import 'sound.dart';
import 'store.dart';
import 'study.dart';

const mascotAssetRoot = 'assets/mascot/';

/// Separate progression, cosmetic identity and animation state.
class CatAppearance {
  final String id, title, kind, asset;
  final int minLevel;
  const CatAppearance(
    this.id,
    this.title,
    this.kind,
    this.asset,
    this.minLevel,
  );
  factory CatAppearance.fromJson(Map<String, dynamic> j) => CatAppearance(
    j['id'],
    j['title'],
    j['kind'],
    '$mascotAssetRoot${j['asset']}',
    j['minLevel'] ?? 0,
  );
}

class CatClip {
  final String id, title, next;
  final List<String> frames;
  final List<int> durations;
  final bool loop;
  final int priority;
  CatClip(this.id, Map<String, dynamic> j)
    : title = j['title'],
      next = j['next'],
      loop = j['loop'],
      priority = j['priority'],
      frames = (j['frames'] as List).map((p) => '$mascotAssetRoot$p').toList(),
      durations = List<int>.from(j['durationsMs']) {
    if (frames.isEmpty ||
        frames.length != durations.length ||
        durations.any((d) => d <= 0)) {
      throw FormatException('Invalid clip: $id');
    }
  }
  int get durationMs => durations.fold(0, (a, b) => a + b);
  int frameAt(int elapsedMs) {
    var time = loop
        ? elapsedMs % durationMs
        : elapsedMs.clamp(0, durationMs - 1);
    for (var i = 0; i < durations.length; i++) {
      if (time < durations[i]) return i;
      time -= durations[i];
    }
    return frames.length - 1;
  }
}

class MascotCatalog {
  static final appearances =
      (jsonDecode(mascotAppearanceJson)['appearances'] as List)
          .map((j) => CatAppearance.fromJson(Map<String, dynamic>.from(j)))
          .toList();
  static final clips = <String, CatClip>{
    for (final e
        in (jsonDecode(mascotAnimationJson)['states'] as Map<String, dynamic>)
            .entries)
      if (e.value['kind'] != 'views')
        e.key: CatClip(e.key, Map<String, dynamic>.from(e.value)),
  };

  /// Additional clips are separate from the unchanged uploaded v5 contract.
  static final appearanceClips = <String, Map<String, CatClip>>{
    'student': clips,
    for (final entry
        in (jsonDecode(mascotAppearanceAnimationsJson)['appearances']
                as Map<String, dynamic>)
            .entries)
      entry.key: {
        for (final state in (entry.value as Map<String, dynamic>).entries)
          state.key: CatClip(state.key, Map<String, dynamic>.from(state.value)),
      },
  };
  static Map<String, CatClip> clipsFor(String appearanceId) =>
      appearanceClips[appearanceId] ?? const {};
  static String restAsset(String appearanceId) =>
      clipsFor(appearanceId)['idle']?.frames.first ??
      appearance(appearanceId).asset;

  static CatAppearance appearance(String id) => appearances.firstWhere(
    (a) => a.id == id,
    orElse: () => appearances.first,
  );
  static CatAppearance evolution(int level) => appearances.lastWhere(
    (a) => a.kind == 'evolution' && level >= a.minLevel,
    orElse: () => appearances.first,
  );
  static int levelFor(AppStore store) =>
      1 + StudyLedger(store.progress).xp ~/ 100;
  static String selected(AppStore store) {
    final costume = store.setting('catCostume', 'none');
    return appearances.any((a) => a.kind == 'costume' && a.id == costume)
        ? costume
        : evolution(levelFor(store)).id;
  }
}

/// Deterministic clock: renderers supply elapsed wall time, independent of FPS.
/// Unsupported actions retain the selected appearance and its static idle.
class CatAnimationController extends ChangeNotifier {
  String appearanceId, state = 'idle';
  int elapsedMs = 0;
  bool paused = false;
  String? diagnostic, correlationId;
  bool _disposed = false;
  CatAnimationController({String appearanceId = 'beginner'})
    : appearanceId = MascotCatalog.appearance(appearanceId).id;
  Map<String, CatClip> get availableClips =>
      MascotCatalog.clipsFor(appearanceId);
  CatClip get clip => availableClips[state] ?? MascotCatalog.clips['idle']!;
  bool get hasClip => availableClips.containsKey(state);
  String get restAsset => MascotCatalog.restAsset(appearanceId);
  int get frame => hasClip ? clip.frameAt(elapsedMs) : 0;
  String get asset => hasClip
      ? clip.frames[frame]
      : MascotCatalog.appearance(appearanceId).asset;
  void selectAppearance(String id) {
    if (id == appearanceId) return;
    appearanceId = MascotCatalog.appearance(id).id;
    cancel();
  }

  bool play(String id, {String? correlation, bool force = false}) {
    final requested = MascotCatalog.clips[id];
    final available = availableClips[id];
    if (_disposed || requested == null) return false;
    if (!force && requested.priority < clip.priority && state != 'idle') {
      return false;
    }
    correlationId = correlation;
    diagnostic = available != null
        ? null
        : 'Клип «${requested.title}» не подготовлен для выбранной внешности';
    state = available != null ? id : 'idle';
    elapsedMs = 0;
    paused = false;
    notifyListeners();
    return available != null;
  }

  void advance(int milliseconds) {
    if (_disposed || paused || !hasClip || milliseconds <= 0) return;
    final oldAsset = asset;
    var remaining = milliseconds;
    while (remaining > 0) {
      final available = clip.durationMs - elapsedMs;
      if (remaining < available) {
        elapsedMs += remaining;
        break;
      }
      remaining -= available;
      elapsedMs = 0;
      if (!clip.loop) state = clip.next;
    }
    if (oldAsset != asset) notifyListeners();
  }

  void pause() {
    paused = true;
  }

  void resume() {
    if (!_disposed) paused = false;
  }

  void cancel() {
    state = 'idle';
    elapsedMs = 0;
    correlationId = null;
    diagnostic = null;
    if (!_disposed) notifyListeners();
  }

  void complete(String correlation) {
    if (correlationId == correlation) cancel();
  }

  void step(int delta) {
    paused = true;
    final index = (frame + delta) % clip.frames.length;
    elapsedMs = clip.durations.take(index).fold(0, (a, b) => a + b);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String catStateForMood(CatMood mood, {String appearanceId = 'student'}) {
  final preferred = switch (mood) {
    CatMood.greeting => 'greeting',
    CatMood.explaining => 'explaining',
    CatMood.thinking => 'thinking',
    CatMood.encouragement => 'happy',
    CatMood.celebration => 'celebrating',
    CatMood.warning => 'failure',
  };
  if (MascotCatalog.clipsFor(appearanceId).containsKey(preferred)) {
    return preferred;
  }
  return switch (mood) {
    CatMood.greeting || CatMood.encouragement || CatMood.celebration => 'happy',
    CatMood.explaining || CatMood.thinking => 'thinking',
    CatMood.warning => 'error',
  };
}

class MascotScope extends InheritedWidget {
  final String appearanceId;
  const MascotScope({
    super.key,
    required this.appearanceId,
    required super.child,
  });
  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MascotScope>()?.appearanceId ??
      'beginner';
  @override
  bool updateShouldNotify(MascotScope oldWidget) =>
      appearanceId != oldWidget.appearanceId;
}
