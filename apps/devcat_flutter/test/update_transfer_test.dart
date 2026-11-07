import 'dart:async';
import 'dart:io';
import 'package:devcat/core/update_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/update_http.dart';

void main() {
  final uri = Uri.parse('https://example.com/courses.json');
  test('Reports chunk progress and rejects automatic redirects', () async {
    final request = TransferRequest(
      TransferResponse(
        Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]),
        contentLength: 4,
      ),
    );
    final progress = <UpdateDownloadProgress>[];
    final bytes = await readUpdateBytes(
      TransferClient((_) async => request),
      uri,
      4,
      cancellation: UpdateCancellation(),
      expectedSize: 4,
      onProgress: progress.add,
    );
    expect(bytes, [1, 2, 3, 4]);
    expect(progress.map((p) => p.received), [0, 2, 4]);
    expect(progress.last.fraction, 1);
    expect(progress.last.bytesPerSecond, greaterThanOrEqualTo(0));
    expect(request.followRedirects, false);
    expect(request.aborted, true);
  });
  test(
    'Cancellation wakes a stalled body and closes its subscription',
    () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final first = Completer<void>();
      final token = UpdateCancellation();
      final request = TransferRequest(TransferResponse(body.stream));
      final result = readUpdateBytes(
        TransferClient((_) async => request),
        uri,
        100,
        cancellation: token,
        onProgress: (p) {
          if (p.received == 1) first.complete();
        },
      );
      final check = expectLater(result, throwsA(isA<UpdateCancelled>()));
      body.add([1]);
      await first.future;
      token.cancel();
      await check;
      expect(cancelled, true);
      expect(request.aborted, true);
      await body.close();
    },
  );
  test(
    'Cancellation before a connection opens also aborts a late request',
    () async {
      final opening = Completer<HttpClientRequest>();
      final token = UpdateCancellation();
      final result = readUpdateBytes(
        TransferClient((_) => opening.future),
        uri,
        100,
        cancellation: token,
      );
      final check = expectLater(result, throwsA(isA<UpdateCancelled>()));
      token.cancel();
      await check;
      final late = TransferRequest(TransferResponse(const Stream.empty()));
      opening.complete(late);
      await Future<void>.delayed(Duration.zero);
      expect(late.aborted, true);
    },
  );
  test(
    'Redirects stay on HTTPS and relative locations resolve correctly',
    () async {
      final requests = <TransferRequest>[];
      final client = TransferClient((url) async {
        final request = TransferRequest(
          url.path == '/courses.json'
              ? TransferResponse(
                  const Stream.empty(),
                  statusCode: 302,
                  location: '/asset',
                )
              : TransferResponse(Stream.value([9]), contentLength: 1),
        );
        requests.add(request);
        return request;
      });
      expect(
        await readUpdateBytes(
          client,
          uri,
          1,
          cancellation: UpdateCancellation(),
        ),
        [9],
      );
      expect(client.urls.last.toString(), 'https://example.com/asset');
      expect(requests.every((r) => r.aborted && !r.followRedirects), true);
      final insecure = TransferClient(
        (_) async => TransferRequest(
          TransferResponse(
            const Stream.empty(),
            statusCode: 302,
            location: 'http://example.com/asset',
          ),
        ),
      );
      await expectLater(
        readUpdateBytes(insecure, uri, 1, cancellation: UpdateCancellation()),
        throwsFormatException,
      );
      expect(insecure.urls.length, 1);
    },
  );
  test('Redirect loops stop after five hops', () async {
    final client = TransferClient(
      (_) async => TransferRequest(
        TransferResponse(
          const Stream.empty(),
          statusCode: 302,
          location: '/again',
        ),
      ),
    );
    await expectLater(
      readUpdateBytes(client, uri, 100, cancellation: UpdateCancellation()),
      throwsA(isA<HttpException>()),
    );
    expect(client.urls.length, 6);
  });
  test(
    'Advertised, excessive and truncated bodies fail without a valid result',
    () async {
      for (final response in [
        TransferResponse(Stream.value([1, 2, 3, 4]), contentLength: 5),
        TransferResponse(Stream.value([1, 2, 3, 4, 5])),
        TransferResponse(Stream.value([1, 2])),
      ]) {
        final client = TransferClient((_) async => TransferRequest(response));
        await expectLater(
          readUpdateBytes(
            client,
            uri,
            4,
            expectedSize: 4,
            cancellation: UpdateCancellation(),
          ),
          throwsFormatException,
        );
      }
    },
  );
}
