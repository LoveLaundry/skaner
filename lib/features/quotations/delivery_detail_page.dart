import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/sync_engine.dart';
import '../../core/models/json.dart' show asMapList;
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart' show intOf;
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import 'bill_model.dart';
import 'delivery_form_page.dart';
import 'delivery_slips_page.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Shared by every date correction in the feature, matching
/// `lib/date-corrections.ts` in the web app.
const List<String> dateCorrectionReasons = [
  'WRONG_DATE_ENTERED',
  'RECORDING_ERROR',
  'CLIENT_DELAYED',
  'DATA_MIGRATION',
  'OTHER',
];

/// Port of `pages/delivery-detail-page.tsx`.
///
/// The balance call is what makes this page honest: a delivery can draw lines
/// from several gate passes, so only the server knows what each pass looks like
/// afterwards. Everything about outstanding linen here is read from that
/// response.
class DeliveryDetailPage extends StatefulWidget {
  const DeliveryDetailPage({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  State<DeliveryDetailPage> createState() => _DeliveryDetailPageState();
}

class _DeliveryDetailPageState extends State<DeliveryDetailPage> {
  Delivery? _delivery;
  Map<String, dynamic> _balance = const {};
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
    final api = AppScope.read(context).api;
    try {
      final results = await Future.wait([
        api.get(operationsService, DeliveryApi.one(widget.deliveryId)),
        api.get(operationsService, DeliveryApi.balance(widget.deliveryId)),
      ]);
      if (!mounted) return;
      setState(() {
        _delivery =
            Delivery.fromJson(Map<String, dynamic>.from(results[0] as Map));
        _balance = Map<String, dynamic>.from(results[1] as Map? ?? const {});
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

  Future<void> _run(Future<Object?> Function() action, String success) async {
    setState(() => _working = true);
    try {
      final result = await action();
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate('deliveries');
      QueryCacheInvalidator.instance.invalidate('gatepasses');
      await _load();
      if (!mounted) return;
      setState(() => _working = false);
      AppToast.info(
        context,
        result is QueuedResponse
            ? 'Queued — will sync when back online'
            : success,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      AppToast.error(context, e.message);
    }
  }

  Future<void> _cancel(String reason) => _run(
        () => AppScope.read(context).api.post(
          operationsService,
          DeliveryApi.cancel(widget.deliveryId),
          body: {'reason': reason},
        ),
        'Delivery cancelled',
      );

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, deliveriesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Delivery')),
        body: opsNotPermitted('deliveries'),
      );
    }
    final d = _delivery;
    return Scaffold(
      appBar: AppBar(
        title: Text(d?.clientName ?? 'Delivery'),
        actions: [
          if (d != null)
            Row(
              children: [
                AppButton.icon(
                  icon: Icons.print_outlined,
                  tooltip: 'Print slip',
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => DeliverySlipsPage(deliveryId: d.id),
                    ),
                  ),
                ),
                if (!d.isCancelled)
                  AppButton.icon(
                    icon: Icons.edit_outlined,
                    tooltip: 'Correct quantities',
                    onPressed: _working
                        ? null
                        : () async {
                            final saved =
                                await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) =>
                                    DeliveryFormPage(deliveryId: d.id),
                              ),
                            );
                            if (saved == true && mounted) _load();
                          },
                  ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const AppLoader()
          : _error != null
              ? AppErrorState(message: _error, onRetry: _load)
              : d == null
                  ? const AppEmptyState(
                      title: 'Delivery not found',
                      message: 'It may have been removed.',
                      icon: Icons.local_shipping_outlined,
                    )
                  : RefreshIndicator(
                      color: context.c.brand,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          _header(d),
                          const SizedBox(height: 16),
                          _itemsCard(d),
                          const SizedBox(height: 16),
                          if (d.corrections.isNotEmpty) ...[
                            _correctionsCard(d),
                            const SizedBox(height: 16),
                          ],
                          _sourcePassesCard(d),
                          const SizedBox(height: 16),
                          _actionsCard(d),
                        ],
                      ),
                    ),
    );
  }

  Widget _header(Delivery d) {
    final c = context.c;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OpsIcon(Icons.local_shipping_outlined,
                  tone: AppTone.success),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'DLV-${d.id.length > 8 ? d.id.substring(d.id.length - 8).toUpperCase() : d.id.toUpperCase()}',
                        style: context.texts.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      d.clientName,
                      style:
                          context.texts.bodySmall?.copyWith(color: c.fgMuted),
                    ),
                  ],
                ),
              ),
              DeliveryStatusBadge(status: deriveDeliveryStatus(d)),
            ],
          ),
          const SizedBox(height: 12),
          OpsKeyValue(label: 'Delivery date', value: Fmt.date(d.deliveryDate)),
          OpsKeyValue(
            label: 'Delivered by',
            value: d.deliveredBy.isEmpty ? '—' : d.deliveredBy,
          ),
          OpsKeyValue(
            label: 'Received by',
            value: d.receivedBy.isEmpty ? '—' : d.receivedBy,
          ),
          OpsKeyValue(
            label: 'Source gate passes',
            value: d.sources.isEmpty ? '—' : '${d.sources.length}',
          ),
          if ((d.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(d.notes!.trim(), style: context.texts.bodySmall),
          ],
          if (d.isCancelled) ...[
            const SizedBox(height: 12),
            AppNotice(
              title: 'Cancelled',
              message: [
                if (d.cancelledReason.trim().isNotEmpty)
                  d.cancelledReason.trim(),
                if (d.cancelledAt != null) Fmt.dateTime(d.cancelledAt),
                if (d.cancelledBy.isNotEmpty) 'by ${d.cancelledBy}',
              ].join(' · '),
              tone: AppTone.danger,
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemsCard(Delivery d) {
    final c = context.c;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Items delivered', style: context.texts.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${d.lineCount} types · ${Fmt.qty(d.totalPieces)} pieces',
            style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
          ),
          const SizedBox(height: 10),
          if (d.items.isEmpty)
            const AppEmptyState(
              title: 'No items',
              message: 'This delivery has no counted lines.',
              icon: Icons.inventory_2_outlined,
              compact: true,
            )
          else
            for (final line in d.items) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.specification.isEmpty
                              ? line.itemName
                              : '${line.itemName} — ${line.specification}',
                          style: context.texts.bodyMedium,
                        ),
                        if (line.clientCountedQty != null)
                          Text(
                            'Hotel counted ${Fmt.qty(line.clientCountedQty)}'
                            '${line.discrepancy != null && line.discrepancy != 0 ? ' · diff ${line.discrepancy}' : ''}',
                            style: context.texts.bodySmall?.copyWith(
                              color: (line.discrepancy ?? 0) != 0
                                  ? c.warning
                                  : c.fgMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(Fmt.qty(line.quantity), style: context.texts.bodyMedium),
                ],
              ),
              if (line != d.items.last) const Divider(height: 14),
            ],
        ],
      ),
    );
  }

  Widget _correctionsCard(Delivery d) {
    final c = context.c;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Correction history', style: context.texts.titleSmall),
          const SizedBox(height: 2),
          Text(
            'Original quantities are never destroyed, so what was first recorded '
            'stays on the record.',
            style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
          ),
          const SizedBox(height: 10),
          for (final correction in d.corrections) ...[
            Text(
              '${Fmt.dateTime(correction.correctedAt)} · '
              '${correction.correctedBy.isEmpty ? '—' : correction.correctedBy}',
              style: context.texts.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (correction.reason.trim().isNotEmpty)
              Text(
                correction.reason,
                style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
              ),
            const SizedBox(height: 4),
            for (final change in correction.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${change.itemName}${change.specification.isEmpty ? '' : ' — ${change.specification}'}: '
                  '${change.originalQuantity} → ${change.correctedQuantity} '
                  '(${change.delta > 0 ? '+' : ''}${change.delta})',
                  style: context.texts.bodySmall,
                ),
              ),
            if (correction != d.corrections.last) const Divider(height: 16),
          ],
        ],
      ),
    );
  }

  /// The resulting balance of every pass this delivery touched. The point of
  /// the endpoint is that one call answers "what did we record, and what now
  /// remains on each source pass".
  Widget _sourcePassesCard(Delivery d) {
    final c = context.c;
    final passes = asMapList(_balance['source_gate_passes']);
    if (passes.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Source gate passes after this delivery',
              style: context.texts.titleSmall),
          const SizedBox(height: 10),
          for (final p in passes) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    p['gate_pass_number']?.toString() ??
                        p['gate_pass_id']?.toString() ??
                        '—',
                    style: context.texts.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                GatePassStatusBadge(
                  status: (p['derived_status'] ?? p['status'] ?? '').toString(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Builder(
              builder: (_) {
                final totals = Map<String, dynamic>.from(
                  p['totals'] as Map? ?? const {},
                );
                return Wrap(
                  spacing: 14,
                  runSpacing: 2,
                  children: [
                    _stat(c, 'Outstanding',
                        intOf(totals, const ['outstanding_delivery_qty'])),
                    _stat(
                        c, 'Delivered', intOf(totals, const ['delivered_qty'])),
                    _stat(c, 'Returned',
                        intOf(totals, const ['returned_back_qty'])),
                  ],
                );
              },
            ),
            if (p != passes.last) const Divider(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _stat(AppColors c, String label, int value) => Text(
        '$label ${Fmt.qty(value)}',
        style: TextStyle(
          fontSize: 12,
          color: c.fgMuted,
          fontWeight: FontWeight.w500,
        ),
      );

  Widget _actionsCard(Delivery d) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Actions', style: context.texts.titleSmall),
          const SizedBox(height: 10),
          if (!d.isCancelled) ...[
            AppButton(
              label: 'Correct delivery date',
              variant: AppButtonVariant.secondary,
              icon: Icons.event_outlined,
              onPressed: _working ? null : _openDateEdit,
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'Cancel this delivery',
              variant: AppButtonVariant.danger,
              icon: Icons.block,
              onPressed: _working ? null : _openCancel,
            ),
            const SizedBox(height: 6),
            Text(
              'Cancelling releases the quantities back to the source passes.',
              style:
                  context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
            ),
          ] else
            Text(
              'A cancelled delivery cannot be edited.',
              style:
                  context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
            ),
        ],
      ),
    );
  }

  Future<void> _openDateEdit() async {
    final d = _delivery;
    if (d == null) return;
    final result = await showDialog<_DateRequest>(
      context: context,
      builder: (_) => _DateDialog(date: d.deliveryDate),
    );
    if (result == null || !mounted) return;
    await _run(
      () => AppScope.read(context).api.patch(
        operationsService,
        DeliveryApi.date(widget.deliveryId),
        body: {
          'delivery_date': isoDateOf(Fmt.isoDate(result.date)),
          'reason': result.reason,
        },
      ),
      'Delivery date corrected',
    );
  }

  Future<void> _openCancel() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Cancel this delivery',
        icon: Icons.block,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppNotice(
              message:
                  'The delivered quantities go back onto their source gate '
                  'passes as outstanding. The record is kept, not deleted.',
              tone: AppTone.warning,
            ),
            const SizedBox(height: 14),
            AppField(
              label: 'Reason',
              required: true,
              child: AppTextInput(controller: ctrl),
            ),
          ],
        ),
        actions: [
          AppButton(
            label: 'Keep delivery',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          AppButton(
            label: 'Cancel delivery',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(ctrl.text.trim()),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    await _cancel(reason);
  }
}

class _DateRequest {
  const _DateRequest({required this.date, required this.reason});

  final DateTime date;
  final String reason;
}

class _DateDialog extends StatefulWidget {
  const _DateDialog({required this.date});

  final String? date;

  @override
  State<_DateDialog> createState() => _DateDialogState();
}

class _DateDialogState extends State<_DateDialog> {
  final _reasonCtrl = TextEditingController();
  late DateTime _date = Fmt.parseDate(widget.date) ?? Fmt.lktNow();
  String _reason = '';

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
        title: 'Correct delivery date',
        icon: Icons.event_outlined,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppField(
              label: 'Delivery date',
              required: true,
              child: AppDateField(
                value: _date,
                onChanged: (d) {
                  if (d != null) setState(() => _date = d);
                },
              ),
            ),
            const SizedBox(height: 12),
            AppField(
              label: 'Reason',
              optional: true,
              child: AppSearchableSelect<String>(
                value: _reason.isEmpty ? null : _reason,
                searchable: false,
                options: [
                  for (final r in dateCorrectionReasons)
                    AppSelectOption<String>(value: r, label: humaniseStatus(r)),
                ],
                onChanged: (v) => setState(() => _reason = v ?? ''),
              ),
            ),
            const SizedBox(height: 12),
            AppField(
              label: 'Notes',
              optional: true,
              child: AppTextInput(controller: _reasonCtrl),
            ),
          ],
        ),
        actions: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppButton(
            label: 'Save',
            variant: AppButtonVariant.primary,
            onPressed: () => Navigator.of(context).pop(
              _DateRequest(date: _date, reason: _reason),
            ),
          ),
        ],
      );
}
