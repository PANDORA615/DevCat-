import 'package:devcat/core/learning_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const path = 'assets/mascot_pixel/student-idle-000.png';
  testWidgets('A packed frame renders even though it is not a loose asset', (
    tester,
  ) async {
    final bundle = LearningAssets.bundled;
    await tester.runAsync(() async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(manifest.getAssetVariants(path), isNull);
      await bundle.frameFiles();
      await AssetManifest.loadFromAssetBundle(bundle);
    });
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    Object? error;
    await tester.runAsync(
      () => precacheImage(
        AssetImage(path, bundle: bundle),
        context,
        onError: (value, _) => error = value,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: Image.asset(path, bundle: bundle)),
    );
    await tester.pump();
    expect(error, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'An OTA snapshot overrides a packed frame and keeps other bundled frames',
    () async {
      final base = LearningAssets.bundled;
      final frames = await base.frameFiles();
      final replacement = frames['assets/mascot_pixel/student-blink-001.png']!;
      final snapshot = SnapshotAssetBundle({path: replacement}, base);
      expect((await snapshot.load(path)).buffer.asUint8List(), replacement);
      const other = 'assets/mascot_pixel/pirate-idle-000.png';
      expect((await snapshot.load(other)).buffer.asUint8List(), frames[other]);
    },
  );
}
