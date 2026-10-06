import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/api_config.dart';
import '../../core/models/json.dart' as json;
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../data/write_outcome.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';

/// The management backend is mounted under `/api` — every path in this feature
/// carries that prefix, exactly as `management-api.ts` does.
const String mgmt = ServiceNames.management;

/// Canonical write-result handling shared by every management screen.
///
/// See `runWrite` in `data/write_outcome.dart` for why the queued case is
/// detected from the returned value rather than a catch clause.
Future<bool> runMgmtWrite(
  BuildContext context,
  FutureOr<Object?> Function() action, {
  required String success,
  String queuedMessage = 'Offline — change queued and will sync',
}) =>
    runWrite(
      context,
      action: action,
      success: success,
      queued: queuedMessage,
    );

/// CSV exports go to the clipboard: a phone has no download folder the app can
/// write to, and the server hands back text rather than a file handle.
Future<void> copyExport(BuildContext context, String text, String label) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  AppToast.success(context, '$label copied to clipboard');
}

/// Employee rows the backend spells in more than one way.
String employeeName(Map<String, dynamic> row) =>
    str(row, ['name', 'employee_name', 'full_name'], '—');

String employeeDepartment(Map<String, dynamic> row) =>
    str(row, ['department'], '—');

/// The web app reads `e.is_active !== false`, so a record without the key is
/// active rather than inactive.
bool employeeIsActive(Map<String, dynamic> row) =>
    json.asBool(pick(row, ['is_active']), true);

/// Likewise `attendance_required` defaults to on.
bool employeeAttendanceRequired(Map<String, dynamic> row) =>
    json.asBool(pick(row, ['attendance_required']), true);

/// Attendance statuses, from `STATUSES` in attendance-page.tsx. The older
/// summary endpoint still emits `ON_LEAVE`, which the web app treats as
/// `PAID_LEAVE`, so it is accepted everywhere.
const List<String> kAttendanceStatuses = [
  'PRESENT',
  'HALF_DAY',
  'PAID_LEAVE',
  'UNPAID_LEAVE',
  'ABSENT',
];

const List<String> kLeaveStatuses = [
  'PAID_LEAVE',
  'ON_LEAVE',
  'UNPAID_LEAVE',
];

String attendanceStatusLabel(String raw) => switch (raw.toUpperCase()) {
      'PRESENT' => 'Present',
      'HALF_DAY' => 'Half day',
      'PAID_LEAVE' || 'ON_LEAVE' => 'Paid leave',
      'UNPAID_LEAVE' => 'Unpaid leave',
      'ABSENT' => 'Absent',
      _ => Fmt.humanise(raw, fallback: raw),
    };

/// Colour carries status meaning, per the visual contract — these mirror the
/// `STATUS_STYLE` table in attendance-page.tsx.
AppTone attendanceStatusTone(String raw) => switch (raw.toUpperCase()) {
      'PRESENT' => AppTone.success,
      'HALF_DAY' => AppTone.warning,
      'PAID_LEAVE' || 'ON_LEAVE' => AppTone.info,
      'UNPAID_LEAVE' => AppTone.warning,
      'ABSENT' => AppTone.danger,
      _ => AppTone.neutral,
    };

/// Salary-slip statuses, from `STATUS_COLORS` in salary-history-page.tsx.
AppTone slipStatusTone(String raw) => switch (raw.toUpperCase()) {
      'DRAFT' => AppTone.warning,
      'FINALIZED' => AppTone.success,
      'PAID' => AppTone.info,
      'CANCELLED' => AppTone.danger,
      _ => AppTone.neutral,
    };

/// Advance statuses, from the badge colours in advances-page.tsx.
AppTone advanceStatusTone(String raw) => switch (raw.toUpperCase()) {
      'OUTSTANDING' => AppTone.warning,
      'FULLY_DEDUCTED' => AppTone.success,
      _ => AppTone.danger,
    };
