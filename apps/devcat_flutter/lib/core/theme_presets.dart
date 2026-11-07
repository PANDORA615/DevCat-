import 'dart:convert';
import 'learning_assets.dart';

class ThemePresets {
  static Map<int, String> colors = const {
    0xff416c57: 'Шалфей',
    0xff376493: 'Небо',
    0xffa15c35: 'Терракота',
    0xff8b5368: 'Роза',
    0xff526367: 'Нейтральная',
  };
  static Map<int, String> decode(String text) {
    final data = jsonDecode(text);
    if (data['schema'] != 1 ||
        data['presets'] is! List ||
        data['presets'].isEmpty ||
        data['presets'].length > 32) {
      throw const FormatException('Неверный набор тем.');
    }
    final result = <int, String>{};
    for (final preset in data['presets']) {
      final color = preset['color'], name = preset['name'];
      if (color is! String ||
          !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(color) ||
          name is! String ||
          name.trim().isEmpty ||
          name.length > 40) {
        throw const FormatException('Неверный цвет или название темы.');
      }
      if (result.containsKey(0xff000000 | int.parse(color, radix: 16))) {
        throw const FormatException('Повтор цвета темы.');
      }
      result[0xff000000 | int.parse(color, radix: 16)] = name;
    }
    return Map.unmodifiable(result);
  }

  static Future<void> load() async {
    colors = decode(
      await LearningAssets.bundle.loadString('assets/config/themes.json'),
    );
  }
}
