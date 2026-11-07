import 'package:flutter/material.dart';

import '../state/app_services.dart';
import 'access.dart';

/// One destination in the app's navigation contract.
///
/// A route carries everything three consumers need and nothing they should have
/// to derive: the drawer (label, group, icon, permission), the bottom bar
/// (which five are primary), and the command palette (searchable keywords).
@immutable
class AppRoute {
  const AppRoute({
    required this.path,
    required this.label,
    required this.builder,
    this.group = 'Operations',
    this.icon,
    this.permission,
    this.readPermission,
    this.roles,
    this.adminOnly = false,
    this.platformOnly = false,
    this.tenantOnly = false,
    this.keywords = const [],
    this.showInDrawer = true,
    this.showInCommand = true,
    this.bottomBar = false,
    this.tabIndex,
    this.guest = false,
  });

  /// Slash-prefixed path, e.g. `/quotations`. `:id` marks a parameter.
  final String path;
  final String label;
  final WidgetBuilder builder;
  final String group;
  final IconData? icon;

  /// Write permission. Hides the create/edit/delete affordances.
  final String? permission;

  /// Read permission. Hides the whole destination.
  final String? readPermission;

  /// Role ids permitted to reach the destination. Null means "any role".
  final Set<String>? roles;

  /// Tenant-admin only (ADMIN / MANAGER) — payroll, HR, expenses, reporting.
  final bool adminOnly;

  /// Platform-admin only — the registry-style surfaces.
  final bool platformOnly;

  /// Platform administrators are excluded (tenant operations).
  final bool tenantOnly;

  final List<String> keywords;
  final bool showInDrawer;
  final bool showInCommand;

  /// Included in the persistent bottom bar.
  final bool bottomBar;

  /// Ordering hint for the bottom bar; 0 is the first tab.
  final int? tabIndex;

  /// Reachable without a session.
  final bool guest;

  /// The access rule this destination enforces. Read and write are independent
  /// grants, so a route that declares both is gated on the *read* permission.
  AccessSpec get accessSpec => AccessSpec(
        permissions: [
          if (readPermission != null) readPermission!,
          if (readPermission == null && permission != null) permission!,
        ],
        roles: roles,
        adminOnly: adminOnly,
        platformOnly: platformOnly,
        tenantOnly: tenantOnly,
      );

  /// Whether the destination should be offered at all.
  ///
  /// Delegates to the shared access policy so the drawer, the bottom bar, the
  /// command palette and the router gate agree. A route that declares only a
  /// write permission is still gated on it — otherwise it would be reachable by
  /// nobody but its author.
  bool isVisibleTo(AppServices s) => canAccess(
        roleId: s.auth.user?.roleId,
        permissionList: s.auth.user?.permissionList ?? const [],
        spec: accessSpec,
        isPlatformOnly: s.auth.isPlatformOnly,
        platformAdmin: s.auth.isPlatformAdmin,
      );

  /// Whether the create/edit/delete affordances inside the destination render.
  bool isWritableBy(AppServices s) =>
      permission == null || s.auth.hasPermission(permission!);
}

class AppRoutes {
  AppRoutes._();

  // Paths mirror `quotations-ui/src/routes/index.tsx` so a deep link copied from
  // the web app resolves to the same screen here.
  static const String home = '/';
  static const String login = '/login';

  // Home
  static const String today = '/today';
  static const String todaySheet = '/today-sheet';

  // Bills
  static const String bills = '/bills';
  static const String billNew = '/bills/new';
  static const String billDetail = '/bills/:id';
  static const String billPrint = '/bills/:id/print';
  static const String statements = '/statements';

  // Gate passes
  static const String gatepasses = '/gate-passes';
  static const String gatepassNew = '/gate-passes/new';
  static const String gatepassDetail = '/gate-passes/:id';
  static const String gatepassSlip = '/gate-passes/:id/slip';

  // Deliveries & dispatch
  static const String deliveries = '/deliveries';
  static const String deliveryNew = '/deliveries/new';
  static const String deliveryDetail = '/deliveries/:id';
  static const String deliverySlips = '/deliveries/slips';

  // Returns
  static const String returns = '/returns';
  static const String returnNew = '/returns/new';
  static const String returnDetail = '/returns/:id';

  // Workers

  // Linen
  static const String hotelLinenFlow = '/hotel-linen-flow';
  static const String hotelLinenFlowDetail = '/hotel-linen-flow/:hotel';
  static const String linen = '/linen';
  static const String linenInventory = '/linen/inventory';
  static const String linenDetail = '/linen/:id';
  static const String linenScanner = '/linen/scanner';
  static const String garmentDetail = '/linen/garment/:code';

  // Insights, chat, system
  static const String settings = '/settings';
  static const String profile = '/profile';

  // Derived screens the web app links to but has no route for
  static const String entryFlow = '/entry-flow';

  /// Registered in [register] and consumed by the navigator.
  static final Map<String, AppRoute> table = {};

  static void register(Map<String, AppRoute> routes) {
    table
      ..clear()
      ..addAll(routes);
  }

  static AppRoute? lookup(String path) {
    if (table.containsKey(path)) return table[path];
    for (final route in table.values) {
      if (_matches(route.path, path)) return route;
    }
    return null;
  }

  static bool _matches(String pattern, String path) {
    final p = pattern.split('/');
    final a = path.split('/');
    if (p.length != a.length) return false;
    for (var i = 0; i < p.length; i++) {
      if (p[i].startsWith(':')) continue;
      if (p[i] != a[i]) return false;
    }
    return true;
  }

  /// Fills `:id`-style parameters from a concrete path.
  static Map<String, String> paramsFor(String pattern, String path) {
    final p = pattern.split('/');
    final a = path.split('/');
    final out = <String, String>{};
    for (var i = 0; i < p.length && i < a.length; i++) {
      if (p[i].startsWith(':')) out[p[i].substring(1)] = a[i];
    }
    return out;
  }

  /// Route names used for named navigation from deep widgets (e.g. the command
  /// palette), derived from the path so there is a single source of truth.
  static String nameFor(String path) => path;
}
