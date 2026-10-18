import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../config/api_config.dart';

/// Device-level settings that outlive a session but are not part of the account:
/// runtime backend URL overrides only. AI authentication is server-side and is
/// intentionally not configurable in the client.
///
/// The web app reads these from Vite env vars, which a shipped APK has no
/// equivalent of, so URL overrides live in SharedPreferences and are pushed
/// into [ApiConfig] on load.
class AppSettingsStore {
  AppSettingsStore._();

  static const _urlsKey = 'll_api_overrides';
  static bool _loaded = false;

  /// Empty by design: the APK never stores or sends a shared AI credential.
  static String get aiKey => ApiConfig.defaultAiKey;

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
    _loaded = true;
  }

  /// Retained as a no-op for compatibility with older settings screens.
  static Future<void> setAiKey(String value) async {
    // AI credentials must never be accepted from or persisted by the client.
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
