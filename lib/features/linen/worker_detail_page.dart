import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/json.dart' as json;
import '../../core/models/worker.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../quotations/shared_widgets.dart';
import '_linen_shared.dart' show LinenDetailGrid;
import 'worker_form_page.dart';
import 'worker_payroll_page.dart';
import 'workers_page.dart';
import '../../ui/theme.dart';

/// Port of the worker profile in `features/workers/pages/workers-page.tsx`.
///
/// The workers service has no `GET /workers/{id}`, so the record is resolved
/// out of the list payload and the daily history comes from `/daily-logs`
/// filtered by name — the same two calls the web app makes.
class WorkerDetailPage extends StatefulWidget {
  const WorkerDetailPage({super.key, required this.workerId});

  final String workerId;

  @override
  State<WorkerDetailPage> createState() => _WorkerDetailPageState();
}

class _WorkerDetailPageState extends State<WorkerDetailPage> {
  late final ResourceController<Worker> _worker;
  late final ResourceController<List<DailyLog>> _logs;

  @override
  void initState() {
    super.initState();
    _worker = ResourceController(
      key: 'worker-${widget.workerId}',
      cache: AppScope.read(context).cache,
      fetcher: _fetchWorker,
    )..addListener(_onChanged);
    _logs = ResourceController(
      key: 'worker-logs-${widget.workerId}',
      cache: AppScope.read(context).cache,
      fetcher: _fetchLogs,
    )..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _worker.removeListener(_onChanged);
    _logs.removeListener(_onChanged);
    _worker.dispose();
    _logs.dispose();
    super.dispose();
  }

  Future<Worker> _fetchWorker() async {
    final services = AppScope.read(context);
    try {
      final payload = await services.api
          .get(ServiceNames.workers, '/workers/${widget.workerId}');
      return Worker.fromJson(json.asMap(payload));
    } on ApiException {
      // No single-worker endpoint on this service — fall back to the roster and
      // match by id, which is how the web app's detail view resolves too.
      final payload = await services.api.get(ServiceNames.workers, '/workers');
      final rows = json.unwrapList(payload).items;
      for (final row in rows) {
        final w = Worker.fromJson(row);
        if (w.id == widget.workerId) return w;
      }
      throw ApiException('Worker not found in the roster');
    }
  }

  Future<List<DailyLog>> _fetchLogs() async {
    final name = _worker.data?.workerName;
    if (name == null) return const [];
    final payload = await AppScope.read(context).api.get(
      ServiceNames.workers,
      '/daily-logs',
      query: {
        'worker_name': name,
        'skip': 0,
        'limit': 30,
      },
    );
    return json
        .unwrapList(payload)
        .items
        .where((row) => row['worker_name'] == name)
        .map(DailyLog.fromJson)
        .toList();
  }

