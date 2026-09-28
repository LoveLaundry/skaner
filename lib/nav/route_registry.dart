import 'package:flutter/material.dart';

import '../features/auth/login_page.dart';
import '../features/linen/garment_detail_page.dart';
import '../features/linen/linen_flow_hotel_page.dart';
import '../features/linen/linen_flow_page.dart';
import '../features/linen/linen_items_page.dart';
import '../features/linen/linen_tracking_detail_page.dart';
import '../features/linen/linen_tracking_page.dart';
import '../features/linen/scanner_page.dart';
import '../features/linen/worker_detail_page.dart';
import '../features/linen/worker_form_page.dart';
import '../features/linen/worker_payroll_page.dart';
import '../features/linen/workers_page.dart';
import '../features/management/announcements_page.dart';
import '../features/management/attendance_page.dart';
import '../features/management/departments_page.dart';
import '../features/management/employee_detail_page.dart';
import '../features/management/employee_form_page.dart';
import '../features/management/employees_page.dart';
import '../features/management/expenses_page.dart';
import '../features/management/leave_page.dart';
import '../features/management/management_dashboard_page.dart';
import '../features/management/payroll_page.dart';
import '../features/management/performance_page.dart';
import '../features/management/permissions_page.dart';
import '../features/management/reports_page.dart';
import '../features/management/roles_page.dart';
import '../features/management/training_page.dart';
import '../features/misc/ai_insights_page.dart';
import '../features/misc/backup_restore_page.dart';
import '../features/misc/chat_page.dart';
import '../features/misc/dashboard_page.dart';
import '../features/misc/database_sync_page.dart';
import '../features/misc/error_page.dart';
import '../features/misc/guest_pickup_page.dart';
import '../features/misc/guest_quotation_page.dart';
import '../features/misc/guest_shop_page.dart';
import '../features/misc/guest_track_page.dart';
import '../features/misc/notifications_page.dart';
import '../features/misc/profile_page.dart';
import '../features/misc/settings_page.dart';
import '../features/misc/today_page.dart';
import '../features/misc/users_page.dart';
import '../features/quotations/bill_detail_page.dart';
import '../features/quotations/bill_form_page.dart';
import '../features/quotations/bill_print_page.dart';
import '../features/quotations/bills_page.dart';
import '../features/quotations/billing_history_page.dart';
import '../features/quotations/deliveries_page.dart';
import '../features/quotations/delivery_detail_page.dart';
import '../features/quotations/delivery_form_page.dart';
import '../features/quotations/delivery_slips_page.dart';
import '../features/quotations/dispatch_detail_page.dart';
import '../features/quotations/dispatch_page.dart';
import '../features/quotations/entry_flow_page.dart';
import '../features/quotations/export_page.dart';
import '../features/quotations/gatepass_detail_page.dart';
import '../features/quotations/gatepass_form_page.dart';
import '../features/quotations/gatepass_slip_page.dart';
import '../features/quotations/gatepasses_page.dart';
import '../features/quotations/price_list_page.dart';
import '../features/quotations/quotation_detail_page.dart';
import '../features/quotations/quotation_form_page.dart';
import '../features/quotations/quotation_print_page.dart';
import '../features/quotations/quotations_page.dart';
import '../features/quotations/return_detail_page.dart';
import '../features/quotations/return_form_page.dart';
import '../features/quotations/returns_page.dart';
import '../features/shop_bills/client_statement_page.dart';
import '../features/shop_bills/legacy_invoice_page.dart';
import '../features/shop_bills/shop_bill_detail_page.dart';
import '../features/shop_bills/shop_bill_form_page.dart';
import '../features/shop_bills/shop_bill_print_page.dart';
import '../features/shop_bills/shop_bill_templates_page.dart';
import '../features/shop_bills/shop_bills_page.dart';
import 'app_route.dart';

/// The single place that knows what exists, what it is called, which drawer
/// group it lives in, and who may see it. Paths mirror the web router so a deep
/// link copied from the browser resolves to the same screen here.
class AppRouteRegistry {
  AppRouteRegistry._();

