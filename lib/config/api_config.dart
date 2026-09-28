/// Identifiers the offline outbox uses to attribute a queued write. Kept
/// identical to the web app's names so a row written by either client is
/// recognisable to the other.
class ServiceNames {
  ServiceNames._();

  static const String quotation = 'quotation';
  static const String bills = 'bills';
  static const String users = 'users';
  static const String workers = 'workers';
  static const String management = 'management';
  static const String ai = 'ai';

  static const List<String> all = [
    quotation,
    bills,
    users,
    workers,
    management,
    ai,
  ];
}

/// Central registry of the six backend services the mobile app talks to.
///
/// The web app reads these from Vite env vars; a shipped APK has no env layer,
/// so the production URLs live here and can be overridden at runtime from the
/// Settings screen (handy for pointing a debug build at a local backend).
class ApiConfig {
  ApiConfig._();

  static const String _kQuotes = 'api.quotation';
  static const String _kBills = 'api.bills';
  static const String _kUsers = 'api.users';
  static const String _kWorkers = 'api.workers';
  static const String _kManagement = 'api.management';
  static const String _kAi = 'api.ai';

  /// Live deployment.
  static const String defaultQuotation = 'https://quotation-service-three.vercel.app';
  static const String defaultBills = 'https://bill-service-puce.vercel.app';
  static const String defaultUsers = 'https://love-laundry-user-service.vercel.app';
  static const String defaultWorkers = 'https://worker-service-zeta.vercel.app';
  static const String defaultManagement = 'https://laundry-management.vercel.app';
  static const String defaultAi = 'https://love-ai.vercel.app';

  static const String defaultAiKey = 'dev-key-change-me';

  /// Local development fallbacks (adb reverse / emulator host loopback).
  static const String localQuotation = 'http://localhost:8000';
  static const String localBills = 'http://localhost:8001';
  static const String localUsers = 'http://localhost:8002';
  static const String localWorkers = 'http://localhost:8003';
  static const String localManagement = 'http://localhost:8004';
  static const String localAi = 'http://localhost:8009';

  /// Which env the app is currently talking to.
  static const String envLocal = 'local';
  static const String envProduction = 'production';

  static String environment = envProduction;

  static Map<String, String> get _overrides => _runtimeOverrides;
  static final Map<String, String> _runtimeOverrides = <String, String>{};

  static String _resolve(String overrideKey, String prod, String local) {
    final override = _overrides[overrideKey];
    if (override != null && override.trim().isNotEmpty) {
      return _normalise(override.trim());
    }
    return _normalise(environment == envLocal ? local : prod);
  }

  /// The workers service sits behind a Vercel redirect; an http:// URL to a
  /// non-loopback host would 301 into a CORS-failing https:// preflight.
  static String _normalise(String url) {
    var u = url;
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    final isLoopback = u.contains('localhost') || u.contains('127.0.0.1') || u.contains('10.0.2.2');
    if (u.startsWith('http://') && !isLoopback) {
      u = u.replaceFirst('http://', 'https://');
    }
    return u;
  }

  // ── Service base URLs ──────────────────────────────────────────────────────
  static String get quotationBase => _resolve(_kQuotes, defaultQuotation, localQuotation);
  static String get billsBase => _resolve(_kBills, defaultBills, localBills);
  static String get usersBase => _resolve(_kUsers, defaultUsers, localUsers);
  static String get workersBase => _resolve(_kWorkers, defaultWorkers, localWorkers);
  static String get managementBase => _resolve(_kManagement, defaultManagement, localManagement);
  static String get aiBase => _resolve(_kAi, defaultAi, localAi);

  static String baseFor(String service) => switch (service) {
        ServiceNames.quotation => quotationBase,
        ServiceNames.bills => billsBase,
        ServiceNames.users => usersBase,
        ServiceNames.workers => workersBase,
        ServiceNames.management => managementBase,
        ServiceNames.ai => aiBase,
        _ => quotationBase,
      };

  /// Request timeouts, matching the web clients.
  static const Duration shortTimeout = Duration(seconds: 10);
  static const Duration mediumTimeout = Duration(seconds: 15);
  static const Duration longTimeout = Duration(seconds: 30);

  static void setOverride(String service, String? url) {
    final key = 'api.$service';
    if (url == null || url.trim().isEmpty) {
      _runtimeOverrides.remove(key);
    } else {
      _runtimeOverrides[key] = url.trim();
    }
  }

  static void setEnvironment(String env) => environment = env;

  static void resetOverrides() => _runtimeOverrides.clear();

  /// Everything the Settings screen needs to render the server editor.
  static Map<String, String> get currentOverrides => Map.unmodifiable(_overrides);
}
