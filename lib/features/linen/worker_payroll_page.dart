import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/models/json.dart' as json;
import '../../core/models/worker.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '_linen_shared.dart' show LinenDetailGrid;
import '../../ui/theme.dart';

/// Payroll view for the team.
///
/// The workers service has no salary, wage or payslip route — `worker.service.ts`
/// only exposes the roster, the daily logs and the daily summary — so there is
/// nothing to show a figure from. Rather than invent an endpoint, this screen
/// reports what the service *can* answer: the attendance and output the payroll
/// would be calculated from. When a worker is passed in, the same figures are
/// narrowed to that person.
class WorkerPayrollPage extends StatefulWidget {
  const WorkerPayrollPage({super.key, this.worker});

  final Worker? worker;

  @override
  State<WorkerPayrollPage> createState() => _WorkerPayrollPageState();
}

class _WorkerPayrollPageState extends State<WorkerPayrollPage> {
  late final ResourceController<List<DailyLog>> _logs;

  @override
  void initState() {
    super.initState();
    _logs = ResourceController(
      key: 'worker-payroll-${widget.worker?.id ?? 'all'}',
      cache: AppScope.read(context).cache,
      fetcher: _fetch,
    )..addListener(_onChanged);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _logs.load(force: true));
  }

  @override
  void dispose() {
    _logs.removeListener(_onChanged);
    _logs.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<List<DailyLog>> _fetch() async {
    final name = widget.worker?.workerName;
    final payload = await AppScope.read(context).api.get(
      ServiceNames.workers,
      '/daily-logs',
      query: {
        if (name != null) 'worker_name': name,
        'skip': 0,
        'limit': 200,
      },
    );
    final rows = json.unwrapList(payload).items;
    return rows
        .where((row) => name == null || row['worker_name'] == name)
        .map(DailyLog.fromJson)
        .toList();
  }

  double _sum(List<DailyLog> logs, double Function(DailyLog) pick) =>
      logs.fold<double>(0, (sum, l) => sum + pick(l));

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    final logs = _logs.data ?? const <DailyLog>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.worker == null
            ? 'Staff payroll'
            : '${widget.worker!.workerName} · payroll'),
        actions: [
          AppButton.icon(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            loading: _logs.isLoading,
            onPressed: () => _logs.load(force: true),
          ),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _logs.status,
            updatedAt: _logs.lastUpdated,
            label: 'Payroll inputs',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: c.brand,
              onRefresh: () => _logs.load(force: true),
              child: _logs.phase == LoadPhase.failed && logs.isEmpty
                  ? AppErrorState(
                      message: _logs.error,
                      onRetry: () => _logs.load(force: true),
                    )
                  : _logs.isLoading && logs.isEmpty
                      ? const AppSkeletonList()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                          children: [
                            const AppNotice(
                              title: 'Salary figures are not served',
                              message:
                                  'This backend keeps the roster, daily logs and the '
                                  'daily summary, but no wage or payslip records. The '
                                  'figures below are the attendance and output a '
                                  'payroll run would be built from.',
                              tone: AppTone.info,
                            ),
                            const SizedBox(height: 10),
                            if (logs.isEmpty)
                              AppEmptyState(
                                title: 'No payroll inputs yet',
                                message: widget.worker == null
                                    ? 'Record daily logs against staff and they will '
                                        'be summarised here.'
                                    : 'No daily logs have been recorded for '
                                        '${widget.worker!.workerName} yet.',
                                icon: Icons.payments_outlined,
                              )
                            else ...[
                              AppCard(
                                title: 'Period totals',
                                child: LinenDetailGrid(
                                  entries: [
                                    ('Log entries', '${logs.length}'),
                                    (
                                      'Distinct staff',
                                      '${logs.map((l) => l.workerName).toSet().length}'
                                    ),
                                    (
                                      'Present days',
                                      '${_count(logs, 'PRESENT')}'
                                    ),
                                    (
                                      'Half days',
                                      '${_count(logs, 'HALF_DAY')}'
                                    ),
                                    ('Absent', '${_count(logs, 'ABSENT')}'),
                                    ('On leave', '${_count(logs, 'ON_LEAVE')}'),
                                    (
                                      'Overtime hours',
                                      Fmt.qty(
                                          _sum(logs, (l) => l.overtimeHours))
                                    ),
                                    (
                                      'Pieces counted',
                                      Fmt.qty(_sum(logs, (l) => l.totalCounted))
                                    ),
                                    (
                                      'Weight (kg)',
                                      Fmt.qty(
                                          _sum(logs, (l) => l.totalWeightKg))
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              AppCard(
                                title: 'By person',
                                child: Column(
                                  children: [
                                    for (final roll in _byPerson(logs))
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          children: [
                                            AppAvatar(
                                                name: roll.name, size: 30),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                roll.name,
                                                style: context.texts.bodyMedium
                                                    ?.copyWith(color: c.fg),
                                              ),
                                            ),
                                            Text(
                                              '${roll.days} days · '
                                              '${Fmt.qty(roll.overtime)}h OT',
                                              style: context.texts.bodySmall
                                                  ?.copyWith(color: c.fgMuted),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
  }

  static int _count(List<DailyLog> logs, String status) =>
      logs.where((l) => l.attendanceStatus == status).length;

  /// One line per person: the days they logged and the overtime they claimed,
  /// which is the pair a supervisor would need before touching a wage.
  static List<_PersonRoll> _byPerson(List<DailyLog> logs) {
    final out = <String, _PersonRoll>{};
    for (final l in logs) {
      final roll =
          out.putIfAbsent(l.workerName, () => _PersonRoll(l.workerName));
      roll.days++;
      roll.overtime += l.overtimeHours;
    }
    return out.values.toList()..sort((a, b) => b.days.compareTo(a.days));
  }
}

class _PersonRoll {
  _PersonRoll(this.name);

  final String name;
  int days = 0;
  double overtime = 0;
}
