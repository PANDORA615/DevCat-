/// Deterministic, frame-duration-driven DevCat v5 animation engine.
///
/// The engine never decodes artwork and never assumes an unreviewed asset is
/// production-ready. A UI ticker calls [advance]; the renderer reads [asset].
/// This intentionally does not use Flutter frame rate as an animation clock.
class MascotFrame {
  const MascotFrame(this.asset, this.durationMs);

  final String asset;
  final int durationMs;
}

class MascotClip {
  MascotClip({
    required this.id,
    required List<MascotFrame> frames,
    required this.loop,
    required this.next,
    required this.priority,
  }) : frames = List.unmodifiable(frames) {
    if (frames.isEmpty ||
        frames.any((frame) => frame.durationMs <= 0 || frame.asset.isEmpty)) {
      throw ArgumentError.value(
        frames,
        'frames',
        'All frames need a path and positive duration',
      );
    }
  }

  final String id;
  final List<MascotFrame> frames;
  final bool loop;
  final String next;
  final int priority;
}

/// Only explicitly approved clips enter the playable catalog.
/// The review archive's productionReady=false frames are never loaded here.
class MascotCatalog {
  MascotCatalog(Map<String, Map<String, MascotClip>> clips)
    : _clips = {
        for (final appearance in clips.entries)
          appearance.key: Map.unmodifiable(appearance.value),
      };

  final Map<String, Map<String, MascotClip>> _clips;

  MascotClip? getClip(String appearance, String state) =>
      _clips[appearance]?[state];

  /// Read the approved subset of v5 animation_contract.json.
  ///
  /// A production pipeline must additionally check each path exists and each
  /// image passed manual visual acceptance before marking productionReady.
  factory MascotCatalog.fromContract(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 5 || json['states'] is! Map) {
      throw const FormatException('Expected DevCat v5 animation contract');
    }
    final clips = <String, Map<String, MascotClip>>{};
    for (final entry in (json['states'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Malformed animation entry');
      }
      final value = entry.value as Map;
      if (value['productionReady'] != true || value['kind'] == 'views') {
        continue;
      }
      final appearance = value['appearance'];
      final paths = value['frames'];
      final durations = value['durationsMs'];
      if (appearance is! String ||
          appearance.isEmpty ||
          paths is! List ||
          durations is! List ||
          paths.length != durations.length ||
          paths.isEmpty ||
          paths.length != value['requiredFrameCount'] ||
          value['loop'] is! bool ||
          value['next'] is! String ||
          value['priority'] is! int) {
        throw FormatException('Invalid approved clip: ${entry.key}');
      }
      final frames = <MascotFrame>[];
      for (var i = 0; i < paths.length; i++) {
        if (paths[i] is! String || durations[i] is! int) {
          throw FormatException('Invalid frame: ${entry.key} index $i');
        }
        final asset = paths[i] as String;
        if (!asset.startsWith('animations/$appearance/${entry.key}/') ||
            asset.contains('..') ||
            !asset.endsWith('/${i.toString().padLeft(3, '0')}.png')) {
          throw FormatException('Unsafe or incorrectly ordered frame: $asset');
        }
        frames.add(MascotFrame(asset, durations[i] as int));
      }
      final map = clips.putIfAbsent(appearance, () => {});
      map[entry.key as String] = MascotClip(
        id: entry.key as String,
        frames: frames,
        loop: value['loop'] as bool,
        next: value['next'] as String,
        priority: value['priority'] as int,
      );
    }
    return MascotCatalog(clips);
  }
}

enum MascotSpeechPhase { none, start, loop, end }

/// The caller is responsible for lifecycle notifications and visible-text
/// cadence; [stopSpeech] must be called when typing ends or is skipped.
class MascotPlaybackController {
  MascotPlaybackController(this.catalog, {required String appearance})
    : _appearance = appearance {
    _returnToIdle();
  }

  final MascotCatalog catalog;
  String _appearance;
  MascotClip? _clip;
  int _index = 0;
  int _elapsedMs = 0;
  bool _paused = false;
  bool _disposed = false;
  bool _endSpeechRequested = false;
  String? _correlationId;
  MascotSpeechPhase _speechPhase = MascotSpeechPhase.none;
  final List<String> diagnostics = [];

  String get appearance => _appearance;
  String? get state => _clip?.id;
  String? get asset => _clip?.frames[_index].asset;
  int get frameIndex => _index;
  int get elapsedMs => _elapsedMs;
  bool get isPaused => _paused;
  bool get isDisposed => _disposed;
  MascotSpeechPhase get speechPhase => _speechPhase;

  /// No cross-costume fallback: absent clips display the same appearance's
  /// approved idle, or no sprite at all, and emit a diagnostic.
  void setAppearance(String appearance) {
    _assertActive();
    if (_appearance == appearance) return;
    _appearance = appearance;
    _correlationId = null;
    _speechPhase = MascotSpeechPhase.none;
    _endSpeechRequested = false;
    _returnToIdle();
  }

