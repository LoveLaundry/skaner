import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/sync_engine.dart';
import '../../core/models/json.dart' show asMapList;
import '../../data/resource_controller.dart' show asRows;
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import 'bill_form_page.dart';
import 'bill_model.dart';
import 'gatepass_form_page.dart';
import 'gatepass_slip_page.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Port of `pages/gatepass-detail-page.tsx`.
///
/// Everything on this screen about quantities comes from
/// `GET /gatepasses/{id}/balance`. The web page used to subtract delivered
/// quantities per line itself, which made a delivery spanning two passes charge
/// every line to whichever pass the screen asked about; the server owns that
/// arithmetic now and this page only renders it.
class GatepassDetailPage extends StatefulWidget {
  const GatepassDetailPage({super.key, required this.gatepassId});

  final String gatepassId;

  @override
  State<GatepassDetailPage> createState() => _GatepassDetailPageState();
}

class _GatepassDetailPageState extends State<GatepassDetailPage> {
  GatePass? _pass;
  GatePassBalance? _balance;
  List<Delivery> _deliveries = const [];
  List<ReturnRecord> _returns = const [];

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
        api.get(operationsService, GatePassApi.one(widget.gatepassId)),
        api.get(operationsService, GatePassApi.balance(widget.gatepassId)),
        api.get(operationsService, GatePassApi.deliveries(widget.gatepassId)),
        api.get(
          operationsService,
          ReturnApi.list,
          query: {'gate_pass_id': widget.gatepassId},
        ),
      ]);
      if (!mounted) return;
      final deliveriesPayload = results[2];
      final refs = deliveriesPayload is Map
          ? asMapList(deliveriesPayload['deliveries'])
          : asRows(deliveriesPayload);
      setState(() {
        _pass = GatePass.fromJson(Map<String, dynamic>.from(results[0] as Map));
        _balance = GatePassBalance.fromJson(
          Map<String, dynamic>.from(results[1] as Map),
        );
        _deliveries = refs.map(Delivery.fromJson).toList();
        _returns = returnsFrom(results[3]);
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

  /// The balance keys a line by `name||specification`; the same key lets the
  /// items table and the balance table line up without the app re-matching on
  /// names alone.
  static String itemKey(String name, String spec) => '$name||${spec.trim()}';

  GatePassBalanceItem? _balanceFor(GatePassItem item) {
    final key = itemKey(item.itemName, item.specification);
    for (final row in _balance?.items ?? const <GatePassBalanceItem>[]) {
      if (row.itemKey == key) return row;
    }
    return null;
  }

  bool get _hasMovement =>
      _deliveries.any((d) => !d.isCancelled) || _returns.isNotEmpty;

  /// A pass that has already moved linen must not have its counts rewritten.
  bool get _canEdit {
    final pass = _pass;
    if (pass == null) return false;
    if (pass.isClosed) return false;
    return !_hasMovement;
  }

  Future<void> _run(
    Future<Object?> Function() action, {
    required String success,
    bool invalidate = true,
  }) async {
    setState(() => _working = true);
    try {
      final result = await action();
      if (!mounted) return;
      if (invalidate) QueryCacheInvalidator.instance.invalidate('gatepasses');
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

  Future<void> _updateStatus(String status) => _run(
        () => AppScope.read(context).api.patch(
          operationsService,
          GatePassApi.status(widget.gatepassId),
          query: {'status_update': status},
        ),
        success: 'Status set to ${humaniseStatus(status)}',
      );

  Future<void> _markDelivered(String note, DateTime when) => _run(
        () => AppScope.read(context).api.post(
          operationsService,
          GatePassApi.markDelivered(widget.gatepassId),
          body: {'note': note, 'delivered_date': Fmt.isoDate(when)},
        ),
        success: 'Marked delivered',
      );

  /// The legacy reopen is the only way back for a pass closed by
  /// `mark-delivered`, because no delivery document exists to re-open.
  Future<void> _reopenLegacy() => _run(
        () => AppScope.read(context)
            .api
            .post(operationsService, GatePassApi.reopen(widget.gatepassId)),
        success: 'Gate pass reopened',
      );

  Future<void> _updateDate(DateTime when, String reason) => _run(
        () => AppScope.read(context).api.patch(
          operationsService,
          GatePassApi.date(widget.gatepassId),
          body: {
            'receiving_date': isoDateOf(Fmt.isoDate(when)),
            'reason': reason
          },
        ),
        success: 'Receiving date corrected',
      );

  Future<void> _adjust(
    String itemName,
    String specification,
    int correctedQty,
    String reason,
  ) =>
      _run(
        () => AppScope.read(context).api.post(
          operationsService,
          GatePassApi.adjust(widget.gatepassId),
          body: {
            'item_name': itemName,
            'specification': specification,
            'corrected_qty': correctedQty,
            'reason': reason,
          },
        ),
        success: 'Quantity corrected',
      );

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, gatePassesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gate pass')),
        body: opsNotPermitted('gate passes'),
      );
    }
    final pass = _pass;
    return Scaffold(
      appBar: AppBar(
        title: Text(pass?.clientName ?? 'Gate pass'),
        actions: [
          if (pass != null)
            AppButton.icon(
              icon: Icons.print_outlined,
              tooltip: 'Print slip',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      GatepassSlipPage(gatepassId: widget.gatepassId),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const AppLoader()
          : _error != null
              ? AppErrorState(message: _error, onRetry: _load)
              : pass == null
                  ? const AppEmptyState(
                      title: 'Gate pass not found',
                      message: 'It may have been deleted.',
                      icon: Icons.inbox_outlined,
                    )
                  : RefreshIndicator(
                      color: context.c.brand,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          _header(context, pass),
                          const SizedBox(height: 16),
                          CompactMetrics(items: _metrics(pass)),
                          const SizedBox(height: 16),
                          if (pass.markedDelivered != null) ...[
                            AppNotice(
                              title: 'Completed without a delivery record',
                              message: '${pass.markedDelivered!.note} · '
                                  '${Fmt.date(pass.markedDelivered!.deliveredDate)}'
                                  '${pass.markedDelivered!.userId.isEmpty ? '' : ' · ${pass.markedDelivered!.userId}'}',
                              tone: AppTone.warning,
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_balance != null) ...[
                            _balanceCard(context, pass),
                            const SizedBox(height: 16),
                          ],
                          _itemsCard(context, pass),
                          const SizedBox(height: 16),
                          if (_deliveries.isNotEmpty) ...[
                            _deliveriesCard(),
                            const SizedBox(height: 16),
                          ],
                          if (_returns.isNotEmpty) ...[
                            _returnsCard(),
                            const SizedBox(height: 16),
                          ],
                          _actionsCard(context, pass),
                        ],
                      ),
                    ),
    );
  }

  Widget _header(BuildContext context, GatePass pass) {
    final c = context.c;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OpsIcon(Icons.assignment_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pass.gatePassNumber.isEmpty ? '—' : pass.gatePassNumber,
                      style: context.texts.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pass.clientName,
                      style:
                          context.texts.bodySmall?.copyWith(color: c.fgMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Fmt.date(pass.receivingDate)} · received by '
                      '${pass.receivedBy.isEmpty ? '—' : pass.receivedBy}',
                      style:
                          context.texts.bodySmall?.copyWith(color: c.fgMuted),
                    ),
                  ],
                ),
              ),
              GatePassStatusBadge(status: pass.status),
            ],
          ),
          if (_balance != null && _balance!.statusStale) ...[
            const SizedBox(height: 10),
            AppNotice(
              message:
                  'The stored status lags the counts. The server derives this pass '
                  'as "${humaniseStatus(_balance!.derivedStatus)}".',
              tone: AppTone.info,
            ),
          ],
          if ((pass.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(pass.notes!.trim(), style: context.texts.bodySmall),
          ],
        ],
      ),
    );
  }

  List<OpsMetric> _metrics(GatePass pass) {
    // Totals come from the balance document, never from a local sum.
    final totals = _balance?.totals;
    return [
      OpsMetric(
        id: 'received',
        label: 'Received',
        value: Fmt.qty(totals?.receivedQty ?? pass.totalReceived),
        icon: Icons.move_to_inbox_outlined,
        tone: AppTone.info,
      ),
      OpsMetric(
        id: 'delivered',
        label: 'Delivered',
        value: Fmt.qty(totals?.deliveredQty ?? 0),
        icon: Icons.local_shipping_outlined,
        tone: AppTone.success,
      ),
      OpsMetric(
        id: 'pending',
        label: 'Pending',
        value: Fmt.qty(totals?.outstandingDeliveryQty ?? 0),
        icon: Icons.pending_actions_outlined,
        tone: AppTone.warning,
      ),
      OpsMetric(
        id: 'returned',
        label: 'Returned',
        value: Fmt.qty(totals?.returnedBackQty ?? 0),
        icon: Icons.undo,
        tone: AppTone.neutral,
      ),
      OpsMetric(
        id: 'mismatch',
        label: 'Mismatches',
        value: '${pass.mismatchCount}',
        icon: Icons.warning_amber_rounded,
        tone: pass.mismatchCount > 0 ? AppTone.danger : AppTone.neutral,
      ),
    ];
  }

  Widget _balanceCard(BuildContext context, GatePass pass) {
    final c = context.c;
    final rows = _balance!.items;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Server balance', style: context.texts.titleSmall),
              ),
              AppBadge(
                'Computed by the server',
                tone: AppTone.info,
                compact: true,
                icon: Icons.verified_outlined,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'What is still owed to this hotel, per line. These are the numbers '
            'the delivery form will accept.',
            style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const AppEmptyState(
              title: 'No balance rows',
              message: 'The server returned no per-line balance for this pass.',
              icon: Icons.balance_outlined,
              compact: true,
            )
          else
            for (final row in rows) ...[
              _BalanceRow(row: row),
              if (row != rows.last) const Divider(height: 14),
            ],
          const Divider(height: 18),
          OpsTotalRow(
            label: 'Expected',
            value: Fmt.qty(_balance!.totals.expectedQty),
          ),
          OpsTotalRow(
            label: 'Received',
            value: Fmt.qty(_balance!.totals.receivedQty),
          ),
          OpsTotalRow(
            label: 'Delivered',
            value: Fmt.qty(_balance!.totals.deliveredQty),
          ),
          OpsTotalRow(
            label: 'Returned',
            value: Fmt.qty(_balance!.totals.returnedBackQty),
          ),
          OpsTotalRow(
            label: 'Outstanding',
            value: Fmt.qty(_balance!.totals.outstandingDeliveryQty),
            strong: true,
            tone: _balance!.totals.outstandingDeliveryQty > 0
                ? AppTone.warning
                : AppTone.success,
          ),
        ],
      ),
    );
  }

  Widget _itemsCard(BuildContext context, GatePass pass) {
    final c = context.c;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Items received', style: context.texts.titleSmall),
              ),
              if (_canEdit)
                AppButton(
                  label: 'Edit',
                  size: AppButtonSize.xs,
                  variant: AppButtonVariant.secondary,
                  icon: Icons.edit_outlined,
                  onPressed: _editItems,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (pass.items.isEmpty)
            const AppEmptyState(
              title: 'No items',
              message: 'This pass has no counted lines.',
              icon: Icons.inventory_2_outlined,
              compact: true,
            )
          else
            for (final item in pass.items) ...[
              _ItemRow(
                item: item,
                balance: _balanceFor(item),
                canEdit: _canEdit,
                onAdjust: () => _openAdjust(item),
              ),
              if (item != pass.items.last) const Divider(height: 14),
            ],
          if (_canEdit) ...[
            const SizedBox(height: 10),
            Text(
              'Counts can be corrected until the linen has moved.',
              style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deliveriesCard() {
    final live = _deliveries.where((d) => !d.isCancelled).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Deliveries from this pass', style: context.texts.titleSmall),
          const SizedBox(height: 10),
          for (final d in live) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Fmt.date(d.deliveryDate),
                        style: context.texts.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${d.totalPieces} pcs · delivered by '
                        '${d.deliveredBy.isEmpty ? '—' : d.deliveredBy}',
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.c.fgMuted),
                      ),
                    ],
                  ),
                ),
                DeliveryStatusBadge(status: d.status),
              ],
            ),
            if (d != live.last) const Divider(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _returnsCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Returns against this pass', style: context.texts.titleSmall),
          const SizedBox(height: 10),
          for (final r in _returns) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.returnId.isEmpty ? r.key : r.returnId,
                        style: context.texts.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${r.totalPieces} pcs · ${Fmt.date(r.createdAt)}',
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.c.fgMuted),
                      ),
                    ],
                  ),
                ),
                ReturnStatusBadge(status: r.status),
              ],
            ),
            if (r != _returns.last) const Divider(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _actionsCard(BuildContext context, GatePass pass) {
    final c = context.c;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Actions', style: context.texts.titleSmall),
          const SizedBox(height: 10),
          if (!pass.isClosed)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  label: 'Mark delivered',
                  variant: AppButtonVariant.primary,
                  icon: Icons.check_circle_outline,
                  onPressed: _working ? null : _openMarkDelivered,
                ),
                AppButton(
                  label: 'Create bill',
                  variant: AppButtonVariant.secondary,
                  icon: Icons.receipt_long_outlined,
                  onPressed: _working ? null : _openCreateBill,
                ),
              ],
            ),
          if (pass.markedDelivered != null) ...[
            const SizedBox(height: 10),
            AppButton(
              label: 'Reopen (legacy pass)',
              variant: AppButtonVariant.ghost,
              icon: Icons.restart_alt,
              onPressed: _working ? null : _confirmReopen,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Receiving date: ${Fmt.date(pass.receivingDate)}',
            style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                label: 'Correct receiving date',
                size: AppButtonSize.xs,
                variant: AppButtonVariant.secondary,
                onPressed: _working ? null : _openDateEdit,
              ),
              if (!pass.isClosed)
                AppButton(
                  label: 'Update status',
                  size: AppButtonSize.xs,
                  variant: AppButtonVariant.secondary,
                  onPressed: _working ? null : _openStatusPicker,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editItems() async {
    final id = widget.gatepassId;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GatepassFormPage(gatepassId: id)),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _openAdjust(GatePassItem item) async {
    final result = await showDialog<_AdjustRequest>(
      context: context,
      builder: (_) => _AdjustDialog(item: item),
    );
    if (result == null || !mounted) return;
    await _adjust(
      result.itemName,
      result.specification,
      result.correctedQty,
      result.reason,
    );
  }

  Future<void> _openStatusPicker() async {
    final current = _pass?.status ?? '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final s in gatePassStatuses)
              if (s != current)
                ListTile(
                  leading: GatePassStatusBadge(status: s),
                  title: Text(humaniseStatus(s)),
                  onTap: () => Navigator.of(context).pop(s),
                ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) await _updateStatus(picked);
  }

  Future<void> _openMarkDelivered() async {
    final result = await showDialog<_MarkDeliveredRequest>(
      context: context,
      builder: (_) => const _MarkDeliveredDialog(),
    );
    if (result == null || !mounted) return;
    await _markDelivered(result.note, result.date);
  }

  Future<void> _openDateEdit() async {
    final result = await showDialog<_DateChangeRequest>(
      context: context,
      builder: (_) => _DateChangeDialog(current: _pass?.receivingDate),
    );
    if (result == null || !mounted) return;
    await _updateDate(result.date, result.reason);
  }

  Future<void> _confirmReopen() async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Reopen this gate pass?',
      message:
          'This pass was completed without a delivery record. Reopening it puts '
          'it back into the pending deliveries queue so the linen can be '
          'delivered properly.',
      confirmLabel: 'Reopen',
    );
    if (ok && mounted) await _reopenLegacy();
  }

  /// Billing is the bill form's job: it already knows which gate pass it came
  /// from and which lines are billable, so this screen only opens it.
  Future<void> _openCreateBill() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BillFormPage(gatePassId: widget.gatepassId),
      ),
    );
    if (created == true && mounted) {
      AppToast.success(context, 'Bill created from this gate pass');
    }
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.row});

  final GatePassBalanceItem row;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.specification.isEmpty
                    ? row.itemName
                    : '${row.itemName} — ${row.specification}',
                style: context.texts.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (row.rewashed)
              const AppBadge('Re-wash', tone: AppTone.neutral, compact: true),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 14,
          runSpacing: 2,
          children: [
            _cell(context, 'Received', row.receivedQty),
            _cell(context, 'Delivered', row.deliveredQty),
            _cell(context, 'Returned', row.returnedBackQty),
            _cell(
              context,
              'Pending',
              row.outstandingDeliveryQty,
              strong: true,
            ),
            if (row.notReceivedQty != 0)
              _cell(context, 'Not received', row.notReceivedQty),
            if (row.extraReceivedQty != 0)
              _cell(context, 'Extra', row.extraReceivedQty),
          ],
        ),
        if (row.flags.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            row.flags.map(humaniseStatus).join(' · '),
            style: context.texts.bodySmall?.copyWith(color: c.warning),
          ),
        ],
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    String label,
    int value, {
    bool strong = false,
  }) =>
      Text(
        '$label ${Fmt.qty(value)}',
        style: context.texts.bodySmall?.copyWith(
          color: strong ? context.c.brandText : context.c.fgMuted,
          fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
        ),
      );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.balance,
    required this.canEdit,
    required this.onAdjust,
  });

  final GatePassItem item;
  final GatePassBalanceItem? balance;
  final bool canEdit;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.specification.isEmpty
                        ? item.itemName
                        : '${item.itemName} — ${item.specification}',
                    style: context.texts.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (item.category.trim().isNotEmpty)
                    Text(
                      item.category,
                      style:
                          context.texts.bodySmall?.copyWith(color: c.fgFaint),
                    ),
                ],
              ),
            ),
            if (canEdit)
              AppButton.icon(
                icon: Icons.tune,
                tooltip: 'Correct quantity',
                size: AppButtonSize.iconSm,
                onPressed: onAdjust,
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 14,
          runSpacing: 2,
          children: [
            _cell(context, 'Client', item.clientQty),
            _cell(context, 'Received', item.receivedQty, strong: true),
            _cell(
              context,
              'Difference',
              item.difference,
              strong: true,
              tone: item.hasMismatch ? c.warning : null,
            ),
            if (balance != null)
              _cell(context, 'Delivered', balance!.deliveredQty),
            if (balance != null)
              _cell(context, 'Pending', balance!.outstandingDeliveryQty),
          ],
        ),
        if (item.hasMismatch) ...[
          const SizedBox(height: 6),
          AppNotice(
            message: [
              if (item.mismatchReason.isNotEmpty)
                humaniseStatus(item.mismatchReason),
              if (item.mismatchNotes.trim().isNotEmpty)
                item.mismatchNotes.trim(),
            ].join(' — '),
            tone: AppTone.warning,
          ),
        ],
        if (item.rewashed) ...[
          const SizedBox(height: 6),
          const AppBadge(
            'Re-wash — not billed',
            tone: AppTone.success,
            compact: true,
          ),
        ],
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    String label,
    int value, {
    bool strong = false,
    Color? tone,
  }) =>
      Text(
        '$label ${Fmt.qty(value)}',
        style: context.texts.bodySmall?.copyWith(
          color: tone ?? (strong ? context.c.fg : context.c.fgMuted),
          fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
        ),
      );
}

