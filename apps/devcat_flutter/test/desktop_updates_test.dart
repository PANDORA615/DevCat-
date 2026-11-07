import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:devcat/core/content_runtime.dart';
import 'package:devcat/core/desktop_updates.dart';
import 'package:devcat/core/update_download.dart';
import 'package:flutter_test/flutter_test.dart';

// Redirect only the transport to a local TLS fixture. Production URL validation
// still sees GitHub URLs; TLS verifies the fixture's explicit trust root.
class LocalClient implements HttpClient {
  final HttpClient delegate;
  final int port;
  LocalClient(this.delegate, this.port);
  @override
  Future<HttpClientRequest> getUrl(Uri uri) =>
      delegate.getUrl(uri.replace(host: '127.0.0.1', port: port));
  @override
  set connectionTimeout(Duration? value) => delegate.connectionTimeout = value;
  @override
  set autoUncompress(bool value) => delegate.autoUncompress = value;
  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory certificates, directory;
  late HttpServer server;
  late SecurityContext trusted, serving;
  late SimpleKeyPair key;
  late ContentRuntime runtime;
  Future<String> digest(List<int> bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  HttpClient client() => LocalClient(
    HttpClient(context: trusted)..findProxy = (_) => 'DIRECT',
    server.port,
  );
  final data = utf8.encode('real packaged application fixture');
  final url = Uri.parse(
    'https://github.com/PANDORA615/DevCat-/releases/download/v0.9.2/file.zip',
  );
  Future<UpdateFile> descriptor({String name = 'file.zip'}) async =>
      UpdateFile(name, await digest(data), data.length);
  Future<String> signedIndex({String? wrongPlatform}) async {
    Map<String, Object> file(String name) => {
      'name': name,
      'sha256': 'a' * 64,
      'bytes': 100,
    };
    final payload = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'kind': 'devcat-update-index',
        'version': '0.9.2',
        'appBuild': 12,
        'channel': 'beta',
        'notes': 'Новые уроки',
        'content': {
          ...file('DevCat-0.9.2-content.json'),
          'revision': 2,
          'minAppBuild': 11,
        },
        'platforms': {
          'windows-x64': [
            file(wrongPlatform ?? 'DevCat-0.9.2-windows-x64-setup.exe'),
          ],
          'linux-x64': [
            for (final suffix in [
              'linux-amd64.deb',
              'linux-fedora-x86_64.rpm',
              'linux-opensuse-x86_64.rpm',
              'linux-x86_64.AppImage',
              'linux-x86_64.tar.gz',
              'linux-x86_64.pkg.tar.zst',
            ])
              file('DevCat-0.9.2-$suffix'),
          ],
          'macos-universal': [file('DevCat-0.9.2-macos-universal.dmg')],
        },
      }),
    );
    return jsonEncode({
      'keyId': 'test',
      'payload': base64Encode(payload),
      'signature': base64Encode(
        (await Ed25519().sign(payload, keyPair: key)).bytes,
      ),
    });
  }

  setUpAll(() async {
    certificates = await Directory.systemTemp.createTemp('devcat-updates-tls-');
    final cert = '${certificates.path}/cert.pem',
        privateKey = '${certificates.path}/key.pem';
    final result = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      privateKey,
      '-out',
      cert,
      '-days',
      '1',
      '-subj',
      '/CN=localhost',
      '-addext',
      'subjectAltName=IP:127.0.0.1',
    ]);
    expect(result.exitCode, 0);
    trusted = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(cert);
    serving = SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(privateKey);
  });
  tearDownAll(() => certificates.delete(recursive: true));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('devcat-updates-');
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serving,
    );
    key = await Ed25519().newKeyPair();
    runtime = ContentRuntime.forTesting(directory, {
      'test': (await key.extractPublicKey()).bytes,
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
    'A resumed HTTPS download verifies the whole file and uses the cached result',
    () async {
      final file = await descriptor();
      await File(
        '${directory.path}/${file.sha256}.part',
      ).writeAsBytes(data.sublist(0, 7));
      var requests = 0;
      server.listen((request) async {
        requests++;
        expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=7-');
        request.response.statusCode = 206;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 7-${data.length - 1}/${data.length}',
        );
        request.response.contentLength = data.length - 7;
        request.response.add(data.sublist(7));
        await request.response.close();
      });
      final download = UpdateDownload(directory, createClient: client);
      expect(await (await download.fetch(url, file)).readAsBytes(), data);
      expect(await (await download.fetch(url, file)).readAsBytes(), data);
      expect(requests, 1);
    },
  );

  test(
    'Wrong hash, bad range and untrusted redirect never produce an installer',
    () async {
      var mode = 'hash';
      server.listen((request) async {
        if (mode == 'redirect') {
          request.response.statusCode = 302;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'https://example.org/installer.exe',
          );
        } else if (mode == 'range') {
          request.response.statusCode = 206;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-2/3',
          );
          request.response.add([1, 2, 3]);
        } else {
          request.response.add(List.filled(data.length, 0));
        }
        await request.response.close();
      });
      final file = await descriptor();
      final download = UpdateDownload(directory, createClient: client);
      await expectLater(download.fetch(url, file), throwsFormatException);
      expect(await File('${directory.path}/${file.name}').exists(), isFalse);
      mode = 'range';
      await File(
        '${directory.path}/${file.sha256}.part',
      ).writeAsBytes(data.sublist(0, 7));
      await expectLater(download.fetch(url, file), throwsFormatException);
      mode = 'redirect';
      await expectLater(download.fetch(url, file), throwsFormatException);
      await expectLater(
        download.fetch(Uri.parse('http://github.com/file.zip'), file),
        throwsFormatException,
      );
      expect(await File('${directory.path}/${file.name}').exists(), isFalse);
    },
  );

  test('Cancellation retains a partial download that can resume', () async {
    final firstChunkSent = Completer<void>();
    final releaseServer = Completer<void>();
    server.listen((request) async {
      request.response.contentLength = data.length;
      request.response.add(data.sublist(0, 7));
      await request.response.flush();
      firstChunkSent.complete();
      await releaseServer.future;
      try {
        request.response.add(data.sublist(7));
        await request.response.close();
      } on IOException {
        /* Client deliberately closed its connection. */
      }
    });
    final file = await descriptor();
    final download = UpdateDownload(directory, createClient: client);
    final pending = download.fetch(
      url,
      file,
      onProgress: (received, _) {
        if (received >= 7) download.cancel();
      },
    );
    final rejected = expectLater(pending, throwsA(isA<UpdateCancelled>()));
    await firstChunkSent.future;
    releaseServer.complete();
    await rejected;
    expect(await File('${directory.path}/${file.name}').exists(), isFalse);
    expect(
      await File('${directory.path}/${file.sha256}.part').exists(),
      isTrue,
    );
  });

  test('Signed index is bound to the release tag and platform', () async {
    final signed = await signedIndex();
    final plan = await UpdatePlan.verify(signed, runtime, 'v0.9.2');
    expect(plan.appBuild, 12);
    expect(plan.platforms['linux-x64'], hasLength(6));
    await expectLater(
      UpdatePlan.verify(signed, runtime, 'v9.0.0'),
      throwsFormatException,
    );
    await expectLater(
      UpdatePlan.verify(
        await signedIndex(wrongPlatform: 'DevCat-0.9.2-linux-x64.zip'),
        runtime,
        'v0.9.2',
      ),
      throwsFormatException,
    );
    final tampered = jsonDecode(signed)
      ..['payload'] = base64Encode(utf8.encode('{}'));
    await expectLater(
      UpdatePlan.verify(jsonEncode(tampered), runtime, 'v0.9.2'),
      throwsFormatException,
    );
  });

  test(
    'ETag and verified cached index survive restart without another network check',
    () async {
      final index = await signedIndex();
      var requests = 0, releaseRequests = 0;
      server.listen((request) async {
        requests++;
        if (request.uri.path.endsWith('/releases')) {
          releaseRequests++;
          if (releaseRequests == 1) {
            request.response.headers.set(
              HttpHeaders.etagHeader,
              '"release-list"',
            );
            request.response.write(
              jsonEncode([
                {
                  'draft': false,
                  'prerelease': true,
                  'tag_name': 'v0.9.2',
                  'assets': [
                    {'name': 'content-index.json'},
                  ],
                },
              ]),
            );
          } else {
            expect(
              request.headers.value(HttpHeaders.ifNoneMatchHeader),
              '"release-list"',
            );
            request.response.statusCode = 304;
          }
        } else {
          request.response.write(index);
        }
        await request.response.close();
      });
      final service = DesktopUpdates(runtime, createClient: client);
      await service.check();
      expect(service.hasAppUpdate, isTrue);
      expect(service.hasContentUpdate, isTrue);
      await service.check();
      expect(service.phase, 'available');
      service.dispose();
      final restarted = DesktopUpdates(runtime, createClient: client);
      addTearDown(restarted.dispose);
      final before = requests;
      await restarted.check(automatic: true);
      expect(restarted.hasAppUpdate, isTrue);
      expect(requests, before);
      expect(releaseRequests, 2);
    },
  );
  test('Rate limits back off, and stable excludes beta releases', () async {
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.statusCode = 429;
      await request.response.close();
    });
    final service = DesktopUpdates(runtime, createClient: client);
    addTearDown(service.dispose);
    await service.check(beta: false);
    expect(service.phase, 'error');
    await service.check(beta: false);
    expect(requests, 1);
    expect(service.hasAppUpdate, isFalse);
  });

  test('Cache budget removes only older files in its own directory', () async {
    final outside = File('${directory.path}/progress.json');
    await outside.writeAsString('keep');
    final cache = await Directory('${directory.path}/downloads').create();
    final old = File('${cache.path}/old.zip');
    await old.writeAsBytes(List.filled(data.length, 0));
    server.listen((request) async {
      request.response.contentLength = data.length;
      request.response.add(data);
      await request.response.close();
    });
    final download = UpdateDownload(
      cache,
      createClient: client,
      maxCacheBytes: data.length,
    );
    await download.fetch(url, await descriptor());
    expect(await old.exists(), isFalse);
    expect(await outside.readAsString(), 'keep');
  });
}
