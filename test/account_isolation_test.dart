import 'package:flutter_test/flutter_test.dart';
import 'package:love_mobi/core/api/api_client.dart';
import 'package:love_mobi/core/api/connectivity_service.dart';
import 'package:love_mobi/core/api/outbox_store.dart';
import 'package:love_mobi/core/api/sync_engine.dart';
import 'package:love_mobi/state/auth_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('queued-write account isolation', () {
    test('session changes pause replay and clear the outbox', () async {
      final connectivity = ConnectivityService();
      final outbox = _FakeOutboxStore();
      final api = ApiClient(connectivity: connectivity, outbox: outbox);
      final sync = SyncEngine(
        api: api,
        connectivity: connectivity,
        outbox: outbox,
        counts: () => const OutboxStatusCounts(pending: 0, rows: []),
      );
      addTearDown(sync.dispose);
      addTearDown(connectivity.dispose);

      await sync.pauseAndClearOutbox();

      expect(outbox.clearCount, 1);
      expect(await sync.drain(force: true), isFalse);
      expect(outbox.pendingCalls, 0);

      sync.resume();
      expect(await sync.drain(force: true), isTrue);
      expect(outbox.pendingCalls, 1);
    });

    test('login and logout clean queued writes before changing identity',
        () async {
      SharedPreferences.setMockInitialValues({});
      final connectivity = ConnectivityService();
      final outbox = _FakeOutboxStore();
      final api = ApiClient(connectivity: connectivity, outbox: outbox);
      final sync = SyncEngine(
        api: api,
        connectivity: connectivity,
        outbox: outbox,
        counts: () => const OutboxStatusCounts(pending: 0, rows: []),
      );
      final auth = AuthState(api: api)
        ..onBeforeSessionChange = sync.pauseAndClearOutbox;
      addTearDown(auth.dispose);
      addTearDown(sync.dispose);
      addTearDown(connectivity.dispose);

      await auth.login('token-a', _user('account-a'));
      expect(outbox.clearCount, 1);
      sync.resume();

      await auth.login('token-b', _user('account-b'));
      expect(outbox.clearCount, 2);
      expect(auth.user?.id, 'account-b');
      sync.resume();

      final pendingBeforeLogout = outbox.pendingCalls;
      await auth.logout();
      expect(outbox.clearCount, 3);
      expect(auth.isAuthenticated, isFalse);
      expect(await sync.drain(force: true), isFalse);
      expect(outbox.pendingCalls, pendingBeforeLogout);
    });
  });
}

AppUser _user(String id) => AppUser(
      id: id,
      userName: id,
      authId: id,
      roleId: 'USER',
      status: 'ACTIVE',
    );

class _FakeOutboxStore extends OutboxStore {
  int clearCount = 0;
  int pendingCalls = 0;

  @override
  Future<void> clearAll() async {
    clearCount++;
  }

  @override
  Future<List<OutboxRow>> pending() async {
    pendingCalls++;
    return const [];
  }
}
