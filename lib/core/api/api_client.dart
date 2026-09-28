import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../utils/idempotency.dart';
import 'api_exception.dart';
import 'connectivity_service.dart';
import 'outbox_store.dart';

/// Supplies the bearer token and the current user scope. Implemented by the
/// auth controller; injected so [ApiClient] never depends on Flutter state.
abstract class AuthTokenProvider {
  String? get token;
  String? get userId;
}

class _TokenBridge implements AuthTokenProvider {
  _TokenBridge(this._client);
  final ApiClient _client;
  String? _token;
  String? _userId;

  set token(String? v) => _token = v;
  set userId(String? v) => _userId = v;

  @override
  String? get token => _token ?? _client.legacyToken;
  @override
  String? get userId => _userId;
}

/// Raised when a write was accepted into the outbox instead of being sent.
/// Carries the marker the web client uses (`HTTP 202`).
class QueuedResponse implements Exception {
  QueuedResponse(this.outboxId, this.service, this.method, this.url);
  final int outboxId;
  final String service;
  final String method;
  final String url;
  Map<String, dynamic> toJson() => {
        'queued': true,
        'outbox_id': outboxId,
        'service': service,
        'method': method,
        'url': url,
        'queued_at': DateTime.now().toIso8601String(),
      };
}

/// One configured backend service.
class ApiServiceClient {
  ApiServiceClient({
    required this.name,
    required String Function() baseUrlResolver,
    this.timeout = ApiConfig.mediumTimeout,
    this.allowQueueing = true,
  }) : _baseUrlResolver = baseUrlResolver;

  final String name;
  final String Function() _baseUrlResolver;
  final Duration timeout;

  /// The user service is never queued: a login or token refresh that cannot
  /// reach the network must fail loudly, not silently replay later.
  final bool allowQueueing;

  String get baseUrl => _baseUrlResolver();
}

/// Shared HTTP plumbing: auth headers, timeouts, retry, error normalisation,
/// and the offline write queue.
class ApiClient {
  ApiClient({
    required ConnectivityService connectivity,
    required OutboxStore outbox,
    http.Client? httpClient,
  })  : _connectivity = connectivity,
        _outbox = outbox,
        _http = httpClient ?? http.Client() {
    _auth = _TokenBridge(this);
  }

  final ConnectivityService _connectivity;
  final OutboxStore _outbox;
  final http.Client _http;
  late final _TokenBridge _auth;

  /// Set by the shell so a 401 anywhere can force a sign-out.
  void Function()? onUnauthorized;

  /// Set by the sync engine: `resource` names the cache prefix to invalidate
  /// after a replayed row lands.
  void Function(String resource)? onReplayApplied;

  /// Filled in once the session is known; used for scoping the cache DB.
  String? legacyToken;

  final Map<String, ApiServiceClient> _services = {
    ServiceNames.quotation: ApiServiceClient(
      name: ServiceNames.quotation,
      baseUrlResolver: () => ApiConfig.quotationBase,
      timeout: ApiConfig.shortTimeout,
    ),
    ServiceNames.bills: ApiServiceClient(
      name: ServiceNames.bills,
      baseUrlResolver: () => ApiConfig.billsBase,
      timeout: ApiConfig.longTimeout,
    ),
    ServiceNames.users: ApiServiceClient(
      name: ServiceNames.users,
      baseUrlResolver: () => ApiConfig.usersBase,
      timeout: ApiConfig.shortTimeout,
      allowQueueing: false,
    ),
    ServiceNames.workers: ApiServiceClient(
      name: ServiceNames.workers,
      baseUrlResolver: () => ApiConfig.workersBase,
      timeout: ApiConfig.shortTimeout,
    ),
    // Matches the web client: the management backend has no 401 interceptor,
    // so an expired session surfaces here rather than signing the user out.
    ServiceNames.management: ApiServiceClient(
      name: ServiceNames.management,
      baseUrlResolver: () => ApiConfig.managementBase,
      timeout: ApiConfig.mediumTimeout,
    ),
    ServiceNames.ai: ApiServiceClient(
      name: ServiceNames.ai,
      baseUrlResolver: () => ApiConfig.aiBase,
      timeout: ApiConfig.mediumTimeout,
      allowQueueing: false,
    ),
  };

  AuthTokenProvider get authProvider => _auth;

  void setToken(String? token) => _auth.token = token;
  void setUserId(String? userId) => _auth.userId = userId;
  String? get token => _auth.token;

