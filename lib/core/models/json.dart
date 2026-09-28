/// Small helpers shared by every model: null-safe readers that coerce the
/// loose typing a hand-written API can return.
library;

int asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  if (v is bool) return v ? 1 : 0;
  return fallback;
}

double asDouble(Object? v, [double fallback = 0]) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? fallback;
  return fallback;
}

String asString(Object? v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return v.toString();
}

String? asStringOrNull(Object? v) {
  if (v == null) return null;
  final s = v is String ? v : v.toString();
  return s.isEmpty ? null : s;
}

bool asBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
  }
  return fallback;
}

List<Map<String, dynamic>> asMapList(Object? v) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => e.map((k, val) => MapEntry(k.toString(), val)))
      .toList();
}

Map<String, dynamic> asMap(Object? v) {
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val));
  }
  return <String, dynamic>{};
}

/// Accepts either a bare list or a `{items,total}` envelope and always yields
/// the list plus the total. Several endpoints return one, some the other.
({List<Map<String, dynamic>> items, int total}) unwrapList(Object? v) {
  if (v is List) {
    final items = asMapList(v);
    return (items: items, total: items.length);
  }
  final m = asMap(v);
  for (final k in ['items', 'results', 'data', 'rows', 'records']) {
    if (m[k] is List) {
      final items = asMapList(m[k]);
      final total = m['total'] is num
          ? asInt(m['total'])
          : (m['count'] is num ? asInt(m['count']) : items.length);
      return (items: items, total: total);
    }
  }
  return (items: const [], total: 0);
}

/// The first list it can find inside a nested envelope, e.g. `{data:{items:[]}}`.
List<Map<String, dynamic>> deepList(Object? v) {
  if (v is List) return asMapList(v);
  final m = asMap(v);
  final direct = unwrapList(m);
  if (direct.items.isNotEmpty) return direct.items;
  for (final val in m.values) {
    if (val is List) {
      final items = asMapList(val);
      if (items.isNotEmpty) return items;
    }
    if (val is Map) {
      final nested = deepList(val);
      if (nested.isNotEmpty) return nested;
    }
  }
  return const [];
}
