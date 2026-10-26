import 'dart:convert';
import 'dart:io';
import 'package:devcat/core/progress.dart';
import 'package:devcat/core/sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WebDAV rejects cleartext, credentials in URL and queries', () {
    for (final u in [
      'http://example.org/',
      'https://u:p@example.org/',
      'https://example.org/?token=x',
    ]) {
      expect(() => SyncClient.endpoint(u), throwsFormatException);
    }
  });
  test(
    'Real HTTPS WebDAV retries stale ETag and merges both devices',
    () async {
      final dir = await Directory.systemTemp.createTemp('devcat-tls');
      addTearDown(() => dir.delete(recursive: true));
      final cert = '${dir.path}/cert.pem', key = '${dir.path}/key.pem';
      final generated = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        key,
        '-out',
        cert,
        '-days',
        '1',
        '-subj',
        '/CN=localhost',
        '-addext',
        'subjectAltName=IP:127.0.0.1',
      ]);
      expect(generated.exitCode, 0);
      final context = SecurityContext()
        ..useCertificateChain(cert)
        ..usePrivateKey(key);
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      addTearDown(() => server.close(force: true));
      var remote = ProgressData()..attempt('sql.basics', 'sql', true);
      var revision = 1, gets = 0, puts = 0;
      final phone = ProgressData()
        ..draft('python.loops', 'phone edit', 'phone');
      server.listen((req) async {
        expect(
          req.headers.value('authorization'),
          'Basic ${base64Encode(utf8.encode('student:app-password'))}',
        );
        if (req.method == 'GET') {
          gets++;
          req.response.headers.set('ETag', '"$revision"');
          req.response.write(remote.encode());
          await req.response.close();
          if (gets == 1) {
            remote = remote.merge(phone);
            revision++;
          }
        } else {
          puts++;
          final body = await utf8.decoder.bind(req).join();
          if (req.headers.value('if-match') != '"$revision"') {
            req.response.statusCode = 412;
          } else {
            remote = ProgressData.decode(body);
            revision++;
            req.response.statusCode = 204;
          }
          await req.response.close();
        }
      });
      var local = ProgressData()
        ..attempt('python.loops', 'python', true)
        ..draft('python.loops', 'desktop edit', 'desktop');
      final http = HttpClient(
        context: SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates(cert),
      );
      await SyncClient(client: http).synchronize(
        'https://127.0.0.1:${server.port}/',
        'student',
        'app-password',
        () async => local,
        (p) async {
          local = local.merge(p);
        },
      );
      expect(gets, 2);
      expect(puts, 2);
      expect(local.solved, {'python.loops', 'sql.basics'});
      expect(remote.solved, local.solved);
      expect(remote.draftsFor('python.loops').length, 2);
    },
  );
}
