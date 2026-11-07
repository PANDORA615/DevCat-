import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:devcat/core/content_runtime.dart';
import 'package:devcat/core/content_validation.dart';
import 'package:devcat/core/learning_assets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final languages = [
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
  ];
  Map<String, Uint8List> fixture({String title = 'Начало'}) {
    Uint8List json(Object value) =>
        Uint8List.fromList(utf8.encode(jsonEncode(value)));
    Map<String, Object> course(String id) => {
      'id': id,
      'name': id,
      'version': '1',
      'subtitle': '',
      'source': '',
      'lessons': [
        {
          'id': '$id.first',
          'title': title,
          'theory': 'Подробное объяснение.',
          'kind': 'theory',
          'examples': <String>[],
          'mistakes': <String>[],
        },
      ],
    };
    return {
      'assets/content/courses.json': json(
        languages.where((v) => v != 'git').map(course).toList(),
      ),
      'assets/content/git_course.json': json(course('git')),
      'assets/content/study_path.json': json({
        'schema': 1,
        'revision': 2,
        'topics': [
          for (final id in languages)
            {
              'id': '$id.first',
              'course': id,
              'title': title,
              'chapter': 'Основы',
              'index': 0,
              'rounds': [
                for (var round = 0; round < 3; round++)
                  {
                    'id': '$id.first.$round',
                    'title': title,
                    'level': round,
                    'steps': [
                      {
                        'id': '$id.first.$round.learn',
                        'kind': 'learn',
                        'prompt': title,
                      },
                    ],
                  },
              ],
            },
        ],
      }),
    };
  }

  test(
    'The complete bundled curriculum passes update schema validation',
    () async {
      final files = <String, Uint8List>{};
      for (final namespace in ['content', 'mascot_pixel', 'config']) {
        await for (final file in Directory('assets/$namespace').list()) {
          if (file is File &&
              !file.path.endsWith('/frames.json') &&
              (file.path.endsWith('.json') || file.path.endsWith('.png'))) {
            files[file.path] = await file.readAsBytes();
          }
        }
      }
      files.remove('assets/mascot_pixel/frames.json');
      files.addAll(await LearningAssets.bundled.frameFiles());
      expect(validateLearningSnapshot(files).length, 516);
    },
  );

  test(
    'Incomplete courses, missing progress IDs and unknown exercise kinds are rejected',
    () {
      final files = fixture();
      expect(validateLearningSnapshot(files).length, 11);
      expect(
        () =>
            validateLearningSnapshot(files, requiredLessonIds: {'old.lesson'}),
        throwsFormatException,
      );
      expect(
        () => validateLearningSnapshot(
          {...files}..remove('assets/content/git_course.json'),
        ),
        throwsFormatException,
      );
      final path = utf8
          .decode(files['assets/content/study_path.json']!)
          .replaceAll('"learn"', '"unknown"');
      expect(
        () => validateLearningSnapshot({
          ...files,
          'assets/content/study_path.json': Uint8List.fromList(
            utf8.encode(path),
          ),
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'Signed lessons activate only on restart; first update rolls back to built-in lessons',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'devcat-runtime-',
      );
      addTearDown(() async {
        ContentRuntime.current = null;
        LearningAssets.bundle = rootBundle;
        await directory.delete(recursive: true);
      });
      final key = await Ed25519().newKeyPair();
      final keys = {'test': (await key.extractPublicKey()).bytes};
      final base = fixture();
      base['assets/branding/desktop_update_keys.json'] = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'schema': 1,
            'keys': {'test': base64Encode(keys['test']!)},
            'appVersion': '0.9.1',
            'appBuild': 11,
            'bundledRevision': 1,
          }),
        ),
      );
      final bundle = SnapshotAssetBundle(base, rootBundle);
      final progress = File('${directory.path}/progress.json');
      await progress.writeAsString('preserve progress and drafts');
      await ContentRuntime.initialize(directory, bundled: bundle);
      expect(ContentRuntime.current!.revision, 1);
      final updated = fixture(title: 'Обновлённая лекция');
      final rows =
          jsonDecode(utf8.decode(updated['assets/content/courses.json']!))
              as List;
      rows.first['lessons'].add({
        ...rows.first['lessons'].first as Map<String, dynamic>,
        'id': 'c.second',
      });
      updated['assets/content/courses.json'] = Uint8List.fromList(
        utf8.encode(jsonEncode(rows)),
      );
      final path = jsonDecode(
        utf8.decode(updated['assets/content/study_path.json']!),
      );
      final extra = jsonDecode(
        jsonEncode(path['topics'].first).replaceAll('c.first', 'c.second'),
      );
      extra['index'] = 1;
      path['topics'].add(extra);
      updated['assets/content/study_path.json'] = Uint8List.fromList(
        utf8.encode(jsonEncode(path)),
      );
      final entries = <Map<String, Object>>[];
      for (final entry in updated.entries) {
        final hash = (await Sha256().hash(
          entry.value,
        )).bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
        entries.add({
          'path': entry.key,
          'size': entry.value.length,
          'sha256': hash,
          'data': base64Encode(entry.value),
        });
      }
      final payload = utf8.encode(
        jsonEncode({
          'kind': 'devcat-content',
          'schemaVersion': 1,
          'revision': 2,
          'minAppBuild': 11,
          'files': entries,
        }),
      );
      final envelope = jsonEncode({
        'keyId': 'test',
        'payload': base64Encode(payload),
        'signature': base64Encode(
          (await Ed25519().sign(payload, keyPair: key)).bytes,
        ),
      });
      final runtime = ContentRuntime.current!;
      await runtime.install(await runtime.validatePackage(envelope));
      expect(
        await LearningAssets.bundle.loadString('assets/content/courses.json'),
        isNot(contains('Обновлённая')),
      );
      await ContentRuntime.initialize(directory, bundled: bundle);
      expect(ContentRuntime.current!.revision, 2);
      expect(ContentRuntime.current!.requiredLessonIds, contains('c.second'));
      expect(
        () => validateLearningSnapshot(
          fixture(),
          requiredLessonIds: ContentRuntime.current!.requiredLessonIds,
        ),
        throwsFormatException,
      );
      expect(
        await LearningAssets.bundle.loadString('assets/content/courses.json'),
        contains('Обновлённая'),
      );
      expect(await ContentRuntime.current!.store.rollback(), isTrue);
      await ContentRuntime.initialize(directory, bundled: bundle);
      expect(ContentRuntime.current!.revision, 1);
      expect(
        await LearningAssets.bundle.loadString('assets/content/courses.json'),
        isNot(contains('Обновлённая')),
      );
      expect(await progress.readAsString(), 'preserve progress and drafts');
    },
  );
}