  ApiServiceClient serviceFor(String name) =>
      _services[name] ?? _services[ServiceNames.quotation]!;

  /// True while the sync engine is replaying the outbox, so those writes are
  /// sent directly instead of re-queued.
  bool isReplaying = false;

  /// Invoked after every enqueue. `AppServices` wires this to
  /// `SyncEngine.notifyEnqueued` so a write made mid-session drains without
  /// waiting for connectivity to change or the app to restart.
  void Function()? onEnqueued;

  // ── URL building ───────────────────────────────────────────────────────────
  static String buildUrl(
    String baseUrl,
    String path, [
    Map<String, dynamic>? query,
  ]) {
    var base = baseUrl;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    var p = path.startsWith('/') ? path : '/$path';
    final params = <String, String>{};
    query?.forEach((k, v) {
      if (v == null) return;
      final s = v is List ? v.join(',') : v.toString();
      if (s.isEmpty) return;
      params[k] = s;
    });
    if (params.isEmpty) return '$base$p';
    final uri = Uri.parse('$base$p');
    return uri.replace(queryParameters: params).toString();
  }

  Map<String, String> _headers({
    required bool json,
    Map<String, String>? extra,
    bool includeAuth = true,
  }) {
    final h = <String, String>{};
    if (json) h['Accept'] = 'application/json';
    if (includeAuth) {
      final t = _auth.token;
      if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    }
    if (extra != null) h.addAll(extra);
    return h;
  }

  bool _isAuthPath(String path) {
    final p = path.toLowerCase();
    return p.startsWith('/auth') ||
        p.contains('/token') ||
        p.contains('/login') ||
        p.contains('/register');
  }

  /// Paths whose writes are never queued, mirroring `NEVER_QUEUE` on the web.
  bool _neverQueue(String path) {
    final p = path.toLowerCase();
    return RegExp(r'^/(auth|token|login|register|share|uploads)(\/|$)')
        .hasMatch(p);
  }

  // ── Read ───────────────────────────────────────────────────────────────────
  Future<dynamic> get(
    String service,
    String path, {
    Map<String, dynamic>? query,
    bool includeAuth = true,
  }) =>
      _send(
        service: service,
        method: 'GET',
        path: path,
        query: query,
        includeAuth: includeAuth,
      );

  /// Raw response body as text, for the CSV / XLSX / blob export endpoints.
  Future<String> getText(
    String service,
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final svc = serviceFor(service);
    final url = buildUrl(svc.baseUrl, path, query);
    final resp = await _http
        .get(Uri.parse(url), headers: _headers(json: false))
        .timeout(svc.timeout);
    return _unwrap(resp, url: url, method: 'GET', service: svc.name);
  }

