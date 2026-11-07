import 'dart:convert';
import 'dart:typed_data';
import 'mascot_playback.dart';
import 'sound.dart';
import 'theme_presets.dart';

/// Media updates contain declarative data only; no new scripts or plugins.
void validateContentMedia(Map<String, Uint8List> files) {
  final themes = files['assets/config/themes.json'];
  if (themes != null) ThemePresets.decode(utf8.decode(themes));
  final sounds = {...SoftSounds.cues.values, ...SoftSounds.voiceDurations.keys};
  for (final entry in files.entries.where(
    (e) => e.key.startsWith('assets/audio/'),
  )) {
    final name = entry.key
        .substring('assets/audio/'.length)
        .replaceFirst(RegExp(r'\.wav$'), '');
    if (!sounds.contains(name)) {
      throw const FormatException('Неизвестный звук приложения.');
    }
    _validateWave(entry.value);
  }
  if (!files.keys.any((name) => name.startsWith('assets/mascot_pixel/'))) {
    return;
  }
  final source = files['assets/mascot_pixel/catalog.json'];
  if (source == null) throw const FormatException('Нет описания образов кота.');
  final catalog = jsonDecode(utf8.decode(source));
  if (catalog['schema'] != 1) {
    throw const FormatException('Неверная схема маскота.');
  }
  final appearances = catalog['appearances'] as List;
  final clips = catalog['clips'] as Map<String, dynamic>;
  final states = catalog['states'] as Map<String, dynamic>;
  const known = {
    'idle',
    'blink',
    'talk',
    'happy',
    'thinking',
    'error',
    'angry',
    'celebrating',
    'excited',
    'explaining',
    'failure',
    'greeting',
    'idea',
    'jump',
    'land',
    'loading',
    'new',
    'notification',
    'orientations',
    'reading',
    'run',
    'sad',
    'shy',
    'sleeping',
    'sleepy',
    'success',
    'text_typing',
    'thoughtful',
    'typing',
    'waiting',
    'walk',
    'surprised',
  };
  const canonical = {
    'beginner',
    'student',
    'developer',
    'middle',
    'senior',
    'architect',
    'space',
    'hacker',
    'samurai',
    'winter',
    'mage',
    'engineer',
    'pirate',
    'cyberpunk',
    'scientist',
    'book',
  };
  final ids = <String>{};
  void picture(dynamic name) {
    if (name is! String ||
        !name.startsWith('assets/mascot_pixel/') ||
        !name.endsWith('.png') ||
        !files.containsKey(name)) {
      throw const FormatException('Нет кадра выбранного образа.');
    }
    final header = ByteData.sublistView(files[name]!);
    if (header.getUint32(16) != 128 || header.getUint32(20) != 128) {
      throw const FormatException('Кадр кота должен иметь размер 128 × 128.');
    }
  }

  void clip(dynamic raw) {
    final data = raw as Map<String, dynamic>;
    final parsed = MascotClip.fromJson(data);
    final frames = data['frames'] as List;
    final anchors = data['mouthAnchors'] as List;
    if (frames.isEmpty ||
        frames.length > 32 ||
        frames.length != parsed.durations.length ||
        anchors.length != frames.length ||
        parsed.durations.any((duration) => duration > 2000) ||
        parsed.priority < 0 ||
        parsed.priority > 100 ||
        !known.contains(parsed.next) ||
        data['frameSize'].toString() != '[128, 128]' ||
        data['pivotNormalized'].toString() != '[0.5, 0.875]') {
      throw const FormatException('Несовместимая анимация кота.');
    }
    for (final frame in frames) {
      picture(frame);
    }
    for (final anchor in anchors) {
      if (anchor is! List ||
          anchor.length != 2 ||
          anchor.any((v) => v is! int || v < 4 || v > 116)) {
        throw const FormatException('Неверная позиция рта.');
      }
    }
  }

  if (appearances.length < canonical.length ||
      appearances.length > 32 ||
      states.length != known.length ||
      !known.containsAll(states.keys)) {
    throw const FormatException('Неполный набор образов или действий.');
  }
  for (final appearance in appearances) {
    final id = appearance['id'], title = appearance['title'];
    if (id is! String ||
        !RegExp(r'^[a-z][a-z0-9_]{0,29}$').hasMatch(id) ||
        !ids.add(id) ||
        title is! String ||
        title.isEmpty ||
        title.length > 100) {
      throw const FormatException('Неверный образ кота.');
    }
    picture(appearance['asset']);
    final actions = clips[id] as Map<String, dynamic>;
    if (!actions.keys.toSet().containsAll({
          'idle',
          'blink',
          'talk',
          'happy',
          'thinking',
          'error',
        }) ||
        !known.containsAll(actions.keys)) {
      throw const FormatException('У костюма отсутствуют основные действия.');
    }
    for (final action in actions.values) {
      clip(action);
    }
  }
  if (!ids.containsAll(canonical) || clips.length != ids.length) {
    throw const FormatException('Обновление удаляет существующие образы.');
  }
  final student = clips['student'] as Map<String, dynamic>;
  if (student.length != states.length) {
    throw const FormatException('Не все действия ученика готовы.');
  }
  for (final entry in states.entries) {
    clip(entry.value);
    final actual = student[entry.key] as Map<String, dynamic>;
    for (final field in [
      'frames',
      'durationsMs',
      'loop',
      'next',
      'priority',
      'kind',
    ]) {
      if (entry.value[field].toString() != actual[field].toString()) {
        throw const FormatException('Описание действий и кадров не совпадает.');
      }
    }
  }
}

void _validateWave(Uint8List bytes) {
  if (bytes.length < 44 ||
      bytes.length > 2 * 1024 * 1024 ||
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
    throw const FormatException('Недопустимый WAV.');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(4, Endian.little) != bytes.length - 8) {
    throw const FormatException('Повреждён WAV.');
  }
  var offset = 12, format = false, audio = false;
  while (offset + 8 <= bytes.length) {
    final kind = ascii.decode(
      bytes.sublist(offset, offset + 4),
      allowInvalid: true,
    );
    final size = data.getUint32(offset + 4, Endian.little);
    if (offset + 8 + size > bytes.length) {
      throw const FormatException('Повреждён WAV.');
    }
    if (kind == 'fmt ') {
      if (format ||
          size < 16 ||
          data.getUint16(offset + 8, Endian.little) != 1 ||
          data.getUint16(offset + 10, Endian.little) != 1 ||
          data.getUint32(offset + 12, Endian.little) != 32000 ||
          data.getUint32(offset + 16, Endian.little) != 64000 ||
          data.getUint16(offset + 20, Endian.little) != 2 ||
          data.getUint16(offset + 22, Endian.little) != 16) {
        throw const FormatException('Несовместимый формат звука.');
      }
      format = true;
    } else if (kind == 'data') {
      if (audio || !format || size == 0 || size.isOdd) {
        throw const FormatException('Нет звуковых данных.');
      }
      audio = true;
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  if (!format || !audio || offset != bytes.length) {
    throw const FormatException('Неполный WAV.');
  }
}
