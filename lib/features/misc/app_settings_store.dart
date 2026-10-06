import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../config/api_config.dart';

/// Device-level settings that outlive a session but are not part of the account:
/// the runtime backend URLs and the AI service key.
///
/// The web app reads these from Vite env vars, which a shipped APK has no
/// equivalent of, so they live in SharedPreferences and are pushed into
/// [ApiConfig] overrides on load. The AI key is deliberately kept out of
/// [ApiConfig] because it is not a URL.
class AppSettingsStore {
  AppSettingsStore._();

  static const _urlsKey = 'll_api_overrides';
  static const _aiKey = 'll_ai_key';

  static String _ai = ApiConfig.defaultAiKey;
  static bool _loaded = false;

  /// Last saved AI key, defaulting to the compiled-in development key.
  static String get aiKey => _ai;

  static bool get loaded => _loaded;

  /// Applies persisted overrides into [ApiConfig] and caches the AI key.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_urlsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            // Stored as bare service names; ApiConfig adds the `api.` prefix.
            final service = '${entry.key}'.replaceFirst('api.', '');
            if (value is String && value.trim().isNotEmpty) {
              ApiConfig.setOverride(service, value);
            }
          }
        }
      } catch (_) {
        // A corrupt blob must not brick the app; the defaults are still valid.
      }
    }
    _ai = prefs.getString(_aiKey) ?? ApiConfig.defaultAiKey;
    _loaded = true;
  }

  static Future<void> setAiKey(String value) async {
    _ai = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiKey, _ai);
  }

  /// [service] is a [ServiceNames] value; the override key is `api.<service>`.
  static Future<void> setServiceUrl(String service, String url) async {
    ApiConfig.setOverride(service, url);
    await _persist();
  }

  static String serviceUrl(String service) =>
      ApiConfig.currentOverrides['api.$service'] ?? ApiConfig.baseFor(service);

  static Future<void> resetServiceUrls() async {
    ApiConfig.resetOverrides();
    await _persist();
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final overrides = {
      for (final e in ApiConfig.currentOverrides.entries)
        e.key.replaceFirst('api.', ''): e.value,
    };
    if (overrides.isEmpty) {
      await prefs.remove(_urlsKey);
      return;
    }
    await prefs.setString(_urlsKey, jsonEncode(overrides));
  }

  /// Service label for the settings editor.
  static String labelFor(String service) => switch (service) {
        ServiceNames.quotation => 'Quotation service',
        ServiceNames.bills => 'Bill service',
        ServiceNames.users => 'User service',
        ServiceNames.workers => 'Worker service',
        ServiceNames.management => 'Management service',
        ServiceNames.ai => 'AI service',
        _ => service,
      };
}