  Future<List<int>> getBytes(
    String service,
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final svc = serviceFor(service);
    final url = buildUrl(svc.baseUrl, path, query);
    final resp = await _http
        .get(Uri.parse(url), headers: _headers(json: false))
        .timeout(svc.timeout);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return resp.bodyBytes;
    throw ApiException(
      extractErrorMessage(_tryDecode(resp.body)),
      statusCode: resp.statusCode,
      url: url,
      method: 'GET',
    );
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  /// Sends a JSON write, queueing it offline. Returns the decoded body, or a
  /// [QueuedResponse] marker when the write went to the outbox.
  Future<dynamic> write(
    String service,
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool includeAuth = true,
    bool allowQueueing = true,
    String? idempotencyKey,
    Map<String, String>? extraHeaders,
  }) async {
    final svc = serviceFor(service);
    final encoded = body == null ? null : jsonEncode(body);

    if (allowQueueing && svc.allowQueueing && _shouldQueue(svc, path)) {
      final id = await _enqueue(
        svc: svc,
        method: method,
        path: path,
        query: query,
        body: body,
        idempotencyKey: idempotencyKey ??
            (method == 'POST' ? randomIdempotencyKey() : null),
      );
      return QueuedResponse(id, svc.name, method, path);
    }

    return _send(
      service: svc.name,
      method: method,
      path: path,
      query: query,
      jsonBody: encoded,
      includeAuth: includeAuth,
      extraHeaders: extraHeaders,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<dynamic> post(String s, String path,
          {Object? body,
          Map<String, dynamic>? query,
          bool includeAuth = true}) =>
      write(s, 'POST', path,
          body: body, query: query, includeAuth: includeAuth);

  Future<dynamic> patch(String s, String path,
          {Object? body, Map<String, dynamic>? query}) =>
      write(s, 'PATCH', path, body: body, query: query);

  Future<dynamic> put(String s, String path,
          {Object? body, Map<String, dynamic>? query}) =>
      write(s, 'PUT', path, body: body, query: query);

  Future<dynamic> delete(String s, String path,
          {Object? body, Map<String, dynamic>? query}) =>
      write(s, 'DELETE', path, body: body, query: query);

  /// Multipart upload (avatar, import file, signature). Never queued — a file
  /// cannot be replayed from the outbox reliably.
  Future<dynamic> upload(
    String service,
    String path, {
    required String field,
    required List<int> bytes,
    String filename = 'upload.bin',
    String contentType = 'application/octet-stream',
    Map<String, String> fields = const {},
    Map<String, dynamic>? query,
  }) async {
    final svc = serviceFor(service);
    final url = buildUrl(svc.baseUrl, path, query);
    try {
      final req = http.MultipartRequest('POST', Uri.parse(url))
        ..fields.addAll(fields)
        ..files.add(
          http.MultipartFile.fromBytes(field, bytes, filename: filename),
        );
      final t = _auth.token;
      if (t != null) req.headers['Authorization'] = 'Bearer $t';
      final streamed = await req.send().timeout(const Duration(minutes: 2));
      final resp = await http.Response.fromStream(streamed);
      return _unwrap(resp, url: url, method: 'POST', service: svc.name);
    } on TimeoutException {
      throw ApiException('Upload timed out', url: url, method: 'POST');
    } on SocketException catch (e) {
      throw ApiException('Connection error: ${e.message}',
          url: url, method: 'POST');
    }
  }

  // ── Core send ──────────────────────────────────────────────────────────────
  Future<dynamic> _send({
    required String service,
    required String method,
    required String path,
    Map<String, dynamic>? query,
    String? jsonBody,
    bool includeAuth = true,
    Map<String, String>? extraHeaders,
    String? idempotencyKey,
  }) async {
    final svc = serviceFor(service);
    final url = buildUrl(svc.baseUrl, path, query);
    final headers = _headers(
      json: jsonBody != null,
      includeAuth: includeAuth,
      extra: {
        if (jsonBody != null) 'Content-Type': 'application/json',
        if (idempotencyKey != null) 'X-Idempotency-Key': idempotencyKey,
        ...?extraHeaders,
      },
    );

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final req = http.Request(method, Uri.parse(url))
          ..headers.addAll(headers);
        if (jsonBody != null) req.body = jsonBody;
        final streamed = await _http.send(req).timeout(svc.timeout);
        final resp = await http.Response.fromStream(streamed);
        return _unwrap(resp, url: url, method: method, service: svc.name);
      } on TimeoutException {
        if (attempt == maxAttempts) {
          _markDown(svc.name);
          throw ApiException('Request timed out', url: url, method: method);
        }
        await _backoff(attempt);
      } on SocketException catch (e) {
        if (attempt == maxAttempts) {
          _markDown(svc.name);
          throw ApiException('Connection error: ${e.message}',
              url: url, method: method);
        }
        await _backoff(attempt);
      } on http.ClientException catch (e) {
        if (attempt == maxAttempts) {
          _markDown(svc.name);
          throw ApiException('Connection error: ${e.message}',
              url: url, method: method);
        }
        await _backoff(attempt);
      }
    }
    throw ApiException('Request failed', url: url, method: method);
  }

  Future<void> _backoff(int attempt) => Future<void>.delayed(
      Duration(milliseconds: (1000 * (1 << (attempt - 1))).clamp(400, 5000)));

  void _markDown(String service) {
    if (service != ServiceNames.ai) _connectivity.markServiceDown(service);
  }

  dynamic _unwrap(
    http.Response resp, {
    required String url,
    required String method,
    required String service,
  }) {
    final status = resp.statusCode;

    if (status == 401 && includeAuthPath(url, service)) {
      onUnauthorized?.call();
      throw ApiException(
        extractErrorMessage(_tryDecode(resp.body), fallback: 'Session expired'),
        statusCode: 401,
        url: url,
        method: method,
      );
    }

    if (status >= 200 && status < 300) {
      _connectivity.markServiceUp(service);
      return _tryDecode(resp.body);
    }

    // A write that the server accepted as queued (the web backend can do this
    // itself for idempotent replays) is still a success.
    if (status == 202) return _tryDecode(resp.body);

    throw ApiException(
      extractErrorMessage(_tryDecode(resp.body),
          fallback: 'Request failed (HTTP $status)'),
      statusCode: status,
      url: url,
      method: method,
      body: _tryDecode(resp.body),
    );
  }

