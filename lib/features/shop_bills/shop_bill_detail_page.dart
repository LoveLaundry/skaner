import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'shop_bill_form_page.dart';
import 'shop_bill_model.dart';
import 'shop_bill_print_page.dart';

/// Port of `features/shop-bills/pages/shop-bill-detail-page.tsx`.
///
/// Every mutation here mirrors a `shop-bill.service.ts` route: status advance
/// and lock are plain PATCHes on the bill, while payment, split, duplicate and
/// recurrence each have their own action endpoint. A bill the server has locked
/// hides the edit affordance rather than letting the operator start a change
/// the server will reject.
class ShopBillDetailPage extends StatefulWidget {
  const ShopBillDetailPage({super.key, required this.billId});

  final String billId;

  @override
  State<ShopBillDetailPage> createState() => _ShopBillDetailPageState();
}

class _ShopBillDetailPageState extends State<ShopBillDetailPage> {
  Map<String, dynamic> _bill = const {};
  List<Map<String, dynamic>> _payments = const [];
  List<Map<String, dynamic>> _timeline = const [];

  bool _loading = true;
  String? _error;
  String? _busyAction;
  int _tab = 0;

  static const _statusFlow = <String, String>{
    'PENDING': 'PROCESSING',
    'PROCESSING': 'DELIVERED',
    'DELIVERED': 'COMPLETED',
  };

