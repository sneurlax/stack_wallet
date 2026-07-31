import 'dart:convert' show Encoding, jsonEncode, utf8;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stackwallet/networking/http.dart';
import 'package:stackwallet/services/shopinbit/src/client.dart';

void main() {
  test('attachment downloads authenticate with headers only', () async {
    final http = _RecordingHttp();
    final client = _client(http);

    final response = await client.getAttachment(
      'tickets/file.png',
      customerKey: 'customer-secret',
    );

    expect(response.valueOrThrow.bodyBytes, [1, 2, 3]);
    expect(http.lastGetUrl?.queryParameters, isEmpty);
    expect(http.lastGetHeaders?['Authorization'], 'Bearer bearer-secret');
    expect(http.lastGetHeaders?['External-Customer-Key'], 'customer-secret');
  });
}

ShopInBitClient _client(HTTP http) => ShopInBitClient(
  accessKey: 'access-key',
  partnerSecret: 'partner-secret',
  baseUrl: 'https://shopinbit.test',
  httpClient: http,
);

class _RecordingHttp extends HTTP {
  Uri? lastGetUrl;
  Map<String, String>? lastGetHeaders;

  @override
  Future<Response> post({
    required Uri url,
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    required ({InternetAddress host, int port})? proxyInfo,
  }) async {
    return Response(
      utf8.encode(
        jsonEncode({'access_token': 'bearer-secret', 'token_type': 'bearer'}),
      ),
      200,
    );
  }

  @override
  Future<Response> get({
    required Uri url,
    Map<String, String>? headers,
    required ({InternetAddress host, int port})? proxyInfo,
    Duration? connectionTimeout,
  }) async {
    lastGetUrl = url;
    lastGetHeaders = headers;
    return Response([1, 2, 3], 200);
  }
}
