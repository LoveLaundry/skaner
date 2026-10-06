import 'dart:convert';

/// A failure that carries the HTTP status and the server's `detail` message,
/// mirroring the shape the web client's normalised `Error` exposes.
class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.url,
    this.method,
    this.body,
  });

  final String message;
  final int? statusCode;
  final String? url;
  final String? method;
  final dynamic body;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isValidation => statusCode == 400 || statusCode == 422;

  /// 5xx and transport errors are worth retrying; the rest are not.
  bool get isRetryable =>
      statusCode == null || (statusCode != null && statusCode! >= 500);

  /// Thrown when the write was accepted into the local outbox rather than sent.
  bool get isQueued => statusCode == 202;

  /// Field name → message, lifted out of a FastAPI 422 body so a form can
  /// highlight the exact inputs that failed instead of only showing a banner.
  Map<String, String> get fieldErrors {
    if (!isValidation || body is! String) return const {};
    try {
      final decoded = jsonDecode(body! as String);
      if (decoded is! Map) return const {};
      final detail = decoded['detail'];
      if (detail is! List) return const {};
      final out = <String, String>{};
      for (final item in detail) {
        if (item is! Map) continue;
        final msg = item['msg'];
        final loc = item['loc'];
        if (msg is! String) continue;
        final field =
            loc is List && loc.isNotEmpty ? loc.last.toString() : null;
        if (field != null && field.isNotEmpty) out[field] = msg;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  @override
  String toString() => message;
}

/// Pulls a human-readable message out of any of the body shapes FastAPI emits:
/// `{"detail": "..."}`, `{"detail": [{...}]}` (422 validation), or a bare string.
String extractErrorMessage(dynamic body, {String fallback = 'Request failed'}) {
  if (body == null) return fallback;
  if (body is String) {
    if (body.trim().isEmpty) return fallback;
    try {
      return extractErrorMessage(jsonDecode(body), fallback: fallback);
    } catch (_) {
      return body;
    }
  }
  if (body is Map) {
    final detail = body['detail'] ?? body['message'] ?? body['error'];
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map) {
        final msg = first['msg'];
        final loc = first['loc'];
        if (msg is String && loc is List && loc.isNotEmpty) {
          final field = loc.last.toString();
          return '$field: $msg';
        }
        if (msg is String) return msg;
      }
      return detail.join(', ');
    }
    if (detail != null) return detail.toString();
  }
  return fallback;
}