  static const _paymentMethods = <String>[
    'Cash',
    'Card',
    'Bank Transfer',
    'Cheque',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _id => widget.billId;

  String? get _nextStatus => _statusFlow[billStatus(_bill)];

  bool get _locked => boolOf(_bill, const ['locked']);

  bool get _isCancelled => billStatus(_bill) == 'CANCELLED';

  bool get _isPaid => billPaymentStatus(_bill) == 'PAID';

  bool get _isRecurring => boolOf(_bill, const ['is_recurring']);

  bool _isBusy(String action) => _busyAction == action;

  Future<void> _load() async {
    if (!mounted) return;
    final services = AppScope.read(context);
    try {
      final payload =
          await services.api.get(ServiceNames.bills, ShopBillApi.one(_id));
      if (!mounted) return;
      setState(() {
        _bill = asMap(payload);
        _loading = false;
        _error = null;
      });
      _loadSideChannels();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// History is decoration, not the bill: a failure here leaves the tabs empty
  /// instead of turning a loaded bill into an error screen.
  Future<void> _loadSideChannels() async {
    final api = AppScope.read(context).api;
    try {
      _payments = asRows(
        await api.get(ServiceNames.bills, ShopBillApi.paymentHistory(_id)),
      );
    } catch (_) {
      _payments = const [];
    }
    try {
      _timeline = asRows(
        await api.get(ServiceNames.bills, ShopBillApi.timeline(_id)),
      );
    } catch (_) {
      _timeline = const [];
    }
    if (mounted) setState(() {});
  }

  /// Runs one mutation, then re-reads the bill so the header, totals and
  /// payment status all come from the server instead of a local guess.
  Future<void> _act(
    String name,
    String method,
    String path, {
    Object? body,
    String? success,
    bool pop = false,
    void Function(dynamic result)? onDone,
  }) async {
    if (_busyAction != null) return;
    setState(() => _busyAction = name);
    final services = AppScope.read(context);
    final api = services.api;
    try {
      final result = switch (method) {
        'POST' => await api.post(ServiceNames.bills, path, body: body),
        'PATCH' => await api.patch(ServiceNames.bills, path, body: body),
        'PUT' => await api.put(ServiceNames.bills, path, body: body),
        _ => await api.delete(ServiceNames.bills, path, body: body),
      };
      services.cache.invalidateResource('bills');
      if (!mounted) return;
      if (pop) {
        Navigator.of(context).pop();
        return;
      }
      if (result is QueuedResponse) {
        AppToast.info(context, 'Queued — will sync when you are back online');
      } else if (success != null) {
        AppToast.success(context, success);
      }
      setState(() => _busyAction = null);
      onDone?.call(result);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busyAction = null);
      AppToast.error(context, e.message);
    }
  }

  Future<void> _advanceStatus() async {
    final next = _nextStatus;
    if (next == null) return;
    await _act(
      'status',
      'PATCH',
      ShopBillApi.one(_id),
      body: {'status': next},
      success: 'Marked as ${Fmt.humanise(next)}',
    );
  }

  Future<void> _toggleLock() async {
    await _act(
      'lock',
      'PATCH',
      ShopBillApi.one(_id),
      body: {'locked': !_locked},
      success: _locked ? 'Bill unlocked' : 'Bill locked',
    );
  }

  Future<void> _recordPayment() {
    final outstanding = billOutstanding(_bill);
    final amount = TextEditingController(
      text: outstanding > 0 ? outstanding.toStringAsFixed(2) : '',
    );
    final reference = TextEditingController();
    final notes = TextEditingController();
    var method = _paymentMethods.first;
    var date = Fmt.lktNow();

    return AppDialog.show<bool>(
      context,
      title: 'Record payment',
      icon: Icons.payments_outlined,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (outstanding > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppNotice(
                message: 'Outstanding: ${Fmt.money(outstanding)}',
                tone: AppTone.warning,
              ),
            ),
          AppField(
            label: 'Amount',
            required: true,
            child: AppMoneyInput(controller: amount),
          ),
          const SizedBox(height: 10),
          AppField(
            label: 'Method',
            child: AppSearchableSelect<String>(
              value: method,
              searchable: false,
              options: [
                for (final m in _paymentMethods)
                  AppSelectOption<String>(value: m, label: m),
              ],
              onChanged: (v) {
                if (v != null) method = v;
              },
            ),
          ),
          const SizedBox(height: 10),
          AppField(
            label: 'Date',
            child: AppDateField(
              value: date,
              onChanged: (v) => date = v ?? date,
            ),
          ),
          const SizedBox(height: 10),
          AppField(
            label: 'Reference',
            optional: true,
            child:
                AppTextInput(controller: reference, hint: 'Cheque no. / ref'),
          ),
          const SizedBox(height: 10),
          AppField(
            label: 'Notes',
            optional: true,
            child: AppTextInput(controller: notes, maxLines: 2),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Record',
          variant: AppButtonVariant.primary,
          icon: Icons.check,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ).then((ok) async {
      final value = double.tryParse(amount.text.replaceAll(',', '').trim());
      amount.dispose();
      reference.dispose();
      notes.dispose();
      if (ok != true || value == null || value <= 0) {
        if (ok == true && mounted) {
          AppToast.error(context, 'Enter an amount to record');
        }
        return;
      }
      await _act(
        'payment',
        'POST',
        ShopBillApi.recordPayment(_id),
        body: {
          'amount': value,
          'method': method,
          'date': Fmt.isoDate(date),
          if (reference.text.trim().isNotEmpty)
            'reference': reference.text.trim(),
          if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
        },
        success: 'Payment recorded',
      );
    });
  }

  Future<void> _duplicate() async {
    await _act(
      'duplicate',
      'POST',
      ShopBillApi.duplicate(_id),
      success: 'Bill duplicated',
      onDone: (result) {
        final copy = asMap(result);
        final copyId = str(copy, const ['id', 'bill_id', 'new_bill_id']);
        if (copyId.isNotEmpty) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => ShopBillDetailPage(billId: copyId)),
          );
        }
      },
    );
  }

