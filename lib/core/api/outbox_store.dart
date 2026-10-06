import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// Count + row snapshot handed to the sync engine so it can render without
/// owning the store or awaiting SQLite on every tick.
@immutable
class OutboxStatusCounts {
  const OutboxStatusCounts({required this.pending, required this.rows});

  final int pending;
  final List<OutboxRow> rows;
}

/// One pending write waiting to reach the server.
class OutboxRow {
  OutboxRow({
    this.id,
    required this.service,
    required this.method,
    required this.url,
    required this.baseUrl,
    this.body,
    this.idempotencyKey,
    this.resource,
    this.kind,
    this.entityId,
    this.status = OutboxStatus.pending,
    this.attempts = 0,
    this.lastError,
    required this.createdAt,
  });

  final int? id;
  final String service;
  final String method;
  final String url;
  final String baseUrl;
  final String? body;
  final String? idempotencyKey;

  /// First path segment after stripping `api/` and `management/`, so
  /// `/api/advances` queues under `advances`.
  final String? resource;

  /// `create` | `update` | `delete`.
  final String? kind;
  final String? entityId;
  final OutboxStatus status;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;

  bool get isPending => status == OutboxStatus.pending;
  bool get isFailed => status == OutboxStatus.failed;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'service': service,
        'method': method,
        'url': url,
        'base_url': baseUrl,
        'body': body,
        'idempotency_key': idempotencyKey,
        'resource': resource,
        'kind': kind,
        'entity_id': entityId,
        'status': status.name,
        'attempts': attempts,
        'last_error': lastError,
        'created_at': createdAt.toIso8601String(),
      };

  factory OutboxRow.fromMap(Map<String, Object?> m) => OutboxRow(
        id: m['id'] as int?,
        service: m['service'] as String? ?? '',
        method: m['method'] as String? ?? 'POST',
        url: m['url'] as String? ?? '',
        baseUrl: m['base_url'] as String? ?? '',
        body: m['body'] as String?,
        idempotencyKey: m['idempotency_key'] as String?,
        resource: m['resource'] as String?,
        kind: m['kind'] as String?,
        entityId: m['entity_id'] as String?,
        status: OutboxStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => OutboxStatus.pending,
        ),
        attempts: (m['attempts'] as int?) ?? 0,
        lastError: m['last_error'] as String?,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  /// Key used by the pending-sync badges: `service:entity_id`.
  String get entityKey => '$service:${entityId ?? ''}';
}

enum OutboxStatus { pending, syncing, failed }

/// Durable queue of writes made while offline.
///
/// Mirrors the web app's Dexie `outbox` table: strict FIFO, one row at a time,
/// and a hard stop on the first server rejection so ordering is preserved.
class OutboxStore {
  OutboxStore({this.fileName = 'outbox.db'});

  final String fileName;
  Database? _db;

  /// Mirrors of the queue state so [statusCounts] can answer synchronously —
  /// the sync engine reads it on every snapshot without awaiting SQLite.
  int _pendingCount = 0;
  List<OutboxRow> _countsRows = const [];

  OutboxStatusCounts get statusCounts =>
      OutboxStatusCounts(pending: _pendingCount, rows: _countsRows);

  Future<OutboxStore> open() async {
    await _open();
    await refreshCounts();
    return this;
  }

  Future<void> refreshCounts() async {
    final db = await _open();
    final rows = await db.query('outbox', orderBy: 'created_at ASC, id ASC');
    _countsRows = rows.map(OutboxRow.fromMap).toList();
    _pendingCount = _countsRows
        .where((r) =>
            r.status == OutboxStatus.pending ||
            r.status == OutboxStatus.syncing)
        .length;
    _countsRows = List.unmodifiable(_countsRows);
  }

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      '$dir/$fileName',
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            service TEXT NOT NULL,
            method TEXT NOT NULL,
            url TEXT NOT NULL,
            base_url TEXT NOT NULL,
            body TEXT,
            idempotency_key TEXT,
            resource TEXT,
            kind TEXT,
            entity_id TEXT,
            status TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_outbox_status ON outbox(status, created_at)');
      },
    );
    return _db!;
  }

  Future<int> enqueue(OutboxRow row) async {
    final db = await _open();
    final id = await db.insert('outbox', row.toMap());
    await refreshCounts();
    return id;
  }

  /// Strict FIFO by creation time — the engine replays in exactly this order.
  Future<List<OutboxRow>> pending() async {
    final db = await _open();
    final rows = await db.query(
      'outbox',
      where: 'status = ?',
      whereArgs: [OutboxStatus.pending.name],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(OutboxRow.fromMap).toList();
  }

  Future<List<OutboxRow>> all() async {
    final db = await _open();
    final rows = await db.query('outbox', orderBy: 'created_at ASC, id ASC');
    return rows.map(OutboxRow.fromMap).toList();
  }

  Future<List<OutboxRow>> byStatus(OutboxStatus status) async {
    final db = await _open();
    final rows = await db.query(
      'outbox',
      where: 'status = ?',
      whereArgs: [status.name],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(OutboxRow.fromMap).toList();
  }

  /// Returns rows stranded in `syncing` by a killed process to `pending`.
  ///
  /// `markSyncing` takes no lease, so a crash between marking and finishing
  /// would otherwise strand the row forever: `pending()` skips it, so it is
  /// never replayed, and it still counts towards the "pending sync" badge.
  Future<int> recoverStranded() async {
    final db = await _open();
    final n = await db.update('outbox', {'status': OutboxStatus.pending.name},
        where: 'status = ?', whereArgs: [OutboxStatus.syncing.name]);
    await refreshCounts();
    return n;
  }

  Future<void> markSyncing(int id) async {
    final db = await _open();
    await db.update('outbox', {'status': OutboxStatus.syncing.name},
        where: 'id = ?', whereArgs: [id]);
    await refreshCounts();
  }

  Future<void> markPending(int id, {String? error, int? attempts}) async {
    final db = await _open();
    await db.update(
      'outbox',
      {
        'status': OutboxStatus.pending.name,
        'last_error': error,
        if (attempts != null) 'attempts': attempts,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await refreshCounts();
  }

  Future<void> markFailed(int id, String error) async {
    final db = await _open();
    await db.update(
      'outbox',
      {'status': OutboxStatus.failed.name, 'last_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
    await refreshCounts();
  }

  Future<void> remove(int id) async {
    final db = await _open();
    await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
    await refreshCounts();
  }

  Future<void> clear() async {
    final db = await _open();
    await db.delete('outbox');
    await refreshCounts();
  }

  Future<int> count({OutboxStatus? status}) async {
    final db = await _open();
    if (status == null) {
      final r = await db.rawQuery('SELECT COUNT(*) AS c FROM outbox');
      return (r.first['c'] as int?) ?? 0;
    }
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM outbox WHERE status = ?',
      [status.name],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  /// Signing out discards everything this user queued — the rows are scoped to
  /// a session, not to the device.
  Future<void> clearAll() => clear();

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  void dispose() {
    unawaited(close());
  }

  static String encodeBody(Object? body) =>
      body == null ? '' : jsonEncode(body);
}
