import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'content_update.dart';
import 'content_validation.dart';
import 'learning_assets.dart';

class ContentRuntime {
  static ContentRuntime? current;
  static String? startupNotice;
  final Directory directory;
  final Map<String, List<int>> keys;
  final Set<String> requiredLessonIds;
  final String appVersion;
  final int appBuild, bundledRevision, activeRevision;
  ContentRuntime._(
    this.directory,
    this.keys,
    this.requiredLessonIds,
    this.appVersion,
    this.appBuild,
    this.bundledRevision,
    this.activeRevision,
  );

  /// Dependency injection for deterministic signature/network tests.
  factory ContentRuntime.forTesting(
    Directory directory,
    Map<String, List<int>> keys, {
    String appVersion = '0.9.1',
    int appBuild = 11,
    int bundledRevision = 1,
    Set<String> requiredLessonIds = const {},
  }) => ContentRuntime._(
    directory,
    Map.unmodifiable(
      keys.map((id, bytes) => MapEntry(id, List<int>.unmodifiable(bytes))),
    ),
    Set.unmodifiable(requiredLessonIds),
    appVersion,
    appBuild,
    bundledRevision,
    0,
  );

  ContentVerifier get verifier => ContentVerifier(keys, appBuild: appBuild);
  ContentUpdateStore get store => ContentUpdateStore(directory, verifier);
  int get revision =>
      activeRevision > bundledRevision ? activeRevision : bundledRevision;

  static Future<void> initialize(
    Directory userData, {
    AssetBundle? bundled,
  }) async {
    final base = bundled ?? LearningAssets.bundled;
    LearningAssets.bundle = base;
    LearningAssets.mediaPaths = const {};
    current = null;
    startupNotice = null;
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    try {
      final config = jsonDecode(
        await base.loadString('assets/branding/desktop_update_keys.json'),
      );
      final keys = <String, List<int>>{
        for (final entry in (config['keys'] as Map<String, dynamic>).entries)
          entry.key: List<int>.unmodifiable(base64Decode(entry.value)),
      };
      if (config['schema'] != 1 ||
          config['appBuild'] is! int ||
          config['appBuild'] <= 0 ||
          config['bundledRevision'] is! int ||
          config['bundledRevision'] <= 0 ||
          config['appVersion'] is! String ||
          keys.isEmpty ||
          keys.values.any((k) => k.length != 32)) {
        throw const FormatException('Неверный ключ обновлений.');
      }
      final bundled = await Future.wait([
        base.loadString('assets/content/courses.json'),
        base.loadString('assets/content/git_course.json'),
      ]);
      final required = await Isolate.run(() {
        final ids = <String>{};
        for (final course in [
          ...(jsonDecode(bundled[0]) as List),
          jsonDecode(bundled[1]),
        ]) {
          for (final lesson in course['lessons'] as List) {
            ids.add(lesson['id'] as String);
          }
        }
        return ids;
      });
      final path = '${userData.path}${Platform.pathSeparator}content-updates';
      final build = config['appBuild'] as int;
      final resolved = await Isolate.run(() async {
        final storage = ContentUpdateStore(
          Directory(path),
          ContentVerifier(keys, appBuild: build),
        );
        for (var attempt = 0; attempt < 2; attempt++) {
          final candidate = await storage.active();
          if (candidate == null) return null;
          try {
            final ids = validateLearningSnapshot(
              candidate.files,
              requiredLessonIds: required,
            );
            return (content: candidate, lessonIds: ids);
          } catch (_) {
            try {
              if (!await storage.rollback()) return null;
            } catch (_) {
              return null;
            }
          }
        }
        return null;
      });
      final snapshot = resolved?.content;
      if (resolved != null) required.addAll(resolved.lessonIds);
      if (snapshot != null) {
        LearningAssets.bundle = SnapshotAssetBundle(snapshot.files, base);
        LearningAssets.mediaPaths = Map.unmodifiable({
          for (final name in snapshot.files.keys.where(
            (name) => name.startsWith('assets/audio/'),
          ))
            name: '$path/versions/${snapshot.revision}/$name',
        });
      }
      current = ContentRuntime._(
        Directory(path),
        Map.unmodifiable(keys),
        Set.unmodifiable(required),
        config['appVersion'],
        build,
        config['bundledRevision'],
        snapshot?.revision ?? 0,
      );
    } catch (_) {
      current = null;
      startupNotice =
          'Обновления сейчас недоступны. Встроенные уроки и твой прогресс доступны.';
    }
  }

  Future<VerifiedContent> validatePackage(String envelope) async {
    final trusted = keys, minimum = requiredLessonIds, build = appBuild;
    return Isolate.run(() async {
      final candidate = await ContentVerifier(
        trusted,
        appBuild: build,
      ).verify(envelope);
      validateLearningSnapshot(candidate.files, requiredLessonIds: minimum);
      return candidate;
    });
  }

  Future<VerifiedContent> validateFile(String filePath) async {
    final trusted = keys, minimum = requiredLessonIds, build = appBuild;
    return Isolate.run(() async {
      final file = File(filePath);
      if (await file.length() > ContentVerifier.maxPackageBytes * 2) {
        throw const FormatException('Пакет слишком большой.');
      }
      final candidate = await ContentVerifier(
        trusted,
        appBuild: build,
      ).verify(await file.readAsString());
      validateLearningSnapshot(candidate.files, requiredLessonIds: minimum);
      return candidate;
    });
  }

  /// Activation affects the next launch; the current lesson's bundle stays put.
  Future<void> install(VerifiedContent content) async {
    if (content.revision <= revision) {
      throw const FormatException('Эта версия уроков уже установлена.');
    }
    final trusted = keys, minimum = requiredLessonIds, build = appBuild;
    final path = directory.path, envelope = content.envelope;
    await Isolate.run(() async {
      final checked = await ContentVerifier(
        trusted,
        appBuild: build,
      ).verify(envelope);
      validateLearningSnapshot(checked.files, requiredLessonIds: minimum);
      await ContentUpdateStore(
        Directory(path),
        ContentVerifier(trusted, appBuild: build),
      ).install(checked);
    });
  }
}
