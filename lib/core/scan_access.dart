/// Side-aware access to the linen scan vocabulary.
///
/// The mobile app has one scanner screen for two kinds of account. A hotel /
/// shop client moves linen across the client boundary; laundry staff move it
/// through the wash cycle. A role label alone is not enough to decide which
/// side a session belongs to: a client login can also carry a `laundry_id`
/// (the client's provider) and a staff administrator can carry hotel
/// memberships. This helper takes all of the identity signals together and
/// fails closed — an unknown or contradictory side gets no scan actions.
///
/// Platform administrators are the deliberate exception: they override both
/// sides, exactly as they do elsewhere in the app.
library;

import '../core/models/linen.dart';

enum ScanSide {
  /// Hotel / shop client: outbound and exception scans only.
  hotel,

  /// Laundry staff: inbound, processing, delivery and exception scans.
  laundry,

  /// Platform administrator: every documented action.
  both,

  /// Missing or contradictory identity signals. No actions at all.
  unknown,
}

class ScanAccess {
  const ScanAccess(this.side);

  static const ScanAccess none = ScanAccess(ScanSide.unknown);

  final ScanSide side;

  /// Hotel-side outbound scans. There is no separate client-receipt action in
  /// [LinenScanAction]; a delivery receipt is not represented by `receive`,
  /// which is the laundry's inbound step.
  static const Set<String> hotelActions = LinenScanAction.hotelValues;

  /// Laundry-side scans. The two exception actions are deliberately shared
  /// with the hotel side.
  static const Set<String> laundryActions = LinenScanAction.laundryValues;

  // `final` (not `const`) because the exception actions deliberately appear on
  // both sides; a const set literal rejects the duplicate at compile time.
  static final Set<String> allActions = <String>{
    ...LinenScanAction.hotelValues,
    ...LinenScanAction.laundryValues,
  };

  Set<String> get allowedActions => switch (side) {
        ScanSide.hotel => hotelActions,
        ScanSide.laundry => laundryActions,
        ScanSide.both => allActions,
        ScanSide.unknown => const <String>{},
      };

  bool allows(String action) =>
      allowedActions.contains(action.trim().toLowerCase());

  bool canRun(LinenScanAction action) => allows(action.value);
}

/// Derives the scan side from whatever identity signals the API returned.
///
/// [selectedRole] is the login screen's `selected_role` (`hotel` / `laundry`).
/// It resolves sessions that carry an ambiguous generic role, but it cannot
/// override a clear client identity: a hotel account signed in through the
/// laundry radio button is treated as incompatible, not as laundry staff.
ScanAccess scanAccessFor({
  String? roleId,
  Iterable<String> roleIds = const <String>[],
  String? clientType,
  String? hotelId,
  String? shopId,
  String? laundryId,
  String? selectedRole,
  bool platformAdmin = false,
}) {
  final roles = <String>{};
  final primary = (roleId ?? '').trim().toUpperCase();
  if (primary.isNotEmpty) roles.add(primary);
  for (final role in roleIds) {
    final value = role.trim().toUpperCase();
    if (value.isNotEmpty) roles.add(value);
  }
  if (platformAdmin || roles.contains('PLATFORM_ADMIN')) {
    return const ScanAccess(ScanSide.both);
  }

  final type = (clientType ?? '').trim().toUpperCase();
  final selection = (selectedRole ?? '').trim().toLowerCase();
  final hasClientId = (hotelId ?? '').trim().isNotEmpty ||
      (shopId ?? '').trim().isNotEmpty;
  final hasLaundryId = (laundryId ?? '').trim().isNotEmpty;
  final clientRole = roles.any(
      (role) => role.startsWith('HOTEL_') || role.startsWith('SHOP_'));
  final laundryRole = roles.any((role) =>
      role.startsWith('LAUNDRY_') ||
      const <String>{'LAUNDRY', 'ADMIN', 'MANAGER', 'STAFF'}.contains(role));

  // Both ids with no side-bearing type or role is an ambiguous identity.
  if (hasClientId &&
      hasLaundryId &&
      type.isEmpty &&
      !clientRole &&
      !laundryRole) {
    return ScanAccess.none;
  }

  final clientSignal = type == 'HOTEL' ||
      type == 'SHOP' ||
      clientRole ||
      (hasClientId && !laundryRole && type != 'LAUNDRY');
  final laundrySignal = type == 'LAUNDRY' ||
      laundryRole ||
      (hasLaundryId && !hasClientId && type != 'HOTEL' && type != 'SHOP');

  if (selection == 'hotel') {
    // A laundry staff account selecting "hotel" is incompatible, not a client.
    if (laundrySignal && !clientSignal) return ScanAccess.none;
    return const ScanAccess(ScanSide.hotel);
  }
  if (selection == 'laundry') {
    // A hotel / shop client selecting "laundry" must never gain laundry scans.
    if (clientSignal) return ScanAccess.none;
    return const ScanAccess(ScanSide.laundry);
  }

  if (clientSignal && laundrySignal) return ScanAccess.none;
  if (clientSignal) return const ScanAccess(ScanSide.hotel);
  if (laundrySignal) return const ScanAccess(ScanSide.laundry);
  return ScanAccess.none;
}
