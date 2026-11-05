import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:devcat/core/content_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SimpleKeyPair key;
  late ContentVerifier verifier;
  late Directory temp;
  setUp(() async {
    key = await Ed25519().newKeyPair();
    verifier = ContentVerifier({
      'release': (await key.extractPublicKey()).bytes,
    }, appBuild: 9);
    temp = await Directory.systemTemp.createTemp('devcat-content-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Future<String> pack(
    int revision, {
    String path = 'assets/content/example.json',
    SimpleKeyPair? signer,
  }) async {
    final bytes = utf8.encode('{"revision":$revision}');
    final hash = (await Sha256().hash(
      bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final payload = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'kind': 'devcat-content',
        'revision': revision,
        'minAppBuild': 9,
        'files': [
          {
            'path': path,
            'size': bytes.length,
            'sha256': hash,
            'data': base64Encode(bytes),
          },
        ],
      }),
    );
    final signature = await Ed25519().sign(payload, keyPair: signer ?? key);
    return jsonEncode({
      'keyId': 'release',
      'payload': base64Encode(payload),
      'signature': base64Encode(signature.bytes),
    });
  }

  test(
    'Signature verification rejects changed bytes and a substituted key',
    () async {
      final signed = await pack(1);
      expect((await verifier.verify(signed)).revision, 1);
      final modified = jsonDecode(signed);
      modified['payload'] = base64Encode(utf8.encode('{}'));
      await expectLater(
        verifier.verify(jsonEncode(modified)),
        throwsFormatException,
      );
      await expectLater(
        verifier.verify(await pack(2, signer: await Ed25519().newKeyPair())),
        throwsFormatException,
      );
    },
  );
  test(
    'Signed traversal and executable content cannot enter the snapshot',
    () async {
      for (final path in [
        '../user.json',
        'assets/content/../user.json',
        'assets/content/code.dart',
        'assets/content/code.js',
        'assets/content/a/b.json',
      ]) {
        await expectLater(
          verifier.verify(await pack(1, path: path)),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'Install, rollback and downgrade protection preserve local files',
    () async {
      final store = ContentUpdateStore(temp, verifier);
      await File('${temp.path}/progress.json').writeAsString('keep');
      await store.install(await verifier.verify(await pack(1)));
      await store.install(await verifier.verify(await pack(2)));
      expect((await store.active())!.revision, 2);
      expect(await store.rollback(), isTrue);
      expect((await store.active())!.revision, 1);
      await expectLater(
        store.install(await verifier.verify(await pack(1))),
        throwsFormatException,
      );
      expect(await File('${temp.path}/progress.json').readAsString(), 'keep');
    },
  );
  test(
    'Damaged active snapshot falls back to the previous signed version',
    () async {
      final store = ContentUpdateStore(temp, verifier);
      await store.install(await verifier.verify(await pack(1)));
      await store.install(await verifier.verify(await pack(2)));
      await File(
        '${temp.path}/versions/2/assets/content/example.json',
      ).writeAsString('broken');
      expect((await store.active())!.revision, 1);
    },
  );
  test(
    'Retry after a lost pointer is idempotent; only two snapshots remain',
    () async {
      final store = ContentUpdateStore(temp, verifier);
      final first = await verifier.verify(await pack(1));
      await store.install(first);
      await File('${temp.path}/active-0.json').delete();
      await store.install(first);
      expect((await store.active())!.revision, 1);
      await store.install(await verifier.verify(await pack(2)));
      await store.install(await verifier.verify(await pack(3)));
      expect(await Directory('${temp.path}/versions').list().length, 2);
      await store.install(await verifier.verify(await pack(3)));
      expect(await store.rollback(), isTrue);
      expect((await store.active())!.revision, 2);
    },
  );
  test(
    'Installer checks its own trust root even for an already verified object',
    () async {
      final other = await Ed25519().newKeyPair();
      final alien = ContentVerifier({
        'release': (await other.extractPublicKey()).bytes,
      }, appBuild: 9);
      final content = await alien.verify(await pack(1, signer: other));
      await expectLater(
        ContentUpdateStore(temp, verifier).install(content),
        throwsFormatException,
      );
      expect(await ContentUpdateStore(temp, verifier).active(), isNull);
    },
  );
}
