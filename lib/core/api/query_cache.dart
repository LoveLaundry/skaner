import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// A cached resource read, with the metadata the sync pills display.
@immutable
class CachedResource {
  const CachedResource({
    required this.key,
    required this.data,
    required this.updatedAt,
    this.status = CacheStatus.fresh,
  });

  final String key;
  final dynamic data;
  final DateTime updatedAt;
  final CacheStatus status;

  bool get isEmpty => data == null;

  CachedResource copyWith(
          {dynamic data, DateTime? updatedAt, CacheStatus? status}) =>
      CachedResource(
        key: key,
        data: data ?? this.data,
        updatedAt: updatedAt ?? this.updatedAt,
        status: status ?? this.status,
      );
}

enum CacheStatus { fresh, syncing, stale, offline, syncedFailed }

/// Durable key/value cache for server reads, scoped per signed-in user.
///
/// Reads are always attempted against the network first. This cache is what
/// makes the app useful in a laundry back-room with no signal: a list renders
/// from here instantly and refreshes when the connection returns.
class QueryCache extends ChangeNotifier {
  QueryCache({this.version = '20260920-v1'});

  /// Bumped when a response shape changes so old entries are discarded.
  final String version;

  static const Duration maxAge = Duration(days: 7);
  static const _debounce = Duration(milliseconds: 400);

  /// Only these resource prefixes are worth persisting; the rest (today's ops
  /// feed, chat, database status) is either ephemeral or always network-bound.
  static const Set<String> persistable = {
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
  };

  /// How long a resource stays "fresh" before the UI nudges a refresh.
  static const Map<String, Duration> staleness = {
    'mgmt-dashboard': Duration(seconds: 60),
    'dashboard': Duration(seconds: 60),
    'notifications': Duration(seconds: 60),
    'reports': Duration(minutes: 2),
    'attendance': Duration(minutes: 2),
    'shop-bills': Duration(minutes: 3),
    'bills': Duration(minutes: 3),
    'payments': Duration(minutes: 3),
    'transactions': Duration(minutes: 3),
    'salary': Duration(minutes: 3),
    'legacy-invoices': Duration(minutes: 5),
    'quotations': Duration(minutes: 5),
    'gatepasses': Duration(minutes: 5),
    'deliveries': Duration(minutes: 5),
    'returns': Duration(minutes: 5),
    'dispatch': Duration(minutes: 5),
    'loyalty': Duration(minutes: 5),
    'daily-logs': Duration(minutes: 5),
    'advances': Duration(minutes: 5),
    'extra-work': Duration(minutes: 5),
    'expenses': Duration(minutes: 5),
    'workers': Duration(minutes: 10),
    'employees': Duration(minutes: 10),
    'customers': Duration(minutes: 10),
    'items': Duration(minutes: 10),
    'categories': Duration(minutes: 10),
    'company-settings': Duration(minutes: 10),
    'linens': Duration(minutes: 10),
    'holidays': Duration(minutes: 30),
  };

  Database? _db;
  String? _scope;
  final Map<String, CachedResource> _memory = {};
  Timer? _writeTimer;

  /// In-memory index of everything loaded this session, so a screen can render
  /// instantly on re-entry without touching SQLite.
  Map<String, CachedResource> get inMemory => Map.unmodifiable(_memory);

  static String dbNameFor(String userId) {
    final safe = userId.replaceAll(RegExp(r'[^A-Za-z0-9_:-]'), '');
    final trimmed = safe.length > 48 ? safe.substring(0, 48) : safe;
    return 'love_cache_${trimmed.isEmpty ? 'anon' : trimmed}';
  }

  static Duration stalenessFor(String key) {
    final resource = key.split('|').first.split('?').first;
    return staleness[resource] ?? const Duration(minutes: 1);
  }

