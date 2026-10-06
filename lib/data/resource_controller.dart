import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../core/api/query_cache.dart';
import '../core/utils/formatting.dart';

/// Lifecycle of one remote list, mirroring react-query's four states so the UI
/// can always explain where the rows on screen came from.
enum LoadPhase { idle, loading, ready, failed }

/// A single read that renders cache-first, then refreshes from the network.
///
/// Reads are always attempted against the network first; [QueryCache] is what
/// makes the app useful with no signal. A failed refresh keeps the cached rows
/// on screen and flips [status] to stale/offline rather than blanking the list.
class ResourceController<T> extends ChangeNotifier {
  ResourceController({
    required this.key,
    required this.fetcher,
    required this.cache,
    this.keepPreviousOnReload = true,
  });

  /// Cache prefix, e.g. `bills`. The sync engine invalidates on this name.
  final String key;
  final Future<T> Function() fetcher;
  final QueryCache cache;
  final bool keepPreviousOnReload;

  T? _data;
  LoadPhase _phase = LoadPhase.idle;
  CacheStatus _status = CacheStatus.fresh;
  String? _error;
  bool _disposed = false;
  int _requestSeq = 0;

  T? get data => _data;
  LoadPhase get phase => _phase;
  CacheStatus get status => _status;
  String? get error => _error;
  DateTime? get lastUpdated => _cached?.updatedAt;
  bool get isLoading => _phase == LoadPhase.loading;
  bool get hasData => _data != null;
  bool get isStale => _status != CacheStatus.fresh;

  CachedResource? _cached;

  /// Returns the cached value only when it still matches the shape the fetcher
  /// produces, otherwise null so the caller falls through to the network.
  T? _typed(dynamic value) {
    try {
      return value is T ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> load({bool force = false}) async {
    final seq = ++_requestSeq;
    if (_data == null || force || !keepPreviousOnReload) {
      _phase = LoadPhase.loading;
      _status = CacheStatus.syncing;
    } else {
      _status = CacheStatus.syncing;
    }
    _error = null;
    _safeNotify();

    final cached = await cache.read(key);
    if (_disposed || seq != _requestSeq) return;
    _cached = cached;
    if (cached != null && _data == null) {
      final seeded = _typed(cached.data);
      if (seeded != null) {
        _data = seeded;
        _status = CacheStatus.stale;
        _phase = LoadPhase.ready;
        _safeNotify();
      }
    }

    try {
      final fresh = await fetcher();
      if (_disposed || seq != _requestSeq) return;
      _data = fresh;
      _cached = CachedResource(
        key: key,
        data: fresh,
        updatedAt: DateTime.now(),
        status: CacheStatus.fresh,
      );
      cache.write(key, fresh);
      _status = CacheStatus.fresh;
      _phase = LoadPhase.ready;
      _error = null;
    } catch (e) {
      if (_disposed || seq != _requestSeq) return;
      if (_shouldUseCache(e)) {
        final fallback = await cache.read(key);
        if (_disposed || seq != _requestSeq) return;
        final typed = fallback == null ? null : _typed(fallback.data);
        if (typed != null) {
          _cached = fallback;
          _data = typed;
          _status = CacheStatus.offline;
          _phase = LoadPhase.ready;
          _error = null;
          _safeNotify();
          return;
        }
        if (_data != null) {
          _status = CacheStatus.offline;
          _phase = LoadPhase.ready;
          _safeNotify();
          return;
        }
      }
      _error = e.toString();
      _status = CacheStatus.syncedFailed;
      _phase = LoadPhase.failed;
    }
    _safeNotify();
  }

  /// A write landed. Optimistically re-read so the list reflects the server's
  /// view rather than a guess.
  Future<void> refresh() async {
    cache.invalidateResource(key);
    await load(force: true);
  }

  /// Local mutation, used by optimistic deletes and inline edits so the row
  /// disappears before the round trip completes.
  void setData(T value) {
    _data = value;
    _phase = LoadPhase.ready;
    _safeNotify();
  }

  bool _shouldUseCache(Object e) {
    if (e is QueuedResponse) return false;
    if (e is ApiException) {
      return e.statusCode == null || e.statusCode! >= 500;
    }
    return true;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Normalises the several list envelope shapes the backends return
/// (`{items}`, `{data}`, `{records}`, or a bare array).
List<Map<String, dynamic>> asRows(dynamic payload) {
  if (payload == null) return const [];
  if (payload is List) {
    return payload.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }
  if (payload is Map) {
    final map = Map<String, dynamic>.from(payload);
    for (final key in const [
      'items',
      'data',
      'records',
      'results',
      'rows',
      'list',
    ]) {
      final value = map[key];
      if (value is List) {
        return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
      }
    }
    // A single object response is a one-row list.
    if (map.isNotEmpty && (map['id'] != null || map.containsKey('ID'))) {
      return [map];
    }
  }
  return const [];
}

int asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

double asDouble(Object? v, [double fallback = 0]) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) {
    return double.tryParse(v.replaceAll(',', '').trim()) ?? fallback;
  }
  return fallback;
}

String asString(Object? v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return v.toString();
}

bool asBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }
  return false;
}

DateTime? asDate(Object? v) => Fmt.parseDate(v);

/// Reads a key under any of several spellings — the backends are not
/// consistent about casing, and a page should not care.
Object? pick(Map<String, dynamic> row, List<String> keys) {
  for (final k in keys) {
    if (row.containsKey(k) && row[k] != null) return row[k];
  }
  return null;
}

String str(Map<String, dynamic> row, List<String> keys,
        [String fallback = '']) =>
    asString(pick(row, keys), fallback);

int intOf(Map<String, dynamic> row, List<String> keys, [int fallback = 0]) =>
    asInt(pick(row, keys), fallback);

double numOf(Map<String, dynamic> row, List<String> keys,
        [double fallback = 0]) =>
    asDouble(pick(row, keys), fallback);

bool boolOf(Map<String, dynamic> row, List<String> keys) =>
    asBool(pick(row, keys));

DateTime? dateOf(Map<String, dynamic> row, List<String> keys) =>
    asDate(pick(row, keys));

/// Total page count from a `limit`/`page` query pair.
int pageCount(int total, int limit) =>
    limit <= 0 ? 1 : ((total + limit - 1) ~/ limit).clamp(1, 1 << 30);
