import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'app_version.dart';
import 'course.dart';
import 'store.dart';
import 'update_transfer.dart';
export 'update_transfer.dart';

/// Strict semantic version ordering, including prerelease identifiers.
class AppVersion implements Comparable<AppVersion> {
  final List<int> numbers;
  final List<String> prerelease;
  AppVersion(String value) : numbers = [], prerelease = [] {
    final match = RegExp(
      r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
    ).firstMatch(value);
    if (match == null) throw const FormatException('Неверная версия');
    numbers.addAll([
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    ]);
    if (match[4] != null) {
      prerelease.addAll(match[4]!.split('.'));
      if (prerelease.any(
        (p) =>
            p.isEmpty ||
            (RegExp(r'^\d+$').hasMatch(p) && p.length > 1 && p.startsWith('0')),
      )) {
        throw const FormatException('Неверный prerelease');
      }
    }
  }
  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final c = numbers[i].compareTo(other.numbers[i]);
      if (c != 0) return c;
    }
    if (prerelease.isEmpty || other.prerelease.isEmpty) {
      return prerelease.isEmpty ? (other.prerelease.isEmpty ? 0 : 1) : -1;
    }
    for (var i = 0; i < prerelease.length && i < other.prerelease.length; i++) {
      final a = prerelease[i], b = other.prerelease[i];
      final an = int.tryParse(a), bn = int.tryParse(b);
      final c = an != null && bn != null
          ? an.compareTo(bn)
          : an != null
          ? -1
          : bn != null
          ? 1
          : a.compareTo(b);
      if (c != 0) return c;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }
}

class UpdateArtifact {
  final Uri url;
  final int size;
  final String sha256;
  UpdateArtifact(Map<String, dynamic> j)
    : url = Uri.parse(j['url']),
      size = j['size'],
      sha256 = j['sha256'] {
    if (url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        size <= 0 ||
        size > 2 * 1024 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Неверный артефакт обновления');
    }
  }
}

class VerifiedUpdate {
  final String version, notes, channel;
  final UpdateArtifact? content;
  final Map<String, UpdateArtifact> platforms;
  VerifiedUpdate(Map<String, dynamic> j, String expectedChannel)
    : version = j['version'],
      notes = j['releaseNotes'] ?? '',
      channel = j['channel'],
      content = j['content'] == null
          ? null
          : UpdateArtifact(Map<String, dynamic>.from(j['content'])),
      platforms = {
        for (final e in ((j['platforms'] as Map?) ?? {}).entries)
          e.key: UpdateArtifact(Map<String, dynamic>.from(e.value)),
      } {
    if (j['schemaVersion'] != 1 ||
        channel != expectedChannel ||
        !['stable', 'beta'].contains(channel)) {
      throw const FormatException(
        'Неподдерживаемый канал или схема обновления',
      );
    }
    AppVersion(version);
    if (channel == 'stable' && AppVersion(version).prerelease.isNotEmpty) {
      throw const FormatException('Prerelease в stable');
    }
    if (AppVersion(
          appVersion,
        ).compareTo(AppVersion(j['minSupportedAppVersion'])) <
        0) {
      throw const FormatException('Сначала обнови приложение через установщик');
    }
  }
}