class _AdjustRequest {
  const _AdjustRequest({
    required this.itemName,
    required this.specification,
    required this.correctedQty,
    required this.reason,
  });

  final String itemName;
  final String specification;
  final int correctedQty;
  final String reason;
}

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.item});

  final GatePassItem item;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  late final TextEditingController _qty =
      TextEditingController(text: '${widget.item.receivedQty}');
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _qty.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = (_reasonCtrl.text.trim().isNotEmpty) &&
        (int.tryParse(_qty.text.trim()) ?? -1) >= 0;
    return AppDialog(
      title: 'Correct received quantity',
      icon: Icons.tune,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.item.specification.isEmpty
                ? widget.item.itemName
                : '${widget.item.itemName} — ${widget.item.specification}',
            style: context.texts.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'The hotel counted ${Fmt.qty(widget.item.clientQty)}; we received '
            '${Fmt.qty(widget.item.receivedQty)}.',
            style: context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
          ),
          const SizedBox(height: 14),
          AppField(
            label: 'Corrected quantity',
            required: true,
            child: AppTextInput(
              controller: _qty,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          AppField(
            label: 'Reason',
            required: true,
            hint: 'Why the count is being corrected',
            child: AppTextInput(
              controller: _reasonCtrl,
              onChanged: (_) => setState(() {}),
            ),
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
          label: 'Correct',
          variant: AppButtonVariant.primary,
          onPressed: valid
              ? () => Navigator.of(context).pop(
                    _AdjustRequest(
                      itemName: widget.item.itemName,
                      specification: widget.item.specification,
                      correctedQty: int.tryParse(_qty.text.trim()) ?? 0,
                      reason: _reasonCtrl.text.trim(),
                    ),
                  )
              : null,
        ),
      ],
    );
  }
}

