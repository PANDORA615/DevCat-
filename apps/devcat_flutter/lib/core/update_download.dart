import 'dart:async';
import 'dart:io';
import 'package:cryptography/cryptography.dart';

class UpdateCancelled implements Exception {}

class UpdateFile {
  final String name, sha256;
  final int bytes;
  UpdateFile(this.name, this.sha256, this.bytes) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,149}$').hasMatch(name) ||
        name.contains('..') ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
        bytes <= 0 ||
        bytes >= 2 * 1024 * 1024 * 1024) {
      throw const FormatException('Неверное описание файла обновления.');
    }
  }
  factory UpdateFile.fromJson(Map<String, dynamic> data) =>
      UpdateFile(data['name'], data['sha256'], data['bytes']);
}

/// Downloads into a private cache; no file is opened before its signed hash matches.
class UpdateDownload {
  final Directory directory;
  final Set<String> allowedHosts;
  final int maxCacheBytes;
  final HttpClient Function() createClient;
  HttpClient? _client;
  bool _cancelled = false, _busy = false;
  UpdateDownload(
    this.directory, {
    this.maxCacheBytes = 3 * 1024 * 1024 * 1024,
    this.allowedHosts = const {
      'github.com',
      'objects.githubusercontent.com',
      'release-assets.githubusercontent.com',
    },
    HttpClient Function()? createClient,
  }) : createClient = createClient ?? (() => HttpClient());

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  void _check() {
    if (_cancelled) throw UpdateCancelled();
  }

  void _validateUri(Uri uri) {
    if (uri.scheme != 'https' ||
        !allowedHosts.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('Недопустимый адрес обновления.');
    }
  }

  Future<void> _reserveCache(
    int additionalBytes, {
    required Set<String> keep,
  }) async {
    final candidates = <({File file, int bytes, DateTime modified})>[];
    var total = 0;
    await for (final item in directory.list(followLinks: false)) {
      if (item is! File) continue;
      final stat = await item.stat();
      total += stat.size;
      if (!keep.contains(item.path)) {
        candidates.add((file: item, bytes: stat.size, modified: stat.modified));
      }
    }
    candidates.sort((a, b) => a.modified.compareTo(b.modified));
    for (final item in candidates) {
      if (total + additionalBytes <= maxCacheBytes) break;
      _check();
      await item.file.delete();
      total -= item.bytes;
    }
    if (total + additionalBytes > maxCacheBytes) {
      throw const FormatException('Недостаточно места в кэше обновлений.');
    }
  }

  Future<File> fetch(
    Uri uri,
    UpdateFile file, {
    void Function(int, int)? onProgress,
  }) async {
    if (_busy) throw StateError('Другая загрузка уже выполняется.');
    _busy = true;
    _cancelled = false;
    IOSink? sink;
    try {
      _validateUri(uri);
      await directory.create(recursive: true);
      final target = File(
        '${directory.path}${Platform.pathSeparator}${file.name}',
      );
      Future<bool> valid(File candidate) async {
        if (!await candidate.exists() ||
            await candidate.length() != file.bytes) {
          return false;
        }
        final hash = await updateFileSha256(candidate, onChunk: _check);
        _check();
        return hash == file.sha256;
      }

      if (await valid(target)) {
        onProgress?.call(file.bytes, file.bytes);
        return target;
      }
      if (await target.exists()) await target.delete();
      final part = File(
        '${directory.path}${Platform.pathSeparator}${file.sha256}.part',
      );
      var offset = await part.exists() ? await part.length() : 0;
      if (offset > file.bytes) {
        await part.delete();
        offset = 0;
      }
      await _reserveCache(file.bytes - offset, keep: {part.path, target.path});
      if (offset < file.bytes) {
        final client = createClient()
          ..connectionTimeout = const Duration(seconds: 15)
          ..autoUncompress = false;
        _client = client;
        HttpClientResponse? response;
        for (var redirects = 0; redirects <= 5; redirects++) {
          _check();
          _validateUri(uri);
          final request = await client
              .getUrl(uri)
              .timeout(const Duration(seconds: 20));
          request.followRedirects = false;
          request.headers.set(HttpHeaders.userAgentHeader, 'DevCat-Updater');
          request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
          if (offset > 0) {
            request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
          }
          response = await request.close().timeout(const Duration(seconds: 30));
          if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
            final location = response.headers.value(HttpHeaders.locationHeader);
            if (location == null || redirects == 5) {
              throw const FormatException('Ошибка перенаправления обновления.');
            }
            final next = uri.resolve(location);
            _validateUri(next);
            await response.drain<void>().timeout(const Duration(seconds: 15));
            uri = next;
            continue;
          }
          break;
        }
        final result = response!;
        if (result.statusCode == 200) {
          offset = 0;
        } else if (result.statusCode == 206 && offset > 0) {
          final range =
              result.headers.value(HttpHeaders.contentRangeHeader) ?? '';
          final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range);
          if (match == null ||
              int.parse(match[1]!) != offset ||
              int.parse(match[2]!) != file.bytes - 1 ||
              int.parse(match[3]!) != file.bytes) {
            throw const FormatException('Сервер вернул неверную часть файла.');
          }
        } else {
          throw HttpException('Загрузка недоступна: HTTP ${result.statusCode}');
        }
        if (result.contentLength >= 0 &&
            result.contentLength != file.bytes - offset) {
          throw const FormatException(
            'Размер загрузки не совпадает с подписанным описанием.',
          );
        }
        sink = part.openWrite(
          mode: offset > 0 ? FileMode.append : FileMode.write,
        );
        var received = offset;
        final clock = Stopwatch()..start();
        var emittedAt = -100;
        await sink.addStream(
          result.timeout(const Duration(seconds: 30)).map((chunk) {
            _check();
            received += chunk.length;
            if (received > file.bytes) {
              throw const FormatException(
                'Загрузка превысила ожидаемый размер.',
              );
            }
            if (clock.elapsedMilliseconds - emittedAt >= 100) {
              emittedAt = clock.elapsedMilliseconds;
              onProgress?.call(received, file.bytes);
            }
            return chunk;
          }),
        );
        await sink.flush();
        await sink.close();
        sink = null;
      }
      _check();
      if (!await valid(part)) {
        if (await part.exists()) await part.delete();
        throw const FormatException('Файл не прошёл проверку целостности.');
      }
      await part.rename(target.path);
      onProgress?.call(file.bytes, file.bytes);
      return target;
    } catch (error) {
      if (_cancelled) throw UpdateCancelled();
      rethrow;
    } finally {
      await sink?.close();
      _client?.close(force: true);
      _client = null;
      _busy = false;
    }
  }
}

Future<String> updateFileSha256(File file, {void Function()? onChunk}) async {
  final sink = Sha256().newHashSink();
  try {
    await for (final chunk in file.openRead()) {
      onChunk?.call();
      sink.add(chunk);
    }
  } finally {
    sink.close();
  }
  return (await sink.hash()).bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}
