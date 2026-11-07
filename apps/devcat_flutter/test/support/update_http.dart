import 'dart:async';
import 'dart:io';

class TransferHeaders implements HttpHeaders {
  final String? location;
  TransferHeaders(this.location);
  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TransferResponse extends Stream<List<int>> implements HttpClientResponse {
  final Stream<List<int>> body;
  @override
  final int statusCode, contentLength;
  @override
  final HttpHeaders headers;
  TransferResponse(
    this.body, {
    this.statusCode = 200,
    this.contentLength = -1,
    String? location,
  }) : headers = TransferHeaders(location);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TransferRequest implements HttpClientRequest {
  final HttpClientResponse response;
  bool aborted = false;
  @override
  bool followRedirects = true;
  TransferRequest(this.response);
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) => aborted = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TransferClient implements HttpClient {
  final Future<HttpClientRequest> Function(Uri) openRequest;
  final urls = <Uri>[];
  TransferClient(this.openRequest);
  @override
  Future<HttpClientRequest> getUrl(Uri uri) {
    urls.add(uri);
    return openRequest(uri);
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