class _MarkDeliveredRequest {
  const _MarkDeliveredRequest({required this.note, required this.date});

  final String note;
  final DateTime date;
}

class _MarkDeliveredDialog extends StatefulWidget {
  const _MarkDeliveredDialog();

  @override
  State<_MarkDeliveredDialog> createState() => _MarkDeliveredDialogState();
}

class _MarkDeliveredDialogState extends State<_MarkDeliveredDialog> {
  final _noteCtrl = TextEditingController();
  DateTime _date = Fmt.lktNow();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _noteCtrl.text.trim().isNotEmpty;
    return AppDialog(
      title: 'Mark as delivered',
      icon: Icons.check_circle_outline,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppNotice(
            message:
                'Use this when the linen physically left but no delivery was '
                'recorded. The note is required so the shortcut is auditable.',
            tone: AppTone.warning,
          ),
          const SizedBox(height: 14),
          AppField(
            label: 'Delivered date',
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
            label: 'Note',
            required: true,
            child: AppTextInput(
              controller: _noteCtrl,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
            ),
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
          label: 'Mark delivered',
          variant: AppButtonVariant.primary,
          onPressed: valid
              ? () => Navigator.of(context).pop(
                    _MarkDeliveredRequest(
                      note: _noteCtrl.text.trim(),
                      date: _date,
                    ),
                  )
              : null,
        ),
      ],
    );
  }
}

class _DateChangeRequest {
  const _DateChangeRequest({required this.date, required this.reason});

  final DateTime date;
  final String reason;
}

class _DateChangeDialog extends StatefulWidget {
  const _DateChangeDialog({required this.current});

  final String? current;

  @override
  State<_DateChangeDialog> createState() => _DateChangeDialogState();
}

class _DateChangeDialogState extends State<_DateChangeDialog> {
  final _reasonCtrl = TextEditingController();
  late DateTime _date = Fmt.parseDate(widget.current) ?? Fmt.lktNow();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
        title: 'Correct receiving date',
        icon: Icons.event_outlined,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppNotice(
              message:
                  'Changing the receiving date moves this pass inside or outside '
                  'period reports, so a reason is kept with the change.',
              tone: AppTone.info,
            ),
            const SizedBox(height: 14),
            AppField(
              label: 'Receiving date',
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
              _DateChangeRequest(
                date: _date,
                reason: _reasonCtrl.text.trim(),
              ),
            ),
          ),
        ],
      );
}
