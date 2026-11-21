import '../../core/api/query_cache.dart';

String managementReportCacheKey(
  String report,
  Map<String, dynamic> parameters,
) =>
    QueryCache.cacheKey('reports', {
      'report': report,
      ...parameters,
    });