  /// The log list is only fetched once the worker's name is known, so the
  /// fetcher is allowed to see whatever `_worker` resolved to.
  Future<void> _reload() async {
    await _worker.load(force: true);
    if (mounted && _worker.data != null) await _logs.load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final worker = _worker.data;
    final logs = _logs.data ?? const <DailyLog>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(worker?.workerName ?? 'Staff'),
        actions: [
          if (worker != null) ...[
            AppButton.icon(
              icon: Icons.payments_outlined,
              tooltip: 'Payroll',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WorkerPayrollPage(worker: worker),
                ),
              ),
            ),
            AppButton.icon(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              onPressed: _delete,
            ),
          ],
          AppButton.icon(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            loading: _worker.isLoading,
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _worker.status,
            updatedAt: _worker.lastUpdated,
            label: 'Staff record',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: _reload,
              child: _worker.phase == LoadPhase.failed && worker == null
                  ? AppErrorState(message: _worker.error, onRetry: _reload)
                  : _worker.isLoading && worker == null
                      ? const AppSkeletonList()
                      : worker == null
                          ? AppEmptyState(
                              title: 'Worker not found',
                              message:
                                  'This person is no longer on the roster.',
                              icon: Icons.person_off_outlined,
                            )
                          : _Body(
                              worker: worker,
                              logs: logs,
                              logsLoading: _logs.isLoading && logs.isEmpty,
                              onEdit: _edit,
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit() async {
    final worker = _worker.data;
    if (worker == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkerFormPage(workerId: worker.id),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _delete() async {
    final worker = _worker.data;
    if (worker == null) return;
    final removed = await deleteWorker(context, worker);
    if (!removed || !mounted) return;
    Navigator.of(context).pop();
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.worker,
    required this.logs,
    required this.logsLoading,
    required this.onEdit,
  });

  final Worker worker;
  final List<DailyLog> logs;
  final bool logsLoading;
  final VoidCallback onEdit;

  List<OpsMetric> get _metrics => [
        OpsMetric(
          id: 'days',
          label: 'Days logged',
          value: '${logs.length}',
          icon: Icons.event_available_outlined,
        ),
        OpsMetric(
          id: 'present',
          label: 'Present',
          value: '${logs.where((l) => l.attendanceStatus == 'PRESENT').length}',
          icon: Icons.check_circle_outline,
          tone: AppTone.success,
        ),
        OpsMetric(
          id: 'absent',
          label: 'Absent / leave',
          value: '${logs.where((l) => l.isAbsent).length}',
          icon: Icons.event_busy_outlined,
          tone: AppTone.danger,
        ),
        OpsMetric(
          id: 'ot',
          label: 'Overtime hrs',
          value: Fmt.qty(logs.fold<double>(0, (s, l) => s + l.overtimeHours)),
          icon: Icons.schedule_outlined,
          tone: AppTone.info,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        AppCard(
          child: Column(
            children: [
              AppAvatar(name: worker.workerName, size: 64),
              const SizedBox(height: 10),
              Text(worker.workerName, style: context.texts.titleMedium),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppBadge(
                    worker.departmentLabel,
                    tone: AppTone.info,
                    icon: Icons.apartment_outlined,
                  ),
                  const SizedBox(width: 6),
                  AppBadge(
                    worker.isActive ? 'Active' : 'Inactive',
                    tone: worker.isActive ? AppTone.success : AppTone.neutral,
                    icon: worker.isActive
                        ? Icons.check_circle_outline
                        : Icons.pause_circle_outline,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppButton(
                label: 'Edit details',
                icon: Icons.edit_outlined,
                variant: AppButtonVariant.primary,
                expand: true,
                onPressed: onEdit,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          title: 'Profile',
          child: LinenDetailGrid(
            entries: [
              ('Phone', worker.phone ?? '—'),
              ('Joined', Fmt.date(worker.joinedDate)),
              ('Department', worker.departmentLabel),
              ('Status', worker.isActive ? 'Active' : 'Inactive'),
            ],
          ),
        ),
        if (worker.notes != null && worker.notes!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          AppNotice(message: worker.notes!, tone: AppTone.neutral),
        ],
        const SizedBox(height: 10),
        CompactMetrics(items: _metrics),
        const SizedBox(height: 10),
        AppCard(
          title: 'Recent daily logs',
          trailing: Text(
            '${logs.length} shown',
            style: context.texts.labelSmall?.copyWith(color: c.fgMuted),
          ),
          child: logsLoading
              ? const AppSkeletonList(count: 3, lines: 1)
              : logs.isEmpty
                  ? AppEmptyState(
                      title: 'No logs yet',
                      message:
                          'Daily logs recorded against this person will show here.',
                      icon: Icons.event_note_outlined,
                      compact: true,
                    )
                  : Column(
                      children: [
                        for (final l in logs) _LogTile(log: l),
                      ],
                    ),
        ),
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final DailyLog log;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Icon(
              log.isAbsent
                  ? Icons.event_busy_outlined
                  : Icons.event_available_outlined,
              size: 18,
              color: log.isAbsent ? c.danger : c.success,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.date(log.workDate),
                    style: context.texts.bodyMedium?.copyWith(color: c.fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${log.attendanceLabel} · ${log.shiftLabel} · '
                    '${Fmt.qty(log.totalCounted)} counted',
                    style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
                  ),
                ],
              ),
            ),
            if (log.overtimeHours > 0)
              AppBadge(
                '+${Fmt.qty(log.overtimeHours)}h OT',
                tone: AppTone.warning,
                compact: true,
              ),
          ],
        ),
      ),
    );
  }
}
