import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import 'bill_form_page.dart';
import 'bill_model.dart';
import 'bill_print_page.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Port of `features/quotations/pages/bill-detail-page.tsx`.
///
/// Settling a bill is the whole point of this screen: the payments endpoint is
/// the only way the outstanding balance moves, and the adjustments the server
/// owns (discount, transport, tax, other charges) are edited in one place here
/// rather than at create time.
class BillDetailPage extends StatefulWidget {
  const BillDetailPage({super.key, required this.billId});

  final String billId;

  @override
  State<BillDetailPage> createState() => _BillDetailPageState();
}

class _BillDetailPageState extends State<BillDetailPage> {
  BillRecord? _bill;
  List<BillPayment> _payments = const [];
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final services = AppScope.read(context);
      final payload = await services.api.get(
        operationsService,
        BillApi.one(widget.billId),
      );
      if (!mounted) return;
      setState(() {
        _bill = BillRecord.fromJson(Map<String, dynamic>.from(payload as Map));
        _error = null;
      });
      await _loadPayments();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPayments() async {
    try {
      final payload = await AppScope.read(context)
          .api
          .get(operationsService, BillApi.payments(widget.billId));
      if (!mounted) return;
      setState(() => _payments = billPaymentsFrom(payload));
    } on ApiException {
      // An unavailable payment history must not hide the bill itself.
    }
  }

  Future<void> _recordPayment() async {
    final bill = _bill;
    if (bill == null) return;
    final payment = await showDialog<_NewPayment>(
      context: context,
      builder: (_) => _PaymentDialog(suggestedAmount: bill.owed),
    );
    if (payment == null || !mounted) return;
    setState(() => _working = true);
    try {
      final result = await AppScope.read(context).api.post(
            operationsService,
            BillApi.payments(widget.billId),
            body: BillPayment(
              amount: payment.amount,
              method: payment.method,
              reference: payment.reference,
              notes: payment.notes,
            ).toJson(payment.date),
          );
      if (!mounted) return;
      AppToast.info(
        context,
        result is QueuedResponse
            ? 'Payment queued — will sync when back online'
            : 'Payment recorded',
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveAdjustments() async {
    final bill = _bill;
    if (bill == null) return;
    final result = await showDialog<_Adjustments>(
      context: context,
      builder: (_) => _AdjustmentsDialog(
        initial: _Adjustments(
          clientName: bill.clientName,
          notes: bill.notes ?? '',
          discounts: bill.discounts,
          transportFee: bill.transportFee,
          taxes: bill.taxes,
          additionalCharges: bill.additionalCharges,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _working = true);
    try {
      await AppScope.read(context).api.patch(
        operationsService,
        BillApi.one(widget.billId),
        body: {
          'client_name': result.clientName.trim(),
          'notes': result.notes.trim(),
          'discounts': result.discounts,
          'transport_fee': result.transportFee,
          'taxes': result.taxes,
          'additional_charges': result.additionalCharges,
        },
      );
      if (!mounted) return;
      AppToast.success(context, 'Bill updated');
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editItems() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BillFormPage(billId: widget.billId)),
    );
    if (saved == true) _load();
  }

  Future<void> _delete() async {
    final bill = _bill;
    if (bill == null) return;
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Delete this bill?',
      message: 'Bill #${bill.id} for ${bill.clientName} will be removed '
          'permanently.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context)
          .api
          .delete(operationsService, BillApi.one(bill.id));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    }
  }

  Future<void> _print() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => BillPrintPage(billId: widget.billId)),
    );
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
    final bill = _bill;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill'),
        actions: [
          AppButton.icon(
            icon: Icons.print_outlined,
            tooltip: 'Print',
            onPressed: bill == null ? null : _print,
          ),
          AppButton.icon(
            icon: Icons.delete_outline,
            tooltip: 'Delete',
            variant: AppButtonVariant.dangerGhost,
            onPressed: bill == null ? null : _delete,
          ),
        ],
      ),
      body: _loading
          ? const AppLoader()
          : _error != null
              ? AppErrorState(message: _error, onRetry: _load)
              : bill == null
                  ? const AppEmptyState(
                      title: 'Bill not found',
                      icon: Icons.search_off,
                    )
                  : RefreshIndicator(
                      color: context.c.brand,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          _SummaryCard(bill: bill),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: AppButton(
                                  label: 'Record payment',
                                  icon: Icons.payments_outlined,
                                  variant: AppButtonVariant.primary,
                                  loading: _working,
                                  onPressed: bill.isPaid || bill.isCancelled
                                      ? null
                                      : _recordPayment,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: AppButton(
                                  label: 'Edit items',
                                  icon: Icons.edit_outlined,
                                  variant: AppButtonVariant.secondary,
                                  onPressed: bill.isPaid ? null : _editItems,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppButton(
                                  label: 'Adjust totals',
                                  icon: Icons.tune,
                                  variant: AppButtonVariant.secondary,
                                  loading: _working,
                                  onPressed: _saveAdjustments,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text('Items', style: context.texts.titleSmall),
                          const SizedBox(height: 8),
                          if (bill.items.isEmpty)
                            const AppEmptyState(
                              title: 'No items on this bill',
                              icon: Icons.list_alt_outlined,
                              compact: true,
                            )
                          else
                            for (final line in bill.items) ...[
                              _BillLineCard(line: line),
                              const SizedBox(height: 8),
                            ],
                          const SizedBox(height: 10),
                          Text('Payments', style: context.texts.titleSmall),
                          const SizedBox(height: 8),
                          if (_payments.isEmpty)
                            const AppEmptyState(
                              title: 'No payments recorded yet',
                              icon: Icons.account_balance_wallet_outlined,
                              compact: true,
                            )
                          else
                            for (final p in _payments) ...[
                              _PaymentRow(payment: p),
                              const SizedBox(height: 8),
                            ],
                        ],
                      ),
                    ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.bill});