  static void install() {
    AppRoutes.register({
      // ── Guest: no session required ─────────────────────────────────────────
      AppRoutes.login: AppRoute(
        path: AppRoutes.login,
        label: 'Sign in',
        builder: (_) => const LoginPage(),
        group: 'Account',
        showInDrawer: false,
        showInCommand: false,
        guest: true,
      ),
      AppRoutes.guestShop: AppRoute(
        path: AppRoutes.guestShop,
        label: 'Guest price list',
        builder: (_) => const GuestShopPage(),
        group: 'Guest',
        icon: Icons.storefront_outlined,
        showInDrawer: false,
        guest: true,
      ),
      AppRoutes.guestTrack: AppRoute(
        path: AppRoutes.guestTrack,
        label: 'Track my order',
        builder: (_) => const GuestTrackPage(),
        group: 'Guest',
        icon: Icons.track_changes_outlined,
        guest: true,
      ),
      AppRoutes.guestQuotation: AppRoute(
        path: AppRoutes.guestQuotation,
        label: 'Guest quotation',
        builder: (_) => const GuestQuotationPage(),
        group: 'Guest',
        icon: Icons.request_quote_outlined,
        guest: true,
      ),
      AppRoutes.guestPickup: AppRoute(
        path: AppRoutes.guestPickup,
        label: 'Guest pickup',
        builder: (_) => const GuestPickupPage(),
        group: 'Guest',
        icon: Icons.local_shipping_outlined,
        guest: true,
      ),

      // ── Bottom bar: the five things an operator does all day ───────────────
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
      AppRoutes.quotations: AppRoute(
        path: AppRoutes.quotations,
        label: 'Quotations',
        builder: (_) => const QuotationsPage(),
        group: 'Sales',
        icon: Icons.request_quote_outlined,
        bottomBar: true,
        tabIndex: 1,
        keywords: const ['quote', 'estimate', 'price'],
      ),
      AppRoutes.bills: AppRoute(
        path: AppRoutes.bills,
        label: 'Bills',
        builder: (_) => const BillsPage(),
        group: 'Sales',
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

      // ── Quotations ────────────────────────────────────────────────────────
      AppRoutes.quotationNew: AppRoute(
        path: AppRoutes.quotationNew,
        label: 'New quotation',
        builder: (_) => const QuotationFormPage(),
        group: 'Sales',
        showInDrawer: false,
        keywords: const ['quote', 'create'],
      ),
      AppRoutes.quotationEdit: AppRoute(
        path: AppRoutes.quotationEdit,
        label: 'Edit quotation',
        builder: (context) => QuotationFormPage(quotationId: RouteParams.id),
        group: 'Sales',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.quotationDetail: AppRoute(
        path: AppRoutes.quotationDetail,
        label: 'Quotation',
        builder: (context) => QuotationDetailPage(quotationId: RouteParams.id),
        group: 'Sales',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.quotationPrint: AppRoute(
        path: AppRoutes.quotationPrint,
        label: 'Print quotation',
        builder: (context) => QuotationPrintPage(quotationId: RouteParams.id),
        group: 'Sales',
        showInDrawer: false,
        showInCommand: false,
      ),

      // ── Bills ─────────────────────────────────────────────────────────────
      AppRoutes.billNew: AppRoute(
        path: AppRoutes.billNew,
        label: 'New bill',
        builder: (_) => const BillFormPage(),
        group: 'Sales',
        showInDrawer: false,
        keywords: const ['invoice', 'create'],
      ),
      AppRoutes.billDetail: AppRoute(
        path: AppRoutes.billDetail,
        label: 'Bill',
        builder: (context) => BillDetailPage(billId: RouteParams.id),
        group: 'Sales',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.billPrint: AppRoute(
        path: AppRoutes.billPrint,
        label: 'Print bill',
        builder: (context) => BillPrintPage(billId: RouteParams.id),
        group: 'Sales',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.statements: AppRoute(
        path: AppRoutes.statements,
        label: 'Statements',
        builder: (_) => const BillingHistoryPage(),
        group: 'Sales',
        icon: Icons.receipt_outlined,
        keywords: const ['statement', 'client', 'chronology'],
      ),

      // ── Gate passes ───────────────────────────────────────────────────────
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

      // ── Deliveries & dispatch ─────────────────────────────────────────────
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
      AppRoutes.dispatch: AppRoute(
        path: AppRoutes.dispatch,
        label: 'Dispatch board',
        builder: (_) => const DispatchPage(),
        group: 'Operations',
        icon: Icons.route_outlined,
        keywords: const ['driver', 'route', 'job'],
      ),
      AppRoutes.dispatchDetail: AppRoute(
        path: AppRoutes.dispatchDetail,
        label: 'Dispatch job',
        builder: (context) => DispatchDetailPage(dispatchId: RouteParams.id),
        group: 'Operations',
        showInDrawer: false,
        showInCommand: false,
      ),

      // ── Returns ───────────────────────────────────────────────────────────
      AppRoutes.returns: AppRoute(
        path: AppRoutes.returns,
        label: 'Returns',
        builder: (_) => const ReturnsPage(),
        group: 'Operations',
        icon: Icons.assignment_return_outlined,
        keywords: const ['rejected', 'reject', 'send back'],
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

      // ── Linen ─────────────────────────────────────────────────────────────
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

      // ── Shop bills ────────────────────────────────────────────────────────
      AppRoutes.shopBills: AppRoute(
        path: AppRoutes.shopBills,
        label: 'Shop bills',
        builder: (_) => const ShopBillsPage(),
        group: 'Shop',
        icon: Icons.storefront_outlined,
        keywords: const ['retail', 'walk in', 'counter'],
      ),
      AppRoutes.shopBillNew: AppRoute(
        path: AppRoutes.shopBillNew,
        label: 'New shop bill',
        builder: (_) => const ShopBillFormPage(),
        group: 'Shop',
        showInDrawer: false,
        keywords: const ['retail', 'create'],
      ),
      AppRoutes.shopBillDetail: AppRoute(
        path: AppRoutes.shopBillDetail,
        label: 'Shop bill',
        builder: (context) => ShopBillDetailPage(billId: RouteParams.id),
        group: 'Shop',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.shopBillPrint: AppRoute(
        path: AppRoutes.shopBillPrint,
        label: 'Print shop bill',
        builder: (context) => ShopBillPrintPage(billId: RouteParams.id),
        group: 'Shop',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.shopBillTemplates: AppRoute(
        path: AppRoutes.shopBillTemplates,
        label: 'Shop bill templates',
        builder: (_) => const ShopBillTemplatesPage(),
        group: 'Shop',
        icon: Icons.dashboard_customize_outlined,
        keywords: const ['template', 'preset'],
      ),
      AppRoutes.clientStatement: AppRoute(
        path: AppRoutes.clientStatement,
        label: 'Client statement',
        builder: (_) => const ClientStatementPage(),
        group: 'Shop',
        icon: Icons.account_balance_outlined,
        keywords: const ['statement', 'outstanding', 'loyalty'],
      ),
      AppRoutes.legacyInvoice: AppRoute(
        path: AppRoutes.legacyInvoice,
        label: 'Legacy invoices',
        builder: (_) => const LegacyInvoicePage(),
        group: 'Shop',
        icon: Icons.history_edu_outlined,
        keywords: const ['paper', 'old', 'invoice'],
      ),

      // ── Workers ───────────────────────────────────────────────────────────
      AppRoutes.workers: AppRoute(
        path: AppRoutes.workers,
        label: 'Workers',
        builder: (_) => const WorkersPage(),
        group: 'Workforce',
        icon: Icons.badge_outlined,
        keywords: const ['staff', 'roster', 'team'],
      ),
      AppRoutes.workerNew: AppRoute(
        path: AppRoutes.workerNew,
        label: 'New worker',
        builder: (_) => const WorkerFormPage(),
        group: 'Workforce',
        showInDrawer: false,
      ),
      AppRoutes.workerDetail: AppRoute(
        path: AppRoutes.workerDetail,
        label: 'Worker',
        builder: (context) => WorkerDetailPage(workerId: RouteParams.id),
        group: 'Workforce',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.workerPayroll: AppRoute(
        path: AppRoutes.workerPayroll,
        label: 'Worker payroll',
        builder: (_) => const WorkerPayrollPage(),
        group: 'Workforce',
        icon: Icons.payments_outlined,
        keywords: const ['wages', 'attendance', 'output'],
      ),

      // ── Management ────────────────────────────────────────────────────────
      AppRoutes.management: AppRoute(
        path: AppRoutes.management,
        label: 'Management overview',
        builder: (_) => const ManagementDashboardPage(),
        group: 'Management',
        icon: Icons.dashboard_outlined,
        keywords: const ['hr', 'headcount', 'payroll'],
      ),
      AppRoutes.dashboard: AppRoute(
        path: AppRoutes.dashboard,
        label: 'Dashboard',
        builder: (_) => const DashboardPage(),
        group: 'Management',
        icon: Icons.insights_outlined,
        keywords: const ['kpi', 'metrics', 'overview'],
      ),
      AppRoutes.managementEmployees: AppRoute(
        path: AppRoutes.managementEmployees,
        label: 'Employees',
        builder: (_) => const EmployeesPage(),
        group: 'Management',
        icon: Icons.groups_outlined,
        keywords: const ['staff', 'hr', 'people'],
      ),
      AppRoutes.managementEmployeeNew: AppRoute(
        path: AppRoutes.managementEmployeeNew,
        label: 'New employee',
        builder: (_) => const EmployeeFormPage(),
        group: 'Management',
        showInDrawer: false,
      ),
      AppRoutes.managementEmployeeDetail: AppRoute(
        path: AppRoutes.managementEmployeeDetail,
        label: 'Employee',
        builder: (context) => EmployeeDetailPage(employeeId: RouteParams.id),
        group: 'Management',
        showInDrawer: false,
        showInCommand: false,
      ),
      AppRoutes.managementDepartments: AppRoute(
        path: AppRoutes.managementDepartments,
        label: 'Departments',
        builder: (_) => const DepartmentsPage(),
        group: 'Management',
        icon: Icons.account_tree_outlined,
        keywords: const ['division', 'unit'],
      ),
      AppRoutes.managementRoles: AppRoute(
        path: AppRoutes.managementRoles,
        label: 'Roles',
        builder: (_) => const RolesPage(),
        group: 'Management',
        icon: Icons.workspaces_outlined,
        keywords: const ['access', 'admin', 'manager'],
      ),
      AppRoutes.managementPermissions: AppRoute(
        path: AppRoutes.managementPermissions,
        label: 'Permissions',
        builder: (_) => const PermissionsPage(),
        group: 'Management',
        icon: Icons.key_outlined,
        keywords: const ['access', 'grant', 'role'],
      ),
      AppRoutes.managementAttendance: AppRoute(
        path: AppRoutes.managementAttendance,
        label: 'Attendance',
        builder: (_) => const AttendancePage(),
        group: 'Management',
        icon: Icons.how_to_reg_outlined,
        keywords: const ['present', 'absent', 'overtime'],
      ),
      AppRoutes.managementLeave: AppRoute(
        path: AppRoutes.managementLeave,
        label: 'Leave',
        builder: (_) => const LeavePage(),
        group: 'Management',
        icon: Icons.beach_access_outlined,
        keywords: const ['vacation', 'absent'],
      ),
      AppRoutes.payroll: AppRoute(
        path: AppRoutes.payroll,
        label: 'Payroll run',
        builder: (_) => const PayrollPage(),
        group: 'Management',
        icon: Icons.payments_outlined,
        keywords: const ['salary', 'slip', 'payout'],
      ),
      AppRoutes.managementPerformance: AppRoute(
        path: AppRoutes.managementPerformance,
        label: 'Performance',
        builder: (_) => const PerformancePage(),
        group: 'Management',
        icon: Icons.trending_up_outlined,
        keywords: const ['review', 'rating'],
      ),
      AppRoutes.managementTraining: AppRoute(
        path: AppRoutes.managementTraining,
        label: 'Training',
        builder: (_) => const TrainingPage(),
        group: 'Management',
        icon: Icons.school_outlined,
        keywords: const ['learn', 'course'],
      ),
      AppRoutes.managementAnnouncements: AppRoute(
        path: AppRoutes.managementAnnouncements,
        label: 'Announcements',
        builder: (_) => const AnnouncementsPage(),
        group: 'Management',
        icon: Icons.campaign_outlined,
        keywords: const ['notice', 'holiday', 'calendar'],
      ),
      AppRoutes.managementExpenses: AppRoute(
        path: AppRoutes.managementExpenses,
        label: 'Expenses',
        builder: (_) => const ExpensesPage(),
        group: 'Management',
        icon: Icons.paid_outlined,
        keywords: const ['spend', 'cost', 'adjustment'],
      ),
      AppRoutes.managementReports: AppRoute(
        path: AppRoutes.managementReports,
        label: 'Reports',
        builder: (_) => const ReportsPage(),
        group: 'Management',
        icon: Icons.assessment_outlined,
        keywords: const ['profit', 'loss', 'daily', 'monthly'],
      ),
      AppRoutes.users: AppRoute(
        path: AppRoutes.users,
        label: 'Users',
        builder: (_) => const UsersPage(),
        group: 'Management',
        icon: Icons.manage_accounts_outlined,
        readPermission: 'users.manage',
        keywords: const ['accounts', 'login', 'admin'],
      ),

      // ── Communication & insights ──────────────────────────────────────────
      AppRoutes.notifications: AppRoute(
        path: AppRoutes.notifications,
        label: 'Activity',
        builder: (_) => const NotificationsPage(),
        group: 'Home',
        icon: Icons.notifications_none_outlined,
        keywords: const ['alert', 'history', 'sync'],
      ),
      AppRoutes.liveChat: AppRoute(
        path: AppRoutes.liveChat,
        label: 'Live chat',
        builder: (_) => const ChatPage(),
        group: 'Support',
        icon: Icons.forum_outlined,
        readPermission: 'chat.access',
        keywords: const ['message', 'support', 'conversation'],
      ),
      AppRoutes.aiInsights: AppRoute(
        path: AppRoutes.aiInsights,
        label: 'AI insights',
        builder: (_) => const AiInsightsPage(),
        group: 'Insights',
        icon: Icons.auto_awesome_outlined,
        keywords: const ['forecast', 'trend', 'analysis'],
      ),
      AppRoutes.entryFlow: AppRoute(
        path: AppRoutes.entryFlow,
        label: 'Daily flow',
        builder: (_) => const EntryFlowPage(),
        group: 'Operations',
        icon: Icons.alt_route_outlined,
        keywords: const ['workflow', 'receive', 'deliver', 'return'],
      ),
      AppRoutes.exportCenter: AppRoute(
        path: AppRoutes.exportCenter,
        label: 'Export centre',
        builder: (_) => const ExportPage(),
        group: 'Reports',
        icon: Icons.download_outlined,
        keywords: const ['csv', 'excel', 'xlsx', 'download'],
      ),
      AppRoutes.priceList: AppRoute(
        path: AppRoutes.priceList,
        label: 'Price list',
        builder: (_) => const PriceListPage(),
        group: 'Sales',
        icon: Icons.sell_outlined,
        keywords: const ['rates', 'tariff', 'items'],
      ),

      // ── System ────────────────────────────────────────────────────────────
      AppRoutes.databaseSync: AppRoute(
        path: AppRoutes.databaseSync,
        label: 'Database sync',
        builder: (_) => const DatabaseSyncPage(),
        group: 'System',
        icon: Icons.storage_outlined,
        keywords: const ['reset', 'reindex', 'admin'],
      ),
      AppRoutes.backupRestore: AppRoute(
        path: AppRoutes.backupRestore,
        label: 'Backup & restore',
        builder: (_) => const BackupRestorePage(),
        group: 'System',
        icon: Icons.backup_outlined,
        keywords: const ['snapshot', 'pdf', 'json', 'restore'],
      ),
      AppRoutes.settings: AppRoute(
        path: AppRoutes.settings,
        label: 'Settings',
        builder: (_) => const SettingsPage(),
        group: 'System',
        icon: Icons.settings_outlined,
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
