import 'package:intl/intl.dart';

/// Money, dates and numbers rendered the way the web app renders them:
/// `Rs.` + en-LK with exactly two decimals.
class Fmt {
  Fmt._();

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_LK',
    symbol: 'Rs.',
    decimalDigits: 2,
  );
  static final NumberFormat _moneyCompact = NumberFormat('#,##,##0.00', 'en_LK');
  static final NumberFormat _int = NumberFormat.decimalPattern('en_LK');
  static final DateFormat _date = DateFormat('dd MMM yyyy', 'en_US');
  static final DateFormat _dateShort = DateFormat('dd MMM', 'en_US');
  static final DateFormat _dateTime = DateFormat('dd MMM yyyy, HH:mm', 'en_US');
  static final DateFormat _time = DateFormat('HH:mm', 'en_US');
  static final DateFormat _isoDate = DateFormat('yyyy-MM-dd');
  static final DateFormat _isoDateTime = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final DateFormat _monthYear = DateFormat('MMMM yyyy', 'en_US');
  static final DateFormat _fileStamp = DateFormat('yyyy-MM-dd');

  // ── Numbers ────────────────────────────────────────────────────────────────
  static String money(num? value) => _money.format((value ?? 0).toDouble());

  /// Plain grouped number, no currency marker — for CSV cells.
  static String amount(num? value) => _moneyCompact.format((value ?? 0).toDouble());

  static String count(num? value) => _int.format(value ?? 0);

  /// Compact form for tight stat tiles: 1.2M / 340K / 12.
  static String compact(num? value) {
    final v = (value ?? 0).toDouble();
    final abs = v.abs();
    if (abs >= 1000000) return '${_trim(v / 1000000)}M';
    if (abs >= 1000) return '${_trim(v / 1000)}K';
    return _trim(v);
  }

  static String _trim(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  /// Drops trailing `.0` on quantities so a table reads `12`, not `12.0`.
  static String qty(num? value) {
    final v = (value ?? 0).toDouble();
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  static String percent(num? value, {int decimals = 1}) =>
      '${(value ?? 0).toStringAsFixed(decimals)}%';

  // ── Dates ──────────────────────────────────────────────────────────────────
  static String date(Object? value) {
    final d = parseDate(value);
    return d == null ? '—' : _date.format(d);
  }

  static String dateShort(Object? value) {
    final d = parseDate(value);
    return d == null ? '—' : _dateShort.format(d);
  }

  static String dateTime(Object? value) {
    final d = parseDate(value);
    return d == null ? '—' : _dateTime.format(d);
  }

  static String time(Object? value) {
    final d = parseDate(value);
    return d == null ? '—' : _time.format(d);
  }

  static String monthYear(Object? value) {
    final d = parseDate(value);
    return d == null ? '—' : _monthYear.format(d);
  }

  /// `yyyy-MM-dd` — what every query parameter and POST body expects.
  static String isoDate(Object? value) {
    final d = parseDate(value);
    return d == null ? '' : _isoDate.format(d);
  }

  static String isoDateTime(Object? value) {
    final d = parseDate(value);
    return d == null ? '' : _isoDateTime.format(d);
  }

  static String fileStamp(Object? value) {
    final d = parseDate(value);
    return d == null ? '' : _fileStamp.format(d);
  }

  static String today() => _isoDate.format(DateTime.now());

  static String nowIso() => DateTime.now().toIso8601String();

  /// "3 days ago" / "in 2 hours" for activity feeds.
  static String relative(Object? value) {
    final d = parseDate(value);
    if (d == null) return '—';
    final diff = DateTime.now().difference(d);
    final future = diff.isNegative;
    final abs = diff.abs();
    String unit;
    if (abs.inSeconds < 45) {
      return future ? 'in a moment' : 'just now';
    } else if (abs.inMinutes < 60) {
      unit = '${abs.inMinutes} min';
    } else if (abs.inHours < 24) {
      unit = '${abs.inHours} hr';
    } else if (abs.inDays < 7) {
      unit = '${abs.inDays} day${abs.inDays == 1 ? '' : 's'}';
    } else if (abs.inDays < 31) {
      final w = (abs.inDays / 7).floor();
      unit = '$w week${w == 1 ? '' : 's'}';
    } else if (abs.inDays < 365) {
      final m = (abs.inDays / 30).floor();
      unit = '$m month${m == 1 ? '' : 's'}';
    } else {
      final y = (abs.inDays / 365).floor();
      unit = '$y year${y == 1 ? '' : 's'}';
    }
    return future ? 'in $unit' : '$unit ago';
  }

  /// Accepts ISO strings with or without a zone, `yyyy-MM-dd`, and epoch millis.
  static DateTime? parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) {
      if (value <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    final s = value.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    return DateTime.tryParse(s) ??
        DateTime.tryParse(s.replaceFirst(' ', 'T')) ??
        DateTime.tryParse('$s 00:00:00');
  }

  // ── Text ───────────────────────────────────────────────────────────────────
  /// "RECEIVED_FOR_DELIVERY" → "Received for delivery"
  static String humanise(String? value, {String fallback = '—'}) {
    if (value == null || value.trim().isEmpty) return fallback;
    final v = value.trim();
    final words = v.replaceAll('_', ' ').replaceAll('-', ' ').split(RegExp(r'\s+'));
    if (words.isEmpty) return fallback;
    final first = words.first.toLowerCase();
    final sb = StringBuffer(first[0].toUpperCase() + first.substring(1));
    for (var i = 1; i < words.length; i++) {
      sb.write(' ${words[i]}');
    }
    return sb.toString();
  }

  static String initials(String? name, {int max = 2}) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= max ? max : parts.first.length).toUpperCase();
    }
    return parts.take(max).map((p) => p[0].toUpperCase()).join();
  }

  static String truncate(String? value, int max) {
    final v = (value ?? '').trim();
    if (v.length <= max) return v;
    return '${v.substring(0, max)}…';
  }
}