  final BillRecord bill;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bill.clientName, style: context.texts.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '#${bill.id} · ${Fmt.dateTime(bill.createdAt)}',
                      style:
                          context.texts.bodySmall?.copyWith(color: c.fgMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              BillStatusBadge(status: bill.paymentStatus),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          OpsTotalRow(label: 'Sub total', value: Fmt.money(bill.totalAmount)),
          if (bill.discounts > 0)
            OpsTotalRow(
              label: 'Discount',
              value: '- ${Fmt.money(bill.discounts)}',
              tone: AppTone.warning,
            ),
          if (bill.transportFee > 0)
            OpsTotalRow(
                label: 'Transport', value: '+ ${Fmt.money(bill.transportFee)}'),
          if (bill.taxes > 0)
            OpsTotalRow(label: 'Taxes', value: '+ ${Fmt.money(bill.taxes)}'),
          if (bill.additionalCharges > 0)
            OpsTotalRow(
              label: 'Additional charges',
              value: '+ ${Fmt.money(bill.additionalCharges)}',
            ),
          const Divider(height: 12),
          OpsTotalRow(
              label: 'Grand total', value: Fmt.money(bill.grand), strong: true),
          OpsTotalRow(
            label: 'Paid',
            value: Fmt.money(bill.paidAmount),
            tone: AppTone.success,
          ),
          OpsTotalRow(
            label: 'Outstanding',
            value: Fmt.money(bill.owed),
            strong: true,
            tone: bill.owed > 0 ? AppTone.danger : AppTone.success,
          ),
          if (bill.gatePassId != null && bill.gatePassId!.isNotEmpty) ...[
            const SizedBox(height: 6),
            OpsKeyValue(label: 'Gate pass', value: bill.gatePassId!),
          ],
          if (bill.quotationId.isNotEmpty) ...[
            OpsKeyValue(label: 'Quotation', value: '#${bill.quotationId}'),
          ],
          if (bill.notes != null && bill.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            AppNotice(message: bill.notes!.trim(), tone: AppTone.neutral),
          ],
        ],
      ),
    );
  }
}

class _BillLineCard extends StatelessWidget {
  const _BillLineCard({required this.line});

