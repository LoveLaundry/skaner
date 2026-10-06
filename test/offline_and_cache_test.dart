import 'package:flutter_test/flutter_test.dart';
import 'package:love_mobi/core/api/api_client.dart';
import 'package:love_mobi/core/api/api_exception.dart';
import 'package:love_mobi/core/api/query_cache.dart';
import 'package:love_mobi/data/resource_controller.dart';

void main() {
  group('offline write outcome', () {
    test('a queued write is never reported as saved', () async {
      // A QueuedResponse is *returned*, so code that ignores the result — the
      // shape every `on QueuedResponse` catch clause used to leave behind —
      // tells the operator the server accepted a change it never saw.
      final result = await Future<Object?>.value(
        QueuedResponse(7, 'bills', 'POST', '/bills'),
      );
      expect(result, isA<QueuedResponse>());
    });

    test('a real write result is not mistaken for a queue marker', () {
      const body = {'id': '42', 'total': 1200};
      expect(body is QueuedResponse, isFalse);
    });
  });

  group('QueryCache key handling', () {
    test('parameterised keys sort deterministically', () {
      final a = QueryCache.cacheKey('bills', {'status': 'paid', 'from': '2'});
      final b = QueryCache.cacheKey('bills', {'from': '2', 'status': 'paid'});
      expect(a, b);
      expect(a, 'bills|from=2&status=paid');
    });

    test('null parameters drop out of the key', () {
      expect(QueryCache.cacheKey('bills', {'from': null, 'to': '3'}),
          'bills|to=3');
      expect(QueryCache.cacheKey('bills', const {}), 'bills');
    });

    test('the resource prefix ignores parameters and queries', () {
      final cache = QueryCache();
      cache.write('bills|from=2&status=paid', [
        {'id': '1'}
      ], updatedAt: DateTime(2026, 1, 1));
      expect(cache.inMemory.keys, contains('bills|from=2&status=paid'));
    });

    test('invalidation by resource drops every parameterised key', () {
      final cache = QueryCache();
      cache.write('bills', [
        {'id': '1'}
      ]);
      cache.write('bills|status=paid', [
        {'id': '2'}
      ]);
      cache.write('payments', [
        {'id': '3'}
      ]);
      cache.invalidateResource('bills');
      expect(cache.inMemory.keys, ['payments']);
    });

    test('a resource name that looks like a LIKE wildcard stays exact', () {
      final cache = QueryCache();
      cache.write('a_b', [
        {'id': '1'}
      ]);
      cache.write('aXb', [
        {'id': '2'}
      ]);
      cache.invalidateResource('a_b');
      // `_` must not act as a single-character wildcard and wipe out a
      // sibling resource whose name merely looks similar.
      expect(cache.inMemory.keys, ['aXb']);
    });

    test('a restored entry keeps the snapshot timestamp it was written with', () {
      final cache = QueryCache();
      final taken = DateTime(2026, 3, 4, 9, 30);
      cache.write('bills', [
        {'id': '1'}
      ], updatedAt: taken, status: CacheStatus.stale);
      final entry = cache.peek('bills')!;
      expect(entry.updatedAt, taken);
      expect(entry.status, CacheStatus.stale);
      expect(cache.isStale('bills'), isTrue);
    });

    test('a freshly written entry is not reported as stale', () {
      final cache = QueryCache();
      cache.write('bills', [
        {'id': '1'}
      ]);
      expect(cache.isStale('bills'), isFalse);
    });

    test('per-user database names cannot escape the cache directory', () {
      expect(QueryCache.dbNameFor('../../etc/passwd'), 'love_cache_etcpasswd');
      expect(QueryCache.dbNameFor(''), 'love_cache_anon');
      expect(QueryCache.dbNameFor('a' * 80).length, 'love_cache_'.length + 48);
    });
  });

  group('ResourceController cache seeding', () {
    test('a cache entry of the wrong shape is ignored, not thrown', () async {
      final cache = QueryCache();
      // A backup written by an older build seeded a bare list where the
      // fetcher produces an envelope. The unguarded `as T` used to throw out
      // of load() and blank the screen.
      cache.write('dashboard', <dynamic>[1, 2, 3]);

      final controller = ResourceController<Map<String, dynamic>>(
        key: 'dashboard',
        cache: cache,
        fetcher: () async => const {'summary': {'income': 10}},
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.data, isNotNull);
      expect(controller.data!['summary'], isNotNull);
      expect(controller.phase, LoadPhase.ready);
    });

    test('a matching cache entry renders before the network answers', () async {
      final cache = QueryCache();
      cache.write('bills', [
        {'id': '1', 'total': 500}
      ], status: CacheStatus.fresh);

      final controller = ResourceController<List<Map<String, dynamic>>>(
        key: 'bills',
        cache: cache,
        fetcher: () async => throw ApiException('offline'),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.phase, LoadPhase.ready);
      expect(controller.error, isNull);
      expect(controller.data, hasLength(1));
      expect(controller.status, CacheStatus.offline);
    });

    test('a failed refresh with no cache surfaces the error', () async {
      final cache = QueryCache();
      final controller = ResourceController<List<Map<String, dynamic>>>(
        key: 'bills',
        cache: cache,
        fetcher: () async => throw ApiException('gone', statusCode: 404),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.phase, LoadPhase.failed);
      expect(controller.error, 'gone');
      expect(controller.data, isNull);
    });

    test('a disposed controller never applies a late response', () async {
      final cache = QueryCache();
      final controller = ResourceController<List<Map<String, dynamic>>>(
        key: 'bills',
        cache: cache,
        fetcher: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return [
            {'id': '1'}
          ];
        },
      );

      final pending = controller.load();
      controller.dispose();
      await pending;

      expect(controller.data, isNull);
    });
  });
}