/// Exact decoded payload bytes are signed, so JSON key ordering is irrelevant.
/// The trust key is pinned in the application build, never taken from a release.
class UpdateService {
  static const pinnedKey = String.fromEnvironment('DEVCAT_UPDATE_PUBLIC_KEY');
  final String publicKey;
  final HttpClient client;
  UpdateService({this.publicKey = pinnedKey, HttpClient? client})
    : client = client ?? HttpClient();
  final _operations = <UpdateCancellation>{};
  bool _installing = false, _disposed = false;
  bool get configured => publicKey.isNotEmpty;
  Future<VerifiedUpdate> verifyEnvelope(String raw, String channel) async {
    if (!configured) {
      throw StateError('В сборке не задан публичный ключ обновлений');
    }
    if (utf8.encode(raw).length > 128 * 1024) {
      throw const FormatException('Слишком большой манифест');
    }
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    final bytes = base64Decode(envelope['payload']);
    final key = base64Decode(publicKey),
        signature = base64Decode(envelope['signature']);
    if (key.length != 32 ||
        signature.length != 64 ||
        !await Ed25519().verify(
          bytes,
          signature: Signature(
            signature,
            publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
          ),
        )) {
      throw const FormatException('Подпись обновления не прошла проверку');
    }
    return VerifiedUpdate(
      Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes))),
      channel,
    );
  }

  Future<VerifiedUpdate> check({
    required String owner,
    required String repo,
    required String channel,
    UpdateCancellation? cancellation,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(owner) ||
        !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(repo)) {
      throw const FormatException('Неверный репозиторий');
    }
    final url = Uri.https(
      'github.com',
      '/$owner/$repo/releases/${channel == 'stable' ? 'latest/download' : 'download/beta'}/devcat-update.json',
    );
    final bytes = await _read(url, 128 * 1024, cancellation: cancellation);
    return verifyEnvelope(utf8.decode(bytes), channel);
  }

  Future<List<int>> _read(
    Uri url,
    int limit, {
    UpdateCancellation? cancellation,
    int? expectedSize,
    UpdateProgressCallback? onProgress,
  }) async {
    if (_disposed) throw StateError('Сервис обновлений закрыт');
    final token = cancellation ?? UpdateCancellation();
    final ownsToken = _operations.add(token);
    try {
      return await readUpdateBytes(
        client,
        url,
        limit,
        cancellation: token,
        expectedSize: expectedSize,
        onProgress: onProgress,
      );
    } finally {
      if (ownsToken) _operations.remove(token);
    }
  }

  Future<void> installContent(
    VerifiedUpdate update,
    AppStore store, {
    UpdateCancellation? cancellation,
    UpdateProgressCallback? onProgress,
  }) async {
    if (_disposed) throw StateError('Сервис обновлений закрыт');
    if (_installing) throw StateError('Обновление уже загружается');
    _installing = true;
    final token = cancellation ?? UpdateCancellation();
    _operations.add(token);
    try {
      await _installContent(update, store, token, onProgress);
    } finally {
      _operations.remove(token);
      _installing = false;
    }
  }

  Future<void> _installContent(
    VerifiedUpdate update,
    AppStore store,
    UpdateCancellation token,
    UpdateProgressCallback? onProgress,
  ) async {
    token.throwIfCancelled();
    final artifact = update.content;
    if (artifact == null || artifact.size > 32 * 1024 * 1024) {
      throw const FormatException('Нет допустимого обновления курсов');
    }
    final current = store.setting('contentUpdateActive', appVersion);
    if (AppVersion(update.version).compareTo(AppVersion(current)) <= 0) {
      throw const FormatException(
        'Эта версия контента уже установлена или устарела',
      );
    }
    final bytes = await _read(
      artifact.url,
      artifact.size,
      cancellation: token,
      expectedSize: artifact.size,
      onProgress: onProgress,
    );
    final digest = (await Sha256().hash(
      bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (bytes.length != artifact.size || digest != artifact.sha256) {
      throw const FormatException('Размер или SHA-256 контента не совпали');
    }
    token.throwIfCancelled();
    validateCourses(utf8.decode(bytes));
    final base = Directory('${store.directory.path}/updates');
    await base.create(recursive: true);
    // A unique staging directory keeps interrupted downloads away from active data.
    token.throwIfCancelled();
    final staging = await base.createTemp('.staging-');
    try {
      token.throwIfCancelled();
      await File(
        '${staging.path}/courses.json',
      ).writeAsBytes(bytes, flush: true);
      token.throwIfCancelled();
      final target = Directory('${base.path}/${update.version}');
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);
      token.throwIfCancelled();
      // Once this settings transaction starts, it either commits or reverts.
      final previous = store.setting<String?>('contentUpdateActive', null);
      await store.updateSettings({
        'contentUpdatePrevious': previous,
        'contentUpdatePreviousSha256': store.setting<String?>(
          'contentUpdateSha256',
          null,
        ),
        'contentUpdateActive': update.version,
        'contentUpdateSha256': artifact.sha256,
      });
      // Keep the active and last-known-good data only; cache cleanup is optional.
      try {
        await for (final entry in base.list(followLinks: false)) {
          final name = entry.uri.pathSegments.where((p) => p.isNotEmpty).last;
          if (entry is Directory &&
              name != update.version &&
              name != previous &&
              RegExp(
                r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]+)?$',
              ).hasMatch(name)) {
            await entry.delete(recursive: true);
          }
        }
      } catch (_) {
        /* An optional cache cleanup cannot undo an installed update. */
      }
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  static void validateCourses(String text) {
    final list = jsonDecode(text);
    if (list is! List || list.isEmpty || list.length > 100) {
      throw const FormatException('Неверный каталог курсов');
    }
    final previous = Map.of(coursePracticeBank);
    try {
      final courses = list
          .map((j) => Course(Map<String, dynamic>.from(j)))
          .toList();
      final ids = courses.map((c) => c.id).toSet();
      if (!ids.containsAll(languageNames.keys) ||
          ids.length != courses.length ||
          courses.any((c) => c.lessons.isEmpty)) {
        throw const FormatException('Пустые или повторные курсы');
      }
    } finally {
      coursePracticeBank
        ..clear()
        ..addAll(previous);
    }
  }

  static Future<String?> activeContent(AppStore store) async {
    final version = store.setting<String?>('contentUpdateActive', null);
    if (version == null) return null;
    try {
      AppVersion(version);
      if (!RegExp(r'^[0-9A-Za-z.+-]+$').hasMatch(version)) return null;
      final text = await File(
        '${store.directory.path}/updates/$version/courses.json',
      ).readAsString();
      final digest = (await Sha256().hash(
        utf8.encode(text),
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (digest != store.setting<String?>('contentUpdateSha256', null)) {
        throw const FormatException('Контент повреждён');
      }
      validateCourses(text);
      return text;
    } catch (_) {
      try {
        await rollback(store);
      } catch (_) {
        return null;
      }
      return store.setting<String?>('contentUpdateActive', null) == null
          ? null
          : activeContent(store);
    }
  }

  static Future<void> rollback(AppStore store) async {
    await store.updateSettings({
      'contentUpdateActive': store.setting<String?>(
        'contentUpdatePrevious',
        null,
      ),
      'contentUpdateSha256': store.setting<String?>(
        'contentUpdatePreviousSha256',
        null,
      ),
      'contentUpdatePrevious': null,
      'contentUpdatePreviousSha256': null,
    });
  }

  void dispose() {
    _disposed = true;
    for (final token in _operations) {
      token.cancel();
    }
    client.close(force: true);
  }
}
