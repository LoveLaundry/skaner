import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Canonical JSON with recursively sorted object keys.
///
/// Must stay byte-identical to Python's
/// `json.dumps(payload, sort_keys=True, default=str)`, because the AI service
/// signs and verifies `data_hash` values with that exact serialisation.
String canonicalJson(dynamic value) {
  final buffer = StringBuffer();
  _writeCanonical(value, buffer);
  return buffer.toString();
}

void _writeCanonical(dynamic value, StringBuffer out) {
  if (value == null) {
    out.write('null');
  } else if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    out.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) out.write(',');
      out.write(jsonEncode(keys[i]));
      out.write(':');
      final key = keys[i];
      // Preserve the original value when the key is non-string.
      final raw = value.containsKey(key) ? value[key] : value[keys[i]];
      _writeCanonical(raw, out);
    }
    out.write('}');
  } else if (value is List) {
    out.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) out.write(',');
      _writeCanonical(value[i], out);
    }
    out.write(']');
  } else if (value is DateTime) {
    out.write(jsonEncode(value.toIso8601String()));
  } else if (value is num || value is bool || value is String) {
    out.write(jsonEncode(value));
  } else {
    // Mirrors `default=str` on the Python side.
    out.write(jsonEncode(value.toString()));
  }
}

String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();

String canonicalHash(dynamic value) => sha256Hex(canonicalJson(value));

/// Hmac-SHA256 of [message] under [key], lowercase hex.
String hmacSha256Hex(String key, String message) =>
    Hmac(sha256, utf8.encode(key)).convert(utf8.encode(message)).toString();

/// The `X-Idempotency-Key` the web client derives for a create call: a
/// deterministic hash of the payload, so a double-submit of the same body
/// collapses into one record server-side.
String idempotencyKey(dynamic payload, {String prefix = 's1-'}) {
  return '$prefix${canonicalHash(payload)}';
}

/// Fallback for platforms without a hardware digest: djb2, as the web client
/// uses when `crypto.subtle` is unavailable.
String fallbackIdempotencyKey(dynamic payload) {
  final s = canonicalJson(payload);
  var hash = 5381;
  for (final unit in utf8.encode(s)) {
    hash = ((hash << 5) + hash) + unit;
    hash &= 0xFFFFFFFF;
  }
  return 'f1-${hash.toRadixString(16).padLeft(8, '0')}';
}

/// A fresh, non-deterministic key for payloads the client is inventing
/// (a form the user just filled in, before it is normalised).
String randomIdempotencyKey([String prefix = 's1-']) {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return '$prefix${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}
