import 'package:flutter/services.dart';

/// The running lesson keeps its immutable snapshot until the next app launch.
class LearningAssets {
  static AssetBundle bundle = rootBundle;
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
