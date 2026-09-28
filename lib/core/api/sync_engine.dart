import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/idempotency.dart';
import 'api_client.dart';
import 'connectivity_service.dart';
import 'outbox_store.dart';

export 'outbox_store.dart' show OutboxStatusCounts;

/// Snapshot of what the offline pill shows.
@immutable
class SyncSnapshot {
  const SyncSnapshot({
    this.online = true,
    this.pending = 0,
    this.failed = 0,
    this.syncing = false,
    this.downServices = const {},
    this.lastSyncedAt,
    this.lastError,
  });

  final bool online;
  final int pending;
  final int failed;
  final bool syncing;
  final Set<String> downServices;
  final DateTime? lastSyncedAt;
  final String? lastError;

  bool get hasQueued => pending > 0;
  bool get hasFailed => failed > 0;
  bool get showBar => hasFailed || !online || hasQueued || syncing;

  SyncSnapshot copyWith({
    bool? online,
    int? pending,
    int? failed,
    bool? syncing,
    Set<String>? downServices,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) =>
      SyncSnapshot(
        online: online ?? this.online,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        syncing: syncing ?? this.syncing,
        downServices: downServices ?? this.downServices,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

/// Replays the outbox against the backend, one row at a time, in order.
///
/// Ordering matters: a queued `PATCH /bills/1` must not overtake the
/// `POST /bills/1` in front of it, so the first server rejection stops the
/// drain rather than skipping ahead.
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required ApiClient api,
    required ConnectivityService connectivity,
    required OutboxStore outbox,
    required OutboxStatusCounts Function() counts,
  })  : _api = api,
        _connectivity = connectivity,
        _outbox = outbox,
        _counts = counts {
    _api.onReplayApplied = _invalidateResource;
  }

  final ApiClient _api;
  final ConnectivityService _connectivity;
  final OutboxStore _outbox;
  final OutboxStatusCounts Function() _counts;

  Timer? _debounce;
  bool _started = false;
  bool _draining = false;
  bool _disposed = false;
  DateTime? _lastSyncedAt;
  String? _lastError;
  final _http = http.Client();

  SyncSnapshot get snapshot {
    final c = _counts();
    return SyncSnapshot(
      online: _connectivity.isOnline,
      pending: c.pending,
      failed: c.rows.where((r) => r.isFailed).length,
      syncing: _draining,
      downServices: _connectivity.downServices,
      lastSyncedAt: _lastSyncedAt,
      lastError: _lastError,
    );
  }

  /// Pending rows keyed `service:entityId` and `service:resource`, which is
  /// what the row-level "Pending sync" badges read.
  Map<String, OutboxRow> get byEntity {
    final m = <String, OutboxRow>{};
    for (final r in _counts().rows) {
      m[r.entityKey] = r;
    }
    return m;
  }

  Map<String, List<OutboxRow>> get byResource {
    final m = <String, List<OutboxRow>>{};
    for (final r in _counts().rows) {
      if (r.resource == null) continue;
      m.putIfAbsent('${r.service}:${r.resource}', () => []).add(r);
    }
    return m;
  }

  OutboxRow? rowFor(String service, String entityId) {
    for (final r in _counts().rows) {
      if (r.service == service && r.entityId == entityId) return r;
    }
    return null;
  }

  bool isEntityPending(String service, String entityId) =>
      rowFor(service, entityId) != null;

  /// Idempotent — safe to call from both the shell and a hot restart.
  void start() {
    if (_started) return;
    _started = true;
    unawaited(_recoverStranded());
    _connectivity.onOnlineChange.listen((online) {
      if (!online) {
        _emit();
        return;
      }
      // Give the network stack a beat to settle before replaying.
      _schedule(const Duration(milliseconds: 500));
    });
    _connectivity.onServicesChange.listen((_) {
      if (_connectivity.isOnline) _schedule(const Duration(seconds: 2));
    });
    // A straggler row from a previous session that never got a chance to run.
    _schedule(const Duration(seconds: 4));
  }

  Future<void> _recoverStranded() async {
    final recovered = await _outbox.recoverStranded();
    if (recovered > 0) _schedule(Duration.zero);
  }

  /// Called after every enqueue so a burst of writes drains as one batch.
  void notifyEnqueued() => _schedule(const Duration(milliseconds: 900));