  Future<void> _splitBill() {
    final lines = billLines(_bill);
    if (lines.isEmpty) return Future.value();
    final selected = <int>{};

    return AppDialog.show<bool>(
      context,
      title: 'Split bill',
      icon: Icons.call_split,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select the lines to move to a new bill.',
            style: context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < lines.length; i++)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(i),
                    title: Text('${i + 1}. ${lines[i].itemName}'),
                    subtitle: Text(
                      '${Fmt.qty(lines[i].quantity)} × ${Fmt.money(lines[i].unitPrice)}',
                    ),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        selected.add(i);
                      } else {
                        selected.remove(i);
                      }
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Split',
          variant: AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ).then((ok) async {
      if (ok != true || selected.isEmpty) {
        if (ok == true && mounted) {
          AppToast.error(context, 'Select at least one item');
        }
        return;
      }
      final indices = selected.toList()..sort();
      await _act(
        'split',
        'POST',
        ShopBillApi.splitBill(_id),
        body: {'item_indices': indices},
        success: 'Bill split',
      );
    });
  }

  Future<void> _makeRecurring() {
    var interval = recurringIntervalOptions.contains(billStatus(_bill))
        ? recurringIntervalOptions.first
        : (str(_bill, const ['recurring_interval'], 'MONTHLY').isEmpty
            ? 'MONTHLY'
            : str(_bill, const ['recurring_interval'], 'MONTHLY')
                .toUpperCase());
    DateTime? endDate =
        Fmt.parseDate(pick(_bill, const ['recurring_end_date']));

    return AppDialog.show<bool>(
      context,
      title: 'Make recurring',
      icon: Icons.repeat,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppField(
            label: 'Interval',
            child: AppSearchableSelect<String>(
              value: recurringIntervalOptions.contains(interval)
                  ? interval
                  : recurringIntervalOptions.first,
              searchable: false,
              options: [
                for (final i in recurringIntervalOptions)
                  AppSelectOption<String>(value: i, label: Fmt.humanise(i)),
              ],
              onChanged: (v) {
                if (v != null) interval = v;
              },
            ),
          ),
          const SizedBox(height: 10),
          AppField(
            label: 'End date',
            optional: true,
            child: AppDateField(
              value: endDate,
              onChanged: (v) => endDate = v,
            ),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Set recurring',
          variant: AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ).then((ok) async {
      if (ok != true) return;
      await _act(
        'recurring',
        'POST',
        ShopBillApi.makeRecurring(_id),
        body: {
          'interval': interval,
          if (endDate != null) 'end_date': Fmt.isoDate(endDate),
        },
        success: 'Bill set to recurring',
      );
    });
  }

  Future<void> _showNotesHistory() async {
    List<Map<String, dynamic>> history = const [];
    try {
      history = asRows(
        await AppScope.read(context).api.get(
              ServiceNames.bills,
              ShopBillApi.notesHistory(_id),
            ),
      );
    } catch (_) {
      history = const [];
    }
    if (!mounted) return;
    await AppDialog.show<void>(
      context,
      title: 'Notes history',
      icon: Icons.history,
      body: history.isEmpty
          ? const AppEmptyState(
              title: 'No history',
              message: 'This bill has no earlier notes.',
              icon: Icons.history_toggle_off,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in history)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FieldRow(
                      Fmt.humanise(
                        str(entry, const ['notes', 'note', 'text'], '—'),
                        fallback: '—',
                      ),
                      Fmt.dateTime(
                        pick(entry, const ['created_at', 'updated_at', 'date']),
                      ),
                    ),
                  ),
              ],
            ),
      actions: [
        AppButton(
          label: 'Close',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ShopBillFormPage(billId: _id)),
    );
    if (changed == true) _load();
  }

  Future<void> _print() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ShopBillPrintPage(billId: _id)),
      );

  Future<void> _delete() async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Delete shop bill?',
      message:
          'This permanently removes ${billNumber(_bill)}. Linked payments and '
          'history stay with the business record and cannot be restored here.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    await _act('delete', 'DELETE', ShopBillApi.one(_id), pop: true);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!services.auth.hasPermission(shopBillsPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shop bill')),
        body: const AppErrorState(
          title: 'Not permitted',
          message: 'You do not have access to shop bills.',
          icon: Icons.lock_outline,
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shop bill')),
        body: const AppLoader(label: 'Loading bill…'),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shop bill')),
        body: AppErrorState(message: _error, onRetry: _load),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(billNumber(_bill)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to shop bills',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          AppButton.icon(
            icon: Icons.print_outlined,
            tooltip: 'Print',
            onPressed: _print,
          ),
          if (!_locked && !_isCancelled)
            AppButton.icon(
              icon: Icons.edit_outlined,
              tooltip: 'Edit bill',
              onPressed: _edit,
            ),
          AppButton.icon(
            icon: Icons.delete_outline,
            tooltip: 'Delete bill',
            variant: AppButtonVariant.ghost,
            onPressed: _isBusy('delete') ? null : _delete,
          ),
        ],
      ),
      body: Column(
        children: [
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  AppPageHeader(
                    title: billNumber(_bill),
                    breadcrumb: const AppBreadcrumb(
                      trail: ['Shop bills', 'Detail'],
                    ),
                    subtitle: billClient(_bill),
                    busy: _busyAction != null,
                    tabs: AppTabs(
                      tabs: [
                        AppTabItem('Overview',
                            icon: Icons.receipt_long_outlined),
                        AppTabItem('Payments',
                            icon: Icons.payments_outlined,
                            count: _payments.length),
                        AppTabItem('Timeline',
                            icon: Icons.history, count: _timeline.length),
                      ],
                      index: _tab,
                      onChanged: (i) => setState(() => _tab = i),
                    ),
                    actions: [
                      BillStatusBadge(status: billPaymentStatus(_bill)),
                      AppBadge(
                        Fmt.humanise(billStatus(_bill)),
                        tone: shopBillStatusTone(billStatus(_bill)),
                        compact: true,
                      ),
                      if (_locked)
                        const AppBadge(
                          'Locked',
                          icon: Icons.lock_outline,
                          compact: true,
                        ),
                      if (_isRecurring)
                        AppBadge(
                          Fmt.humanise(
                            str(_bill, const ['recurring_interval'],
                                'Recurring'),
                          ),
                          tone: AppTone.info,
                          icon: Icons.repeat,
                          compact: true,
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    child: switch (_tab) {
                      1 => _PaymentsTab(payments: _payments, bill: _bill),
                      2 => _TimelineTab(entries: _timeline),
                      _ => _OverviewTab(
                          bill: _bill,
                          locked: _locked,
                          cancelled: _isCancelled,
                          paid: _isPaid,
                          busy: _busyAction,
                          onAdvance:
                              _nextStatus == null ? null : _advanceStatus,
                          onPayment: _isPaid ? null : _recordPayment,
                          onDuplicate: _duplicate,
                          onSplit: _splitBill,
                          onLock: _toggleLock,
                          onRecurring: _isRecurring ? null : _makeRecurring,
                          onNotesHistory: _showNotesHistory,
                          onEdit: _edit,
                        ),
                    },
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

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.bill,
    required this.locked,
    required this.cancelled,
    required this.paid,
    required this.busy,
    required this.onAdvance,
    required this.onPayment,
    required this.onDuplicate,
    required this.onSplit,
    required this.onLock,
    required this.onRecurring,
    required this.onNotesHistory,
    required this.onEdit,
  });

  final Map<String, dynamic> bill;
  final bool locked;
  final bool cancelled;
  final bool paid;
  final String? busy;
  final VoidCallback? onAdvance;
  final VoidCallback? onPayment;
  final VoidCallback onDuplicate;
  final VoidCallback onSplit;
  final VoidCallback onLock;
  final VoidCallback? onRecurring;
  final VoidCallback onNotesHistory;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final lines = billLines(bill);
    final subtotal = linesSubtotal(lines);
    final grand = billGrandTotalOf(bill);
    final paidAmount = billPaid(bill);
    final outstanding = billOutstanding(bill);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cancelled)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: AppNotice(
              message: 'This bill was cancelled and is read-only.',
              tone: AppTone.danger,
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onAdvance != null)
              AppButton(
                label: 'Mark as ${Fmt.humanise(_nextLabel(bill))}',
                variant: AppButtonVariant.primary,
                icon: Icons.arrow_forward,
                loading: busy == 'status',
                onPressed: onAdvance,
              ),
            if (onPayment != null)
              AppButton(
                label: 'Record payment',
                variant: AppButtonVariant.secondary,
                icon: Icons.payments_outlined,
                loading: busy == 'payment',
                onPressed: onPayment,
              ),
            if (!locked && !cancelled)
              AppButton(
                label: 'Edit',
                variant: AppButtonVariant.outline,
                icon: Icons.edit_outlined,
                onPressed: onEdit,
              ),
            if (!cancelled)
              AppButton(
                label: 'Duplicate',
                variant: AppButtonVariant.outline,
                icon: Icons.copy_all_outlined,
                loading: busy == 'duplicate',
                onPressed: onDuplicate,
              ),
            if (lines.isNotEmpty && !cancelled)
              AppButton(
                label: 'Split bill',
                variant: AppButtonVariant.outline,
                icon: Icons.call_split,
                loading: busy == 'split',
                onPressed: onSplit,
              ),
            AppButton(
              label: 'Notes history',
              variant: AppButtonVariant.outline,
              icon: Icons.history,
              onPressed: onNotesHistory,
            ),
            AppButton(
              label: locked ? 'Unlock' : 'Lock',
              variant: AppButtonVariant.outline,
              icon: locked ? Icons.lock_open : Icons.lock_outline,
              loading: busy == 'lock',
              onPressed: onLock,
            ),
            if (onRecurring != null)
              AppButton(
                label: 'Make recurring',
                variant: AppButtonVariant.outline,
                icon: Icons.repeat,
                loading: busy == 'recurring',
                onPressed: onRecurring,
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: AppStatCard(
                label: 'Grand total',
                value: Fmt.money(grand),
                icon: Icons.request_quote_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppStatCard(
                label: 'Paid',
                value: Fmt.money(paidAmount),
                icon: Icons.check_circle_outline,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppStatCard(
                label: 'Outstanding',
                value: Fmt.money(outstanding),
                icon: Icons.account_balance_wallet_outlined,
                footer: paid
                    ? const Text('Settled in full')
                    : outstanding > 0
                        ? Text(
                            '${Fmt.percent(outstanding / (grand == 0 ? 1 : grand) * 100)} due')
                        : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AppCard(
          title: 'Bill information',
          child: Column(
            children: [
              FieldRow(
                'Bill number',
                billNumber(bill),
              ),
              FieldRow('Client', billClient(bill)),
              FieldRow(
                'Created',
                Fmt.dateTime(pick(bill, const ['created_at'])),
              ),
              FieldRow(
                'Delivery date',
                Fmt.date(pick(bill, const ['delivery_date'])),
              ),
              FieldRow('Status', Fmt.humanise(billStatus(bill))),
              FieldRow(
                'Payment status',
                Fmt.humanise(billPaymentStatus(bill)),
              ),
              if (str(bill, const ['parent_bill', 'parent_bill_id']).isNotEmpty)
                FieldRow('Parent bill', str(bill, const ['parent_bill'])),
              if (str(bill, const [
                'quotation',
                'quotation_id',
                'quotation_number'
              ]).isNotEmpty)
                FieldRow(
                  'Quotation',
                  str(bill, const [
                    'quotation_number',
                    'quotation',
                    'quotation_id',
                  ]),
                ),
              if (billTags(bill).isNotEmpty)
                FieldRow('Tags', billTags(bill).join(', ')),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          title: 'Items',
          subtitle: '${lines.length} line${lines.length == 1 ? '' : 's'}',
          trailing: AppButton(
            label: 'Add item',
            size: AppButtonSize.sm,
            variant: AppButtonVariant.outline,
            icon: Icons.add,
            onPressed: () => onEdit(),
          ),
          child: lines.isEmpty
              ? const AppEmptyState(
                  title: 'No items',
                  message: 'This bill has no line items.',
                  icon: Icons.inventory_2_outlined,
                )
              : AppDataTable<ShopBillLine>(
                  rows: lines,
                  columns: [
                    AppDataColumn<ShopBillLine>(
                      label: 'Item',
                      value: (l) => l.itemName,
                      minWidth: 140,
                    ),
                    AppDataColumn<ShopBillLine>(
                      label: 'Spec',
                      value: (l) => l.specification.trim().isEmpty
                          ? '—'
                          : l.specification,
                    ),
                    AppDataColumn<ShopBillLine>(
                      label: 'Qty',
                      value: (l) => Fmt.qty(l.quantity),
                      minWidth: 70,
                    ),
                    AppDataColumn<ShopBillLine>(
                      label: 'Price',
                      value: (l) => Fmt.money(l.unitPrice),
                      minWidth: 90,
                    ),
                    AppDataColumn<ShopBillLine>(
                      label: 'Disc',
                      value: (l) => l.discount <= 0
                          ? '—'
                          : '${Fmt.money(l.discount)}'
                              '${l.discountType == 'PERCENT' ? '%' : ''}',
                      minWidth: 80,
                    ),
                    AppDataColumn<ShopBillLine>(
                      label: 'Total',
                      value: (l) => Fmt.money(l.total),
                      minWidth: 90,
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        AppCard(
          title: 'Totals',
          trailing: AppButton(
            label: 'Notes history',
            size: AppButtonSize.sm,
            variant: AppButtonVariant.ghost,
            icon: Icons.history,
            onPressed: onNotesHistory,
          ),
          child: Column(
            children: [
              TotalRow('Subtotal', Fmt.money(subtotal)),
              if (billDiscounts(bill) > 0)
                TotalRow('Discounts', '- ${Fmt.money(billDiscounts(bill))}'),
              if (billTransportFee(bill) > 0)
                TotalRow(
                  'Transport',
                  '+ ${Fmt.money(billTransportFee(bill))}',
                ),
              if (billTaxes(bill) > 0)
                TotalRow('Taxes', '+ ${Fmt.money(billTaxes(bill))}'),
              TotalRow(
                'Grand total',
                Fmt.money(grand),
                strong: true,
                accent: true,
              ),
              TotalRow('Paid', Fmt.money(paidAmount)),
              TotalRow('Outstanding', Fmt.money(outstanding)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          title: 'Notes',
          trailing: AppButton(
            label: 'Edit',
            size: AppButtonSize.sm,
            variant: AppButtonVariant.ghost,
            icon: Icons.edit_outlined,
            onPressed: onEdit,
          ),
          child: Text(
            billNotes(bill).trim().isEmpty
                ? 'No notes on this bill.'
                : billNotes(bill),
            style: context.texts.bodyMedium,
          ),
        ),
      ],
    );
  }

  static String _nextLabel(Map<String, dynamic> bill) =>
      switch (billStatus(bill)) {
        'PENDING' => 'PROCESSING',
        'PROCESSING' => 'DELIVERED',
        'DELIVERED' => 'COMPLETED',
        _ => 'COMPLETED',
      };
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({required this.payments, required this.bill});

  final List<Map<String, dynamic>> payments;
  final Map<String, dynamic> bill;

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return const AppEmptyState(
        title: 'No payments yet',
        message: 'Payments recorded against this bill appear here.',
        icon: Icons.payments_outlined,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppStatCard(
          label: 'Total received',
          value: Fmt.money(billPaid(bill)),
          icon: Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(height: 14),
        AppDataTable<Map<String, dynamic>>(
          rows: payments,
          columns: [
            AppDataColumn<Map<String, dynamic>>(
              label: 'Date',
              value: (r) =>
                  Fmt.date(pick(r, const ['date', 'created_at', 'paid_at'])),
            ),
            AppDataColumn<Map<String, dynamic>>(
              label: 'Method',
              value: (r) => Fmt.humanise(
                str(r, const ['method', 'payment_method', 'mode']),
              ),
            ),
            AppDataColumn<Map<String, dynamic>>(
              label: 'Reference',
              value: (r) {
                final ref = str(r, const ['reference', 'ref', 'cheque_no']);
                return ref.isEmpty ? '—' : ref;
              },
            ),
            AppDataColumn<Map<String, dynamic>>(
              label: 'Amount',
              value: (r) => Fmt.money(
                numOf(r, const ['amount', 'paid_amount', 'value']),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.entries});

  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const AppEmptyState(
        title: 'No activity',
        message: 'Status changes and edits are recorded here.',
        icon: Icons.history_toggle_off,
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: context.c.brand,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Fmt.humanise(
                            str(entry,
                                const ['action', 'event', 'title', 'type']),
                          ),
                          style: context.texts.titleSmall,
                        ),
                        Text(
                          Fmt.relative(
                            pick(entry,
                                const ['created_at', 'timestamp', 'date']),
                          ),
                          style: context.texts.labelSmall
                              ?.copyWith(color: context.c.fgFaint),
                        ),
                        if (str(entry, const ['description', 'note', 'by'])
                            .trim()
                            .isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              str(entry, const [
                                'description',
                                'note',
                                'by',
                              ]),
                              style: context.texts.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
