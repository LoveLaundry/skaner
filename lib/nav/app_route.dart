import 'package:flutter/material.dart';

import '../state/app_services.dart';

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

  final List<String> keywords;
  final bool showInDrawer;
  final bool showInCommand;

  /// Included in the persistent bottom bar.
  final bool bottomBar;

  /// Ordering hint for the bottom bar; 0 is the first tab.
  final int? tabIndex;

  /// Reachable without a session.
  final bool guest;

  /// Whether the destination should be offered at all.
  ///
  /// Reading and writing are independent grants, so a route that declares both
  /// is gated on the *read* permission. An `||` here used to expose write-gated
  /// destinations to a read-only operator. A route that only declares a write
  /// permission is still gated on it — otherwise it would be reachable by
  /// nobody but its author.
  bool isVisibleTo(AppServices s) {
    final gate = readPermission ?? permission;
    return gate == null || s.auth.hasPermission(gate);
  }

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
  static const String dashboard = '/dashboard';
  static const String notifications = '/notifications';

  // Quotations
  static const String quotations = '/quotations';
  static const String quotationNew = '/quotations/new';
  static const String quotationEdit = '/quotations/:id/edit';
  static const String quotationDetail = '/quotations/:id';
  static const String quotationPrint = '/quotations/:id/print';

  // Bills
  static const String bills = '/bills';
  static const String billNew = '/bills/new';
  static const String billDetail = '/bills/:id';
  static const String billPrint = '/bills/:id/print';
  static const String statements = '/statements';
  static const String invoiceNew = '/invoices/new';

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
  static const String dispatch = '/dispatch';
  static const String dispatchDetail = '/dispatch/:id';

  // Returns
  static const String returns = '/returns';
  static const String returnNew = '/returns/new';
  static const String returnDetail = '/returns/:id';

  // Shop bills
  static const String shopBills = '/shop-bills';
  static const String shopBillNew = '/shop-bills/new';
  static const String shopBillDetail = '/shop-bills/:id';
  static const String shopBillPrint = '/shop-bills/:id/print';
  static const String shopBillDashboard = '/shop-bills/dashboard';
  static const String shopBillTemplates = '/shop-bill-templates';
  static const String legacyInvoice = '/legacy-invoice';
  static const String clientStatement = '/client-statement';

  // Workers
  static const String workers = '/workers';
  static const String workerNew = '/workers/new';
  static const String workerDetail = '/workers/:id';
  static const String workerPayroll = '/workers/payroll';

  // Linen
  static const String hotelLinenFlow = '/hotel-linen-flow';
  static const String hotelLinenFlowDetail = '/hotel-linen-flow/:hotel';
  static const String linen = '/linen';
  static const String linenInventory = '/linen/inventory';
  static const String linenDetail = '/linen/:id';
  static const String linenScanner = '/linen/scanner';
  static const String garmentDetail = '/linen/garment/:code';

  // Management
  static const String management = '/management';
  static const String managementReports = '/management/reports';
  static const String managementEmployees = '/management/employees';
  static const String managementEmployeeNew = '/management/employees/new';
  static const String managementEmployeeDetail = '/management/employees/:id';
  static const String managementDepartments = '/management/departments';
  static const String managementRoles = '/management/roles';
  static const String managementPermissions = '/management/permissions';
  static const String managementAttendance = '/management/attendance';
  static const String managementLeave = '/management/leave';
  static const String managementPerformance = '/management/performance';
  static const String managementTraining = '/management/training';
  static const String managementAnnouncements = '/management/announcements';
  static const String managementExpenses = '/management/expenses';
  static const String payroll = '/payroll';
  static const String reports = '/reports';

  // Insights, chat, system
  static const String aiInsights = '/ai-insights';
  static const String liveChat = '/live-chat';
  static const String users = '/users';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String databaseSync = '/database-sync';
  static const String backupRestore = '/backup-restore';

  // Derived screens the web app links to but has no route for
  static const String entryFlow = '/entry-flow';
  static const String exportCenter = '/export';
  static const String priceList = '/price-list';

  // Guest (no session required)
  static const String guestShop = '/guest/shop';
  static const String guestTrack = '/guest/track';
  static const String guestQuotation = '/guest/quotation';
  static const String guestPickup = '/guest/pickup';

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
