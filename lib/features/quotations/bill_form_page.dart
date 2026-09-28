import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import 'bill_model.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Port of `pages/create-bill-page.tsx` + `components/bill-builder.tsx`.
///
/// A bill always hangs off a source: either a quotation, whose agreed rates
/// supply the unit prices, or an unbilled gate pass, whose items were already
/// physically counted in. Quantities are the only thing the operator enters —
/// the web app deliberately offers nothing else on this screen, and the
/// adjustments it does expose live on the detail screen instead.
class BillFormPage extends StatefulWidget {
  const BillFormPage({
    super.key,
    this.billId,
    this.gatePassId,
    this.clientName,
  });

  final String? billId;
  final String? gatePassId;
  final String? clientName;

  @override
  State<BillFormPage> createState() => _BillFormPageState();
}

class _BillFormPageState extends State<BillFormPage> {
  /// One editable line: a priced item plus the count the operator typed.
  final List<_BillDraftLine> _lines = [];

  String _sourceLabel = '';
  String _quotationId = '';
  String _gatePassId = '';
  List<String> _deliveryIds = const [];
  String _clientName = '';
  String? _title;

  bool _loading = false;
  bool _picking = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.billId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loadBill();
    } else if (widget.gatePassId != null) {
      _loadUnbilled(widget.gatePassId!);
    } else {
      _pickQuotation();
    }
  }

  Future<void> _loadBill() async {
    setState(() => _loading = true);
    try {
      final payload = await AppScope.read(context)
          .api
          .get(operationsService, BillApi.one(widget.billId!));
      if (!mounted) return;
      final bill =
          BillRecord.fromJson(Map<String, dynamic>.from(payload as Map));
      setState(() {
        _clientName = bill.clientName;
        _title = bill.title;
        _quotationId = bill.quotationId;
        _gatePassId = bill.gatePassId ?? '';
        _sourceLabel = bill.quotationId.isEmpty
            ? 'Gate pass ${_gatePassId.isEmpty ? '—' : _gatePassId}'
            : 'Quotation #${bill.quotationId}';
        _lines
          ..clear()
          ..addAll(bill.items.map(_BillDraftLine.fromLine).toList());
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Loads one unbilled gate pass and seeds every line at its unbilled count,
  /// so the operator is confirming a real count rather than retyping it.
  Future<void> _loadUnbilled(String id) async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final payload = await AppScope.read(context).api.get(
        operationsService,
        BillApi.unbilledGatePasses,
        query: {
          if (AppScope.read(context).hotels.queryParam != null)
            'client_name': AppScope.read(context).hotels.queryParam,
        },
      );
      if (!mounted) return;
      final gatePass =
          unbilledGatePassesFrom(payload).where((g) => g.id == id).firstOrNull;
      if (gatePass == null) {
        setState(() {
          _error = 'That gate pass is no longer unbilled';
          _picking = false;
        });
        return;
      }
      setState(() {
        _gatePassId = gatePass.id;
        _deliveryIds = gatePass.deliveryIds;
        _quotationId = gatePass.quotationId ?? '';
        _clientName = gatePass.clientName;
        _sourceLabel = 'Gate pass ${gatePass.gatePassNumber}';
        _lines
          ..clear()
          ..addAll(
            gatePass.unbilledItems.map(
              (i) => _BillDraftLine(itemName: i.itemName, category: i.category)
                ..quantity = i.unbilledQty,
            ),
          );
        _picking = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _picking = false;
      });
    }
  }

  Future<void> _pickQuotation() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final payload = await AppScope.read(context)
          .api
          .get(ServiceNames.quotation, QuotationApi.list);
      if (!mounted) return;
      final options = quotationsFrom(payload);
      if (options.isEmpty) {
        setState(() {
          _error =
              'No quotations exist yet. Create a price list first, then bill from it.';
          _picking = false;
        });
        return;
      }
      final chosen = await _QuotationPicker.show(context, options);
      if (!mounted) return;
      setState(() => _picking = false);
      if (chosen == null) return;
      setState(() {
        _quotationId = chosen.id;
        _clientName = chosen.clientName;
        _title = chosen.title;
        _gatePassId = '';
        _deliveryIds = const [];
        _sourceLabel = '${chosen.displayTitle} · #${chosen.id}';
        _lines
          ..clear()
          ..addAll(
            chosen.lineItems
                .map((i) => _BillDraftLine(
                      itemName: i.itemName,
                      category: i.category,
                      unitPrice: i.unitPrice,
                    ))
                .toList(),
          );
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _picking = false;
      });
    }
  }

  double get _totalQty => _lines.fold<double>(0, (sum, l) => sum + l.quantity);

  double get _grandTotal => _lines.fold<double>(
        0,
        (sum, l) => sum + l.unitPrice * l.quantity,
      );

  bool get _valid =>
      _clientName.trim().isNotEmpty && _lines.any((l) => l.quantity > 0);

  Future<void> _save() async {
    if (!_valid) return;
    setState(() => _saving = true);
    final bill = BillRecord(
      id: widget.billId ?? '',
      quotationId: _quotationId,
      clientName: _clientName.trim(),
      title: _title,
      items:
          _lines.where((l) => l.quantity > 0).map((l) => l.toItem()).toList(),
      gatePassId: _gatePassId.isEmpty ? null : _gatePassId,
    );
    final payload = bill.toJson(
      deliveryIds: _deliveryIds,
      gatePassId: _gatePassId,
    );
    try {
      final services = AppScope.read(context);
      final result = _isEdit
          ? await services.api.patch(
              operationsService, BillApi.one(widget.billId!), body: payload)
          : await services.api
              .post(operationsService, BillApi.list, body: payload);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppToast.success(
        context,
        result is QueuedResponse
            ? 'Saved — will sync when back online'
            : _isEdit
                ? 'Bill updated'
                : 'Bill created',
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
    if (!canView(services, billsPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bill')),
        body: opsNotPermitted('bills'),
      );
    }
    final c = context.c;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit bill' : 'New bill'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppButton(
              label: 'Save',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.primary,
              loading: _saving,
              onPressed: _valid ? _save : null,
            ),
          ),
        ],
      ),
      body: _loading || _picking
          ? const AppLoader()
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      if (_error != null) ...[
                        AppNotice(
                          message: _error!,
                          tone: AppTone.danger,
                          action: AppButton(
                            label: 'Retry',
                            size: AppButtonSize.xs,
                            variant: AppButtonVariant.secondary,
                            onPressed: _isEdit
                                ? _loadBill
                                : widget.gatePassId != null
                                    ? () => _loadUnbilled(widget.gatePassId!)
                                    : _pickQuotation,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OpsKeyValue(
                              label: 'Client',
                              value: _clientName.isEmpty ? '—' : _clientName,
                            ),
                            OpsKeyValue(
                              label: 'Source',
                              value: _sourceLabel.isEmpty
                                  ? 'No source chosen'
                                  : _sourceLabel,
                            ),
                            if (!_isEdit) ...[
                              const SizedBox(height: 8),
                              AppButton(
                                label: 'Change source',
                                size: AppButtonSize.sm,
                                variant: AppButtonVariant.secondary,
                                icon: Icons.swap_horiz,
                                onPressed: _pickQuotation,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Add items',
                              style: context.texts.titleSmall,
                            ),
                          ),
                          Text(
                            'Set the count that came in',
                            style: context.texts.labelSmall
                                ?.copyWith(color: c.fgFaint),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      AppNotice(
                        message: _quotationId.isEmpty
                            ? "Only this gate pass's items can be billed. To bill "
                                'a different client, change the source above.'
                            : "Only this quotation's items can be billed. To bill "
                                'a different client, change the source above.',
                        tone: AppTone.info,
                      ),
                      const SizedBox(height: 10),
                      if (_lines.isEmpty)
                        const AppEmptyState(
                          title: 'No items to bill',
                          message: 'The source has no priced lines on it yet.',
                          icon: Icons.inventory_2_outlined,
                          compact: true,
                        )
                      else
                        for (final line in _lines) ...[
                          _CountRow(
                            line: line,
                            onChanged: () => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                        ],
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border(top: BorderSide(color: c.line)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Total quantity',
                              style: context.texts.bodySmall
                                  ?.copyWith(color: c.fgMuted),
                            ),
                            const Spacer(),
                            Text(
                              Fmt.qty(_totalQty),
                              style: context.texts.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Total amount',
                              style: context.texts.bodySmall
                                  ?.copyWith(color: c.fgMuted),
                            ),
                            const Spacer(),
                            Text(
                              Fmt.money(_grandTotal),
                              style: context.texts.titleMedium
                                  ?.copyWith(color: c.brandText),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        AppButton(
                          label: 'Save bill',
                          variant: AppButtonVariant.primary,
                          icon: Icons.check,
                          block: true,
                          loading: _saving,
                          onPressed: _valid ? _save : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The source picker. A bill is always attached to exactly one quotation, so
/// the search is over client and title and picking one returns immediately.
class _QuotationPicker extends StatefulWidget {
  const _QuotationPicker({required this.options});

  final List<Quotation> options;

  static Future<Quotation?> show(BuildContext context, List<Quotation> o) =>
      showModalBottomSheet<Quotation>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _QuotationPicker(options: o),
      );

  @override
  State<_QuotationPicker> createState() => _QuotationPickerState();
}

class _QuotationPickerState extends State<_QuotationPicker> {
  final _q = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final needle = _query.toLowerCase();
    final results = widget.options
        .where((q) =>
            needle.isEmpty ||
            '${q.clientName} ${q.displayTitle}'.toLowerCase().contains(needle))
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: AppTextInput(
                  controller: _q,
                  hint: 'Search quotations by client or title…',
                  icon: Icons.search,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              Divider(height: 1, color: c.line),
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          'No quotations match',
                          style: context.texts.bodySmall
                              ?.copyWith(color: c.fgFaint),
                        ),
                      )
                    : ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: c.line,
                        ),
                        itemBuilder: (context, i) {
                          final q = results[i];
                          return ListTile(
                            title: Text(q.clientName),
                            subtitle: Text(
                              '${q.displayTitle} · ${q.itemCount} items',
                            ),
                            trailing: QuotationStatusBadge(status: q.status),
                            onTap: () => Navigator.of(context).pop(q),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.line, required this.onChanged});

  final _BillDraftLine line;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.itemName,
                  style: context.texts.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${line.category.trim().isEmpty ? 'General' : line.category.trim()} · '
                  '${Fmt.money(line.unitPrice)}',
                  style: context.texts.labelSmall?.copyWith(color: c.fgFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          QtyStepper(
            value: line.quantity,
            onChanged: (v) {
              line.quantity = v;
              onChanged();
            },
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 82,
            child: Text(
              Fmt.money(line.unitPrice * line.quantity),
              textAlign: TextAlign.right,
              style: context.texts.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillDraftLine {
  _BillDraftLine({
    required this.itemName,
    this.category = '',
    this.unitPrice = 0,
  });

  factory _BillDraftLine.fromLine(BillLine line) => _BillDraftLine(
        itemName: line.itemName,
        category: line.category,
        unitPrice: line.unitPrice,
      )..quantity = line.quantity;

  final String itemName;
  final String category;
  final double unitPrice;
  double quantity = 0;

  BillLine toItem() => BillLine(
        itemName: itemName,
        category: category,
        unitPrice: unitPrice,
        quantity: quantity,
        lineTotal: unitPrice * quantity,
      );
}
