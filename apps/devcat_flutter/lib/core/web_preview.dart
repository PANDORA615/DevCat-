import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'project.dart';

/// A local browser preview. Never serves filesystem paths or binds to LAN.
class WebPreview {
  HttpServer? _server;
  DevProject? _project;
  final token = List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  Future<Uri> open(DevProject project) async {
    DevProject.decode(project.encode());
    _project = project;
    _server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (!_listening) {
      _listening = true;
      _server!.listen(_serve);
    }
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _server!.port,
      pathSegments: [token, ...project.entry.split('/')],
    );
  }

  bool _listening = false;
  void _serve(HttpRequest request) {
    final parts = request.uri.pathSegments;
    final response = request.response;
    if (request.method != 'GET' || parts.length < 2 || parts.first != token) {
      response.statusCode = HttpStatus.notFound;
      unawaited(response.close());
      return;
    }
    final name = parts.skip(1).join('/');
    final text = DevProject.validPath(name) ? _project?.files[name] : null;
    if (text == null) {
      response.statusCode = 404;
      unawaited(response.close());
      return;
    }
    response.headers.set('Cache-Control', 'no-store');
    // Preview supports ordinary HTML/CSS/JS and relative project files. Remote
    // dependencies are intentionally blocked to keep beginner examples offline.
    response.headers.set(
      'Content-Security-Policy',
      "default-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'none'; frame-src 'none'; form-action 'none'",
    );
    response.headers.contentType = name.endsWith('.svg')
        ? ContentType('image', 'svg+xml', charset: 'utf-8')
        : ContentType(
            'text',
            name.endsWith('.css')
                ? 'css'
                : name.endsWith('.js')
                ? 'javascript'
                : name.endsWith('.html')
                ? 'html'
                : 'plain',
            charset: 'utf-8',
          );
    response.add(utf8.encode(text));
    unawaited(response.close());
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    _listening = false;
  }
}