  /// The user service is the only one that owns session state; a 401 from
  /// another service should still sign the user out, but a 401 from the login
  /// call itself must not loop.
  bool includeAuthPath(String url, String service) =>
      service != ServiceNames.users ? true : !_isAuthPath(_pathOf(url));

  static String _pathOf(String url) {
    try {
      return Uri.parse(url).path;
    } catch (_) {
      return url;
    }
  }

  dynamic _tryDecode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  // ── Outbox ─────────────────────────────────────────────────────────────────
  bool _shouldQueue(ApiServiceClient svc, String path) {
    if (isReplaying) return false;
    if (_neverQueue(path)) return false;
    return _connectivity.shouldQueue(svc.name);
  }

  Future<int> _enqueue({
    required ApiServiceClient svc,
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) async {
    final identity = PendingIdentity.parse(path, method);
    final row = OutboxRow(
      service: svc.name,
      method: method,
      url: buildUrl(svc.baseUrl, path, query),
      baseUrl: svc.baseUrl,
      body: body == null ? null : jsonEncode(body),
      idempotencyKey: idempotencyKey,
      resource: identity.resource,
      kind: identity.kind,
      entityId: identity.entityId,
      createdAt: DateTime.now(),
    );
    final id = await _outbox.enqueue(row);
    onEnqueued?.call();
    return id;
  }
}

/// Derives the resource / kind / entity identity for a queued request.
///
/// The web client infers this from the path, which mislabels nested creates
/// (a `POST /bills/{id}/payments` was reported as "update bill {id}"). The
/// templates below keep the same shape but recognise the sub-resources, so a
/// payment shows up against `payments` rather than against the bill.
class PendingIdentity {
  const PendingIdentity({
    required this.resource,
    required this.kind,
    this.entityId,
  });

  final String resource;
  final String kind;
  final String? entityId;

  static const Map<String, String> _subResources = {
    'payments': 'payments',
    'payments/': 'payments',
    'adjust': 'adjustments',
    'approve': 'adjustments',
    'reject': 'adjustments',
    'reopen': 'gatepasses',
    'mark-delivered': 'gatepasses',
    'date': 'operations',
    'resent': 'returns',
    'cancel': 'deliveries',
    'split-bill': 'shop-bills',
    'merge-bills': 'shop-bills',
    'duplicate': 'shop-bills',
    'record-payment': 'shop-bills',
    'link-quotation': 'shop-bills',
    'from-quotation': 'shop-bills',
    'generate-tags': 'linens',
    'bulk-scan': 'linens',
    'rates': 'rates',
    'salaries': 'salaries',
    'attendance': 'attendance',
    'advances': 'advances',
    'slips': 'salary',
    'packages': 'salary',
    'activate': 'employees',
  };

  static PendingIdentity parse(String path, String method) {
    final segs =
        path.split('?').first.split('/').where((s) => s.isNotEmpty).toList();
    // Drop the routing prefixes so `/api/advances` and `/advances` agree.
    while (segs.isNotEmpty &&
        (segs.first == 'api' || segs.first == 'management')) {
      segs.removeAt(0);
    }
    if (segs.isEmpty) {
      return PendingIdentity(resource: 'unknown', kind: kindOf(method, 0));
    }

    final tail =
        segs.length >= 2 ? segs.sublist(segs.length - 2).join('/') : '';
    final sub = _subResources[tail];
    if (sub != null) {
      return PendingIdentity(
        resource: sub,
        kind: method == 'POST' ? 'create' : 'update',
        entityId: segs[segs.length - 2],
      );
    }

    final resource = segs.first;
    return PendingIdentity(
      resource: resource,
      kind: kindOf(method, segs.length),
      entityId: segs.length >= 3 ? segs[1] : null,
    );
  }

  /// `DELETE` is always a delete, `PUT`/`PATCH` always an update, and anything
  /// three or more segments deep is a nested update.
  static String kindOf(String method, int depth) {
    if (method == 'DELETE') return 'delete';
    if (method == 'PUT' || method == 'PATCH') return 'update';
    if (depth >= 3) return 'update';
    return 'create';
  }
}
