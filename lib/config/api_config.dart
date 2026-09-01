class ApiConfig {
  static const String baseUrl = 'https://bill-service-puce.vercel.app';

  // Auth
  static const String loginUrl = 'https://user-service-lovelaundry.vercel.app/auth/login';
  static const String authStatusUrl = 'https://user-service-lovelaundry.vercel.app/auth/status';

  // Linen
  static const String linensBase = '$baseUrl/linens';
  static String linenByCode(String code) => '$linensBase/by-code/$code';
  static String linenScan(String docId) => '$linensBase/$docId/scan';
  static String linenEvents(String docId) => '$linensBase/$docId/events';

  // Garment Tags (quotation-service)
  static const String tagBaseUrl = 'https://quotation-service-lovelaundry.vercel.app';
  static String tagByCode(String code) => '$tagBaseUrl/tags/$code';
  static String tagTracking(String code) => '$tagBaseUrl/tags/$code/tracking';
}
