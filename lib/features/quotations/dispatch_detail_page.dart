import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/sync_engine.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import 'bill_model.dart';
import 'print_paper.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Derived screen: the web app has no `dispatch-detail-page.tsx` — it shows a
/// job inside the `JobCard` on the dispatch board and edits it through a modal.
/// The mobile flow needs somewhere to land after tapping a card, so this screen
/// is that card's contents as a route: the same fields, the same
/// `PATCH /dispatch/{id}`, plus the printable job sheet a driver needs on the
/// road.
class DispatchDetailPage extends StatefulWidget {
  const DispatchDetailPage({super.key, required this.dispatchId});

  final String dispatchId;

  @override
  State<DispatchDetailPage> createState() => _DispatchDetailPageState();
}

class _DispatchDetailPageState extends State<DispatchDetailPage> {
  DispatchJob? _job;
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final payload = await AppScope.read(context)
          .api
          .get(operationsService, DispatchApi.one(widget.dispatchId));
      if (!mounted) return;
      setState(() {
        _job = DispatchJob.fromJson(Map<String, dynamic>.from(payload as Map));
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _patch(Map<String, dynamic> body) async {
    setState(() => _working = true);
    try {
      final result = await AppScope.read(context).api.patch(
          operationsService, DispatchApi.one(widget.dispatchId),
          body: body);
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate('dispatch');
      await _load();
      if (!mounted) return;
      setState(() => _working = false);
      AppToast.info(
        context,
        result is QueuedResponse
            ? 'Queued — will sync when back online'
            : 'Job updated',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      AppToast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, deliveriesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dispatch job')),
        body: opsNotPermitted('dispatch'),
      );
    }
    final job = _job;
    return Scaffold(
      appBar: AppBar(
        title: Text(job?.clientName ?? 'Dispatch job'),
        actions: [
          if (job != null)
            AppButton.icon(
              icon: Icons.print_outlined,
              tooltip: 'Job sheet',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => _JobSheet(dispatchId: widget.dispatchId),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const AppLoader()
          : _error != null
              ? AppErrorState(message: _error, onRetry: _load)
              : job == null
                  ? const AppEmptyState(
                      title: 'Job not found',
                      message: 'It may have been deleted.',
                      icon: Icons.local_shipping_outlined,
                    )
                  : RefreshIndicator(
                      color: context.c.brand,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          _header(job),
                          const SizedBox(height: 16),
                          _detailsCard(job),
                          const SizedBox(height: 16),
                          _statusCard(job),
                          const SizedBox(height: 16),
                          if (services.auth.hasPermission(deliveriesPermission))
                            _driverCard(job),
                        ],
                      ),
                    ),
    );
  }

  Widget _header(DispatchJob job) {
    final c = context.c;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OpsIcon(
            job.jobType == 'pickup'
                ? Icons.move_to_inbox_outlined
                : Icons.local_shipping_outlined,
            tone: job.jobType == 'pickup' ? AppTone.warning : AppTone.info,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.clientName.isEmpty ? '—' : job.clientName,
                  style: context.texts.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '${job.jobType == 'pickup' ? 'Pickup' : 'Delivery'} · '
                  '${Fmt.dateTime(job.scheduledAt)}',
                  style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
                ),
              ],
            ),
          ),
          DispatchStatusBadge(status: job.status),
        ],
      ),
    );
  }

  Widget _detailsCard(DispatchJob job) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Details', style: context.texts.titleSmall),
          const SizedBox(height: 8),
          OpsKeyValue(
            label: 'Address',
            value:
                (job.address ?? '').trim().isEmpty ? '—' : job.address!.trim(),
          ),
          OpsKeyValue(
            label: 'Contact',
            value: [
              (job.contactName ?? '').trim(),
              (job.contactPhone ?? '').trim(),
            ].where((s) => s.isNotEmpty).join(' · ').isEmpty
                ? '—'
                : [
                    (job.contactName ?? '').trim(),
                    (job.contactPhone ?? '').trim(),
                  ].where((s) => s.isNotEmpty).join(' · '),
          ),
          OpsKeyValue(
            label: 'Order',
            value: (job.orderId ?? '').isEmpty ? '—' : job.orderId!,
          ),
          if ((job.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(job.notes!.trim(), style: context.texts.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _statusCard(DispatchJob job) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status', style: context.texts.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in dispatchStatuses)
                if (s != job.status)
                  AppFilterChip(
                    label: humaniseStatus(s),
                    selected: false,
                    onTap: _working ? null : () => _patch({'status': s}),
                  ),
            ],
          ),
          if (!job.isOpen) ...[
            const SizedBox(height: 10),
            Text(
              'This job is closed and no longer advances.',
              style:
                  context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _driverCard(DispatchJob job) {
    final ctrl = TextEditingController(text: job.assignedTo ?? '');
    return StatefulBuilder(
      builder: (context, setLocal) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Assigned driver', style: context.texts.titleSmall),
            const SizedBox(height: 10),
            AppTextInput(
              controller: ctrl,
              hint: 'Driver name',
              onChanged: (_) => setLocal(() {}),
            ),
            const SizedBox(height: 10),
            AppButton(
              label: 'Save assignment',
              variant: AppButtonVariant.primary,
              loading: _working,
              onPressed: () async {
                final value = ctrl.text.trim();
                ctrl.dispose();
                await _patch({'assigned_to': value});
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The printable job sheet. Derived alongside the screen: the web app has no
/// dispatch print template, so this is the company letterhead plus the fields a
/// driver needs at the door.
class _JobSheet extends StatefulWidget {
  const _JobSheet({required this.dispatchId});

  final String dispatchId;

  @override
  State<_JobSheet> createState() => _JobSheetState();
}

class _JobSheetState extends State<_JobSheet> with OpsPrintMixin {
  DispatchJob? _job;
  bool _loading = true;
  String? _error;

  @override
  String get paperName => 'dispatch-${_job?.id ?? widget.dispatchId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final payload = await AppScope.read(context)
          .api
          .get(operationsService, DispatchApi.one(widget.dispatchId));
      if (!mounted) return;
      setState(() {
        _job = DispatchJob.fromJson(Map<String, dynamic>.from(payload as Map));
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, deliveriesPermission)) {
      return PaperPageScaffold(
        title: 'Job sheet',
        child: opsNotPermitted('dispatch'),
      );
    }
    final job = _job;
    return PaperPageScaffold(
      title: 'Job sheet',
      actions: job == null ? const [] : paperActions,
      child: _loading
          ? const AppLoader(label: 'Preparing print layout')
          : _error != null
              ? AppErrorState(message: _error, onRetry: _load)
              : job == null
                  ? const AppEmptyState(
                      title: 'Job not found',
                      message: 'It may have been deleted.',
                      icon: Icons.local_shipping_outlined,
                    )
                  : Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
                        child: RepaintBoundary(
                          key: paperKey,
                          child: PaperSheet(child: _sheet(job)),
                        ),
                      ),
                    ),
    );
  }

  Widget _sheet(DispatchJob job) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CompanyLetterhead(),
          const PaperRule(gap: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  job.jobType == 'pickup' ? 'PICKUP' : 'DELIVERY',
                  style: Paper.head.copyWith(
                    fontSize: 16,
                    letterSpacing: 2,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Job: ${Fmt.truncate(job.id, 8).toUpperCase()}',
                    style: Paper.body.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Status: ${humaniseStatus(job.status)}',
                    style: Paper.small,
                  ),
                ],
              ),
            ],
          ),
          const PaperRule(gap: 10),
          PaperField(label: 'Client', value: job.clientName),
          const SizedBox(height: 8),
          PaperField(label: 'Address', value: (job.address ?? '').trim()),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PaperField(
                  label: 'Contact',
                  value: [
                    (job.contactName ?? '').trim(),
                    (job.contactPhone ?? '').trim(),
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: PaperField(
                  label: 'Scheduled',
                  value: Fmt.dateTime(job.scheduledAt),
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PaperField(
            label: 'Assigned driver',
            value: (job.assignedTo ?? '').trim(),
          ),
          if ((job.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            PaperNote('Notes', job.notes!.trim()),
          ],
          const PaperRule(gap: 6),
          const PaperSignatureRow(
            labels: ['Driver', 'Received At Site', 'Authorized Signature'],
          ),
        ],
      );
}
