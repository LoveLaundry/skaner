import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/sync_engine.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'bill_model.dart';
import 'dispatch_detail_page.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Port of `pages/dispatch-page.tsx`.
///
/// Dispatch reuses the deliveries grant, exactly as the web sidebar does. The
/// list is a board rather than a document list: a job advances one step at a
/// time, and the next step is the only action that card offers.
class DispatchPage extends StatefulWidget {
  const DispatchPage({super.key});

  @override
  State<DispatchPage> createState() => _DispatchPageState();
}

class _DispatchPageState extends State<DispatchPage> {
  late final ResourceController<List<DispatchJob>> _jobs;

  String _statusFilter = '';
  String _typeFilter = '';

  @override
  void initState() {
    super.initState();
    _jobs = ResourceController(
      key: 'dispatch',
      cache: AppScope.read(context).cache,
      fetcher: _fetch,
    );
    _jobs.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _jobs.removeListener(_onChanged);
    _jobs.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<List<DispatchJob>> _fetch() async {
    final hotel = AppScope.read(context).hotels.queryParam;
    final payload = await AppScope.read(context).api.get(
      operationsService,
      DispatchApi.list,
      query: {
        if (hotel != null) 'client_name': hotel,
        if (_statusFilter.isNotEmpty) 'status': _statusFilter,
        if (_typeFilter.isNotEmpty) 'job_type': _typeFilter,
        'limit': 200,
      },
    );
    return dispatchJobsFrom(payload);
  }

  Future<void> _reload() => _jobs.load(force: true);

  List<OpsMetric> get _metrics {
    final all = _jobs.data ?? const <DispatchJob>[];
    return [
      OpsMetric(
        id: 'total',
        label: 'Jobs',
        value: '${all.length}',
        icon: Icons.local_shipping_outlined,
        tone: AppTone.info,
      ),
      OpsMetric(
        id: 'scheduled',
        label: 'Scheduled',
        value: '${all.where((j) => j.status == 'SCHEDULED').length}',
        icon: Icons.event_outlined,
        tone: AppTone.neutral,
      ),
      OpsMetric(
        id: 'enroute',
        label: 'En route',
        value: '${all.where((j) => j.status == 'EN_ROUTE').length}',
        icon: Icons.navigation_outlined,
        tone: AppTone.warning,
      ),
      OpsMetric(
        id: 'completed',
        label: 'Completed',
        value: '${all.where((j) => j.status == 'COMPLETED').length}',
        icon: Icons.check_circle_outline,
        tone: AppTone.success,
      ),
      OpsMetric(
        id: 'unassigned',
        label: 'Unassigned',
        value:
            '${all.where((j) => (j.assignedTo ?? '').isEmpty && j.isOpen).length}',
        icon: Icons.person_search_outlined,
        tone: AppTone.danger,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, deliveriesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dispatch')),
        body: opsNotPermitted('dispatch'),
      );
    }
    final canWrite = services.auth.hasPermission(deliveriesPermission);
    final all = _jobs.data ?? const <DispatchJob>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispatch & pickups'),
        actions: [
          AppButton.icon(
            icon: Icons.route_outlined,
            tooltip: 'Plan route',
            onPressed: _openRoutePlanner,
          ),
          AppButton.icon(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            loading: _jobs.isLoading,
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _jobs.status,
            updatedAt: _jobs.lastUpdated,
            label: 'Dispatch',
          ),
          AppOfflineSyncBar(engine: services.sync),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                for (final chip in _typeChips) ...[
                  AppFilterChip(
                    label: chip.$1,
                    selected: _typeFilter == chip.$2,
                    onTap: () {
                      setState(() => _typeFilter = chip.$2);
                      _reload();
                    },
                  ),
                  const SizedBox(width: 6),
                ],
                const SizedBox(width: 6),
                for (final chip in _statusChips) ...[
                  AppFilterChip(
                    label: chip.$1,
                    selected: _statusFilter == chip.$2,
                    onTap: () {
                      setState(() => _statusFilter = chip.$2);
                      _reload();
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          CompactMetrics(items: _metrics),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: _reload,
              child: _jobs.phase == LoadPhase.failed && all.isEmpty
                  ? AppErrorState(message: _jobs.error, onRetry: _reload)
                  : all.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.4,
                              child: AppEmptyState(
                                title: 'No dispatch jobs',
                                message:
                                    'Schedule a pickup or delivery to get started.',
                                icon: Icons.local_shipping_outlined,
                                action: canWrite
                                    ? AppButton(
                                        label: 'New job',
                                        variant: AppButtonVariant.primary,
                                        icon: Icons.add,
                                        onPressed: _openCreate,
                                      )
                                    : null,
                              ),
                            ),
                          ],
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 420,
                            mainAxisExtent: 190,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: all.length,
                          itemBuilder: (_, i) => _JobCard(
                            job: all[i],
                            canWrite: canWrite,
                            onOpen: () => _openDetail(all[i].id),
                            onAdvance: () => _advance(all[i]),
                            onAssign: (driver) =>
                                _update(all[i], {'assigned_to': driver}),
                            onCancel: () => _cancel(all[i]),
                            onDelete: () => _delete(all[i]),
                          ),
                        ),
            ),
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              backgroundColor: context.c.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New job'),
            )
          : null,
    );
  }

  static const List<(String, String)> _typeChips = [
    ('All types', ''),
    ('Pickups', 'pickup'),
    ('Deliveries', 'delivery'),
  ];

  static const List<(String, String)> _statusChips = [
    ('All statuses', ''),
    ('Scheduled', 'SCHEDULED'),
    ('Assigned', 'ASSIGNED'),
    ('En route', 'EN_ROUTE'),
    ('Completed', 'COMPLETED'),
    ('Cancelled', 'CANCELLED'),
  ];

  /// The job advances one step at a time; the web card offers exactly the next
  /// status, and offering anything else would let a job skip its own history.
  static String? nextStatus(String status) => switch (status) {
        'SCHEDULED' => 'ASSIGNED',
        'ASSIGNED' => 'EN_ROUTE',
        'EN_ROUTE' => 'COMPLETED',
        _ => null,
      };

  Future<void> _advance(DispatchJob job) async {
    final next = nextStatus(job.status);
    if (next == null) return;
    await _update(job, {'status': next});
  }

  Future<void> _update(DispatchJob job, Map<String, dynamic> body) async {
    try {
      final result = await AppScope.read(context)
          .api
          .patch(operationsService, DispatchApi.one(job.id), body: body);
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate('dispatch');
      await _reload();
      if (!mounted) return;
      AppToast.info(
        context,
        result is QueuedResponse
            ? 'Queued — will sync when back online'
            : 'Job updated',
      );
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    }
  }

  Future<void> _cancel(DispatchJob job) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Cancel this job?',
      message: 'The ${job.jobType} for ${job.clientName} will be cancelled.',
      confirmLabel: 'Cancel job',
      destructive: true,
    );
    if (ok && mounted) await _update(job, {'status': 'CANCELLED'});
  }

  Future<void> _delete(DispatchJob job) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Delete this job?',
      message: 'The job for ${job.clientName} will be removed permanently.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final result = await AppScope.read(context)
          .api
          .delete(operationsService, DispatchApi.one(job.id));
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate('dispatch');
      await _reload();
      if (!mounted) return;
      AppToast.info(
        context,
        result is QueuedResponse
            ? 'Queued — will sync when back online'
            : 'Job deleted',
      );
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _JobForm()),
    );
    if (created == true && mounted) _reload();
  }

  Future<void> _openRoutePlanner() async {
    final planned = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RoutePlannerSheet(),
    );
    if (planned == true && mounted) _reload();
  }

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => DispatchDetailPage(dispatchId: id)),
    );
    if (mounted) _reload();
  }
}

