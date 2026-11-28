import 'package:flutter_test/flutter_test.dart';
import 'package:love_mobi/core/models/linen.dart';
import 'package:love_mobi/core/scan_access.dart';
import 'package:love_mobi/state/auth_state.dart';

void main() {
  group('scan side detection', () {
    test('laundry staff get only laundry-side actions', () {
      final access = scanAccessFor(
        roleId: 'STAFF',
        laundryId: 'laundry-1',
        selectedRole: 'laundry',
      );
      expect(access.side, ScanSide.laundry);
      expect(access.allows(LinenScanAction.receive.value), isTrue);
      expect(access.allows(LinenScanAction.startWash.value), isTrue);
      expect(access.allows(LinenScanAction.linenOut.value), isFalse);
    });

    test('hotel clients get linen_out but no laundry process actions', () {
      final access = scanAccessFor(
        roleId: 'HOTEL_MANAGER',
        clientType: 'HOTEL',
        hotelId: 'hotel-1',
        laundryId: 'provider-laundry',
        selectedRole: 'hotel',
      );
      expect(access.side, ScanSide.hotel);
      expect(access.allows(LinenScanAction.linenOut.value), isTrue);
      expect(access.allows(LinenScanAction.collect.value), isTrue);
      expect(access.allows(LinenScanAction.receive.value), isFalse);
      expect(access.allows(LinenScanAction.startWash.value), isFalse);
    });

    test('a client cannot choose the laundry side', () {
      final access = scanAccessFor(
        roleId: 'CLIENT',
        clientType: 'SHOP',
        shopId: 'shop-1',
        laundryId: 'provider-laundry',
        selectedRole: 'laundry',
      );
      expect(access.side, ScanSide.unknown);
      expect(access.allowedActions, isEmpty);
    });

    test('platform admins override both sides', () {
      final access = scanAccessFor(
        roleId: 'STAFF',
        laundryId: 'laundry-1',
        platformAdmin: true,
      );
      expect(access.side, ScanSide.both);
      expect(access.allows(LinenScanAction.linenOut.value), isTrue);
      expect(access.allows(LinenScanAction.receive.value), isTrue);
    });

    test('unknown identities fail closed', () {
      expect(scanAccessFor().allowedActions, isEmpty);
    });
  });

  group('persisted session', () {
    test('client scope and role lists survive a reload', () {
      final user = AppUser.fromJson({
        'id': 'u-1',
        'user_name': 'hotel-user',
        'role_id': 'CLIENT',
        'role_ids': ['HOTEL_MANAGER'],
        'client_type': 'HOTEL',
        'hotel_id': 'hotel-1',
        'laundry_id': 'provider-laundry',
        'selected_role': 'hotel',
      });
      expect(user.scanAccess.side, ScanSide.hotel);
      expect(user.allowedLinenScanActions, contains(LinenScanAction.linenOut.value));
      expect(user.canRunLinenScanAction(LinenScanAction.receive.value), isFalse);
    });
  });
}