  bool play(String state, {String? correlationId}) {
    _assertActive();
    if (state == 'talk') return startSpeech(correlationId: correlationId);
    final clip = catalog.getClip(_appearance, state);
    if (clip == null) {
      diagnostics.add('Missing approved $state for $_appearance');
      _returnToIdle();
      return false;
    }
    if (_clip != null &&
        _clip!.id != 'idle' &&
        clip.priority < _clip!.priority) {
      return false;
    }
    if (_clip?.id == state && _correlationId == correlationId) {
      return true; // Deduplicate repeated results/events.
    }
    _begin(clip, correlationId);
    return true;
  }

  bool startSpeech({String? correlationId}) {
    _assertActive();
    final clip = catalog.getClip(_appearance, 'talk');
    if (clip == null || clip.frames.length != 8) {
      diagnostics.add('Missing approved 8-frame talk for $_appearance');
      _returnToIdle();
      return false;
    }
    if (_clip != null &&
        _clip!.id != 'idle' &&
        clip.priority < _clip!.priority) {
      return false;
    }
    if (_speechPhase != MascotSpeechPhase.none &&
        _correlationId == correlationId) {
      return true;
    }
    _begin(clip, correlationId);
    _speechPhase = MascotSpeechPhase.start;
    return true;
  }

  /// An older dialogue's completion must never stop a newer dialogue.
  void stopSpeech({String? correlationId}) {
    _assertActive();
    if (_speechPhase == MascotSpeechPhase.none ||
        (correlationId != null && correlationId != _correlationId)) {
      return;
    }
    _endSpeechRequested = true;
    if (_speechPhase == MascotSpeechPhase.loop) {
      _speechPhase = MascotSpeechPhase.end;
      _index = 6;
      _elapsedMs = 0;
    }
  }

  void advance(Duration delta) {
    _assertActive();
    if (delta.isNegative) throw ArgumentError.value(delta, 'delta');
    if (_paused || _clip == null) return;
    var remaining = delta.inMilliseconds;
    // Monotonic duration accounting, independent of repaint cadence.
    while (remaining > 0 && _clip != null) {
      final duration = _clip!.frames[_index].durationMs;
      final toBoundary = duration - _elapsedMs;
      if (remaining < toBoundary) {
        _elapsedMs += remaining;
        break;
      }
      remaining -= toBoundary;
      _elapsedMs = 0;
      _nextFrame();
    }
  }

  void pause() {
    _assertActive();
    _paused = true;
  }

  void resume() {
    _assertActive();
    _paused = false;
  }

  /// Cancels only the matching operation when an ID is supplied.
  void cancel({String? correlationId}) {
    _assertActive();
    if (correlationId != null && correlationId != _correlationId) return;
    _returnToIdle();
  }

  void dispose() {
    _clip = null;
    _correlationId = null;
    _disposed = true;
  }

  void _nextFrame() {
    final clip = _clip;
    if (clip == null) return;
    if (_speechPhase == MascotSpeechPhase.start) {
      if (_index < 2) {
        _index++;
      } else if (_endSpeechRequested) {
        _speechPhase = MascotSpeechPhase.end;
        _index = 6;
      } else {
        _speechPhase = MascotSpeechPhase.loop;
        _index = 2;
      }
      return;
    }
    if (_speechPhase == MascotSpeechPhase.loop) {
      _index = _index >= 6 ? 2 : _index + 1;
      return;
    }
    if (_speechPhase == MascotSpeechPhase.end) {
      if (_index == 6) {
        _index = 7;
      } else {
        _returnToIdle();
      }
      return;
    }
    if (_index + 1 < clip.frames.length) {
      _index++;
    } else if (clip.loop) {
      _index = 0;
    } else {
      final next = clip.next;
      if (next == 'idle') {
        _returnToIdle();
      } else {
        final nextClip = catalog.getClip(_appearance, next);
        if (nextClip == null || nextClip.id == clip.id) {
          diagnostics.add(
            'Missing next $next for $_appearance after ${clip.id}',
          );
          _returnToIdle();
        } else {
          _begin(nextClip, _correlationId);
        }
      }
    }
  }

  void _begin(MascotClip clip, String? correlationId) {
    _clip = clip;
    _index = 0;
    _elapsedMs = 0;
    _correlationId = correlationId;
    _speechPhase = MascotSpeechPhase.none;
    _endSpeechRequested = false;
  }

  void _returnToIdle() {
    _clip = catalog.getClip(_appearance, 'idle');
    _index = 0;
    _elapsedMs = 0;
    _speechPhase = MascotSpeechPhase.none;
    _endSpeechRequested = false;
    _correlationId = null;
    if (_clip == null)
      diagnostics.add('Missing approved idle for $_appearance');
  }

  void _assertActive() {
    if (_disposed) throw StateError('MascotPlaybackController is disposed');
  }
}
