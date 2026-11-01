/// Duration-based visible text progression for a mascot's speech.
class MascotTextReveal {
  MascotTextReveal(
    this.text, {
    required this.correlationId,
    this.characterDurationMs = 35,
    this.pauseDurationMs = 110,
  }) : assert(characterDurationMs > 0),
       assert(pauseDurationMs > 0),
       _characters = text.runes.toList();

  final String text;
  final String correlationId;
  final int characterDurationMs;
  final int pauseDurationMs;
  final List<int> _characters;
  int _visible = 0;
  int _pendingMs = 0;
  bool _cancelled = false;

  int get visibleCharacters => _visible;
  bool get complete => _visible == _characters.length || _cancelled;
  bool get cancelled => _cancelled;
  String get visibleText => String.fromCharCodes(_characters.take(_visible));

  /// Spaces, punctuation and pauses don't produce mouth movement.
  bool get mouthActive {
    if (complete || _visible == 0) return false;
    return !_isPause(_characters[_visible - 1]);
  }

  void advance(Duration elapsed) {
    if (elapsed.isNegative) throw ArgumentError.value(elapsed, 'elapsed');
    if (complete) return;
    _pendingMs += elapsed.inMilliseconds;
    while (_visible < _characters.length) {
      final next = _characters[_visible];
      final duration = _isPause(next)
          ? pauseDurationMs
          : characterDurationMs;
      if (_pendingMs < duration) break;
      _pendingMs -= duration;
      _visible++;
    }
    if (complete) _pendingMs = 0;
  }

  /// Show complete, accessible text without continuing sound or mouth motion.
  void skip() {
    _visible = _characters.length;
    _pendingMs = 0;
  }

  /// Cancel is distinct from skip so an obsolete dialogue can be identified.
  void cancel() {
    _cancelled = true;
    _pendingMs = 0;
  }

  static bool _isPause(int rune) {
    if (rune <= 32) return true;
    return const {
      0x0021, 0x002C, 0x002D, 0x002E, 0x003A, 0x003B, 0x003F,
      0x2013, 0x2014, 0x2026,
    }.contains(rune);
  }
}
