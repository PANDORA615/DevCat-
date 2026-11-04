import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Review resources retain their actual quality status and coverage.
class MascotCatalog {
  final List<Map<String, dynamic>> appearances;
  final Map<String, dynamic> states;
  MascotCatalog(this.appearances, this.states);
  static Future<MascotCatalog>? _loading;
  static MascotCatalog? cached;
  static Future<MascotCatalog> load() => _loading ??= _load();
  static Future<MascotCatalog> _load() async {
    const base = 'assets/mascot_v5/manifests/';
    final appearances = jsonDecode(
      await rootBundle.loadString('${base}appearance_catalog.json'),
    );
    final animations = jsonDecode(
      await rootBundle.loadString('${base}animation_contract.json'),
    );
    return cached = MascotCatalog(
      List<Map<String, dynamic>>.from(appearances['appearances']),
      Map<String, dynamic>.from(animations['states']),
    );
  }

  static String evolution(int level) => level <= 10
      ? 'beginner'
      : level <= 25
      ? 'student'
      : level <= 50
      ? 'developer'
      : level <= 75
      ? 'middle'
      : level <= 100
      ? 'senior'
      : 'architect';
  Map<String, dynamic> appearance(String id) => appearances.firstWhere(
    (a) => a['id'] == id,
    orElse: () => appearances.first,
  );
  Map<String, dynamic>? clip(String appearance, String state) =>
      appearance == 'student' ? states[state] as Map<String, dynamic>? : null;
  static String asset(String path) => 'assets/mascot_v5/$path';
}

class MascotScope extends InheritedWidget {
  final String appearance;
  const MascotScope({
    super.key,
    required this.appearance,
    required super.child,
  });
  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MascotScope>()?.appearance ??
      'classic';
  @override
  bool updateShouldNotify(MascotScope oldWidget) =>
      oldWidget.appearance != appearance;
}

/// Frame selection uses elapsed milliseconds, independent of display refresh rate.
int mascotFrame(List<int> durations, int elapsedMs, {required bool loop}) {
  final total = durations.fold<int>(0, (a, b) => a + b);
  if (total <= 0 || durations.any((d) => d <= 0)) {
    throw ArgumentError('Invalid frame duration');
  }
  var time = loop
      ? elapsedMs.clamp(0, 1 << 53) % total
      : elapsedMs.clamp(0, total - 1);
  for (var i = 0; i < durations.length; i++) {
    if (time < durations[i]) return i;
    time -= durations[i];
  }
  return durations.length - 1;
}
