import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Tracks overall reachability plus the set of backend services known to be
/// down.
///
/// The web app keeps a per-service "down" set so one unhealthy service routes
/// its writes to the outbox while the rest keep talking to the network.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final Set<String> _downServices = <String>{};
  final StreamController<bool> _onlineController =
      StreamController<bool>.broadcast();
  final StreamController<Set<String>> _servicesController =
      StreamController<Set<String>>.broadcast();

  bool _online = true;
  bool _initialised = false;

  bool get isOnline => _online;
  Set<String> get downServices => Set.unmodifiable(_downServices);
  Stream<bool> get onOnlineChange => _onlineController.stream;
  Stream<Set<String>> get onServicesChange => _servicesController.stream;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      final results = await _connectivity.checkConnectivity();
      _apply(results);
    } catch (_) {
      _online = true;
    }
    _connectivity.onConnectivityChanged.listen(_apply, onError: (_) {});
  }

  void _apply(List<ConnectivityResult> results) {
    final nowOnline = results.any((r) => r != ConnectivityResult.none);
    // A path being restored clears the "known down" marks: give every service
    // another chance rather than pinning them offline for the session.
    if (nowOnline && !_online) {
      _downServices.clear();
      _servicesController.add(Set.unmodifiable(_downServices));
    }
    if (nowOnline != _online) {
      _online = nowOnline;
      _onlineController.add(_online);
    }
  }

  bool isServiceDown(String service) => _downServices.contains(service);

  void markServiceDown(String service) {
    if (_downServices.add(service)) {
      _servicesController.add(Set.unmodifiable(_downServices));
    }
  }

  void markServiceUp(String service) {
    if (_downServices.remove(service)) {
      _servicesController.add(Set.unmodifiable(_downServices));
    }
  }

  /// A write goes straight to the outbox when the device has no network at all,
  /// or when this particular service is already known to be failing.
  bool shouldQueue(String service) => !_online || isServiceDown(service);

  /// Force a value, for the "simulate offline" toggle in Settings.
  void debugSetOnline(bool value) {
    if (value == _online) return;
    _online = value;
    _onlineController.add(_online);
  }

  Future<void> dispose() async {
    await _onlineController.close();
    await _servicesController.close();
  }
}
