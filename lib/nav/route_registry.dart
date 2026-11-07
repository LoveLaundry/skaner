import 'package:flutter/material.dart';

import '../features/auth/login_page.dart';
import '../features/linen/garment_detail_page.dart';
import '../features/linen/linen_flow_hotel_page.dart';
import '../features/linen/linen_flow_page.dart';
import '../features/linen/linen_items_page.dart';
import '../features/linen/linen_tracking_detail_page.dart';
import '../features/linen/linen_tracking_page.dart';
import '../features/linen/scanner_page.dart';
import '../features/misc/error_page.dart';
import '../features/misc/profile_page.dart';
import '../features/misc/settings_page.dart';
import '../features/misc/today_page.dart';
import '../features/misc/today_sheet_page.dart';
import '../features/quotations/bill_detail_page.dart';
import '../features/quotations/bill_form_page.dart';
import '../features/quotations/bill_print_page.dart';
import '../features/quotations/bills_page.dart';
import '../features/quotations/billing_history_page.dart';
import '../features/quotations/deliveries_page.dart';
import '../features/quotations/delivery_detail_page.dart';
import '../features/quotations/delivery_form_page.dart';
import '../features/quotations/delivery_slips_page.dart';
import '../features/quotations/entry_flow_page.dart';
import '../features/quotations/gatepass_detail_page.dart';
import '../features/quotations/gatepass_form_page.dart';
import '../features/quotations/gatepass_slip_page.dart';
import '../features/quotations/gatepasses_page.dart';
import '../features/quotations/return_detail_page.dart';
import '../features/quotations/return_form_page.dart';
import '../features/quotations/returns_page.dart';
import 'app_route.dart';

/// The single place that knows what exists, what it is called, which drawer
/// group it lives in, and who may see it. Only the daily operations flow
/// survives: Today → receive → deliver → return → bill → close the day, plus
/// linen scanning and the account screens.
class AppRouteRegistry {
  AppRouteRegistry._();

