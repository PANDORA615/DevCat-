import 'dart:convert';
import 'dart:typed_data';
import 'course.dart';
import 'study.dart';
import 'content_media_validation.dart';

/// Validates complete course snapshots before they can become active.
Set<String> _validateLearningSnapshot(
  Map<String, Uint8List> files, {
  Set<String> requiredLessonIds = const {},
}) {
  dynamic read(String name) {
    final data = files['assets/content/$name'];
    if (data == null) throw FormatException('В пакете отсутствует $name.');
    return jsonDecode(utf8.decode(data));
  }

  void image(String name) {
    if (name.isEmpty) return;
    if (!name.endsWith('.png') || !files.containsKey('assets/content/$name')) {
      throw FormatException('В пакете нет изображения $name.');
    }
  }

  final courses = read('courses.json') as List;
  final git = read('git_course.json') as Map<String, dynamic>;
  final courseIds = <String>{}, lessonIds = <String>{};
  final lessonCourses = <String, String>{};
  for (final raw in [...courses, git]) {
    final data = raw as Map<String, dynamic>;
    for (final field in ['id', 'name', 'version', 'subtitle', 'source']) {
      if (data[field] is! String) {
        throw const FormatException('Неверные поля курса.');
      }
    }
    if (!courseIds.add(data['id'])) {
      throw const FormatException('Повтор курса.');
    }
    final lessons = data['lessons'] as List;
    if (lessons.isEmpty) throw const FormatException('Пустой курс.');
    for (final row in lessons) {
      final lesson = Lesson(Map<String, dynamic>.from(row));
      if (lesson.id.isEmpty ||
          !lessonIds.add(lesson.id) ||
          lesson.title.isEmpty ||
          lesson.theory.isEmpty) {
        throw const FormatException('Неверный или повторяющийся урок.');
      }
      lessonCourses[lesson.id] = data['id'];
      image(lesson.photo);
      for (final section in lesson.sections) {
        if (section['image'] is String) image(section['image']);
      }
    }
  }
  const supported = {
    'c',
    'cpp',
    'csharp',
    'python',
    'javascript',
    'java',
    'go',
    'sql',
    'html',
    'css',
    'git',
  };
  if (courseIds.length != supported.length ||
      !courseIds.containsAll(supported) ||
      !lessonIds.containsAll(requiredLessonIds)) {
    throw const FormatException(
      'Пакет удаляет существующие уроки или несовместим с языками приложения.',
    );
  }
  final catalog = StudyCatalog.decode(
    utf8.decode(
      files['assets/content/study_path.json'] ??
          (throw const FormatException('Нет учебного маршрута.')),
    ),
  );
  if (!catalog.topics.keys.toSet().containsAll(lessonIds) ||
      !lessonIds.containsAll(catalog.topics.keys)) {
    throw const FormatException('Курсы и учебный маршрут не совпадают.');
  }
  const kinds = {'choice', 'code', 'fill', 'lab', 'learn', 'order', 'write'};
  final exerciseIds = <String>{}, unitIds = <String>{};
  for (final topic in catalog.topics.values) {
    if (topic.course != lessonCourses[topic.id] ||
        topic.title.isEmpty ||
        topic.index < 0) {
      throw const FormatException('Урок относится к неверному курсу.');
    }
    for (final unit in topic.rounds) {
      if (unit.id.isEmpty ||
          !unitIds.add(unit.id) ||
          unit.level < 0 ||
          unit.level > 2) {
        throw const FormatException('Неверное или повторяющееся занятие.');
      }
      if (unit.steps.isEmpty) throw const FormatException('Пустое занятие.');
      for (final exercise in unit.steps) {
        if (!kinds.contains(exercise.kind) ||
            exercise.id.isEmpty ||
            !exerciseIds.add(exercise.id)) {
          throw const FormatException(
            'Несовместимое или повторяющееся задание.',
          );
        }
        // Force the same typed accessors used by the UI before activation.
        if (exercise.prompt.isEmpty) {
          throw const FormatException('Пустой вопрос.');
        }
        exercise.text;
        exercise.code;
        exercise.answer;
        exercise.why;
        exercise.options;
        exercise.pieces;
        if (exercise.data['image'] is String) image(exercise.data['image']);
      }
    }
  }
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  for (final entry in files.entries.where((e) => e.key.endsWith('.png'))) {
    final bytes = entry.value;
    if (bytes.length < 33 ||
        List.generate(8, (i) => bytes[i] == signature[i]).contains(false) ||
        ascii.decode(bytes.sublist(12, 16), allowInvalid: true) != 'IHDR') {
      throw FormatException('Повреждён PNG: ${entry.key}');
    }
    _validatePngChunks(bytes);
    final header = ByteData.sublistView(bytes);
    final width = header.getUint32(16), height = header.getUint32(20);
    if (width == 0 ||
        height == 0 ||
        width > 8192 ||
        height > 8192 ||
        width * height > 16777216) {
      throw FormatException('Недопустимый размер изображения: ${entry.key}');
    }
  }
  validateContentMedia(files);
  return lessonIds;
}

Set<String> validateLearningSnapshot(
  Map<String, Uint8List> files, {
  Set<String> requiredLessonIds = const {},
}) {
  try {
    return _validateLearningSnapshot(
      files,
      requiredLessonIds: requiredLessonIds,
    );
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Пакет содержит несовместимые учебные данные.');
  }
}

final _crcTable = List<int>.generate(256, (index) {
  var value = index;
  for (var bit = 0; bit < 8; bit++) {
    value = (value & 1) == 1 ? 0xedb88320 ^ (value >> 1) : value >> 1;
  }
  return value;
});

void _validatePngChunks(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 8, chunks = 0;
  var hasImage = false, ended = false;
  while (offset + 12 <= bytes.length) {
    final length = data.getUint32(offset);
    if (offset + 12 + length > bytes.length || ended) {
      throw const FormatException('Нарушена структура PNG.');
    }
    final type = ascii.decode(bytes.sublist(offset + 4, offset + 8));
    if (chunks++ == 0 && (type != 'IHDR' || length != 13)) {
      throw const FormatException('Неверный заголовок PNG.');
    }
    var crc = 0xffffffff;
    for (var index = offset + 4; index < offset + 8 + length; index++) {
      crc = _crcTable[(crc ^ bytes[index]) & 255] ^ (crc >> 8);
    }
    if ((crc ^ 0xffffffff) != data.getUint32(offset + 8 + length)) {
      throw const FormatException('Контрольная сумма PNG не совпадает.');
    }
    if (type == 'IDAT') hasImage = true;
    if (type == 'IEND') {
      if (length != 0 || !hasImage) {
        throw const FormatException('Неполный PNG.');
      }
      ended = true;
    }
    offset += length + 12;
  }
  if (!ended || offset != bytes.length) {
    throw const FormatException('Неполный PNG.');
  }
}
