import 'dart:async';
import 'package:flutter/widgets.dart';

/// Reveals whole graphemes and emits bounded, unqueued syllable requests.
class SpeechTimeline extends ChangeNotifier {
  final void Function() onSyllable, onStop;
  final Duration interval;
  SpeechTimeline({
    required this.onSyllable,
    required this.onStop,
    this.interval = const Duration(milliseconds: 32),
  });
  Timer? _timer;
  List<String> _letters = [];
  int _visible = 0, _lettersSinceSound = 0, _syllables = 0;
  DateTime? _started;
  bool talking = false, _disposed = false;
  String get text => _letters.take(_visible).join();
  bool get complete => _visible >= _letters.length;
  void start(String text, {bool instant = false}) {
    _timer?.cancel();
    onStop();
    _letters = text.characters.toList();
    _visible = instant ? _letters.length : 0;
    _lettersSinceSound = _syllables = 0;
    _started = DateTime.now();
    talking = false;
    if (!instant && _letters.isNotEmpty) _schedule(interval);
    notifyListeners();
  }

  void _schedule(Duration delay) => _timer = Timer(delay, _tick);
  void _tick() {
    if (_disposed || complete) return;
    final letter = _letters[_visible++];
    final voiced = RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(letter);
    talking = voiced && !complete;
    if (voiced &&
        ++_lettersSinceSound >= 3 &&
        _syllables < 24 &&
        DateTime.now().difference(_started!) < const Duration(seconds: 4)) {
      _lettersSinceSound = 0;
      _syllables++;
      onSyllable();
    }
    if (complete) {
      talking = false;
      onStop();
    } else {
      _schedule(
        RegExp(r'[.,!?;:…]').hasMatch(letter)
            ? const Duration(milliseconds: 160)
            : interval,
      );
    }
    notifyListeners();
  }

  void reveal() {
    _timer?.cancel();
    _visible = _letters.length;
    talking = false;
    onStop();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    onStop();
    super.dispose();
  }
}
