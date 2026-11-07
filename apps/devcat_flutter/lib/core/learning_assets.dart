import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:isolate';

/// The running lesson keeps its immutable snapshot until the next app launch.
class LearningAssets {
  static final bundled = BundledLearningAssets(rootBundle);
  static AssetBundle bundle = bundled;
  static Map<String, String> mediaPaths = const {};
}

/// A single portable resource container avoids hundreds of tiny packaged files.
/// Logical PNG keys stay identical in the renderer and signed OTA snapshots.
class BundledLearningAssets extends CachingAssetBundle {
  final AssetBundle fallback;
  Future<Map<String, Uint8List>>? _frames;
  BundledLearningAssets(this.fallback);
  Future<Map<String, Uint8List>> frameFiles() => _frames ??= _readFrames();
  Future<Map<String, Uint8List>> _readFrames() async {
    final source = await fallback.loadString('assets/mascot_pixel/frames.json');
    return Isolate.run(() {
      final data = jsonDecode(source);
      final entries = data['files'] as Map<String, dynamic>;
      if (data['schema'] != 1 || entries.length > 4096) {
        throw const FormatException('Несовместимый контейнер кадров.');
      }
      final frames = <String, Uint8List>{};
      for (final entry in entries.entries) {
        if (!RegExp(
          r'^assets/mascot_pixel/[a-z0-9_-]+\.png$',
        ).hasMatch(entry.key)) {
          throw const FormatException('Недопустимый путь кадра.');
        }
        frames[entry.key] = base64Decode(
          entry.value as String,
        ).asUnmodifiableView();
      }
      return Map<String, Uint8List>.unmodifiable(frames);
    });
  }

  @override
  Future<ByteData> load(String key) async {
    if (key.startsWith('assets/mascot_pixel/') && key.endsWith('.png')) {
      final bytes = (await frameFiles())[key];
      if (bytes == null) throw StateError('Не найден кадр: $key');
      return ByteData.sublistView(bytes);
    }
    return fallback.load(key);
  }
}

class SnapshotAssetBundle extends CachingAssetBundle {
  final Map<String, Uint8List> files;
  final AssetBundle fallback;
  SnapshotAssetBundle(this.files, this.fallback);
  @override
  Future<ByteData> load(String key) async {
    final data = files[key];
    return data == null ? fallback.load(key) : ByteData.sublistView(data);
  }
}
