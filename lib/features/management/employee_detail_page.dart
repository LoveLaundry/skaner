import 'package:flutter/material.dart';

import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import '_management_shared.dart';
import 'employee_form_page.dart';

/// Port of the employee drill-down: the record itself, its attendance rollup,
/// its advances and its salary history, in the four sections the web app
/// reaches through `employeesApi` and `salaryApi`.
class EmployeeDetailPage extends StatefulWidget {
  const EmployeeDetailPage({super.key, required this.employeeId});

  final String employeeId;

  @override
  State<EmployeeDetailPage> createState() => _EmployeeDetailPageState();
}

class _EmployeeDetailPageState extends State<EmployeeDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final ResourceController<Map<String, dynamic>> _profile;
  late final ResourceController<Map<String, dynamic>> _attendanceSummary;
  late final ResourceController<Map<String, dynamic>> _advanceSummary;
  late final ResourceController<List<Map<String, dynamic>>> _advances;
  late final ResourceController<List<Map<String, dynamic>>> _salary;

  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    final cache = AppScope.read(context).cache;
    _to = Fmt.lktNow();
    _from = _to.subtract(const Duration(days: 30));

    _profile = ResourceController<Map<String, dynamic>>(
      key: 'employees.${widget.employeeId}',
      cache: cache,
      fetcher: () async {
        final s = AppScope.read(context);
        final p = await s.api.get(mgmt, '/api/employees/${widget.employeeId}');
        return p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{};
      },
    );
    _attendanceSummary = ResourceController<Map<String, dynamic>>(
      key: 'employees.${widget.employeeId}.attendance-summary',
      cache: cache,
      fetcher: _fetchAttendanceSummary,
    );
    _advanceSummary = ResourceController<Map<String, dynamic>>(
      key: 'employees.${widget.employeeId}.advance-summary',
      cache: cache,
      fetcher: () async {
        final s = AppScope.read(context);
        final p = await s.api
            .get(mgmt, '/api/employees/${widget.employeeId}/advances/summary');
        return p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{};
      },
    );
    _advances = ResourceController<List<Map<String, dynamic>>>(
      key: 'employees.${widget.employeeId}.advances',
      cache: cache,
      fetcher: () async {
        final s = AppScope.read(context);
        return asRows(await s.api
            .get(mgmt, '/api/employees/${widget.employeeId}/advances'));
      },
    );
    _salary = ResourceController<List<Map<String, dynamic>>>(
      key: 'employees.${widget.employeeId}.salary-history',
      cache: cache,
      fetcher: () async {
        final s = AppScope.read(context);
        return asRows(await s.api
            .get(mgmt, '/api/employees/${widget.employeeId}/salary-history'));
      },
    );

    for (final c in [
      _profile,
      _attendanceSummary,
      _advanceSummary,
      _advances,
      _salary
    ]) {
      c.addListener(_onLoaded);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadAll());
  }

  Future<Map<String, dynamic>> _fetchAttendanceSummary() async {
    final services = AppScope.read(context);
    final payload = await services.api.get(
      mgmt,
      '/api/attendance/summary',
      query: {
        'employee_id': widget.employeeId,
        'start_date': Fmt.isoDate(_from),
        'end_date': Fmt.isoDate(_to),
      },
    );
    return payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
  }

  void _onLoaded() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _profile,
      _attendanceSummary,
      _advanceSummary,
      _advances,
      _salary
    ]) {
      c.removeListener(_onLoaded);
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _reloadAll() async {
    await Future.wait([
      _profile.load(force: true),
      _attendanceSummary.load(force: true),
      _advanceSummary.load(force: true),
      _advances.load(force: true),
      _salary.load(force: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final employee = _profile.data ?? <String, dynamic>{};
    return Scaffold(
      appBar: AppBar(
        title: Text(employeeName(employee)),
        actions: [
          if (_profile.data != null)
            AppButton.icon(
              icon: Icons.edit_outlined,
              tooltip: 'Edit employee',
              onPressed: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => EmployeeFormPage(employee: _profile.data),
                  ),
                );
                if (saved == true) _reloadAll();
              },
            ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Profile'),
            Tab(text: 'Attendance'),
            Tab(text: 'Advances'),
            Tab(text: 'Salary history'),
          ],
        ),
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _profile.status,
            updatedAt: _profile.lastUpdated,
            label: employeeName(employee),
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _profileTab(employee),
                _attendanceTab(),
                _advancesTab(),
                _salaryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileTab(Map<String, dynamic> e) {
    if (_profile.phase == LoadPhase.failed && _profile.data == null) {
      return AppErrorState(
        message: _profile.error,
        onRetry: () => _profile.load(force: true),
      );
    }
    if (_profile.isLoading && _profile.data == null) {
      return const AppLoader(label: 'Loading employee…');
    }

    final isActive = employeeIsActive(e);
    final salaryType = str(e, ['salary_type'], 'MONTHLY');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        Row(
          children: [
            AppAvatar(name: employeeName(e), size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(employeeName(e), style: context.texts.titleMedium),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      AppBadge(
                        isActive ? 'Active' : 'Inactive',
                        tone: isActive ? AppTone.success : AppTone.neutral,
                        compact: true,
                      ),
                      if (!employeeAttendanceRequired(e))
                        const AppBadge(
                          'Fixed salary',
                          tone: AppTone.warning,
                          compact: true,
                        ),
                      if (dateOf(e, ['leaving_date']) != null)
                        const AppBadge(
                          'Left',
                          tone: AppTone.neutral,
                          compact: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        AppCard(
          title: 'Details',
          child: Column(
            children: [
              _row('Employee code', str(e, ['employee_code', 'code']), '—'),
              _row('Position', str(e, ['position', 'designation']), '—'),
              _row('Department', employeeDepartment(e)),
              _row('Pay frequency', Fmt.humanise(salaryType)),
              _row('Phone', str(e, ['phone']), '—'),
              _row('NIC', str(e, ['nic']), '—'),
              _row('Joined', Fmt.date(pick(e, ['joined_date', 'join_date'])),
                  '—'),
              _row('Leaving', Fmt.date(pick(e, ['leaving_date'])), '—'),
              _row('Notes', str(e, ['notes']), '—'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Pay arrangement',
          child: Column(
            children: [
              _row('Basic salary', Fmt.money(numOf(e, ['basic_salary'])), '—'),
              if (numOf(e, ['daily_rate']) > 0)
                _row('Daily rate', Fmt.money(numOf(e, ['daily_rate'])), '—'),
              if (numOf(e, ['weekly_rate']) > 0)
                _row('Weekly rate', Fmt.money(numOf(e, ['weekly_rate'])), '—'),
              if (numOf(e, ['contract_amount']) > 0)
                _row('Contract amount',
                    Fmt.money(numOf(e, ['contract_amount'])), '—'),
              if (numOf(e, ['overtime_rate']) > 0)
                _row('Overtime rate',
                    '${Fmt.money(numOf(e, ['overtime_rate']))}/hr'),
              _row('Allowance', Fmt.money(numOf(e, ['allowance'])), '—'),
              _row('Allowance type', Fmt.humanise(str(e, ['allowance_type'])),
                  '—'),
              _row('EPF', '${Fmt.qty(numOf(e, ['epf_rate']))}%'),
              _row('ETF', '${Fmt.qty(numOf(e, ['etf_rate']))}%'),
              _row('EPF base', Fmt.humanise(str(e, ['epf_base'])), '—'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _attendanceTab() {
    final summary = _attendanceSummary.data;
    if (_attendanceSummary.phase == LoadPhase.failed && summary == null) {
      return AppErrorState(
        message: _attendanceSummary.error,
        onRetry: () => _attendanceSummary.load(force: true),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppDateField(
                label: 'From',
                value: _from,
                lastDate: _to,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _from = v);
                  _attendanceSummary.load(force: true);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppDateField(
                label: 'To',
                value: _to,
                firstDate: _from,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _to = v);
                  _attendanceSummary.load(force: true);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_attendanceSummary.isLoading && summary == null)
          const AppLoader(compact: true)
        else
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.5,
            children: [
              AppStatCard(
                compact: true,
                label: 'Worked',
                value: Fmt.count(
                    intOf(summary ?? {}, ['worked_days', 'present_days'])),
                icon: Icons.how_to_reg_outlined,
              ),
              AppStatCard(
                compact: true,
                label: 'Half days',
                value: Fmt.count(intOf(summary ?? {}, ['half_days'])),
                icon: Icons.timelapse_outlined,
              ),
              AppStatCard(
                compact: true,
                label: 'Paid leave',
                value: Fmt.count(intOf(summary ?? {}, ['paid_leave_days'])),
                icon: Icons.beach_access_outlined,
              ),
              AppStatCard(
                compact: true,
                label: 'Unpaid / absent',
                value: Fmt.count(
                  intOf(summary ?? {}, ['unpaid_leave_days']) +
                      intOf(summary ?? {}, ['absent_days']),
                ),
                icon: Icons.person_off_outlined,
              ),
            ],
          ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: [
              _row(
                'Period',
                '${Fmt.date(pick(summary ?? {}, ['start_date']))} → '
                    '${Fmt.date(pick(summary ?? {}, ['end_date']))}',
              ),
              _row('Overtime',
                  '${Fmt.qty(numOf(summary ?? {}, ['overtime_hours']))} hrs'),
              _row('Holidays',
                  Fmt.count(intOf(summary ?? {}, ['holiday_count']))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _advancesTab() {
    final rows = _advances.data;
    final summary = _advanceSummary.data;
    if (_advances.phase == LoadPhase.failed && rows == null) {
      return AppErrorState(
        message: _advances.error,
        onRetry: () => _advances.load(force: true),
      );
    }
    if (_advances.isLoading && rows == null) {
      return const AppSkeletonList();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        if (summary != null) ...[
          AppCard(
            title: 'Advance summary',
            child: Column(
              children: [
                _row(
                  'Total advanced',
                  Fmt.money(numOf(
                      summary, ['total_advance', 'total_advanced', 'total'])),
                ),
                _row('Repaid',
                    Fmt.money(numOf(summary, ['total_repaid', 'repaid']))),
                _row(
                  'Outstanding',
                  Fmt.money(numOf(summary,
                      ['outstanding', 'outstanding_amount', 'pending'])),
                ),
                _row('Count',
                    Fmt.count(intOf(summary, ['count', 'total_count']))),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (rows == null || rows.isEmpty)
          const AppEmptyState(
            title: 'No advances',
            message: 'This employee has never taken an advance.',
            icon: Icons.account_balance_wallet_outlined,
            compact: true,
          )
        else
          AppDataTable<Map<String, dynamic>>(
            rows: rows,
            emptyTitle: 'No advances',
            columns: [
              AppDataColumn(
                label: 'Amount',
                value: (r) => Fmt.money(numOf(r, ['amount'])),
              ),
              AppDataColumn(
                label: 'Date',
                value: (r) => Fmt.date(pick(r, ['date', 'advance_date'])),
              ),
              AppDataColumn(
                label: 'Reason',
                value: (r) => str(r, ['reason', 'notes'], '—'),
              ),
            ],
            rowLeading: (context, r) => AppBadge(
              Fmt.humanise(str(r, ['status'], 'OUTSTANDING')),
              tone: advanceStatusTone(str(r, ['status'])),
              compact: true,
            ),
          ),
      ],
    );
  }

  Widget _salaryTab() {
    final rows = _salary.data;
    if (_salary.phase == LoadPhase.failed && rows == null) {
      return AppErrorState(
        message: _salary.error,
        onRetry: () => _salary.load(force: true),
      );
    }
    if (_salary.isLoading && rows == null) {
      return const AppSkeletonList();
    }
    if (rows == null || rows.isEmpty) {
      return const AppEmptyState(
        title: 'No salary history',
        message: 'No salary slip has been generated for this employee.',
        icon: Icons.receipt_long_outlined,
      );
    }

    return RefreshIndicator(
      color: context.c.brand,
      onRefresh: () => _salary.load(force: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final r = rows[i];
          final status = str(r, ['status'], 'DRAFT');
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        str(
                            r,
                            ['slip_number', 'period'],
                            Fmt.monthYear(
                              DateTime(intOf(r, ['year'], Fmt.lktNow().year),
                                  intOf(r, ['month'], Fmt.lktNow().month)),
                            )),
                        style: context.texts.titleSmall,
                      ),
                    ),
                    AppBadge(
                      Fmt.humanise(status),
                      tone: slipStatusTone(status),
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _row('Gross',
                    Fmt.money(numOf(r, ['gross_salary', 'total_earnings']))),
                _row('Deductions',
                    Fmt.money(numOf(r, ['total_deductions', 'deductions']))),
                _row('Net', Fmt.money(numOf(r, ['net_salary', 'net']))),
                _row('Paid', Fmt.money(numOf(r, ['paid_amount']))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, [String empty = '—']) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 132,
              child: Text(
                label,
                style:
                    context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
              ),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? empty : value,
                style: context.texts.bodyMedium?.copyWith(color: context.c.fg),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      );
}
