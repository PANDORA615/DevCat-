import 'dart:math';

class MascotClip {
  final List<int> durations;
  final bool loop;
  final String next;
  final int priority;
  MascotClip({
    required this.durations,
    this.loop = false,
    this.next = 'idle',
    this.priority = 10,
  }) {
    if (durations.isEmpty || durations.any((d) => d <= 0)) {
      throw ArgumentError('Each frame needs a positive duration');
    }
  }
  int get duration => durations.fold(0, (a, b) => a + b);
  factory MascotClip.fromJson(Map<String, dynamic> data) => MascotClip(
    durations: List<int>.from(data['durationsMs']),
    loop: data['loop'] == true,
    next: data['next'] ?? 'idle',
    priority: data['priority'] ?? 10,
  );
}

/// Owns elapsed time and transitions; a renderer never substitutes another skin.
class MascotPlayback {
  final Map<String, MascotClip> clips;
  final bool ambient, followTransitions;
  final Random _random;
  String state = 'idle';
  String? correlationId;
  int elapsedMs = 0, _idleMs = 0;
  late int _blinkAfter;
  bool paused = false, disposed = false, completed = false;
  String? _pending;
  String? _pendingCorrelation;
  MascotPlayback(
    this.clips, {
    this.ambient = true,
    this.followTransitions = true,
    int seed = 0,
  }) : _random = Random(seed) {
    _blinkAfter = _nextBlink();
  }
  int _nextBlink() => 3000 + _random.nextInt(4001);
  int get frame {
    final clip = clips[state];
    if (clip == null) return 0;
    var time = elapsedMs.clamp(0, clip.duration - 1);
    for (var i = 0; i < clip.durations.length; i++) {
      if (time < clip.durations[i]) return i;
      time -= clip.durations[i];
    }
    return clip.durations.length - 1;
  }

  bool play(String requested, {String? correlation, bool force = false}) {
    if (disposed) return false;
    final target = clips[requested];
    if (target == null) {
      cancel();
      return false;
    }
    if (!force &&
        requested == state &&
        correlation == correlationId &&
        !completed) {
      return true;
    }
    final current = clips[state];
    if (!force &&
        (state == 'jump' || state == 'land') &&
        target.priority < 80) {
      _pending = requested;
      _pendingCorrelation = correlation;
      return false;
    }
    if (!force &&
        !completed &&
        current != null &&
        !current.loop &&
        target.priority < current.priority) {
      return false;
    }
    if (force || target.priority >= 80) {
      _pending = null;
      _pendingCorrelation = null;
    }
    _enter(requested, correlation);
    return true;
  }

  void _enter(String requested, String? correlation) {
    state = requested;
    correlationId = correlation;
    elapsedMs = 0;
    completed = false;
    _idleMs = 0;
  }

  void pause() {
    if (!disposed) paused = true;
  }

  void resume() {
    if (!disposed) paused = false;
  }

  void cancel({String? correlation}) {
    if (disposed) return;
    if (correlation != null && correlation != correlationId) {
      if (correlation == _pendingCorrelation) {
        _pending = null;
        _pendingCorrelation = null;
      }
      return;
    }
    _pending = null;
    _pendingCorrelation = null;
    _enter('idle', null);
    _blinkAfter = _nextBlink();
  }

  void seek(int index) {
    final clip = clips[state];
    if (disposed || clip == null) return;
    elapsedMs = clip.durations
        .take(index.clamp(0, clip.durations.length - 1))
        .fold(0, (a, b) => a + b);
    completed = false;
  }

  void advance(int milliseconds) {
    if (disposed || paused || completed || milliseconds <= 0) return;
    var remaining = milliseconds;
    while (remaining > 0) {
      final clip = clips[state];
      if (clip == null) return;
      var step = min(remaining, clip.duration - elapsedMs);
      if (ambient && state == 'idle' && clips.containsKey('blink')) {
        step = min(step, _blinkAfter - _idleMs);
      }
      elapsedMs += step;
      remaining -= step;
      if (state == 'idle') {
        _idleMs += step;
        if (ambient && _idleMs >= _blinkAfter && clips.containsKey('blink')) {
          _enter('blink', null);
          _blinkAfter = _nextBlink();
          continue;
        }
      }
      if (elapsedMs < clip.duration) continue;
      if (clip.loop) {
        elapsedMs = 0;
        continue;
      }
      if (!followTransitions) {
        elapsedMs = clip.duration - 1;
        completed = true;
        return;
      }
      var next = clip.next;
      if (state == 'jump' && clips.containsKey('land')) next = 'land';
      if (state == 'land' && _pending != null) {
        final request = _pending!;
        final owner = _pendingCorrelation;
        _pending = null;
        _pendingCorrelation = null;
        _enter(clips.containsKey(request) ? request : 'idle', owner);
      } else {
        _enter(clips.containsKey(next) ? next : 'idle', correlationId);
      }
    }
  }

  void dispose() {
    disposed = true;
    paused = true;
    _pending = null;
    correlationId = null;
  }
}
