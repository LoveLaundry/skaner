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
import 'employee_detail_page.dart';

/// There is no management leave endpoint, so the leave ledger is read from the
/// attendance collection: the web app's own leave states are
/// `PAID_LEAVE` / `UNPAID_LEAVE` (plus the legacy `ON_LEAVE`), and marking a
/// day in attendance-page.tsx is how leave is recorded there.
class LeavePage extends StatefulWidget {
  const LeavePage({super.key});

  @override
  State<LeavePage> createState() => _LeavePageState();
}

class _LeavePageState extends State<LeavePage> {
  late final ResourceController<List<Map<String, dynamic>>> _records;

  late DateTime _from;
  late DateTime _to;
  String _statusFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    final today = Fmt.lktNow();
    _from = DateTime(today.year, today.month, 1);
    _to = today;
    _records = ResourceController<List<Map<String, dynamic>>>(
      key: 'management.leave',
      cache: AppScope.read(context).cache,
      fetcher: () async {
        final s = AppScope.read(context);
        return asRows(await s.api.get(mgmt, '/api/attendance', query: {
          'start_date': Fmt.isoDate(_from),
          'end_date': Fmt.isoDate(_to),
          'limit': 200,
          'offset': 0,
        }));
      },
    )..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _records.load(force: true),
    );
  }

  @override
  void dispose() {
    _records.removeListener(_onChanged);
    _records.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get _leaveRows {
    final all = _records.data ?? const <Map<String, dynamic>>[];
    final out = all
        .where((r) =>
            kLeaveStatuses.contains(str(r, ['status'], '').toUpperCase()))
        .toList()
      ..sort((a, b) => (dateOf(b, ['date']) ?? DateTime(0))
          .compareTo(dateOf(a, ['date']) ?? DateTime(0)));
    if (_statusFilter == 'ALL') return out;
    return out
        .where((r) => str(r, ['status']).toUpperCase() == _statusFilter)
        .toList();
  }

  int _countOf(String status) {
    var n = 0;
    for (final r in _records.data ?? const <Map<String, dynamic>>[]) {
      if (str(r, ['status'], '').toUpperCase() == status) n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave'),
        actions: [
          AppExportButton(onExport: _export),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _records.status,
            updatedAt: _records.lastUpdated,
            label: 'Leave',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: () => _records.load(force: true),
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_records.phase == LoadPhase.failed && _records.data == null) {
      return AppErrorState(
        message: _records.error,
        onRetry: () => _records.load(force: true),
      );
    }
    if (_records.isLoading && _records.data == null) {
      return const AppSkeletonList();
    }
    final rows = _leaveRows;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
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
                label: 'Paid',
                value: Fmt.count(_countOf('PAID_LEAVE')),
                icon: Icons.beach_access_outlined,
              ),
              AppStatCard(
                compact: true,
                label: 'Unpaid',
                value: Fmt.count(_countOf('UNPAID_LEAVE')),
                icon: Icons.money_off_outlined,
              ),
              AppStatCard(
                compact: true,
                label: 'On leave',
                value: Fmt.count(_countOf('ON_LEAVE')),
                icon: Icons.event_busy_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const AppEmptyState(
            title: 'No leave in this range',
            message: 'Nobody has leave marked in the selected dates.',
            icon: Icons.beach_access_outlined,
          )
        else
          AppDataTable<Map<String, dynamic>>(
            rows: rows,
            emptyTitle: 'No leave in this range',
            columns: [
              AppDataColumn(
                label: 'Date',
                value: (r) => Fmt.date(pick(r, ['date', 'attendance_date'])),
              ),
              AppDataColumn(label: 'Employee', value: (r) => employeeName(r)),
              AppDataColumn(
                label: 'Department',
                value: (r) => employeeDepartment(r),
              ),
              AppDataColumn(
                label: 'Reason',
                value: (r) => str(r, ['notes', 'reason'], '—'),
              ),
            ],
            rowLeading: (context, r) => AppBadge(
              attendanceStatusLabel(str(r, ['status'])),
              tone: attendanceStatusTone(str(r, ['status'])),
              compact: true,
            ),
            rowTrailing: (context, r) {
              final id = str(r, ['employee_id']);
              return AppButton.icon(
                icon: Icons.chevron_right,
                tooltip: 'Open employee',
                size: AppButtonSize.iconSm,
                variant: AppButtonVariant.ghost,
                onPressed: id.isEmpty
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EmployeeDetailPage(employeeId: id),
                          ),
                        ),
              );
            },
          ),
      ],
    );
  }

  Widget _filters() => Container(
        color: context.c.surface,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AppDateField(
                    label: 'From',
                    value: _from,
                    lastDate: _to,
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _from = v);
                      _records.load(force: true);
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
                      _records.load(force: true);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AppSearchableSelect<String>(
              value: _statusFilter,
              searchable: false,
              clearable: false,
              options: [
                const AppSelectOption(value: 'ALL', label: 'All leave types'),
                for (final s in kLeaveStatuses)
                  AppSelectOption(value: s, label: attendanceStatusLabel(s)),
              ],
              onChanged: (v) => setState(() => _statusFilter = v ?? 'ALL'),
            ),
          ],
        ),
      );

  Future<void> _export() async {
    final rows = _leaveRows;
    if (rows.isEmpty) {
      AppToast.warning(context, 'Nothing to export in this range');
      return;
    }
    final buffer = StringBuffer('date,employee,department,status,reason\n');
    for (final r in rows) {
      buffer
        ..write('${Fmt.isoDate(pick(r, ['date', 'attendance_date']))},')
        ..write('${employeeName(r)},')
        ..write('${employeeDepartment(r)},')
        ..write('${str(r, ['status'])},')
        ..writeln(str(r, ['notes', 'reason']));
    }
    // The management API has no export route, so the sheet goes to the clipboard.
    await copyExport(context, buffer.toString(), 'Leave CSV');
  }
}