  static void install() {
    AppRoutes.register({
      // ── Login ──────────────────────────────────────────────────────────
      AppRoutes.login: AppRoute(
        path: AppRoutes.login,
        label: 'Sign in',
        builder: (_) => const LoginPage(),
        group: 'Account',
        showInDrawer: false,
        showInCommand: false,
        guest: true,
      ),

      // ── Bottom bar: the five stops of the day ──────────────────────────
      AppRoutes.today: AppRoute(
        path: AppRoutes.today,
        label: 'Today',
        builder: (_) => const TodayPage(),
        group: 'Home',
        icon: Icons.today_outlined,
        bottomBar: true,
        tabIndex: 0,
        keywords: const ['home', 'start', 'overview'],
      ),
      AppRoutes.todaySheet: AppRoute(
        path: AppRoutes.todaySheet,
        label: 'Today Sheet',
        builder: (_) => const TodaySheetPage(),
        group: 'Operations',
        icon: Icons.grid_on_outlined,
        bottomBar: true,
        tabIndex: 1,
        keywords: const ['today', 'sheet', 'daily', 'entry', 'expenses'],
      ),
      AppRoutes.bills: AppRoute(
        path: AppRoutes.bills,
        label: 'Bills',
        builder: (_) => const BillsPage(),
        group: 'Operations',
        icon: Icons.receipt_long_outlined,
        bottomBar: true,
        tabIndex: 2,
        keywords: const ['invoice', 'payment', 'due'],
      ),
      AppRoutes.linenScanner: AppRoute(
        path: AppRoutes.linenScanner,
        label: 'Scan',
        builder: (_) => const ScannerPage(),
        group: 'Linen',
        icon: Icons.qr_code_scanner,
        bottomBar: true,
        tabIndex: 3,
        keywords: const ['qr', 'barcode', 'tag', 'linen'],
      ),
      AppRoutes.gatepasses: AppRoute(
        path: AppRoutes.gatepasses,
        label: 'Gate passes',
        builder: (_) => const GatepassesPage(),
        group: 'Operations',
        icon: Icons.hourglass_empty_outlined,
        bottomBar: true,
        tabIndex: 4,
        keywords: const ['incoming', 'receive', 'intake'],
      ),

      // ── The flow, in the order the linen moves ─────────────────────────
      AppRoutes.entryFlow: AppRoute(
        path: AppRoutes.entryFlow,
        label: 'Daily flow',
        builder: (_) => const EntryFlowPage(),
        group: 'Operations',
        icon: Icons.alt_route_outlined,
        keywords: const ['workflow', 'receive', 'deliver', 'return', 'bill'],
      ),
      AppRoutes.gatepassNew: AppRoute(
        path: AppRoutes.gatepassNew,
        label: 'New gate pass',
        builder: (_) => const GatepassFormPage(),
        group: 'Operations',
        showInDrawer: false,
        keywords: const ['receive', 'incoming', 'create'],
      ),
      AppRoutes.gatepassDetail: AppRoute(
        path: AppRoutes.gatepassDetail,
        label: 'Gate pass',
        builder: (context) => GatepassDetailPage(gatepassId: RouteParams.id),
        group: 'Operations',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.gatepassSlip: AppRoute(
        path: AppRoutes.gatepassSlip,
        label: 'Gate pass slip',
        builder: (context) => GatepassSlipPage(gatepassId: RouteParams.id),
        group: 'Operations',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.deliveries: AppRoute(
        path: AppRoutes.deliveries,
        label: 'Deliveries',
        builder: (_) => const DeliveriesPage(),
        group: 'Operations',
        icon: Icons.local_shipping_outlined,
        keywords: const ['outbound', 'ready'],
      ),
      AppRoutes.deliveryNew: AppRoute(
        path: AppRoutes.deliveryNew,
        label: 'New delivery',
        builder: (_) => const DeliveryFormPage(),
        group: 'Operations',
        showInDrawer: false,
        keywords: const ['outbound', 'create'],
      ),
      AppRoutes.deliveryDetail: AppRoute(
        path: AppRoutes.deliveryDetail,
        label: 'Delivery',
        builder: (context) => DeliveryDetailPage(deliveryId: RouteParams.id),
        group: 'Operations',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.deliverySlips: AppRoute(
        path: AppRoutes.deliverySlips,
        label: 'Delivery slips',
        builder: (_) => const DeliverySlipsPage(),
        group: 'Operations',
        icon: Icons.description_outlined,
        keywords: const ['print', 'slip', 'paper'],
      ),
      AppRoutes.returns: AppRoute(
        path: AppRoutes.returns,
        label: 'Returns',
        builder: (_) => const ReturnsPage(),
        group: 'Operations',
        icon: Icons.assignment_return_outlined,
        keywords: const ['rejected', 'send back'],
      ),
      AppRoutes.returnNew: AppRoute(
        path: AppRoutes.returnNew,
        label: 'New return',
        builder: (_) => const ReturnFormPage(),
        group: 'Operations',
        showInDrawer: false,
        keywords: const ['reject', 'create'],
      ),
      AppRoutes.returnDetail: AppRoute(
        path: AppRoutes.returnDetail,
        label: 'Return',
        builder: (context) => ReturnDetailPage(returnId: RouteParams.id),
        group: 'Operations',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.billNew: AppRoute(
        path: AppRoutes.billNew,
        label: 'New bill',
        builder: (_) => const BillFormPage(),
        group: 'Operations',
        showInDrawer: false,
        keywords: const ['invoice', 'create'],
      ),
      AppRoutes.billDetail: AppRoute(
        path: AppRoutes.billDetail,
        label: 'Bill',
        builder: (context) => BillDetailPage(billId: RouteParams.id),
        group: 'Operations',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.billPrint: AppRoute(
        path: AppRoutes.billPrint,
        label: 'Print bill',
        builder: (context) => BillPrintPage(billId: RouteParams.id),
        group: 'Operations',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.statements: AppRoute(
        path: AppRoutes.statements,
        label: 'Statements',
        builder: (_) => const BillingHistoryPage(),
        group: 'Operations',
        icon: Icons.receipt_outlined,
        keywords: const ['statement', 'billing', 'history'],
      ),

      // ── Linen ─────────────────────────────────────────────────────────
      AppRoutes.hotelLinenFlow: AppRoute(
        path: AppRoutes.hotelLinenFlow,
        label: 'Hotel linen flow',
        builder: (_) => const LinenFlowPage(),
        group: 'Linen',
        icon: Icons.waves_outlined,
        keywords: const ['hotel', 'pieces', 'balance'],
      ),
      AppRoutes.hotelLinenFlowDetail: AppRoute(
        path: AppRoutes.hotelLinenFlowDetail,
        label: 'Hotel linen flow',
        builder: (context) => LinenFlowHotelPage(hotelName: RouteParams.hotel),
        group: 'Linen',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.linen: AppRoute(
        path: AppRoutes.linen,
        label: 'Linen',
        builder: (_) => const LinenTrackingPage(),
        group: 'Linen',
        icon: Icons.inventory_2_outlined,
        keywords: const ['tracking', 'stock', 'history'],
      ),
      AppRoutes.linenInventory: AppRoute(
        path: AppRoutes.linenInventory,
        label: 'Linen inventory',
        builder: (_) => const LinenItemsPage(),
        group: 'Linen',
        icon: Icons.checkroom_outlined,
        keywords: const ['items', 'pieces', 'stock'],
      ),
      AppRoutes.linenDetail: AppRoute(
        path: AppRoutes.linenDetail,
        label: 'Linen piece',
        builder: (context) => LinenTrackingDetailPage(docId: RouteParams.id),
        group: 'Linen',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.garmentDetail: AppRoute(
        path: AppRoutes.garmentDetail,
        label: 'Garment',
        builder: (context) => GarmentDetailPage(code: RouteParams.code),
        group: 'Linen',
        showInDrawer: false,
        showInCommand: false,
      ),

      // ── System ─────────────────────────────────────────────────────────
      AppRoutes.settings: AppRoute(
        path: AppRoutes.settings,
        label: 'Settings',
        builder: (_) => const SettingsPage(),
        group: 'System',
        icon: Icons.settings_outlined,
        adminOnly: true,
        keywords: const ['theme', 'font', 'service', 'api'],
      ),
      AppRoutes.profile: AppRoute(
        path: AppRoutes.profile,
        label: 'My profile',
        builder: (_) => const ProfilePage(),
        group: 'System',
        icon: Icons.person_outline,
        keywords: const ['account', 'password', 'avatar'],
      ),
    });
  }
}

/// Parameters of the route currently being built.
///
/// The navigator sets [bind] before invoking a route's builder, so a builder
/// reads its `:id` without a context lookup or a closure capture.
class RouteParams {
  RouteParams._();

  static Map<String, String> _current = const {};

  static String get id => _current['id'] ?? '';
  static String get hotel => _current['hotel'] ?? '';
  static String get code => _current['code'] ?? '';

  static void bind(Map<String, String> params) => _current = params;
  static void unbind() => _current = const {};
}

/// Fallback destination for an unknown path.
Widget notFoundPage() => const ErrorPage();
