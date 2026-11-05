import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

/// Only instances produced by signature verification can reach the installer.
class VerifiedContent {
  final int revision;
  final Map<String, Uint8List> files;
  final String envelope;
  VerifiedContent._(this.revision, this.files, this.envelope);
}

/// Signature covers exact decoded payload bytes, never reserialized JSON.
class ContentVerifier {
  final Map<String, SimplePublicKey> keys;
  final int appBuild;
  static const maxPackageBytes = 96 * 1024 * 1024;
  ContentVerifier(Map<String, List<int>> trustedKeys, {required this.appBuild})
    : keys = Map.unmodifiable(
        trustedKeys.map(
          (id, bytes) => MapEntry(
            id,
            SimplePublicKey(
              List.unmodifiable(bytes),
              type: KeyPairType.ed25519,
            ),
          ),
        ),
      );

  Future<VerifiedContent> verify(String envelope) async {
    if (utf8.encode(envelope).length > maxPackageBytes) {
      throw const FormatException('Пакет превышает допустимый размер.');
    }
    final outer = jsonDecode(envelope) as Map<String, dynamic>;
    final key = keys[outer['keyId']];
    if (key == null) {
      throw const FormatException('Неизвестный ключ обновления.');
    }
    final payload = base64Decode(outer['payload'] as String);
    final signature = Signature(
      base64Decode(outer['signature'] as String),
      publicKey: key,
    );
    if (!await Ed25519().verify(payload, signature: signature)) {
      throw const FormatException('Подпись обновления не прошла проверку.');
    }
    final data = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    if (data['schemaVersion'] != 1 ||
        data['kind'] != 'devcat-content' ||
        data['revision'] is! int ||
        data['revision'] <= 0 ||
        data['minAppBuild'] is! int ||
        data['minAppBuild'] > appBuild ||
        data['minAppBuild'] < 0) {
      throw const FormatException('Несовместимый пакет обновления.');
    }
    final entries = data['files'] as List;
    if (entries.isEmpty || entries.length > 4096) {
      throw const FormatException('Недопустимое количество файлов.');
    }
    final files = <String, Uint8List>{}, names = <String>{};
    var total = 0;
    for (final raw in entries) {
      final entry = raw as Map<String, dynamic>;
      final name = entry['path'] as String;
      // Flat data-only namespace. No executables, archives, symlinks or scripts.
      if (!RegExp(
            r'^assets/content/[a-zA-Z0-9][a-zA-Z0-9_.-]*\.(json|png|jpg|jpeg)$',
          ).hasMatch(name) ||
          name.contains('..') ||
          !names.add(name.toLowerCase())) {
        throw const FormatException('Недопустимый или повторяющийся путь.');
      }
      final bytes = base64Decode(entry['data'] as String);
      total += bytes.length;
      if (total > maxPackageBytes || bytes.length != entry['size']) {
        throw const FormatException('Неверный размер содержимого.');
      }
      final digest = (await Sha256().hash(
        bytes,
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (digest != entry['sha256']) {
        throw const FormatException('Повреждён файл обновления.');
      }
      if (name.endsWith('.json')) jsonDecode(utf8.decode(bytes));
      files[name] = bytes.asUnmodifiableView();
    }
    return VerifiedContent._(
      data['revision'],
      Map.unmodifiable(files),
      envelope,
    );
  }
}

/// Two pointer slots preserve the last valid snapshot across interrupted writes.
/// The caller validates curriculum schemas before installing or activating it.
class ContentUpdateStore {
  final Directory directory;
  final ContentVerifier verifier;
  bool _busy = false;
  ContentUpdateStore(this.directory, this.verifier);

  Future<List<({int sequence, int revision, int slot})>> _pointers() async {
    final result = <({int sequence, int revision, int slot})>[];
    for (var slot = 0; slot < 2; slot++) {
      try {
        final data = jsonDecode(
          await File(
            p.join(directory.path, 'active-$slot.json'),
          ).readAsString(),
        );
        if (data['sequence'] is int &&
            data['sequence'] > 0 &&
            data['revision'] is int &&
            data['revision'] > 0) {
          result.add((
            sequence: data['sequence'] as int,
            revision: data['revision'] as int,
            slot: slot,
          ));
        }
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return result..sort((a, b) => b.sequence.compareTo(a.sequence));
  }

  File _manifest(int revision) =>
      File(p.join(directory.path, 'versions', '$revision', 'signed.json'));

  Future<VerifiedContent> _readSnapshot(int revision) async {
    final content = await verifier.verify(
      await _manifest(revision).readAsString(),
    );
    if (content.revision != revision) {
      throw const FormatException('Неверная версия снимка.');
    }
    for (final entry in content.files.entries) {
      final bytes = await File(
        p.join(directory.path, 'versions', '${content.revision}', entry.key),
      ).readAsBytes();
      if (!const ListEqualityBytes().equals(bytes, entry.value)) {
        throw const FormatException('Снимок повреждён.');
      }
    }
    return content;
  }

  Future<VerifiedContent?> active() async {
    for (final pointer in await _pointers()) {
      try {
        return await _readSnapshot(pointer.revision);
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return null;
  }

  Future<void> _activate(int revision) async {
    final pointers = await _pointers();
    final newest = pointers.isEmpty ? null : pointers.first;
    final slot = newest == null ? 0 : 1 - newest.slot;
    final target = File(p.join(directory.path, 'active-$slot.json'));
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'sequence': (newest?.sequence ?? 0) + 1,
        'revision': revision,
      }),
      flush: true,
    );
    // Windows cannot replace an existing destination. The other slot remains valid.
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
  }

  Future<void> install(VerifiedContent content) async {
    if (_busy) throw StateError('Установка уже выполняется.');
    _busy = true;
    final staging = Directory(p.join(directory.path, 'staging'));
    try {
      content = await verifier.verify(content.envelope);
      await directory.create(recursive: true);
      final versions = Directory(p.join(directory.path, 'versions'));
      await versions.create(recursive: true);
      await for (final item in versions.list()) {
        final previous = int.tryParse(p.basename(item.path));
        if (previous != null && previous > content.revision) {
          throw const FormatException(
            'Эта или более новая версия уже установлена.',
          );
        }
      }
      if (await _manifest(content.revision).exists()) {
        await _readSnapshot(content.revision);
        if ((await active())?.revision != content.revision) {
          await _activate(content.revision);
        }
        await _prune();
        return;
      }
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create();
      for (final entry in content.files.entries) {
        final file = File(p.join(staging.path, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
      await File(
        p.join(staging.path, 'signed.json'),
      ).writeAsString(content.envelope, flush: true);
      await staging.rename(p.join(versions.path, '${content.revision}'));
      await _activate(content.revision);
      await _prune();
    } finally {
      _busy = false;
    }
  }

  Future<void> _prune() async {
    final keep = (await _pointers()).map((v) => v.revision).toSet();
    await for (final item in Directory(
      p.join(directory.path, 'versions'),
    ).list()) {
      final revision = int.tryParse(p.basename(item.path));
      if (revision != null && !keep.contains(revision)) {
        try {
          await item.delete(recursive: true);
        } on FileSystemException {
          // Cleanup failure must not undo an already activated snapshot.
        }
      }
    }
  }

  Future<bool> rollback() async {
    if (_busy) throw StateError('Установка уже выполняется.');
    _busy = true;
    try {
      final pointers = await _pointers();
      if (pointers.length < 2 || pointers[0].revision == pointers[1].revision) {
        return false;
      }
      final previous = await _readSnapshot(pointers[1].revision);
      await _activate(previous.revision);
      return true;
    } finally {
      _busy = false;
    }
  }
}

class ListEqualityBytes {
  const ListEqualityBytes();
  bool equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