  void _schedule(Duration delay) {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      unawaited(drain());
    });
  }

  /// Replays every pending row. Returns true when the queue emptied cleanly.
  Future<bool> drain({bool force = false}) async {
    if (_draining) return false;
    if (!force && !_connectivity.isOnline) {
      _emit();
      return false;
    }
    final rows = await _outbox.pending();
    if (rows.isEmpty) {
      _lastError = null;
      _emit();
      return true;
    }

    _draining = true;
    _lastError = null;
    _emit();
    _api.isReplaying = true;

    try {
      for (final row in rows) {
        if (_disposed) return false;
        if (!force && !_connectivity.isOnline) break;

        await _outbox.markSyncing(row.id!);
        _emit();

        final outcome = await _replay(row);
        switch (outcome) {
          case _ReplayOutcome.applied:
            await _outbox.remove(row.id!);
            if (row.resource != null) _invalidateResource(row.resource!);
          case _ReplayOutcome.gone:
            // A delete the server already applied — treat as success.
            await _outbox.remove(row.id!);
            if (row.resource != null) _invalidateResource(row.resource!);
          case _ReplayOutcome.sessionExpired:
            await _outbox.markFailed(
                row.id!, 'Session expired — sign in again to sync.');
            _lastError = 'Session expired — sign in again to sync.';
            _api.onUnauthorized?.call();
            _draining = false;
            _emit();
            return false;
          case _ReplayOutcome.rejected:
            await _outbox.markFailed(row.id!, 'Server rejected the change.');
            _lastError = 'Server rejected a saved change.';
            // Stop: later rows may depend on this one.
            _draining = false;
            _emit();
            return false;
          case _ReplayOutcome.offline:
            await _outbox.markPending(row.id!, attempts: row.attempts + 1);
            _draining = false;
            _emit();
            return false;
        }
        _emit();
      }
      _lastSyncedAt = DateTime.now();
      return true;
    } finally {
      _api.isReplaying = false;
      _draining = false;
      _emit();
    }
  }

  /// The "Retry" action on the offline pill: put failed rows back in the queue
  /// and drain everything.
  Future<void> retryFailed() async {
    for (final row in await _outbox.byStatus(OutboxStatus.failed)) {
      await _outbox.markPending(row.id!, error: null);
    }
    await drain(force: true);
  }

  Future<_ReplayOutcome> _replay(OutboxRow row) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      final t = _api.token;
      if (t != null && t.isNotEmpty) headers['Authorization'] = 'Bearer $t';
      if (row.idempotencyKey != null) {
        headers['X-Idempotency-Key'] = row.idempotencyKey!;
      }

      final uri = Uri.parse(row.url);
      final req = http.Request(row.method, uri)..headers.addAll(headers);
      if (row.body != null && row.body!.isNotEmpty && row.method != 'GET') {
        req.body = row.body!;
      }

      final resp = await http.Response.fromStream(await _http.send(req))
          .timeout(const Duration(seconds: 15));
      final status = resp.statusCode;

      if (status >= 200 && status < 300) return _ReplayOutcome.applied;
      if (row.method == 'DELETE' && status == 404) {
        return _ReplayOutcome.gone;
      }
      if (status == 401) return _ReplayOutcome.sessionExpired;
      return _ReplayOutcome.rejected;
    } on SocketException {
      return _ReplayOutcome.offline;
    } on TimeoutException {
      return _ReplayOutcome.offline;
    } on http.ClientException {
      return _ReplayOutcome.offline;
    }
  }

  /// Resource prefixes the persisted cache knows how to drop wholesale.
  static const Set<String> cacheResources = {
    'gatepasses',
    'bills',
    'deliveries',
    'dispatch',
    'returns',
    'quotations',
    'payments',
    'loyalty',
    'notifications',
    'dashboard',
    'reports',
    'shop-bills',
    'legacy-invoices',
    'workers',
    'daily-logs',
    'linens',
    'mgmt-dashboard',
    'employees',
    'customers',
    'items',
    'categories',
    'expenses',
    'transactions',
    'attendance',
    'salary',
    'advances',
    'holidays',
    'extra-work',
    'company-settings',
    'operations',
    'linen-flow',
  };

  void _invalidateResource(String resource) {
    if (cacheResources.contains(resource)) {
      QueryCacheInvalidator.instance.invalidate(resource);
    } else {
      QueryCacheInvalidator.instance.invalidateAll();
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<List<OutboxRow>> allRows() => _outbox.all();

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _http.close();
    super.dispose();
  }
}

enum _ReplayOutcome { applied, gone, sessionExpired, rejected, offline }

/// Bridge between the sync engine and the resource cache, which is registered
/// once at startup. Avoids a circular dependency between the two.
class QueryCacheInvalidator {
  QueryCacheInvalidator._();
  static final QueryCacheInvalidator instance = QueryCacheInvalidator._();

  void Function(String resource)? _byResource;
  void Function()? _all;

  void register(
      {void Function(String resource)? byResource, void Function()? all}) {
    _byResource = byResource;
    _all = all;
  }

  void invalidate(String resource) => _byResource?.call(resource);
  void invalidateAll() => _all?.call();
}

/// Builds the deterministic key a POST body is hashed into, so the same
/// payload submitted twice produces the same `X-Idempotency-Key`.
String bodyIdempotencyKey(Map<String, dynamic> body) => idempotencyKey(body);

/// Decodes an outbox body back into a map, for the "view queued change" sheet.
Map<String, dynamic> decodeOutboxBody(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : {'value': decoded};
  } catch (_) {
    return {'value': raw};
  }
}
