// Cross-check a real Python/OpenSSL release package with the application verifier.
import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/content_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Release course/media package verifies with the pinned application key',
    () async {
      final path = Platform.environment['DEVCAT_CONTENT_PACKAGE'];
      expect(
        path,
        isNotNull,
        reason: 'Set DEVCAT_CONTENT_PACKAGE to the signed release JSON.',
      );
      final config = jsonDecode(
        await File('assets/branding/desktop_update_keys.json').readAsString(),
      );
      final keys = <String, List<int>>{
        for (final entry in (config['keys'] as Map<String, dynamic>).entries)
          entry.key: base64Decode(entry.value),
      };
      final directory = await Directory.systemTemp.createTemp(
        'devcat-release-content-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final runtime = ContentRuntime.forTesting(
        directory,
        keys,
        appVersion: config['appVersion'],
        appBuild: config['appBuild'],
        bundledRevision: config['bundledRevision'],
      );
      final content = await runtime.validateFile(path!);
      expect(content.revision, config['bundledRevision']);
      expect(
        content.files.keys
            .where((name) => name.startsWith('assets/audio/'))
            .length,
        18,
      );
      expect(
        content.files.keys
            .where(
              (name) =>
                  name.startsWith('assets/mascot_pixel/') &&
                  name.endsWith('.png'),
            )
            .length,
        764,
      );
      expect(content.files.containsKey('assets/config/themes.json'), isTrue);
      debugPrint(
        'Verified release content: revision ${content.revision}, ${content.files.length} files.',
      );
    },
  );
}
