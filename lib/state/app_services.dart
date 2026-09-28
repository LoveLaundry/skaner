import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/api/connectivity_service.dart';
import '../core/api/outbox_store.dart';
import '../core/api/query_cache.dart';
import '../core/api/sync_engine.dart';
import '../data/resource_controller.dart';
import '../features/quotations/bill_model.dart';
import '../features/quotations/quotation_model.dart';
import '../config/api_config.dart';
import 'auth_state.dart';
import 'hotel_scope.dart';
import 'theme_state.dart';

/// Owns every long-lived service and controller for the session.
///
/// Construction order matters: the outbox must exist before the API client
/// (which queues into it), and the sync engine must exist before the auth
/// controller (which pushes 401s back through the client).
class AppServices {
  AppServices._({
    required this.connectivity,
    required this.outbox,
    required this.api,
    required this.cache,
    required this.sync,
    required this.auth,
    required this.theme,
    required this.hotels,
  });

  final ConnectivityService connectivity;
  final OutboxStore outbox;
  final ApiClient api;
  final QueryCache cache;
  final SyncEngine sync;
  final AuthState auth;
  final ThemeState theme;
  final HotelScope hotels;

  static Future<AppServices> boot() async {
    final connectivity = ConnectivityService();
    final outbox = await OutboxStore().open();
    final api = ApiClient(connectivity: connectivity, outbox: outbox);
    final cache = QueryCache();
    final sync = SyncEngine(
      api: api,
      connectivity: connectivity,
      outbox: outbox,
      counts: () => outbox.statusCounts,
    );

    final services = AppServices._(
      connectivity: connectivity,
      outbox: outbox,
      api: api,
      cache: cache,
      sync: sync,
      auth: AuthState(api: api),
      theme: ThemeState(),
      hotels: HotelScope(),
    );

    // A new write must wake the engine immediately. The engine holds this same
    // client, so the hook is the only direction that does not form a cycle.
    api.onEnqueued = sync.notifyEnqueued;

    // Without this the connectivity stream never emits, so the offline banner
    // is dead UI and writes only get queued reactively after they have failed.
    await connectivity.init();

    // Reads are attempted against the network first; the cache is what makes a
    // back-room with no signal usable. The engine owns cache invalidation.
    QueryCacheInvalidator.instance.register(
      byResource: cache.invalidateResource,
      all: cache.invalidateAll,
    );
    return services;
  }

  /// Second phase: needs no token, but must settle before the first frame so
  /// the app never flashes the wrong theme or lands on login while a session
  /// exists.
  Future<void> restore() async {
    await Future.wait([
      theme.restore(),
      auth.restore(),
      outbox.refreshCounts(),
    ]);
    await _bindSession();
    sync.start();
  }

  /// Called on sign-in and sign-out so the durable stores re-scope to the user.
  Future<void> onSessionChanged() async {
    await _bindSession();
  }

  Future<void> _bindSession() async {
    api.setUserId(auth.user?.id);
    await hotels.bindUser(auth.user?.id, auth.isAdmin);
    await cache.open(auth.user?.id ?? 'guest');
  }

  /// Derives the hotel list from `client_name` across the four operations
  /// collections, exactly as the web `HotelContext` does. Laundry records have
  /// no dedicated hotel field, so the distinct client names *are* the hotels.
  /// Best-effort: a failure here leaves the list empty and the shell simply
  /// hides the picker rather than blocking sign-in.
  Future<void> loadHotels() async {
    if (!auth.isAuthenticated) {
      hotels.setHotels(const []);
      return;
    }
    final names = <String>{};
    Future<void> harvest(String service, String path) async {
      try {
        final payload = await api.get(service, path, query: {'limit': 500});
        _collectClientNames(payload, names);
      } catch (_) {
        // One unreachable service must not empty the picker.
      }
    }

    await Future.wait([
      harvest(operationsService, GatePassApi.list),
      harvest(operationsService, DeliveryApi.list),
      harvest(operationsService, BillApi.list),
      harvest(ServiceNames.quotation, QuotationApi.list),
    ]);
    hotels.setHotels(names);
  }

  void dispose() {
    sync.dispose();
    cache.dispose();
    connectivity.dispose();
    outbox.dispose();
    auth.dispose();
    theme.dispose();
    hotels.dispose();
  }
}

/// Bridges the sync engine into the widget tree. The engine is a
/// [ChangeNotifier] already; this subclass exists so the shell can listen to a
/// single object and read a snapshot without touching the engine directly.
class SyncController extends ChangeNotifier {
  SyncController(this._sync, this._connectivity) {
    _sync.addListener(_onEngineChanged);
    _connectivity.onOnlineChange.listen((_) => _onEngineChanged());
    _connectivity.onServicesChange.listen((_) => _onEngineChanged());
  }

  final SyncEngine _sync;
  final ConnectivityService _connectivity;

  SyncSnapshot get snapshot => _sync.snapshot;
  bool get online => _connectivity.isOnline;
  Set<String> get downServices => _sync.snapshot.downServices;

  void _onEngineChanged() => notifyListeners();

  Future<void> retryFailed() => _sync.retryFailed();

  @override
  void dispose() {
    _sync.removeListener(_onEngineChanged);
    super.dispose();
  }
}

/// Pulls `client_name` out of a list payload without knowing its shape. The
/// operations services wrap rows differently (`items`, `data`, or a bare array),
/// so the collector walks the first list it finds rather than hard-coding one.
void _collectClientNames(dynamic payload, Set<String> into) {
  for (final row in asRows(payload)) {
    final name = row['client_name'] ?? row['clientName'];
    if (name is String && name.trim().isNotEmpty) into.add(name.trim());
  }
}
