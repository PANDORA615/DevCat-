import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class UpdateCancelled implements Exception {
  const UpdateCancelled();
  @override
  String toString() => 'Загрузка отменена';
}

/// A single operation's cancellation; it never closes unrelated HTTP requests.
class UpdateCancellation {
  final Completer<Never> _signal = Completer<Never>();
  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  UpdateCancellation() {
    // Cancellation may precede the first awaited network request.
    _signal.future.ignore();
  }
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _signal.completeError(const UpdateCancelled());
  }

  void throwIfCancelled() {
    if (_cancelled) throw const UpdateCancelled();
  }

  Future<T> race<T>(Future<T> operation) {
    if (_cancelled) {
      operation.ignore();
      throw const UpdateCancelled();
    }
    return Future.any([operation, _signal.future]);
  }
}

class UpdateDownloadProgress {
  final int received;
  final int? total;
  final double bytesPerSecond;
  const UpdateDownloadProgress(this.received, this.total, this.bytesPerSecond);
  double? get fraction => total == null ? null : received / total!;
}

typedef UpdateProgressCallback = void Function(UpdateDownloadProgress progress);

/// Bounded HTTPS transport, including every redirect; cancellation also wakes a
/// stalled connection or stream. The caller authenticates downloaded bytes.
Future<List<int>> readUpdateBytes(
  HttpClient client,
  Uri url,
  int limit, {
  required UpdateCancellation cancellation,
  int? expectedSize,
  UpdateProgressCallback? onProgress,
}) async {
  final clock = Stopwatch()..start();
  final bytes = BytesBuilder(copy: false);
  for (var redirects = 0; redirects <= 5; redirects++) {
    cancellation.throwIfCancelled();
    if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
      throw const FormatException('Обновления требуют HTTPS');
    }
    var finished = false;
    HttpClientRequest? request;
    StreamIterator<List<int>>? stream;
    try {
      final opened = await cancellation.race<HttpClientRequest>(
        client
            .getUrl(url)
            .then((opened) {
              // getUrl can complete after cancellation won the race.
              if (cancellation.isCancelled || finished) {
                opened.abort();
              }
              return opened;
            })
            .timeout(const Duration(seconds: 20)),
      );
      request = opened;
      opened.followRedirects = false;
      final response = await cancellation.race(
        opened.close().timeout(const Duration(seconds: 20)),
      );
      stream = StreamIterator(response);
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || redirects == 5) {
          throw const HttpException('Неверное перенаправление обновления');
        }
        url = url.resolve(location);
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      if (response.contentLength > limit ||
          (expectedSize != null &&
              response.contentLength >= 0 &&
              response.contentLength != expectedSize)) {
        throw const FormatException('Неверный размер загрузки');
      }
      final total =
          expectedSize ??
          (response.contentLength > 0 ? response.contentLength : null);
      onProgress?.call(UpdateDownloadProgress(0, total, 0));
      while (await cancellation.race(
        stream.moveNext().timeout(const Duration(seconds: 30)),
      )) {
        cancellation.throwIfCancelled();
        final chunk = stream.current;
        if (bytes.length + chunk.length > limit) {
          throw const FormatException('Превышен размер загрузки');
        }
        bytes.add(chunk);
        final elapsed = clock.elapsedMicroseconds;
        onProgress?.call(
          UpdateDownloadProgress(
            bytes.length,
            total,
            elapsed == 0 ? 0 : bytes.length * 1000000 / elapsed,
          ),
        );
      }
      cancellation.throwIfCancelled();
      if (expectedSize != null && bytes.length != expectedSize) {
        throw const FormatException(
          'Загрузка прервана до получения всех данных',
        );
      }
      return bytes.takeBytes();
    } finally {
      finished = true;
      // Abort before cancelling the iterator so a hung body cannot delay exit.
      request?.abort();
      await stream?.cancel();
    }
  }
  throw const HttpException('Слишком много перенаправлений');
}
