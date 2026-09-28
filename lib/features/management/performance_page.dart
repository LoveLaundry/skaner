import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
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
import 'employee_detail_page.dart';

/// There is no management performance endpoint. Attendance is the only
/// measured record the API keeps per employee, so this screen scores the
/// period from `/api/attendance/summary` — the same worked/leave/overtime
/// figures the web app's own salary forecast reads.
class PerformancePage extends StatefulWidget {
  const PerformancePage({super.key});

  @override
  State<PerformancePage> createState() => _PerformancePageState();
}

class _PerformancePageState extends State<PerformancePage> {
  late final ResourceController<List<Map<String, dynamic>>> _employees;
  late final ResourceController<Map<String, dynamic>> _records;

  late DateTime _from;
  late DateTime _to;
  bool _loadingSummaries = false;

  /// `employee_id` → the summary row the API returned for them.
  final Map<String, Map<String, dynamic>> _summaries = {};

  @override
  void initState() {
    super.initState();
    final cache = AppScope.read(context).cache;
    final today = DateTime.now();
    _from = DateTime(today.year, today.month, 1);
    _to = today;
    _employees = ResourceController<List<Map<String, dynamic>>>(
      key: 'employees',
      cache: cache,
      fetcher: () async {
        final s = AppScope.read(context);
        return asRows(await s.api.get(mgmt, '/api/employees'));
      },
    );
    _records = ResourceController<Map<String, dynamic>>(
      key: 'management.performance.records',
      cache: cache,
      fetcher: _fetchRecords,
    );
    for (final c in [_employees, _records]) {
      c.addListener(_onChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _employees.load(force: true).then((_) => _loadSummaries());
      _records.load(force: true);
    });
  }

