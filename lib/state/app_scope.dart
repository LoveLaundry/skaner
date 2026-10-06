import 'package:flutter/material.dart';

import 'app_services.dart';

/// Makes [AppServices] reachable from any widget without a DI package, and
/// rebuilds listeners only for the slices a screen actually reads.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.services,
    required this.sync,
    required super.child,
  });

  final AppServices services;
  final SyncController sync;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget.');
    return scope!.services;
  }

  /// Reads the services without subscribing — for event handlers, where a
  /// rebuild would be wasted.
  static AppServices read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget.');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.services != services || oldWidget.sync != sync;
}
