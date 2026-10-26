import 'dart:convert';
import 'dart:io';
import 'progress.dart';

class SyncClient {
  static Uri endpoint(String base) {
    final uri = Uri.parse(base.trim());
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Нужен HTTPS URL папки WebDAV без пароля, query и fragment.',
      );
    }
    return uri.replace(
      path:
          '${uri.path.endsWith('/') ? uri.path : '${uri.path}/'}devcat-progress-v1.json',
    );
  }

  final HttpClient client;
  SyncClient({HttpClient? client}) : client = client ?? HttpClient() {
    this.client.connectionTimeout = const Duration(seconds: 15);
  }
  Future<({int status, String body, String? etag})> _request(
    String method,
    Uri uri,
    String auth, {
    String? body,
    String? etag,
    bool create = false,
  }) async {
    final req = await client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 20));
    req.followRedirects =
        false; // Do not forward Basic credentials to another host.
    req.headers.set(HttpHeaders.authorizationHeader, auth);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (etag != null) req.headers.set(HttpHeaders.ifMatchHeader, etag);
    if (create) req.headers.set(HttpHeaders.ifNoneMatchHeader, '*');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(body));
    }
    final response = await req.close().timeout(const Duration(seconds: 25));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 25))) {
      bytes.addAll(chunk);
      if (bytes.length > 5 * 1024 * 1024) {
        throw const FormatException('Ответ синхронизации превышает 5 МиБ.');
      }
    }
    return (
      status: response.statusCode,
      body: utf8.decode(bytes),
      etag: response.headers.value(HttpHeaders.etagHeader),
    );
  }

  Future<ProgressData> synchronize(
    String base,
    String user,
    String password,
    Future<ProgressData> Function() local,
    Future<void> Function(ProgressData) persist,
  ) async {
    final uri = endpoint(base);
    final auth = 'Basic ${base64Encode(utf8.encode('$user:$password'))}';
    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        final remote = await _request('GET', uri, auth);
        if (remote.status != 200 && remote.status != 404) {
          throw HttpException(
            'WebDAV GET: HTTP ${remote.status}. Проверь URL, доступ к папке и пароль приложения.',
          );
        }
        if (remote.status == 200 &&
            (remote.etag == null || remote.etag!.startsWith('W/'))) {
          throw const FormatException(
            'WebDAV должен возвращать сильный ETag: небезопасная перезапись отменена.',
          );
        }
        final merged = (await local()).merge(
          remote.status == 404
              ? ProgressData()
              : ProgressData.decode(remote.body),
        );
        await persist(
          merged,
        ); // Download is durable before upload; no progress lost on disconnect.
        final encoded = merged.encode();
        if (utf8.encode(encoded).length > 5 * 1024 * 1024) {
          throw const FormatException(
            'Прогресс превышает 5 МиБ. Сначала экспортируй резервную копию.',
          );
        }
        final write = await _request(
          'PUT',
          uri,
          auth,
          body: encoded,
          etag: remote.etag,
          create: remote.status == 404,
        );
        if ([200, 201, 204].contains(write.status)) return merged;
        if (write.status != 412) {
          throw HttpException('WebDAV PUT: HTTP ${write.status}.');
        }
      }
      throw const HttpException(
        'Хранилище меняется одновременно. Повтори синхронизацию.',
      );
    } finally {
      client.close(force: true);
    }
  }
}
