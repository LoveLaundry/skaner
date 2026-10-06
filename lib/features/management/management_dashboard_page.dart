import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';

/// Port of `pages/management-dashboard.tsx`. The web app's financial KPIs
/// (revenue, profit, outstanding) are folded into the operator-facing HR tiles
/// here because this screen is reached from the management module on a phone.
class ManagementDashboardPage extends StatefulWidget {
  const ManagementDashboardPage({super.key});

  @override
  State<ManagementDashboardPage> createState() =>
      _ManagementDashboardPageState();
}

class _ManagementDashboardPageState extends State<ManagementDashboardPage> {
  late final ResourceController<Map<String, dynamic>> _controller;
  late final ResourceController<List<Map<String, dynamic>>> _attendance;

  @override
  void initState() {
    super.initState();
    final cache = AppScope.read(context).cache;
    _controller = ResourceController<Map<String, dynamic>>(
      key: 'management.dashboard',
      cache: cache,
      fetcher: _fetchDashboard,
    );
    _attendance = ResourceController<List<Map<String, dynamic>>>(
      key: 'management.dashboard.attendance',
      cache: cache,
      fetcher: _fetchAttendance,
    );
    _controller.addListener(_onChanged);
    _attendance.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.load(force: true);
      _attendance.load(force: true);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _attendance.removeListener(_onChanged);
    _controller.dispose();
    _attendance.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<Map<String, dynamic>> _fetchDashboard() async {
    final services = AppScope.read(context);
    final payload =
        await services.api.get(ServiceNames.management, '/api/dashboard');
    return asMap(payload);
  }

  /// The dashboard payload carries `present_today` / `on_leave_today` but no
  /// absent count, so the day's attendance is read from the attendance
  /// collection to keep the absent tile honest.
  Future<List<Map<String, dynamic>>> _fetchAttendance() async {
    final services = AppScope.read(context);
    final payload = await services.api.get(
      ServiceNames.management,
      '/api/attendance',
      query: {'start_date': Fmt.today(), 'end_date': Fmt.today()},
    );
    return asRows(payload);
  }

  static Map<String, dynamic> asMap(dynamic payload) =>
      payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      body: Column(
        children: [
          AppPageHeader(
            title: 'Management',
          ),
          AppSyncStatusBar(
            status: _controller.status,
            updatedAt: _controller.lastUpdated,
            label: 'Dashboard',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: _refresh,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    await Future.wait([
      _controller.load(force: true),
      _attendance.load(force: true),
    ]);
  }

  Widget _body() {
    final data = _controller.data;
    if (_controller.phase == LoadPhase.failed && data == null) {
      return AppErrorState(
        message: _controller.error,
        onRetry: () => _controller.load(force: true),
      );
    }
    if (_controller.isLoading && data == null) {
      return const AppSkeletonList();
    }

    final rows = _attendance.data ?? const <Map<String, dynamic>>[];
    final present = _countOf(rows, const ['PRESENT']);
    final absent = _countOf(rows, const ['ABSENT']);
    final onLeave =
        _countOf(rows, const ['PAID_LEAVE', 'UNPAID_LEAVE', 'ON_LEAVE']);

    final headcount = data == null
        ? null
        : (pick(data, ['active_employees', 'total_employees']) as num?)
            ?.round();
    final draftSlips = data == null
        ? null
        : (pick(data, ['draft_slips_month']) as num?)?.round();
    final unpaidSlips = data == null
        ? null
        : (pick(data, ['unpaid_slips_month']) as num?)?.round();
    final monthExpenses = data == null
        ? null
        : (pick(data, ['total_expenses']) as num?)?.toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.35,
          children: [
            AppStatCard(
              label: 'Headcount',
              value: Fmt.count(headcount),
              icon: Icons.groups_outlined,
              caption: 'active employees',
            ),
            AppStatCard(
              label: 'Present today',
              value: Fmt.count(present),
              icon: Icons.how_to_reg_outlined,
              trend: headcount == null || headcount == 0
                  ? null
                  : (present > headcount / 2 ? StatTrend.up : StatTrend.down),
              trendLabel: headcount == null
                  ? null
                  : '${Fmt.percent(headcount == 0 ? 0 : present / headcount * 100)} of headcount',
            ),
            AppStatCard(
              label: 'Absent today',
              value: Fmt.count(absent),
              icon: Icons.person_off_outlined,
              trend: absent > 0 ? StatTrend.down : StatTrend.flat,
              trendLabel: absent > 0 ? 'unmarked in' : 'all present',
            ),
            AppStatCard(
              label: 'On leave today',
              value: Fmt.count(onLeave),
              icon: Icons.beach_access_outlined,
            ),
            AppStatCard(
              label: 'Pending payroll',
              value: Fmt.count(draftSlips),
              icon: Icons.receipt_long_outlined,
              trend: (draftSlips ?? 0) > 0 ? StatTrend.down : StatTrend.flat,
              trendLabel: '${Fmt.count(unpaidSlips)} finalized unpaid',
            ),
            AppStatCard(
              label: "This month's expenses",
              value: Fmt.money(monthExpenses),
              icon: Icons.trending_down_rounded,
              trend: StatTrend.down,
              trendLabel: 'outgoings',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _attendanceTrend(rows),
        const SizedBox(height: 16),
        _quickLinks(),
      ],
    );
  }

  /// Bars for the days that have attendance rows, oldest first. The web
  /// app draws this as a recharts bar chart; on a phone a fixed set of bars
  /// reads the same without the dependency.
  Widget _attendanceTrend(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const AppCard(
        title: 'Attendance today',
        child: Text('No attendance recorded yet.'),
      );
    }
    final byDay = <String, int>{};
    for (final r in rows) {
      final status = str(r, ['status'], 'PRESENT').toUpperCase();
      if (status != 'PRESENT' && status != 'HALF_DAY') continue;
      final day = Fmt.dateShort(pick(r, ['date', 'attendance_date']));
      byDay[day] = (byDay[day] ?? 0) + 1;
    }
    if (byDay.isEmpty) {
      return const AppCard(
        title: 'Attendance today',
        child: Text('No one is marked present yet today.'),
      );
    }
    final peak = byDay.values.fold<int>(1, (a, b) => a > b ? a : b);
    final entries = byDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return AppCard(
      title: 'Attendance today',
      subtitle: '${Fmt.count(byDay.length)} day(s) with staff on duty',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in entries.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(e.key,
                        style: context.texts.labelSmall
                            ?.copyWith(color: context.c.fgMuted)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      child: LinearProgressIndicator(
                        value: e.value / peak,
                        minHeight: 8,
                        backgroundColor: context.c.surface3,
                        valueColor: AlwaysStoppedAnimation(context.c.brand),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 30,
                    child: Text(
                      Fmt.count(e.value),
                      style: context.texts.labelSmall
                          ?.copyWith(color: context.c.fg2),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Quick links navigate rather than act, so they are inert tiles here: the
  /// route registry owns where each one lands.
  Widget _quickLinks() {
    const links = [
      ('Employees', Icons.badge_outlined),
      ('Attendance', Icons.event_note_outlined),
      ('Payroll', Icons.account_balance_wallet_outlined),
      ('Expenses', Icons.request_quote_outlined),
      ('Reports', Icons.insert_chart_outlined),
    ];
    return AppCard(
      title: 'Quick links',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, icon) in links)
            AppBadge(
              label,
              tone: AppTone.brand,
              icon: icon,
            ),
        ],
      ),
    );
  }

  static int _countOf(List<Map<String, dynamic>> rows, List<String> statuses) {
    var n = 0;
    for (final r in rows) {
      if (statuses.contains(str(r, ['status'], 'PRESENT').toUpperCase())) n++;
    }
    return n;
  }
}