  Future<void> open(String userId) async {
    if (_scope == userId && _db != null) return;
    await _close();
    _scope = userId;
    _memory.clear();
    final dir = await getDatabasesPath();
    try {
      _db = await openDatabase(
        '$dir/${dbNameFor(userId)}',
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
              'CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
          await db.execute(
              'CREATE TABLE resources (resource TEXT PRIMARY KEY, created_at TEXT, last_updated_at TEXT, cache_version TEXT, sync_status TEXT)');
        },
      );
    } catch (_) {
      // Cache is best-effort: a device that cannot open the DB still works,
      // it just never renders offline data.
      _db = null;
    }
  }

  static String cacheKey(String resource, [Map<String, dynamic>? params]) {
    if (params == null || params.isEmpty) return resource;
    final entries = params.entries.where((e) => e.value != null).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return resource;
    final qs = entries.map((e) => '${e.key}=${e.value}').join('&');
    return '$resource|$qs';
  }

  CachedResource? peek(String key) => _memory[key];

  /// Reads through to storage, so a cold screen still has something to draw.
  Future<CachedResource?> read(String key) async {
    final mem = _memory[key];
    if (mem != null) return mem;
    final db = _db;
    if (db == null) return null;
    try {
      final rows = await db.query('kv', where: 'key = ?', whereArgs: [key]);
      if (rows.isEmpty) return null;
      final raw = rows.first['value'] as String?;
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      // Rows written before the timestamp envelope existed are still readable,
      // but only the `resources` mirror knows when they were written — and the
      // `kv` table has no such column, so they are treated as ancient and the
      // reader refreshes instead of showing them as current.
      dynamic data = decoded;
      var updatedAt = DateTime.fromMillisecondsSinceEpoch(0);
      var status = CacheStatus.stale;
      if (decoded is Map && decoded.containsKey('d') && decoded.containsKey('a')) {
        data = decoded['d'];
        updatedAt = DateTime.tryParse(decoded['a'] as String? ?? '') ?? updatedAt;
        status = CacheStatus.values.firstWhere(
          (v) => v.name == decoded['s'],
          orElse: () => CacheStatus.fresh,
        );
      }
      final res = CachedResource(
        key: key,
        data: data,
        updatedAt: updatedAt,
        status: status,
      );
      _memory[key] = res;
      return res;
    } catch (_) {
      return null;
    }
  }

  void write(
    String key,
    dynamic data, {
    DateTime? updatedAt,
    CacheStatus status = CacheStatus.fresh,
  }) {
    if (data == null) return;
    final at = updatedAt ?? DateTime.now();
    final resource = key.split('|').first.split('?').first;
    _memory[key] =
        CachedResource(key: key, data: data, updatedAt: at, status: status);
    if (persistable.contains(resource)) _scheduleWrite();
    notifyListeners();
  }

  void _scheduleWrite() {
    _writeTimer?.cancel();
    _writeTimer = Timer(_debounce, _flush);
  }

  Future<void> _flush() async {
    final db = _db;
    if (db == null) return;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    var queued = 0;
    for (final entry in _memory.entries) {
      final resource = entry.key.split('|').first.split('?').first;
      if (!persistable.contains(resource)) continue;
      try {
        batch.insert(
          'kv',
          {
            'key': entry.key,
            'value': jsonEncode({
              'a': entry.value.updatedAt.toIso8601String(),
              's': entry.value.status.name,
              'd': entry.value.data,
            }),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        batch.insert(
          'resources',
          {
            'resource': resource,
            'created_at': now,
            'last_updated_at': entry.value.updatedAt.toIso8601String(),
            'cache_version': version,
            'sync_status': CacheStatus.fresh.name,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        queued++;
      } catch (_) {
        // A value that will not serialise is simply not cached.
      }
      if (queued >= 200) break;
    }
    try {
      await batch.commit(noResult: true);
    } catch (_) {
      // Persistence is best-effort; the network remains the source of truth.
    }
  }

  /// Drops every entry whose resource prefix matches — what a replayed outbox
  /// row triggers.
  ///
  /// The database delete must not sit behind an in-memory check: on a cold
  /// start nothing is in `_memory` yet, so the early return used to leave the
  /// persisted row in place and the invalidated resource was rehydrated stale.
  void invalidateResource(String resource) {
    final keys = _memory.keys
        .where((k) => k.split('|').first.split('?').first == resource)
        .toList();
    for (final k in keys) {
      _memory.remove(k);
    }
    final db = _db;
    if (db != null) {
      // `_` and `%` are LIKE wildcards; a resource containing either would
      // over-match and evict unrelated entries.
      final escaped = resource
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      unawaited(() async {
        try {
          await db.delete('kv',
              where: "key LIKE ? ESCAPE '\\'", whereArgs: ['$escaped|%']);
          await db.delete('kv', where: 'key = ?', whereArgs: [resource]);
        } catch (_) {
          // Cache eviction is best-effort.
        }
      }());
    }
    notifyListeners();
  }

  void invalidateAll() {
    _memory.clear();
    unawaited(
        _db?.delete('kv').catchError((Object _) => 0) ?? Future<int>.value(0));
    notifyListeners();
  }

  bool isStale(String key) =>
      DateTime.now().difference(_memory[key]?.updatedAt ?? DateTime(2000)) >
      stalenessFor(key);

  /// Drops stale entries on launch so the cache cannot grow unbounded.
  Future<void> prune() async {
    final cutoff = DateTime.now().subtract(maxAge);
    for (final e in _memory.entries.toList()) {
      if (e.value.updatedAt.isBefore(cutoff)) _memory.remove(e.key);
    }
    await _flush();
  }

  /// Signing out clears the cache entirely, as the web client does when it
  /// drops the user's IndexedDB database.
  Future<void> clearAll() async {
    _memory.clear();
    final db = _db;
    if (db != null) {
      await db.delete('kv').catchError((Object _) => 0);
      await db.delete('resources').catchError((Object _) => 0);
    }
    notifyListeners();
  }

  Future<void> _close() async {
    await _db?.close();
    _db = null;
    _scope = null;
  }

  @override
  void dispose() {
    _writeTimer?.cancel();
    unawaited(_close());
    super.dispose();
  }
}
