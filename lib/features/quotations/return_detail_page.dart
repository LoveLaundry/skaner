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
import 'quotation_model.dart';
import 'return_form_page.dart';
import 'shared_widgets.dart';

/// Port of `pages/return-detail-page.tsx`.
///
/// Status only ever moves one step forward — a record is never walked backwards
/// from the web UI — so the picker offers the single next state rather than all
/// three.
class ReturnDetailPage extends StatefulWidget {
  const ReturnDetailPage({super.key, required this.returnId});

  final String returnId;

  @override
  State<ReturnDetailPage> createState() => _ReturnDetailPageState();
}

class _ReturnDetailPageState extends State<ReturnDetailPage> {
  ReturnRecord? _record;
  bool _loading = true;
  bool _working = false;
  String? _error;

  static const Map<String, List<String>> _transitions = {
    'PENDING': ['RECEIVED'],
    'RECEIVED': ['PROCESSED'],
    'PROCESSED': [],
  };

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
          .get(operationsService, ReturnApi.one(widget.returnId));
      if (!mounted) return;
      setState(() {
        _record =
            ReturnRecord.fromJson(Map<String, dynamic>.from(payload as Map));
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

  Future<void> _setStatus(String status) async {
    setState(() => _working = true);
    try {
      final result = await AppScope.read(context).api.patch(
        operationsService,
        ReturnApi.one(widget.returnId),
        body: {'status': status},
      );
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate('returns');
      if (result is! QueuedResponse && result is Map) {
        setState(() {
          _record = ReturnRecord.fromJson(Map<String, dynamic>.from(result));
          _working = false;
        });
      } else {
        setState(() => _working = false);
        await _load();
      }
      if (!mounted) return;
      AppToast.info(
        context,
        result is QueuedResponse
            ? 'Queued — will sync when back online'
            : 'Status updated to ${humaniseStatus(status)}',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      AppToast.error(context, e.message);
    }
  }

  Future<void> _markResent(ReturnLine line) async {
    try {
      final result = await AppScope.read(context).api.post(
        operationsService,
        ReturnApi.resent(widget.returnId),
        body: null,
        query: {
          'item_name': line.itemName,
          'specification': line.specification,
        },
      );
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate('returns');
      if (result is! QueuedResponse && result is Map) {
        setState(() {
          _record = ReturnRecord.fromJson(Map<String, dynamic>.from(result));
        });
      } else {
        await _load();
      }
      if (!mounted) return;
      AppToast.success(
        context,
        result is QueuedResponse
            ? 'Marked as sent — will sync when back online'
            : 'Marked as sent',
      );
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, gatePassesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Return')),
        body: opsNotPermitted('returns'),
      );
    }
    final record = _record;
    final canWrite = services.auth.hasPermission(gatePassesPermission);
    return Scaffold(
      appBar: AppBar(
        title: Text(record?.clientName ?? 'Return'),
        actions: [
          if (record != null && canWrite)
            AppButton.icon(
              icon: Icons.edit_outlined,
              tooltip: 'Edit return',
              onPressed: _openEdit,
            ),
        ],
      ),
      body: _loading
          ? const AppLoader()
          : _error != null
              ? AppErrorState(message: _error, onRetry: _load)
              : record == null
                  ? const AppEmptyState(
                      title: 'Return not found',
                      message: 'It may have been removed.',
                      icon: Icons.assignment_return_outlined,
                    )
                  : RefreshIndicator(
                      color: context.c.brand,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          _header(record),
                          const SizedBox(height: 12),
                          _metrics(record),
                          const SizedBox(height: 12),
                          if (canWrite &&
                              (_transitions[record.status.toUpperCase()] ??
                                      const [])
                                  .isNotEmpty)
                            _statusCard(record),
                          if (canWrite &&
                              (_transitions[record.status.toUpperCase()] ??
                                      const [])
                                  .isNotEmpty)
                            const SizedBox(height: 12),
                          _itemsCard(record, canWrite),
                          if (record.billAdjustment.applies) ...[
                            const SizedBox(height: 12),
                            _adjustmentCard(record),
                          ],
                          if ((record.notes ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Notes',
                                      style: context.texts.titleSmall),
                                  const SizedBox(height: 6),
                                  Text(
                                    record.notes!.trim(),
                                    style: context.texts.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Future<void> _openEdit() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
          builder: (_) => ReturnFormPage(returnId: widget.returnId)),
    );
    if (mounted) _load();
  }

  Widget _header(ReturnRecord record) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OpsIcon(Icons.assignment_return_outlined,
              tone: AppTone.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.clientName.isEmpty ? '—' : record.clientName,
                  style: context.texts.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Return ID: ${record.returnId.isEmpty ? '—' : record.returnId}',
                  style: context.texts.bodySmall
                      ?.copyWith(color: context.c.fgMuted),
                ),
              ],
            ),
          ),
          ReturnStatusBadge(status: record.status),
        ],
      ),
    );
  }

  Widget _metrics(ReturnRecord record) {
    return Row(
      children: [
        Expanded(
          child: _info(
            Icons.event_outlined,
            'Recorded',
            Fmt.date(record.createdAt),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _info(
            Icons.person_outline,
            'Recorded by',
            record.recordedBy.isEmpty ? '—' : record.recordedBy,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _info(
            Icons.inventory_2_outlined,
            'Returned',
            '${record.totalPieces} pcs',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _info(
            Icons.badge_outlined,
            'Gate pass',
            record.gatePassId.isEmpty
                ? '—'
                : Fmt.truncate(record.gatePassId, 8).toUpperCase(),
          ),
        ),
      ],
    );
  }

  Widget _info(IconData icon, String label, String value) => AppCard(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: context.c.fgFaint),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.c.fgFaint,
                      fontSize: 10,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _statusCard(ReturnRecord record) {
    final next = _transitions[record.status.toUpperCase()] ?? const <String>[];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change status', style: context.texts.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Move to:',
            style: context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in next)
                AppButton(
                  label: humaniseStatus(s),
                  size: AppButtonSize.xs,
                  variant: AppButtonVariant.outline,
                  icon: switch (s) {
                    'RECEIVED' => Icons.move_to_inbox_outlined,
                    'PROCESSED' => Icons.task_alt,
                    _ => null,
                  },
                  onPressed: _working ? null : () => _setStatus(s),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemsCard(ReturnRecord record, bool canWrite) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Returned items (${record.items.length})',
            style: context.texts.titleSmall,
          ),
          const SizedBox(height: 10),
          if (record.items.isEmpty)
            Text(
              'No items recorded.',
              style:
                  context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
            )
          else
            // Seven columns cannot fit a phone, so the grid scrolls sideways
            // rather than dropping a column the operator needs to see.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 64,
                ),
                child: Column(
                  children: [
                    const _ItemHeaderRow(),
                    for (var i = 0; i < record.items.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: context.c.line),
                      _ItemRow(
                        line: record.items[i],
                        canWrite: canWrite,
                        onMarkResent: () => _markResent(record.items[i]),
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

  Widget _adjustmentCard(ReturnRecord record) {
    final a = record.billAdjustment;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bill adjustment', style: context.texts.titleSmall),
          const SizedBox(height: 8),
          OpsKeyValue(
            label: 'Type',
            value: _adjustmentLabel(a.adjustmentType),
          ),
          OpsKeyValue(label: 'Amount', value: Fmt.money(a.amount)),
          if (a.notes.trim().isNotEmpty)
            OpsKeyValue(label: 'Notes', value: a.notes.trim()),
        ],
      ),
    );
  }

  static String _adjustmentLabel(String value) {
    for (final o in returnAdjustmentOptions) {
      if (o.value == value) return o.label;
    }
    return value;
  }
}

class _ItemHeaderRow extends StatelessWidget {
  const _ItemHeaderRow();

  static const List<String> _labels = [
    'Item',
    'Spec',
    'Qty',
    'Reason',
    'Condition',
    'Action',
    'Resend',
  ];
  static const List<double> _widths = [140, 74, 52, 132, 132, 132, 96];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.c.surfaceSunken,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            SizedBox(
              width: _widths[i],
              child: Text(
                _labels[i].toUpperCase(),
                style: context.texts.bodySmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: context.c.fgMuted,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.line,
    required this.canWrite,
    required this.onMarkResent,
  });

  final ReturnLine line;
  final bool canWrite;
  final VoidCallback onMarkResent;

  static const List<double> _widths = [140, 74, 52, 132, 132, 132, 96];

  @override
  Widget build(BuildContext context) {
    final resendable = returnResendActions.contains(line.action);
    final cell = _widths;
    return Container(
      color: context.c.surface,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: cell[0],
            child: Text(
              line.itemName.isEmpty ? '—' : line.itemName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: cell[1],
            child: line.specification.isEmpty
                ? Text('—',
                    style: context.texts.bodySmall
                        ?.copyWith(color: context.c.fgFaint))
                : AppBadge(
                    line.specification,
                    tone: AppTone.neutral,
                    compact: true,
                  ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: cell[2],
            child: Text(
              '${line.returnedQty}',
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: cell[3],
            child: _muted(context, _label(returnReasonOptions, line.reason)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: cell[4],
            child:
                _muted(context, _label(returnConditionOptions, line.condition)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: cell[5],
            child: _muted(context, _label(returnActionOptions, line.action)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: cell[6],
            child: !resendable
                ? Text('—',
                    textAlign: TextAlign.center,
                    style: context.texts.bodySmall
                        ?.copyWith(color: context.c.fgFaint))
                : line.resendStatus == 'SENT'
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle,
                              size: 13, color: context.c.success),
                          const SizedBox(width: 3),
                          Text(
                            'Sent',
                            style: context.texts.bodySmall
                                ?.copyWith(color: context.c.success),
                          ),
                        ],
                      )
                    : canWrite
                        ? AppButton(
                            label: 'Mark sent',
                            size: AppButtonSize.xs,
                            variant: AppButtonVariant.secondary,
                            icon: Icons.send_outlined,
                            onPressed: onMarkResent,
                          )
                        : Text(
                            'Pending',
                            textAlign: TextAlign.center,
                            style: context.texts.bodySmall
                                ?.copyWith(color: context.c.warning),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _muted(BuildContext context, String text) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
      );

  /// Unknown values render as themselves rather than disappearing, so a
  /// server-side addition stays visible instead of showing a blank cell.
  static String _label(List<AppSelectOption<String>> options, String value) {
    for (final o in options) {
      if (o.value == value) return o.label;
    }
    return value;
  }
}