class _JobCard extends StatefulWidget {
  const _JobCard({
    required this.job,
    required this.canWrite,
    required this.onOpen,
    required this.onAdvance,
    required this.onAssign,
    required this.onCancel,
    required this.onDelete,
  });

  final DispatchJob job;
  final bool canWrite;
  final VoidCallback onOpen;
  final VoidCallback onAdvance;
  final ValueChanged<String> onAssign;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  State<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<_JobCard> {
  late final TextEditingController _driver =
      TextEditingController(text: widget.job.assignedTo ?? '');
  bool _dirty = false;

  DispatchJob get job => widget.job;

  @override
  void dispose() {
    _driver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final next = _DispatchPageState.nextStatus(job.status);
    return AppCard(
      onTap: widget.onOpen,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OpsIcon(
                job.jobType == 'pickup'
                    ? Icons.move_to_inbox_outlined
                    : Icons.local_shipping_outlined,
                tone: job.jobType == 'pickup' ? AppTone.warning : AppTone.info,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.clientName.isEmpty ? '—' : job.clientName,
                      style: context.texts.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      Fmt.dateTime(job.scheduledAt),
                      style:
                          context.texts.bodySmall?.copyWith(color: c.fgMuted),
                    ),
                  ],
                ),
              ),
              DispatchStatusBadge(status: job.status),
            ],
          ),
          const SizedBox(height: 8),
          if ((job.address ?? '').trim().isNotEmpty)
            _line(context, Icons.place_outlined, job.address!),
          if ((job.contactName ?? '').trim().isNotEmpty ||
              (job.contactPhone ?? '').trim().isNotEmpty)
            _line(
              context,
              Icons.person_outline,
              [
                (job.contactName ?? '').trim(),
                (job.contactPhone ?? '').trim(),
              ].where((s) => s.isNotEmpty).join(' · '),
            ),
          if (widget.canWrite) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: AppTextInput(
                    controller: _driver,
                    hint: 'Assign driver',
                    onChanged: (v) => setState(() =>
                        _dirty = v.trim() != (job.assignedTo ?? '').trim()),
                  ),
                ),
                const SizedBox(width: 6),
                AppButton(
                  label: 'Assign',
                  size: AppButtonSize.xs,
                  variant: AppButtonVariant.outline,
                  onPressed: _dirty
                      ? () => widget.onAssign(_driver.text.trim())
                      : null,
                ),
              ],
            ),
          ] else
            _line(
              context,
              Icons.badge_outlined,
              (job.assignedTo ?? '').trim().isEmpty
                  ? 'Unassigned'
                  : job.assignedTo!.trim(),
            ),
          const Spacer(),
          Row(
            children: [
              if (widget.canWrite && next != null)
                AppButton(
                  label: 'Mark ${humaniseStatus(next).toLowerCase()}',
                  size: AppButtonSize.xs,
                  variant: AppButtonVariant.primary,
                  onPressed: widget.onAdvance,
                )
              else
                AppButton(
                  label: 'Open',
                  size: AppButtonSize.xs,
                  variant: AppButtonVariant.ghost,
                  onPressed: widget.onOpen,
                ),
              const Spacer(),
              if (widget.canWrite && job.isOpen)
                AppButton.icon(
                  icon: Icons.block,
                  tooltip: 'Cancel job',
                  size: AppButtonSize.iconSm,
                  onPressed: widget.onCancel,
                ),
              if (widget.canWrite)
                AppButton.icon(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete',
                  size: AppButtonSize.iconSm,
                  variant: AppButtonVariant.dangerGhost,
                  onPressed: widget.onDelete,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 13, color: context.c.fgFaint),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
              ),
            ),
          ],
        ),
      );
}

