import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'content_runtime.dart';
import 'update_download.dart';

class UpdatePlan {
  final String version, notes, channel;
  final int appBuild, contentRevision, contentMinBuild;
  final UpdateFile content;
  final Map<String, List<UpdateFile>> platforms;
  UpdatePlan._(
    this.version,
    this.notes,
    this.channel,
    this.appBuild,
    this.contentRevision,
    this.contentMinBuild,
    this.content,
    this.platforms,
  );
  static Future<UpdatePlan> verify(
    String text,
    ContentRuntime runtime,
    String tag,
  ) async {
    final data = await runtime.verifier.signedPayload(text, limit: 65536);
    final version = data['version'];
    if (data['schemaVersion'] != 1 ||
        data['kind'] != 'devcat-update-index' ||
        version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?$').hasMatch(version) ||
        tag != 'v$version' ||
        data['appBuild'] is! int ||
        data['appBuild'] <= 0 ||
        !['stable', 'beta'].contains(data['channel']) ||
        data['notes'] is! String ||
        (data['notes'] as String).length > 12000) {
      throw const FormatException('Неверное подписанное описание обновления.');
    }
    final content = data['content'] as Map<String, dynamic>;
    if (content['revision'] is! int ||
        content['revision'] <= 0 ||
        content['minAppBuild'] is! int ||
        content['minAppBuild'] < 0) {
      throw const FormatException('Неверная версия учебных данных.');
    }
    final package = UpdateFile.fromJson(content);
    if (package.name != 'DevCat-$version-content.json' ||
        package.bytes > 192 * 1024 * 1024) {
      throw const FormatException('Несовместимый пакет уроков.');
    }
    final platforms = <String, List<UpdateFile>>{};
    for (final entry in (data['platforms'] as Map<String, dynamic>).entries) {
      if (![
        'windows-x64',
        'linux-x64',
        'macos-universal',
      ].contains(entry.key)) {
        throw const FormatException('Неизвестная платформа обновления.');
      }
      final files = (entry.value as List)
          .map((v) => UpdateFile.fromJson(Map<String, dynamic>.from(v)))
          .toList();
      if (files.isEmpty ||
          files.length > 6 ||
          files.any(
            (f) =>
                !f.name.startsWith('DevCat-$version-${entry.key}') ||
                !RegExp(
                  r'\.(exe|zip|dmg|deb|rpm|AppImage|tar\.gz|pkg\.tar\.zst)$',
                ).hasMatch(f.name),
          )) {
        throw const FormatException('Недопустимый установщик.');
      }
      platforms[entry.key] = List.unmodifiable(files);
    }
    if (platforms.length != 3) {
      throw const FormatException('Нет пакетов всех ПК-платформ.');
    }
    return UpdatePlan._(
      version,
      data['notes'],
      data['channel'],
      data['appBuild'],
      content['revision'],
      content['minAppBuild'],
      package,
      Map.unmodifiable(platforms),
    );
  }
}