  final BillLine line;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.itemName, style: context.texts.bodyMedium),
                Text(
                  '${Fmt.qty(line.quantity)} × ${Fmt.money(line.unitPrice)}',
                  style: context.texts.labelSmall?.copyWith(color: c.fgFaint),
                ),
              ],
            ),
          ),
          Text(
            Fmt.money(line.lineTotal),
            style:
                context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final BillPayment payment;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 17, color: c.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Fmt.money(payment.amount),
                  style: context.texts.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  [
                    if (payment.method.isNotEmpty) payment.method,
                    Fmt.date(payment.paidAt),
                    if (payment.reference.isNotEmpty) payment.reference,
                  ].join(' · '),
                  style: context.texts.labelSmall?.copyWith(color: c.fgFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.suggestedAmount});

  final double suggestedAmount;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final TextEditingController _amount =
      TextEditingController(text: Fmt.amount(widget.suggestedAmount));
  late final TextEditingController _reference = TextEditingController();
  late final TextEditingController _notes = TextEditingController();

  String _method = 'Cash';
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
        title: 'Record payment',
        icon: Icons.payments_outlined,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Submit a new payment record for this bill.',
              style:
                  context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
            ),
            const SizedBox(height: 14),
            AppField(
              label: 'Amount',
              required: true,
              child: AppMoneyInput(controller: _amount, currency: 'LKR'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppField(
                    label: 'Method',
                    required: true,
                    child: AppSearchableSelect<String>(
                      value: _method,
                      searchable: false,
                      options: [
                        for (final m in BillPayment.methods)
                          AppSelectOption<String>(value: m, label: m),
                      ],
                      onChanged: (v) => setState(() => _method = v ?? 'Cash'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppField(
                    label: 'Date',
                    required: true,
                    child: AppDateField(
                      value: _date,
                      onChanged: (d) {
                        if (d != null) setState(() => _date = d);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppField(
              label: 'Reference',
              optional: true,
              child: AppTextInput(controller: _reference),
            ),
            const SizedBox(height: 12),
            AppField(
              label: 'Notes',
              optional: true,
              child: AppTextInput(controller: _notes),
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
            label: 'Record payment',
            variant: AppButtonVariant.primary,
            onPressed: () {
              final amount = double.tryParse(_amount.text.replaceAll(',', ''));
              if (amount == null || amount <= 0) return;
              Navigator.of(context).pop(
                _NewPayment(
                  amount: amount,
                  method: _method,
                  reference: _reference.text,
                  notes: _notes.text,
                  date: _date,
                ),
              );
            },
          ),
        ],
      );
}

/// What the payment dialog hands back before it becomes a `BillPayment`.
class _NewPayment {
  const _NewPayment({
    required this.amount,
    required this.method,
    required this.reference,
    required this.notes,
    required this.date,
  });

  final double amount;
  final String method;
  final String reference;
  final String notes;
  final DateTime date;
}

class _Adjustments {
  _Adjustments({
    required this.clientName,
    required this.notes,
    required this.discounts,
    required this.transportFee,
    required this.taxes,
    required this.additionalCharges,
  });

  String clientName;
  String notes;
  double discounts;
  double transportFee;
  double taxes;
  double additionalCharges;
}

class _AdjustmentsDialog extends StatefulWidget {
  const _AdjustmentsDialog({required this.initial});

  final _Adjustments initial;

  @override
  State<_AdjustmentsDialog> createState() => _AdjustmentsDialogState();
}

class _AdjustmentsDialogState extends State<_AdjustmentsDialog> {
  late final TextEditingController _client =
      TextEditingController(text: widget.initial.clientName);
  late final TextEditingController _notes =
      TextEditingController(text: widget.initial.notes);
  late final TextEditingController _discounts =
      TextEditingController(text: Fmt.amount(widget.initial.discounts));
  late final TextEditingController _transport =
      TextEditingController(text: Fmt.amount(widget.initial.transportFee));
  late final TextEditingController _taxes =
      TextEditingController(text: Fmt.amount(widget.initial.taxes));
  late final TextEditingController _other =
      TextEditingController(text: Fmt.amount(widget.initial.additionalCharges));

  @override
  void dispose() {
    _client.dispose();
    _notes.dispose();
    _discounts.dispose();
    _transport.dispose();
    _taxes.dispose();
    _other.dispose();
    super.dispose();
  }

  double _of(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final a = widget.initial;
    return AppDialog(
      title: 'Adjust totals',
      icon: Icons.tune,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppField(
              label: 'Client',
              required: true,
              child: AppTextInput(controller: _client),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppField(
                    label: 'Discounts',
                    child: AppMoneyInput(
                      controller: _discounts,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppField(
                    label: 'Transport',
                    child: AppMoneyInput(
                      controller: _transport,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppField(
                    label: 'Taxes',
                    child: AppMoneyInput(
                      controller: _taxes,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppField(
                    label: 'Other charges',
                    child: AppMoneyInput(
                      controller: _other,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppField(
              label: 'Notes',
              optional: true,
              child: AppTextInput(controller: _notes, maxLines: 2),
            ),
          ],
        ),
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
          onPressed: () {
            a
              ..clientName = _client.text
              ..notes = _notes.text
              ..discounts = _of(_discounts)
              ..transportFee = _of(_transport)
              ..taxes = _of(_taxes)
              ..additionalCharges = _of(_other);
            Navigator.of(context).pop(a);
          },
        ),
      ],
    );
  }
}