/// The new-job form, from the web app's `NewJobModal`.
class _JobForm extends StatefulWidget {
  const _JobForm();

  @override
  State<_JobForm> createState() => _JobFormState();
}

class _JobFormState extends State<_JobForm> {
  final _clientCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _driverCtrl = TextEditingController();

  String _type = 'delivery';
  String _assignedTo = '';
  DateTime _scheduledAt = DateTime.now();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _clientCtrl.text = AppScope.read(context).hotels.selectedHotel;
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _addressCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    _driverCtrl.dispose();
    super.dispose();
  }

  bool get _valid => _clientCtrl.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_valid) return;
    setState(() => _saving = true);
    final job = DispatchJob(
      jobType: _type,
      clientName: _clientCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      contactName: _contactCtrl.text.trim(),
      contactPhone: _phoneCtrl.text.trim(),
      scheduledAt: Fmt.isoDateTime(_scheduledAt),
      status: 'SCHEDULED',
      assignedTo: _assignedTo,
      notes: _notesCtrl.text.trim(),
    );
    try {
      final result = await AppScope.read(context)
          .api
          .post(operationsService, DispatchApi.list, body: job.toJson());
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate('dispatch');
      Navigator.of(context).pop(true);
      AppToast.success(
        context,
        result is QueuedResponse
            ? 'Saved — will sync when back online'
            : 'Job scheduled',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, deliveriesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('New job')),
        body: opsNotPermitted('dispatch'),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('New dispatch job')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          AppField(
            label: 'Job type',
            required: true,
            child: AppSearchableSelect<String>(
              value: _type,
              searchable: false,
              options: const [
                AppSelectOption<String>(value: 'delivery', label: 'Delivery'),
                AppSelectOption<String>(value: 'pickup', label: 'Pickup'),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'delivery'),
            ),
          ),
          const SizedBox(height: 12),
          AppField(
            label: 'Client',
            required: true,
            child: AppTextInput(
              controller: _clientCtrl,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          AppField(
            label: 'Address',
            optional: true,
            child: AppTextInput(controller: _addressCtrl, maxLines: 2),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppField(
                  label: 'Contact name',
                  optional: true,
                  child: AppTextInput(controller: _contactCtrl),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppField(
                  label: 'Contact phone',
                  optional: true,
                  child: AppTextInput(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppField(
            label: 'Scheduled for',
            required: true,
            child: AppDateField(
              value: _scheduledAt,
              onChanged: (d) {
                if (d != null) setState(() => _scheduledAt = d);
              },
            ),
          ),
          const SizedBox(height: 12),
          AppField(
            label: 'Assigned to',
            optional: true,
            child: AppTextInput(
              controller: _driverCtrl,
              onChanged: (v) => setState(() => _assignedTo = v),
            ),
          ),
          const SizedBox(height: 12),
          AppField(
            label: 'Notes',
            optional: true,
            child: AppTextInput(controller: _notesCtrl, maxLines: 3),
          ),
          const SizedBox(height: 20),
          AppButton(
            label: 'Schedule job',
            variant: AppButtonVariant.primary,
            block: true,
            loading: _saving,
            onPressed: _valid ? _save : null,
          ),
        ],
      ),
    );
  }
}

/// The web app's `RoutePlannerModal`: a driver, an optional date, and the
/// ordered stop list the server returns from `POST /dispatch/optimize`.
class _RoutePlannerSheet extends StatefulWidget {
  const _RoutePlannerSheet();

  @override
  State<_RoutePlannerSheet> createState() => _RoutePlannerSheetState();
}

class _RoutePlannerSheetState extends State<_RoutePlannerSheet> {
  final _driverCtrl = TextEditingController();
  DateTime? _date;
  RoutePlan? _plan;
  bool _planning = false;

  @override
  void dispose() {
    _driverCtrl.dispose();
    super.dispose();
  }

  Future<void> _runPlan() async {
    final driver = _driverCtrl.text.trim();
    if (driver.isEmpty) return;
    setState(() => _planning = true);
    try {
      final payload = await AppScope.read(context).api.post(
        operationsService,
        DispatchApi.optimize,
        body: {
          'assigned_to': driver,
          if (_date != null) 'date': Fmt.isoDate(_date),
        },
      );
      if (!mounted) return;
      setState(() {
        _plan = RoutePlan.fromJson(
          Map<String, dynamic>.from(payload as Map),
        );
        _planning = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _planning = false);
      AppToast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = _plan?.stops ?? const <DispatchJob>[];
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plan driver route', style: context.texts.titleMedium),
            const SizedBox(height: 14),
            AppField(
              label: 'Driver',
              required: true,
              child: AppTextInput(
                controller: _driverCtrl,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 12),
            AppField(
              label: 'Date',
              optional: true,
              child: AppDateField(
                value: _date,
                onChanged: (d) => setState(() => _date = d),
              ),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'Plan route',
              variant: AppButtonVariant.primary,
              block: true,
              loading: _planning,
              onPressed: _driverCtrl.text.trim().isEmpty ? null : _runPlan,
            ),
            if (stops.isNotEmpty) ...[
              const SizedBox(height: 16),
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${stops.length} ${stops.length == 1 ? 'stop' : 'stops'}',
                      style: context.texts.titleSmall,
                    ),
                    const SizedBox(height: 10),
                    for (var i = 0; i < stops.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StopIndex(index: i + 1),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stops[i].clientName.isEmpty
                                      ? '—'
                                      : stops[i].clientName,
                                  style: context.texts.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  [
                                    stops[i].jobType == 'pickup'
                                        ? 'Pickup'
                                        : 'Delivery',
                                    (stops[i].address ?? '').trim(),
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  style: context.texts.bodySmall?.copyWith(
                                    color: context.c.fgMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            AppButton(
              label: 'Done',
              variant: AppButtonVariant.ghost,
              block: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopIndex extends StatelessWidget {
  const _StopIndex({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.c.brand,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$index',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
