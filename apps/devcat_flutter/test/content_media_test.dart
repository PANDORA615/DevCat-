import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:devcat/core/content_media_validation.dart';
import 'package:devcat/core/sound.dart';
import 'package:devcat/core/learning_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Uint8List> files;
  setUp(() async {
    files = {};
    for (final namespace in ['mascot_pixel', 'config']) {
      await for (final file in Directory('assets/$namespace').list()) {
        if (file is File && !file.path.endsWith('/frames.json')) {
          files[file.path] = await file.readAsBytes();
        }
      }
    }
    files.addAll(await LearningAssets.bundled.frameFiles());
    for (final name in {
      ...SoftSounds.cues.values,
      ...SoftSounds.voiceDurations.keys,
    }) {
      final path = 'assets/audio/$name.wav';
      files[path] = await File(path).readAsBytes();
    }
  });
  test(
    'All bundled skins, WAV cues and themes satisfy the OTA media contract',
    () {
      expect(() => validateContentMedia(files), returnsNormally);
    },
  );
  test(
    'Missing costume frames or actions and divergent clocks are rejected',
    () {
      final source = jsonDecode(
        utf8.decode(files['assets/mascot_pixel/catalog.json']!),
      );
      source['clips']['pirate'].remove('happy');
      files['assets/mascot_pixel/catalog.json'] = Uint8List.fromList(
        utf8.encode(jsonEncode(source)),
      );
      expect(() => validateContentMedia(files), throwsFormatException);
    },
  );
  test('Unknown audio and unsupported sample formats are rejected', () {
    final valid = files['assets/audio/ui_soft_tap.wav']!;
    files['assets/audio/unknown.wav'] = valid;
    expect(() => validateContentMedia(files), throwsFormatException);
    files.remove('assets/audio/unknown.wav');
    final changed = Uint8List.fromList(valid);
    changed[0] = 0;
    files['assets/audio/ui_soft_tap.wav'] = changed;
    expect(() => validateContentMedia(files), throwsFormatException);
  });
  test('A bad theme cannot replace the previous usable snapshot', () {
    files['assets/config/themes.json'] = Uint8List.fromList(
      utf8.encode(
        '{"schema":1,"presets":[{"color":"not-a-color","name":"Theme"}]}',
      ),
    );
    expect(() => validateContentMedia(files), throwsFormatException);
  });
}
