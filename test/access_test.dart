import 'package:flutter_test/flutter_test.dart';
import 'package:love_mobi/nav/access.dart';
import 'package:love_mobi/nav/app_route.dart';
import 'package:love_mobi/nav/route_registry.dart';

/// Evaluates a registered route's declared access rule for a role, exactly as
/// `AppRoute.isVisibleTo` does, without constructing the whole service graph.
bool routeAllows(String path, String? roleId, {List<String> permissions = const []}) {
  final route = AppRoutes.lookup(path);
  expect(route, isNotNull, reason: path);
  return canAccess(
    roleId: roleId,
    permissionList: permissions,
    spec: route!.accessSpec,
    platformAdmin: isPlatformAdminRole(roleId),
  );
}

void main() {
  setUpAll(AppRouteRegistry.install);

  group('role primitives', () {
    test('ADMIN and PLATFORM_ADMIN are admin-shaped', () {
      expect(isAdminRole('ADMIN'), isTrue);
      expect(isAdminRole('admin'), isTrue);
      expect(isAdminRole('PLATFORM_ADMIN'), isTrue);
      expect(isAdminRole('MANAGER'), isFalse);
      expect(isAdminRole('STAFF'), isFalse);
      expect(isAdminRole(null), isFalse);
    });

    test('only PLATFORM_ADMIN is a platform admin', () {
      expect(isPlatformAdminRole('PLATFORM_ADMIN'), isTrue);
      expect(isPlatformAdminRole('ADMIN'), isFalse);
    });

    test('tenant admins are ADMIN and MANAGER', () {
      expect(isTenantAdminRole('ADMIN'), isTrue);
      expect(isTenantAdminRole('MANAGER'), isTrue);
      expect(isTenantAdminRole('PLATFORM_ADMIN'), isFalse);
      expect(isTenantAdminRole('STAFF'), isFalse);
    });
  });

  group('canAccess', () {
    test('an adminOnly route is closed to staff', () {
      const spec = AccessSpec(adminOnly: true);
      expect(canAccess(roleId: 'STAFF', permissionList: const [], spec: spec),
          isFalse);
      expect(canAccess(roleId: 'MANAGER', permissionList: const [], spec: spec),
          isTrue);
      expect(canAccess(roleId: 'ADMIN', permissionList: const [], spec: spec),
          isTrue);
    });

    test('PLATFORM_ADMIN satisfies an adminOnly route', () {
      expect(
        canAccess(
          roleId: 'PLATFORM_ADMIN',
          permissionList: const [],
          spec: const AccessSpec(adminOnly: true),
        ),
        isTrue,
      );
    });

    test('platformOnly confines the route to platform admins', () {
      const spec = AccessSpec(platformOnly: true);
      expect(canAccess(roleId: 'ADMIN', permissionList: const [], spec: spec),
          isFalse);
      expect(
        canAccess(roleId: 'PLATFORM_ADMIN', permissionList: const [], spec: spec),
        isTrue,
      );
    });

    test('tenantOnly excludes a platform admin', () {
      const spec = AccessSpec(tenantOnly: true);
      expect(canAccess(roleId: 'ADMIN', permissionList: const [], spec: spec),
          isTrue);
      expect(
        canAccess(
            roleId: 'PLATFORM_ADMIN', permissionList: const [], spec: spec),
        isFalse,
      );
    });

    test('a permission must be held unless the role is admin', () {
      const spec = AccessSpec(permissions: ['users.manage']);
      expect(canAccess(roleId: 'STAFF', permissionList: const [], spec: spec),
          isFalse);
      expect(
        canAccess(
            roleId: 'STAFF', permissionList: const ['users.manage'], spec: spec),
        isTrue,
      );
      expect(canAccess(roleId: 'ADMIN', permissionList: const [], spec: spec),
          isTrue);
    });

    test('a wildcard grant passes any permission', () {
      const spec = AccessSpec(permissions: ['reports.view']);
      expect(
        canAccess(roleId: 'STAFF', permissionList: const ['*'], spec: spec),
        isTrue,
      );
    });
  });

  group('route gating is not open to every role', () {
    test('staff cannot open the admin-only settings surface', () {
      expect(routeAllows('/settings', 'STAFF'), isFalse);
      expect(routeAllows('/settings', 'MANAGER'), isTrue);
      expect(routeAllows('/settings', 'ADMIN'), isTrue);
      expect(routeAllows('/settings', 'PLATFORM_ADMIN'), isTrue);
    });

    test('operational surfaces stay open to staff', () {
      for (final path in const <String>[
        '/today',
        '/today-sheet',
        '/bills',
        '/gate-passes',
        '/deliveries',
        '/returns',
        '/linen/scanner',
        '/statements',
        '/entry-flow',
        '/profile',
      ]) {
        expect(routeAllows(path, 'STAFF'), isTrue, reason: path);
      }
    });
  });
}