class DesktopUpdates extends ChangeNotifier {
  static DesktopUpdates? current;
  final ContentRuntime runtime;
  final String owner, repository;
  final HttpClient Function() createClient;
  late final UpdateDownload downloader;
  HttpClient? _metadataClient;
  UpdatePlan? plan;
  String status = 'Обновления проверяются по твоему выбору.', phase = 'idle';
  int received = 0, total = 0;
  bool busy = false, restartRequired = false, _disposed = false;
  DesktopUpdates(
    this.runtime, {
    this.owner = 'PANDORA615',
    this.repository = 'DevCat-',
    HttpClient Function()? createClient,
  }) : createClient = createClient ?? (() => HttpClient()) {
    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(owner) ||
        !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(repository)) {
      throw ArgumentError('Invalid repository');
    }
    downloader = UpdateDownload(
      Directory('${runtime.directory.path}/downloads'),
      createClient: this.createClient,
    );
  }
  String get platform => Platform.isWindows
      ? 'windows-x64'
      : Platform.isMacOS
      ? 'macos-universal'
      : 'linux-x64';
  List<UpdateFile> get appFiles => plan?.platforms[platform] ?? const [];
  bool get hasAppUpdate => (plan?.appBuild ?? 0) > runtime.appBuild;
  bool get hasContentUpdate =>
      (plan?.contentRevision ?? 0) > runtime.revision &&
      (plan?.contentMinBuild ?? 0) <= runtime.appBuild &&
      !restartRequired;
  String get mascotAction => switch (phase) {
    'checking' || 'verifying' || 'installing' => 'thinking',
    'downloading' => 'loading',
    'available' => hasAppUpdate ? 'notification' : 'new',
    'installed' || 'verified' => 'success',
    'error' => 'error',
    'cancelled' => 'waiting',
    _ => 'idle',
  };
  void _show(String nextPhase, String message) {
    if (_disposed) return;
    phase = nextPhase;
    status = message;
    notifyListeners();
  }

  Uri _asset(String version, String name) => Uri.https(
    'github.com',
    '/$owner/$repository/releases/download/v$version/$name',
  );
  void cancel() {
    if (phase == 'installing' || phase == 'verifying') return;
    downloader.cancel();
    _metadataClient?.close(force: true);
    _show('cancelled', 'Загрузка отменена. Можно продолжить позже.');
  }

  Future<({int code, String body, String? etag})> _get(
    Uri uri, {
    String? etag,
    int maxBytes = 524288,
  }) async {
    final client = createClient()
      ..connectionTimeout = const Duration(seconds: 15);
    _metadataClient = client;
    try {
      for (var i = 0; i <= 5; i++) {
        if (uri.scheme != 'https' ||
            !{
              'api.github.com',
              'github.com',
              'release-assets.githubusercontent.com',
              'objects.githubusercontent.com',
            }.contains(uri.host) ||
            uri.userInfo.isNotEmpty ||
            uri.port != 443 ||
            uri.fragment.isNotEmpty) {
          throw const FormatException(
            'Небезопасный адрес описания обновления.',
          );
        }
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 20));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'DevCat-Updater');
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/vnd.github+json',
        );
        if (etag != null) {
          request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
        }
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || i == 5) {
            throw const FormatException('Ошибка адреса обновления.');
          }
          await response.drain<void>().timeout(const Duration(seconds: 15));
          uri = uri.resolve(location);
          continue;
        }
        final builder = BytesBuilder();
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          if (builder.length + chunk.length > maxBytes) {
            throw const FormatException('Описание обновления слишком большое.');
          }
          builder.add(chunk);
        }
        return (
          code: response.statusCode,
          body: utf8.decode(builder.takeBytes()),
          etag: response.headers.value(HttpHeaders.etagHeader),
        );
      }
      throw const FormatException('Слишком много перенаправлений.');
    } finally {
      client.close(force: true);
      if (identical(_metadataClient, client)) _metadataClient = null;
    }
  }

  Future<void> check({bool beta = true, bool automatic = false}) async {
    if (busy || _disposed) return;
    busy = true;
    _show('checking', 'Проверяю, появились ли новые уроки и версия DevCat…');
    final cache = File(
      '${runtime.directory.path}/metadata-${beta ? 'beta' : 'stable'}.json',
    );
    try {
      Map<String, dynamic> saved = {};
      try {
        saved = Map<String, dynamic>.from(
          jsonDecode(await cache.readAsString()),
        );
      } catch (_) {}
      UpdatePlan? cachedPlan;
      String? cachedEnvelope;
      try {
        cachedEnvelope = saved['index'] as String?;
        if (cachedEnvelope != null) {
          cachedPlan = await UpdatePlan.verify(
            cachedEnvelope,
            runtime,
            saved['tag'] as String,
          );
          if (!beta && cachedPlan.channel != 'stable') cachedPlan = null;
        }
      } catch (_) {
        cachedPlan = null;
        cachedEnvelope = null;
      }
      plan = cachedPlan;
      final now = DateTime.now().millisecondsSinceEpoch;
      if ((saved['retryAt'] as int? ?? 0) > now ||
          (automatic && now - (saved['checkedAt'] as int? ?? 0) < 86400000)) {
        _show(
          hasAppUpdate || hasContentUpdate ? 'available' : 'idle',
          hasAppUpdate || hasContentUpdate
              ? 'Есть проверенное обновление. Можно установить его, когда удобно.'
              : 'Проверка уже выполнялась недавно. Попробуй позже.',
        );
        return;
      }
      final response = await _get(
        Uri.https('api.github.com', '/repos/$owner/$repository/releases', {
          'per_page': '10',
        }),
        etag: saved['etag'],
      );
      if (response.code == 403 ||
          response.code == 429 ||
          response.code >= 500) {
        final failures = ((saved['failures'] as int? ?? 0) + 1).clamp(1, 6);
        saved['failures'] = failures;
        saved['retryAt'] =
            now +
            (response.code >= 500 ? 60000 * (1 << (failures - 1)) : 900000);
        await cache.parent.create(recursive: true);
        await cache.writeAsString(jsonEncode(saved), flush: true);
        throw const HttpException('Источник обновлений временно недоступен.');
      }
      final body = response.code == 304
          ? saved['body'] as String?
          : response.body;
      if (![200, 304].contains(response.code) || body == null) {
        throw const HttpException('Не удалось получить список выпусков.');
      }
      final releases = jsonDecode(body) as List;
      UpdatePlan? newest = cachedPlan;
      String? newestEnvelope = cachedEnvelope;
      for (final item in releases) {
        if (item['draft'] == true || (!beta && item['prerelease'] == true)) {
          continue;
        }
        if (!RegExp(
          r'^v\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$',
        ).hasMatch(item['tag_name'] as String? ?? '')) {
          continue;
        }
        final assets = item['assets'] as List;
        if (!assets.any((v) => v['name'] == 'content-index.json')) continue;
        final tag = item['tag_name'] as String;
        final index = await _get(
          _asset(tag.substring(1), 'content-index.json'),
          maxBytes: 65536,
        );
        if (index.code != 200) continue;
        final candidate = await UpdatePlan.verify(index.body, runtime, tag);
        if (!beta && candidate.channel != 'stable') continue;
        if (newest == null ||
            candidate.appBuild > newest.appBuild ||
            (candidate.appBuild == newest.appBuild &&
                candidate.contentRevision > newest.contentRevision)) {
          newest = candidate;
          newestEnvelope = index.body;
        }
      }
      plan = newest;
      await cache.parent.create(recursive: true);
      await cache.writeAsString(
        jsonEncode({
          'body': body,
          'etag': response.etag ?? saved['etag'],
          'checkedAt': now,
          if (newest != null && newestEnvelope != null) 'index': newestEnvelope,
          if (newest != null) 'tag': 'v${newest.version}',
        }),
        flush: true,
      );
      _show(
        hasAppUpdate || hasContentUpdate ? 'available' : 'idle',
        hasAppUpdate || hasContentUpdate
            ? 'Есть обновление. Его можно установить, когда тебе удобно.'
            : 'Доступных обновлений нет. Можно продолжать учиться.',
      );
    } catch (error) {
      _error(error);
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _error(Object error) {
    if (phase == 'cancelled' || error is UpdateCancelled || _disposed) return;
    _show(
      'error',
      error is FormatException
          ? error.message.toString()
          : 'Не удалось получить обновление. Уроки и прогресс остаются доступны. Попробуй позже.',
    );
  }

  Future<File?> downloadApp(UpdateFile file) async {
    if (busy ||
        !hasAppUpdate ||
        !appFiles.any((v) => v.name == file.name && v.sha256 == file.sha256)) {
      return null;
    }
    busy = true;
    received = 0;
    total = file.bytes;
    _show(
      'downloading',
      'Скачиваю новую версию. Устанавливать её сейчас необязательно.',
    );
    try {
      final result = await downloader.fetch(
        _asset(plan!.version, file.name),
        file,
        onProgress: _progress,
      );
      _show(
        'verified',
        'Файл проверен. Перед установкой сохрани проекты и заверши запущенный код.',
      );
      return result;
    } catch (error) {
      _error(error);
      return null;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _progress(int value, int limit) {
    if (_disposed) return;
    received = value;
    total = limit;
    notifyListeners();
  }

  Future<void> installContent() async {
    if (busy || !hasContentUpdate) return;
    busy = true;
    received = 0;
    total = plan!.content.bytes;
    _show(
      'downloading',
      'Скачиваю новые уроки. Текущий урок можно закончить без изменений.',
    );
    try {
      final file = await downloader.fetch(
        _asset(plan!.version, plan!.content.name),
        plan!.content,
        onProgress: _progress,
      );
      await _applyContent(file, expectedRevision: plan!.contentRevision);
    } catch (error) {
      _error(error);
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> importContent(File file) async {
    if (busy || restartRequired || _disposed) return;
    busy = true;
    try {
      await _applyContent(file);
    } catch (error) {
      _error(error);
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _applyContent(File file, {int? expectedRevision}) async {
    _show('verifying', 'Проверяю новые уроки перед установкой…');
    final checked = await runtime.validateFile(file.path);
    if (_disposed) return;
    if (expectedRevision != null && checked.revision != expectedRevision) {
      throw const FormatException(
        'Версия уроков не совпадает с описанием выпуска.',
      );
    }
    _show('installing', 'Сохраняю проверенное обновление…');
    await runtime.install(checked);
    restartRequired = true;
    _show(
      'installed',
      'Обновление сохранено. Оно появится после следующего запуска DevCat.',
    );
  }

  Future<void> rollback() async {
    if (busy || restartRequired || _disposed) return;
    busy = true;
    try {
      if (await runtime.store.rollback()) {
        restartRequired = true;
        _show(
          'installed',
          'Выбрана предыдущая версия уроков. Перезапусти DevCat, когда закончишь занятие.',
        );
      } else {
        _show(
          'idle',
          'Предыдущего обновления пока нет. Встроенные уроки всегда доступны.',
        );
      }
    } catch (error) {
      _error(error);
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    downloader.cancel();
    _metadataClient?.close(force: true);
    super.dispose();
  }
}
