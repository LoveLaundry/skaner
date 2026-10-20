import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:love_mobi/config/api_config.dart';
import 'package:love_mobi/core/api/api_client.dart';
import 'package:love_mobi/core/api/connectivity_service.dart';
import 'package:love_mobi/core/api/outbox_store.dart';

void main() {
  test('direct POST retries reuse one idempotency key', () async {
    final client = _RetryingHttpClient();
    final connectivity = ConnectivityService();
    final api = ApiClient(
      connectivity: connectivity,
      outbox: OutboxStore(),
      httpClient: client,
    );
    addTearDown(connectivity.dispose);

    await api.post(
      ServiceNames.bills,
      '/bills',
      body: const {'client_id': 42, 'total': 1200},
    );

    expect(client.requests, hasLength(2));
    final firstKey = client.requests.first.headers['X-Idempotency-Key'];
    expect(firstKey, isNotNull);
    expect(firstKey, isNotEmpty);
    expect(client.requests.last.headers['X-Idempotency-Key'], firstKey);
  });
}

class _RetryingHttpClient extends http.BaseClient {
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (requests.length == 1) {
      throw http.ClientException('Connection reset', request.url);
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{}')),
      201,
      request: request,
    );
  }
}
