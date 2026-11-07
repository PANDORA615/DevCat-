import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:devcat/core/store.dart';
import 'package:devcat/core/course.dart';
import 'package:devcat/core/updates.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryHttpClient implements HttpClient {
  final List<int> bytes;
  MemoryHttpClient(this.bytes);
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => MemoryHttpRequest(bytes);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryHttpRequest implements HttpClientRequest {
  final List<int> bytes;
  MemoryHttpRequest(this.bytes);
  @override
  Future<HttpClientResponse> close() async => MemoryHttpResponse(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final List<int> bytes;
  MemoryHttpResponse(this.bytes);
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Semver orders prereleases, release and multi-digit components', () {
    final values = [
      '0.9.2-alpha.2',
      '0.9.2-alpha.10',
      '0.9.2-beta',
      '0.9.2',
      '0.10.0',
      '1.0.0',
    ];
    for (var i = 0; i < values.length - 1; i++) {
      expect(
        AppVersion(values[i]).compareTo(AppVersion(values[i + 1])),
        lessThan(0),
      );
    }
    expect(AppVersion('0.9.2+5009').compareTo(AppVersion('0.9.2')), 0);
    for (final value in ['../escape', '01.9.2', '0.9', '0.9.2-alpha.01']) {
      expect(() => AppVersion(value), throwsFormatException);
    }
  });
  test('Only a pinned key can authenticate the exact signed payload', () async {
    final algorithm = Ed25519();
    final key = await algorithm.newKeyPair();
    final pub = await key.extractPublicKey();
    final service = UpdateService(publicKey: base64Encode(pub.bytes));
    addTearDown(service.dispose);
    final payload = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'version': '0.9.3',
        'channel': 'stable',
        'minSupportedAppVersion': '0.9.2',
        'releaseNotes': 'Новые курсы',
        'content': {
          'url':
              'https://github.com/PANDORA615/DevCat-/releases/download/v0.9.3/courses.json',
          'size': 123,
          'sha256': 'a' * 64,
        },
      }),
    );
    final signature = await algorithm.sign(payload, keyPair: key);
    String envelope(List<int> bytes) => jsonEncode({
      'payload': base64Encode(bytes),
      'signature': base64Encode(signature.bytes),
    });
    final verified = await service.verifyEnvelope(envelope(payload), 'stable');
    expect(verified.version, '0.9.3');
    expect(
      service.verifyEnvelope(envelope([...payload, 32]), 'stable'),
      throwsFormatException,
    );
    expect(
      service.verifyEnvelope(envelope(payload), 'beta'),
      throwsFormatException,
    );
    final wrong = UpdateService(
      publicKey: base64Encode(
        (await (await algorithm.newKeyPair()).extractPublicKey()).bytes,
      ),
    );
    addTearDown(wrong.dispose);
    expect(
      wrong.verifyEnvelope(envelope(payload), 'stable'),
      throwsFormatException,
    );
  });
  test('Unconfigured signing cannot accept an update', () async {
    final service = UpdateService(publicKey: '');
    addTearDown(service.dispose);
    expect(service.verifyEnvelope('{}', 'stable'), throwsStateError);
  });
  test('Artifact validation rejects HTTP and missing integrity metadata', () {
    expect(
      () => UpdateArtifact({
        'url': 'http://example.com/update',
        'size': 1,
        'sha256': 'a' * 64,
      }),
      throwsFormatException,
    );
    expect(
      () => UpdateArtifact({
        'url': 'https://example.com/update',
        'size': 0,
        'sha256': 'a' * 64,
      }),
      throwsFormatException,
    );
    expect(
      () => UpdateArtifact({
        'url': 'https://example.com/update',
        'size': 1,
        'sha256': 'bad',
      }),
      throwsFormatException,
    );
  });
  test(
    'Damaged content returns to bundled courses without touching progress',
    () async {
      final directory = await Directory.systemTemp.createTemp('devcat-ota-');
      addTearDown(() => directory.delete(recursive: true));
      final store = AppStore(directory);
      await store.load();
      await store.record('test-task', 'python', true);
      await store.updateSettings({'contentUpdateActive': '0.9.3'});
      expect(await UpdateService.activeContent(store), isNull);
      expect(store.progress.solved, contains('test-task'));
      expect(store.setting<String?>('contentUpdateActive', null), isNull);
      expect(() => UpdateService.validateCourses('[]'), throwsFormatException);
    },
  );
  test(
    'Content staging verifies bytes, activates once and restores last-known-good',
    () async {
      final root = await Directory.systemTemp.createTemp('devcat-content-');
      addTearDown(() => root.delete(recursive: true));
      final store = AppStore(root);
      await store.load();
      await store.record('saved-work', 'python', true);
      final bytes = utf8.encode(
        jsonEncode([
          for (final id in languageNames.keys)
            {
              'id': id,
              'name': 'Python',
              'version': 'test',
              'subtitle': 'test',
              'source': 'test',
              'lessons': [
                {
                  'id': 'intro',
                  'title': 'Intro',
                  'theory': 'Read',
                  'kind': 'theory',
                  'examples': <String>[],
                  'mistakes': <String>[],
                },
              ],
            },
        ]),
      );
      final hash = (await Sha256().hash(
        bytes,
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      VerifiedUpdate plan(String version, String digest) => VerifiedUpdate({
        'schemaVersion': 1,
        'version': version,
        'minSupportedAppVersion': '0.9.2',
        'channel': 'stable',
        'content': {
          'url': 'https://example.com/courses.json',
          'size': bytes.length,
          'sha256': digest,
        },
      }, 'stable');
      final service = UpdateService(client: MemoryHttpClient(bytes));
      addTearDown(service.dispose);
      await expectLater(
        service.installContent(plan('0.9.3', '0' * 64), store),
        throwsFormatException,
      );
      expect(store.setting<String?>('contentUpdateActive', null), isNull);
      await service.installContent(plan('0.9.3', hash), store);
      expect(await UpdateService.activeContent(store), utf8.decode(bytes));
      await service.installContent(plan('0.9.4', hash), store);
      await File('${root.path}/updates/0.9.4/courses.json').writeAsString('[]');
      expect(await UpdateService.activeContent(store), utf8.decode(bytes));
      expect(store.setting('contentUpdateActive', ''), '0.9.3');
      expect(store.progress.solved, contains('saved-work'));
      await expectLater(
        service.installContent(plan('0.9.3', hash), store),
        throwsFormatException,
      );
    },
  );
}
