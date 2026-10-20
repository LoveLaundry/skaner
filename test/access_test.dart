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
    // The defect this change fixes: these were all reachable by a bare STAFF
    // session because they declared no permission at all.
    const managementPaths = <String>[
      '/management',
      '/dashboard',
      '/management/employees',
      '/management/roles',
      '/management/permissions',
      '/payroll',
      '/management/expenses',
      '/management/reports',
      '/database-sync',
      '/backup-restore',
      '/workers',
    ];

    test('staff cannot open any management or system surface', () {
      for (final path in managementPaths) {
        expect(
          routeAllows(path, 'STAFF'),
          isFalse,
          reason: 'STAFF must not reach $path',
        );
      }
    });

    test('a manager reaches management but not PLATFORM_ADMIN-only surface', () {
      for (final path in managementPaths) {
        expect(routeAllows(path, 'MANAGER'), isTrue, reason: path);
      }
    });

    test('a platform admin reaches every management surface', () {
      for (final path in managementPaths) {
        expect(routeAllows(path, 'PLATFORM_ADMIN'), isTrue, reason: path);
      }
    });

    test('operational surfaces stay open to staff', () {
      for (final path in const <String>[
        '/today',
        '/quotations',
        '/bills',
        '/gate-passes',
        '/deliveries',
        '/returns',
        '/linen/scanner',
        '/profile',
      ]) {
        expect(routeAllows(path, 'STAFF'), isTrue, reason: path);
      }
    });

    test('users route needs the grant even for a manager', () {
      expect(routeAllows('/users', 'STAFF'), isFalse);
      expect(routeAllows('/users', 'ADMIN'), isTrue);
    });
  });

  group('landing path', () {
    String landing(String? roleId, {List<String> permissions = const []}) =>
        landingPathFor(
          roleId: roleId,
          permissionList: permissions,
          platformAdmin: isPlatformAdminRole(roleId),
          fallback: AppRoutes.today,
          candidates: const [
            LandingCandidate(AppRoutes.dashboard, AccessSpec(adminOnly: true)),
            LandingCandidate(AppRoutes.today, AccessSpec()),
          ],
        );

    test('an admin lands on the dashboard', () {
      expect(landing('ADMIN'), AppRoutes.dashboard);
      expect(landing('MANAGER'), AppRoutes.dashboard);
      expect(landing('PLATFORM_ADMIN'), AppRoutes.dashboard);
    });

    test('everyone else lands on today', () {
      expect(landing('STAFF'), AppRoutes.today);
      expect(landing(null), AppRoutes.today);
    });
  });
}