  @override
  void dispose() {
    for (final c in [_employees, _records]) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<Map<String, dynamic>> _fetchRecords() async {
    final s = AppScope.read(context);
    final payload = await s.api.get(mgmt, '/api/attendance', query: {
      'start_date': Fmt.isoDate(_from),
      'end_date': Fmt.isoDate(_to),
      'limit': 500,
      'offset': 0,
    });
    return payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
  }

  /// The summary endpoint is per employee, so the roster is walked one call at
  /// a time and each answer is kept as it lands.
  Future<void> _loadSummaries() async {
    final staff = (_employees.data ?? const <Map<String, dynamic>>[])
        .where((e) => boolOf(e, ['is_active']))
        .toList();
    if (staff.isEmpty) return;
    setState(() => _loadingSummaries = true);
    final services = AppScope.read(context);
    for (final e in staff) {
      final id = str(e, ['id']);
      if (id.isEmpty) continue;
      try {
        final payload =
            await services.api.get(mgmt, '/api/attendance/summary', query: {
          'employee_id': id,
          'start_date': Fmt.isoDate(_from),
          'end_date': Fmt.isoDate(_to),
        });
        if (payload is Map) {
          _summaries[id] = Map<String, dynamic>.from(payload);
        }
      } on ApiException {
        // A single employee without a summary simply scores zero.
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _loadingSummaries = false);
  }

  /// Attendance rate over the days actually recorded for the period: worked
  /// days plus half days against everything the employee was marked for.
  double _rate(Map<String, dynamic> s) {
    final worked = numOf(s, ['worked_days']);
    final half = numOf(s, ['half_days']);
    final paid = numOf(s, ['paid_leave_days']);
    final unpaid = numOf(s, ['unpaid_leave_days']) + numOf(s, ['absent_days']);
    final denominator = worked + half + paid + unpaid;
    if (denominator == 0) return 0;
    return (worked + half * 0.5) / denominator * 100;
  }

  List<Map<String, dynamic>> get _scored {
    final out = <Map<String, dynamic>>[];
    for (final e in _employees.data ?? const <Map<String, dynamic>>[]) {
      if (!employeeIsActive(e)) continue;
      final id = str(e, ['id']);
      final summary = _summaries[id] ?? <String, dynamic>{};
      out.add({
        'employee_id': id,
        'employee': e,
        'summary': summary,
        'rate': _rate(summary),
        'overtime': numOf(summary, ['overtime_hours']),
        'worked': numOf(summary, ['worked_days']),
        'absent': numOf(summary, ['absent_days']),
      });
    }
    out.sort((a, b) => numOf(b, ['rate']).compareTo(numOf(a, ['rate'])));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance'),
        actions: [
          AppExportButton(onExport: _export),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _employees.status,
            updatedAt: _employees.lastUpdated,
            label: 'Performance',
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
    _summaries.clear();
    await _employees.load(force: true);
    await _records.load(force: true);
    await _loadSummaries();
  }

  Widget _body() {
    if (_employees.phase == LoadPhase.failed && _employees.data == null) {
      return AppErrorState(
        message: _employees.error,
        onRetry: () => _employees.load(force: true),
      );
    }
    if (_employees.isLoading && _employees.data == null) {
      return const AppSkeletonList();
    }
    final scored = _scored;
    final withData = scored
        .where((r) =>
            numOf(r['summary'] as Map<String, dynamic>, ['worked_days']) > 0)
        .toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _filters(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.1,
            children: [
              AppStatCard(
                compact: true,
                label: 'Staff',
                value: Fmt.count(scored.length),
                icon: Icons.groups_outlined,
              ),
              AppStatCard(
                compact: true,
                label: 'Avg rate',
                value: Fmt.percent(
                  withData.isEmpty
                      ? 0
                      : withData
                              .map((r) => numOf(r, ['rate']))
                              .reduce((a, b) => a + b) /
                          withData.length,
                ),
                icon: Icons.speed_outlined,
              ),
              AppStatCard(
                compact: true,
                label: 'OT hours',
                value: Fmt.qty(scored.fold<double>(
                  0,
                  (sum, r) => sum + numOf(r, ['overtime']),
                )),
                icon: Icons.timer_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingSummaries && scored.isEmpty)
          const AppSkeletonList()
        else if (scored.isEmpty)
          const AppEmptyState(
            title: 'No active staff',
            message: 'Add employees to score attendance.',
            icon: Icons.insights_outlined,
          )
        else
          AppDataTable<Map<String, dynamic>>(
            rows: scored,
            onRowTap: (r) {
              final id = str(r, ['employee_id']);
              if (id.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EmployeeDetailPage(employeeId: id),
                ),
              );
            },
            emptyTitle: 'No scores',
            columns: [
              AppDataColumn(
                label: 'Employee',
                value: (r) =>
                    employeeName(r['employee'] as Map<String, dynamic>),
              ),
              AppDataColumn(
                label: 'Attendance',
                value: (r) => Fmt.percent(numOf(r, ['rate'])),
              ),
              AppDataColumn(
                label: 'Worked',
                value: (r) => Fmt.qty(numOf(r, ['worked'])),
              ),
              AppDataColumn(
                label: 'Absent',
                value: (r) => Fmt.qty(numOf(r, ['absent'])),
              ),
              AppDataColumn(
                label: 'Overtime',
                value: (r) => '${Fmt.qty(numOf(r, ['overtime']))} hrs',
              ),
            ],
            rowLeading: (context, r) => AppAvatar(
              name: employeeName(r['employee'] as Map<String, dynamic>),
              size: 32,
            ),
            rowTrailing: (context, r) => AppBadge(
              Fmt.percent(numOf(r, ['rate'])),
              tone: numOf(r, ['rate']) >= 90
                  ? AppTone.success
                  : numOf(r, ['rate']) >= 70
                      ? AppTone.warning
                      : AppTone.danger,
              compact: true,
            ),
          ),
      ],
    );
  }

  Widget _filters() => Container(
        color: context.c.surface,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: AppDateField(
                label: 'From',
                value: _from,
                lastDate: _to,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _from = v);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppDateField(
                label: 'To',
                value: _to,
                firstDate: _from,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _to = v);
                },
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              label: 'Score',
              variant: AppButtonVariant.secondary,
              loading: _loadingSummaries,
              onPressed: _loadingSummaries ? null : _refresh,
            ),
          ],
        ),
      );

  Future<void> _export() async {
    final scored = _scored;
    if (scored.isEmpty) {
      AppToast.warning(context, 'Nothing to export');
      return;
    }
    final buffer = StringBuffer(
        'employee,department,attendance_rate,worked,absent,overtime\n');
    for (final r in scored) {
      final e = r['employee'] as Map<String, dynamic>;
      buffer.writeln(
        '${employeeName(e)},${employeeDepartment(e)},${numOf(r, ['rate'])},'
        '${numOf(r, ['worked'])},${numOf(r, ['absent'])},${numOf(r, [
              'overtime'
            ])}',
      );
    }
    // The management API has no export route, so the sheet goes to the clipboard.
    await copyExport(context, buffer.toString(), 'Performance CSV');
  }
}
