import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'progress.dart';
import 'store.dart';

/// The QR is a short-lived bearer secret. Only AES-GCM ciphertext crosses LAN.
/// No discovery broadcast, cloud service, account or credentials are involved.
class NearbySync {
  static const maxBytes = 8 * 1024 * 1024;
  static final cipher = AesGcm.with256bits();
  HttpServer? _server;
  Timer? _expiry;
  final Set<String> _seen = {};
  final AppStore store;
  final void Function(String)? onStatus;
  late SecretKey _key;
  late String _session;
  String? connectionCode;
  DateTime? expiresAt;
  int _failures = 0;
  NearbySync(this.store, {this.onStatus});

  static bool privateAddress(String host) {
    final ip = InternetAddress.tryParse(host);
    if (ip == null || ip.type != InternetAddressType.IPv4) return false;
    final b = ip.rawAddress;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        b[0] == 127;
  }

  static Map<String, dynamic> parseCode(String text) {
    final code = text.trim();
    if (!code.startsWith('devcat1.') || code.length > 4096) {
      throw const FormatException('Это не код подключения DevCat.');
    }
    final data = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(code.substring(8)))),
    );
    if (data is! Map ||
        data['port'] is! int ||
        data['port'] < 1 ||
        data['port'] > 65535 ||
        data['host'] is! String ||
        !privateAddress(data['host']) ||
        data['key'] is! String ||
        base64Url.decode(data['key']).length != 32 ||
        data['session'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(data['session']) ||
        data['expires'] is! int) {
      throw const FormatException('Повреждён код локального подключения.');
    }
    if (DateTime.now().millisecondsSinceEpoch > data['expires']) {
      throw const FormatException(
        'Код истёк. Создай новый на первом устройстве.',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  Future<String> start({String? address}) async {
    await close();
    _seen.clear();
    _failures = 0;
    String? host = address;
    if (host == null) {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final addresses = interfaces
          .expand((i) => i.addresses)
          .where((a) => privateAddress(a.address) && !a.isLoopback)
          .toList();
      if (addresses.isEmpty) {
        throw const SocketException(
          'Подключи устройства к одной Wi-Fi сети. Локальный адрес не найден.',
        );
      }
      host = addresses.first.address;
    }
    if (!privateAddress(host)) {
      throw const FormatException('Разрешён только адрес локальной сети.');
    }
    _key = await cipher.newSecretKey();
    _session = newId();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    expiresAt = DateTime.now().add(const Duration(minutes: 5));
    connectionCode =
        'devcat1.${base64Url.encode(utf8.encode(jsonEncode({'host': host, 'port': server.port, 'key': base64Url.encode(await _key.extractBytes()), 'session': _session, 'expires': expiresAt!.millisecondsSinceEpoch})))}';
    _expiry = Timer(const Duration(minutes: 5), () {
      close();
      onStatus?.call('Код истёк. Создай новый для подключения.');
    });
    server.listen((req) => unawaited(_serve(req)));
    return connectionCode!;
  }

  static Future<String> _read(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final part in stream.timeout(const Duration(seconds: 20))) {
      if (bytes.length + part.length > maxBytes) {
        throw const FormatException('Превышен размер передачи.');
      }
      bytes.addAll(part);
    }
    return utf8.decode(bytes);
  }

  static Future<String> encrypt(
    SecretKey key,
    Map<String, dynamic> data,
  ) async {
    final box = await cipher.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: key,
    );
    return jsonEncode({
      'nonce': base64Url.encode(box.nonce),
      'data': base64Url.encode(box.cipherText),
      'mac': base64Url.encode(box.mac.bytes),
    });
  }

  static Future<Map<String, dynamic>> decrypt(
    SecretKey key,
    String text,
  ) async {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final bytes = await cipher.decrypt(
      SecretBox(
        base64Url.decode(j['data']),
        nonce: base64Url.decode(j['nonce']),
        mac: Mac(base64Url.decode(j['mac'])),
      ),
      secretKey: key,
    );
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)));
  }

  Future<void> _serve(HttpRequest request) async {
    try {
      if (request.method != 'POST' ||
          request.uri.path != '/devcat/$_session' ||
          _failures >= 8 ||
          expiresAt == null ||
          DateTime.now().isAfter(expiresAt!)) {
        request.response.statusCode = 404;
        return;
      }
      final data = await decrypt(_key, await _read(request));
      final id = data['request'];
      if (data['session'] != _session ||
          id is! String ||
          id.length > 64 ||
          !_seen.add(id)) {
        throw const FormatException('Неверный или повторный запрос.');
      }
      if (_seen.length > 50) {
        throw const FormatException(
          'Слишком много запросов. Создай новый код.',
        );
      }
      final incoming = ProgressData.decode(jsonEncode(data['progress']));
      await store.merge(incoming);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        await encrypt(_key, {
          'session': _session,
          'request': id,
          'progress': store.progress.toJson(),
        }),
      );
      onStatus?.call(
        'Готово! Прогресс и черновики объединены на обоих устройствах.',
      );
    } catch (_) {
      _failures++;
      request.response.statusCode = 400;
      request.response.write('Не удалось принять зашифрованные данные.');
    } finally {
      await request.response.close();
    }
  }

  Future<void> connect(String code) async {
    final data = parseCode(code), id = newId();
    final key = SecretKey(base64Url.decode(data['key']));
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .postUrl(
            Uri(
              scheme: 'http',
              host: data['host'],
              port: data['port'],
              path: '/devcat/${data['session']}',
            ),
          )
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      await store.flush();
      req.write(
        await encrypt(key, {
          'session': data['session'],
          'request': id,
          'progress': store.progress.toJson(),
        }),
      );
      final response = await req.close().timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw const HttpException(
          'Устройство отклонило подключение. Создай новый код.',
        );
      }
      final incoming = await decrypt(key, await _read(response));
      if (incoming['session'] != data['session'] || incoming['request'] != id) {
        throw const FormatException('Ответ относится к другому подключению.');
      }
      await store.merge(ProgressData.decode(jsonEncode(incoming['progress'])));
    } finally {
      client.close(force: true);
    }
  }

  Future<void> close() async {
    _expiry?.cancel();
    _expiry = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
    connectionCode = null;
  }
}
