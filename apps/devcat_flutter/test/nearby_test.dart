import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/nearby_sync.dart';
import 'package:devcat/core/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Nearby transfer persists the union on both devices and keeps device drafts',
    () async {
      final directory = await Directory.systemTemp.createTemp('devcat-nearby-');
      final first = AppStore(Directory('${directory.path}/first')),
          second = AppStore(Directory('${directory.path}/second'));
      await first.load();
      await second.load();
      await first.record('python.basics', 'python', true);
      await first.draft('python.loops', 'first code');
      await second.record('go.basics', 'go', true);
      await second.draft('python.loops', 'second code');
      final host = NearbySync(first), guest = NearbySync(second);
      try {
        final code = await host.start(address: '127.0.0.1');
        await guest.connect(code);
        expect(
          first.progress.solved,
          containsAll(['python.basics', 'go.basics']),
        );
        expect(second.progress.solved, first.progress.solved);
        expect(first.progress.draftsFor('python.loops').length, 2);
        final restored = AppStore(second.directory);
        await restored.load();
        expect(restored.progress.solved, first.progress.solved);
        await second.record('sql.left', 'sql', true);
        await guest.connect(code);
        expect(first.progress.solved, contains('sql.left'));
        // A different bearer key cannot authenticate ciphertext to the host.
        final parsed = NearbySync.parseCode(code);
        parsed['key'] = base64Url.encode(List<int>.filled(32, 1));
        final altered =
            'devcat1.${base64Url.encode(utf8.encode(jsonEncode(parsed)))}';
        await expectLater(
          guest.connect(altered),
          throwsA(isA<HttpException>()),
        );
      } finally {
        await host.close();
        await guest.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test('Pairing rejects expired codes, public hosts and malformed keys', () {
    String code(Map<String, dynamic> changes) =>
        'devcat1.${base64Url.encode(utf8.encode(jsonEncode({'host': '192.168.1.2', 'port': 1234, 'key': base64Url.encode(List<int>.filled(32, 0)), 'session': 'a' * 32, 'expires': DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch, ...changes})))}';
    for (final change in [
      {'host': '8.8.8.8'},
      {'host': 'example.com'},
      {'expires': 0},
      {'key': 'AA=='},
      {'port': 0},
    ]) {
      expect(() => NearbySync.parseCode(code(change)), throwsFormatException);
    }
  });
}
