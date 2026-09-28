import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../ui/kit/feedback.dart';

/// Canonical write-result handling for every screen in the app.
///
/// A write made while offline is **returned** as a [QueuedResponse], not thrown.
/// An `on QueuedResponse` clause in a catch block therefore never fires, the
/// success branch runs instead, and the operator is told "Saved" for a change
/// the server never received — the exact failure the outbox exists to prevent.
/// Inspecting the returned value is the only correct pattern, so it lives here
/// once rather than being re-derived (and re-broken) at every call site.
///
/// [onSuccess] runs only for a write the server actually accepted; [onQueued]
/// only for one that is waiting on the outbox.
Future<bool> runWrite(
  BuildContext context, {
  required FutureOr<Object?> Function() action,
  required String success,
  String queued = 'Offline — change queued and will sync',
  void Function(Object? result)? onSuccess,
  void Function()? onQueued,
}) async {
  try {
    final result = await action();
    if (!context.mounted) return true;
    if (result is QueuedResponse) {
      AppToast.info(context, queued);
      onQueued?.call();
      return true;
    }
    AppToast.success(context, success);
    onSuccess?.call(result);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) AppToast.error(context, e.message);
    return false;
  } catch (e) {
    if (context.mounted) AppToast.error(context, '$e');
    return false;
  }
}
