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

/// Port of `attendance-page.tsx` / `attendance-log-page.tsx`: a date-range sheet
/// for one employee with bulk marking, and an all-staff view for the range.
class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final ResourceController<List<Map<String, dynamic>>> _employees;
  late final ResourceController<List<Map<String, dynamic>>> _records;
  late final ResourceController<Map<String, dynamic>> _summary;

  late DateTime _from;
  late DateTime _to;
  String? _employeeId;
  String _statusFilter = 'ALL';
  final Set<String> _picked = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
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
    _records = ResourceController<List<Map<String, dynamic>>>(
      key: 'management.attendance',
      cache: cache,
      fetcher: _fetchRecords,
    );
    _summary = ResourceController<Map<String, dynamic>>(
      key: 'management.attendance.summary',
      cache: cache,
      fetcher: _fetchSummary,
    );
    for (final c in [_employees, _records, _summary]) {
      c.addListener(_onChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _employees.load(force: true);
      _reload();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_employees, _records, _summary]) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<List<Map<String, dynamic>>> _fetchRecords() async {
    final s = AppScope.read(context);
    final path = _employeeId == null
        ? '/api/attendance'
        : '/api/employees/$_employeeId/attendance';
    return asRows(await s.api.get(
      mgmt,
      path,
      query: {
        'start_date': Fmt.isoDate(_from),
        'end_date': Fmt.isoDate(_to),
      },
    ));
  }

  Future<Map<String, dynamic>> _fetchSummary() async {
    if (_employeeId == null) return <String, dynamic>{};
    final s = AppScope.read(context);
    final payload = await s.api.get(
      mgmt,
      '/api/attendance/summary',
      query: {
        'employee_id': _employeeId,
        'start_date': Fmt.isoDate(_from),
        'end_date': Fmt.isoDate(_to),
      },
    );
    return payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
  }

  void _reload() {
    _records.load(force: true);
    _summary.load(force: true);
  }

  List<Map<String, dynamic>> get _rows {
    final all = _records.data ?? const <Map<String, dynamic>>[];
    if (_statusFilter == 'ALL') return all;
    return all
        .where(
            (r) => str(r, ['status'], 'PRESENT').toUpperCase() == _statusFilter)
        .toList();
  }

  /// Days in the range, so bulk marking can offer the ones with no record.
  List<DateTime> get _days {
    final out = <DateTime>[];
    for (var d = _from; !d.isAfter(_to); d = d.add(const Duration(days: 1))) {
      out.add(d);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'My sheet'),
            Tab(text: 'All staff'),
          ],
        ),
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
            label: 'Attendance',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: Column(
              children: [
                _toolbar(),
                if (_tabs.index == 0) _summaryStrip(),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [_sheet(), _allStaff()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() => Container(
        color: context.c.surface,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                      _reload();
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
                      _reload();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppSearchableSelect<String>(
                    value: _employeeId ?? '',
                    hint: 'All employees',
                    searchable: true,
                    clearable: true,
                    options: [
                      for (final e
                          in _employees.data ?? const <Map<String, dynamic>>[])
                        AppSelectOption(
                          value: str(e, ['id']),
                          label: employeeName(e),
                          subtitle: str(e, ['employee_code'], ''),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _employeeId = v;
                        _picked.clear();
                      });
                      _reload();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppSearchableSelect<String>(
                    value: _statusFilter,
                    searchable: false,
                    clearable: false,
                    options: [
                      const AppSelectOption(
                          value: 'ALL', label: 'All statuses'),
                      for (final s in kAttendanceStatuses)
                        AppSelectOption(
                            value: s, label: attendanceStatusLabel(s)),
                    ],
                    onChanged: (v) =>
                        setState(() => _statusFilter = v ?? 'ALL'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _summaryStrip() {
    final s = _summary.data;
    if (s == null) return const SizedBox.shrink();
    final tiles = [
      (
        'Worked',
        intOf(s, ['worked_days']),
        Icons.how_to_reg_outlined,
        context.c.success
      ),
      (
        'Half',
        intOf(s, ['half_days']),
        Icons.timelapse_outlined,
        context.c.warning
      ),
      (
        'Paid leave',
        intOf(s, ['paid_leave_days']),
        Icons.beach_access_outlined,
        context.c.info
      ),
      (
        'Unpaid / absent',
        intOf(s, ['unpaid_leave_days']) + intOf(s, ['absent_days']),
        Icons.person_off_outlined,
        context.c.danger
      ),
      (
        'OT hrs',
        intOf(s, ['overtime_hours']),
        Icons.timer_outlined,
        context.c.brand
      ),
    ];
    return Container(
      color: context.c.surface,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: SizedBox(
        height: 62,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: tiles.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final (label, value, icon, colour) = tiles[i];
            return Container(
              width: 104,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.c.surface2,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: context.c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 13, color: colour),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelSmall
                              ?.copyWith(color: context.c.fgMuted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Fmt.count(value),
                    style:
                        context.texts.titleSmall?.copyWith(color: context.c.fg),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sheet() {
    if (_records.phase == LoadPhase.failed && _records.data == null) {
      return AppErrorState(
        message: _records.error,
        onRetry: () => _records.load(force: true),
      );
    }
    if (_records.isLoading && _records.data == null) {
      return const AppSkeletonList();
    }
    final rows = _rows;
    if (rows.isEmpty) {
      return AppEmptyState(
        title: 'No attendance in this range',
        message: 'Use the day buttons below to mark the days that are missing.',
        icon: Icons.event_available_outlined,
        action: AppButton(
          label: 'Reload',
          variant: AppButtonVariant.secondary,
          onPressed: () => _records.load(force: true),
        ),
      );
    }
    return RefreshIndicator(
      color: context.c.brand,
      onRefresh: () => _records.load(force: true),
      child: AppDataTable<Map<String, dynamic>>(
        rows: rows,
        onRowTap: (r) => _editRecord(r),
        emptyTitle: 'No attendance in this range',
        columns: [
          AppDataColumn(
            label: 'Date',
            value: (r) => Fmt.date(pick(r, ['date', 'attendance_date'])),
          ),
          AppDataColumn(
            label: 'Status',
            value: (r) => attendanceStatusLabel(str(r, ['status'])),
          ),
          AppDataColumn(
            label: 'OT',
            value: (r) => '${Fmt.qty(numOf(r, ['overtime_hours']))} hrs',
          ),
          AppDataColumn(
            label: 'Notes',
            value: (r) => str(r, ['notes'], '—'),
          ),
        ],
        rowLeading: (context, r) => AppBadge(
          attendanceStatusLabel(str(r, ['status'])),
          tone: attendanceStatusTone(str(r, ['status'])),
          compact: true,
        ),
        rowTrailing: (context, r) => numOf(r, ['overtime_hours']) > 0
            ? AppBadge(
                'OT ${Fmt.qty(numOf(r, ['overtime_hours']))}h',
                tone: AppTone.brand,
                compact: true,
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  /// One strip per day so a supervisor can bulk-mark a week in a few taps.
  Widget _allStaff() {
    if (_records.phase == LoadPhase.failed && _records.data == null) {
      return AppErrorState(
        message: _records.error,
        onRetry: () => _records.load(force: true),
      );
    }
    final days = _days;
    if (days.isEmpty) {
      return const AppEmptyState(
        title: 'Pick a range',
        message: 'Choose a from and to date to see the sheet.',
        icon: Icons.date_range_outlined,
      );
    }
    return RefreshIndicator(
      color: context.c.brand,
      onRefresh: () => _records.load(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          for (final d in days)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                onTap: () => _markDay(d),
                trailing: _picked.contains(Fmt.isoDate(d))
                    ? AppBadge('Picked', tone: AppTone.brand, compact: true)
                    : null,
                child: Row(
                  children: [
                    SizedBox(
                      width: 88,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Fmt.dateShort(d),
                            style: context.texts.bodyMedium
                                ?.copyWith(color: context.c.fg),
                          ),
                          Text(
                            Fmt.isoDate(d),
                            style: context.texts.labelSmall
                                ?.copyWith(color: context.c.fgFaint),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: _dayCounts(d)),
                  ],
                ),
              ),
            ),
          if (_picked.isNotEmpty) _bulkBar(),
        ],
      ),
    );
  }

  Widget _dayCounts(DateTime day) {
    final iso = Fmt.isoDate(day);
    final counts = <String, int>{};
    for (final r in _records.data ?? const <Map<String, dynamic>>[]) {
      if (Fmt.isoDate(pick(r, ['date', 'attendance_date'])) != iso) continue;
      final st = str(r, ['status'], 'PRESENT').toUpperCase();
      counts[st] = (counts[st] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      return Text(
        'Nothing marked',
        style: context.texts.bodySmall?.copyWith(color: context.c.fgFaint),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final e in counts.entries)
          AppBadge(
            '${attendanceStatusLabel(e.key)} ${e.value}',
            tone: attendanceStatusTone(e.key),
            compact: true,
          ),
      ],
    );
  }

  Widget _bulkBar() => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_picked.length} day(s) picked',
                      style: context.texts.bodyMedium
                          ?.copyWith(color: context.c.fg),
                    ),
                  ),
                  AppButton(
                    label: 'Clear',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    onPressed: () => setState(_picked.clear),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _bulkEditor(),
            ],
          ),
        ),
      );

  Widget _bulkEditor() {
    String status = 'PRESENT';
    double ot = 0;
    return StatefulBuilder(
      builder: (context, setInner) => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: AppSearchableSelect<String>(
                  value: status,
                  searchable: false,
                  clearable: false,
                  options: [
                    for (final s in kAttendanceStatuses)
                      AppSelectOption(
                          value: s, label: attendanceStatusLabel(s)),
                  ],
                  onChanged: (v) => setInner(() => status = v ?? 'PRESENT'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: AppNumberInput(
                  controller: TextEditingController(text: ot == 0 ? '' : '$ot'),
                  hint: 'OT hrs',
                  allowDecimal: true,
                  onChanged: (v) =>
                      setInner(() => ot = double.tryParse(v) ?? 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'Mark picked days',
            variant: AppButtonVariant.primary,
            block: true,
            loading: _busy,
            onPressed: _busy ? null : () => _bulkMark(status, ot),
          ),
        ],
      ),
    );
  }

  Future<void> _bulkMark(String status, double ot) async {
    final employee = _employeeId;
    if (employee == null) {
      AppToast.warning(context, 'Pick one employee to mark days for');
      return;
    }
    final services = AppScope.read(context);
    setState(() => _busy = true);
    // The bulk route takes one `dates` value per day, and the shared query
    // helper cannot repeat a key, so the query is written out here.
    final query = [
      'employee_id=${Uri.encodeQueryComponent(employee)}',
      'status=${Uri.encodeQueryComponent(status)}',
      if (ot > 0) 'overtime_hours=$ot',
      for (final d in _picked) 'dates=${Uri.encodeQueryComponent(d)}',
    ].join('&');
    final ok = await runMgmtWrite(
      context,
      () => services.api.post(mgmt, '/api/attendance/bulk?$query'),
      success: '${_picked.length} day(s) marked',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _picked.clear();
    });
    if (ok) _reload();
  }

  Future<void> _markDay(DateTime day) async {
    final iso = Fmt.isoDate(day);
    setState(() {
      if (!_picked.remove(iso)) _picked.add(iso);
    });
  }

  Future<void> _editRecord(Map<String, dynamic> row) async {
    String status = str(row, ['status'], 'PRESENT').toUpperCase();
    var ot = numOf(row, ['overtime_hours']);
    final changed = await AppDialog.show<bool>(
      context,
      title: Fmt.date(pick(row, ['date', 'attendance_date'])),
      body: StatefulBuilder(
        builder: (context, setInner) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSearchableSelect<String>(
              label: 'Status',
              value: status,
              searchable: false,
              clearable: false,
              options: [
                for (final s in kAttendanceStatuses)
                  AppSelectOption(value: s, label: attendanceStatusLabel(s)),
              ],
              onChanged: (v) => setInner(() => status = v ?? 'PRESENT'),
            ),
            const SizedBox(height: 10),
            AppNumberInput(
              controller: TextEditingController(text: ot == 0 ? '' : '$ot'),
              label: 'Overtime hours',
              allowDecimal: true,
              onChanged: (v) => setInner(() => ot = double.tryParse(v) ?? 0),
            ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Delete',
          variant: AppButtonVariant.dangerGhost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Save',
          variant: AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (changed == null || !mounted) return;
    final services = AppScope.read(context);
    final id = str(row, ['id']);
    if (changed == false) {
      final confirm = await AppConfirmDialog.show(
        context,
        title: 'Delete this record?',
        message: 'The day goes back to unmarked.',
        confirmLabel: 'Delete',
        destructive: true,
      );
      if (!confirm || !mounted) return;
      await runMgmtWrite(
        context,
        () => services.api.delete(mgmt, '/api/attendance/$id'),
        success: 'Record deleted',
      );
    } else {
      await runMgmtWrite(
        context,
        () => services.api.put(mgmt, '/api/attendance/$id',
            body: {'status': status, 'overtime_hours': ot}),
        success: 'Record updated',
      );
    }
    _reload();
  }

  Future<void> _export() async {
    final rows = _rows;
    if (rows.isEmpty) {
      AppToast.warning(context, 'Nothing to export in this range');
      return;
    }
    final buffer = StringBuffer('date,employee,status,overtime_hours,notes\n');
    for (final r in rows) {
      buffer
        ..write('${Fmt.isoDate(pick(r, ['date', 'attendance_date']))},')
        ..write('${employeeName(r)},')
        ..write('${str(r, ['status'])},')
        ..write('${numOf(r, ['overtime_hours'])},')
        ..writeln(str(r, ['notes']));
    }
    // The management API has no export route, so the sheet goes to the clipboard.
    await copyExport(context, buffer.toString(), 'Attendance CSV');
  }
}
