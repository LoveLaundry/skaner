import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'shop_bill_model.dart';

/// Port of `features/shop-bills/pages/create-shop-bill-page.tsx`, widened to
/// also cover editing an existing bill.
///
/// Create posts the whole document to `/shop-bills`; edit patches
/// `/shop-bills/{id}`. In edit mode the four scalar sub-resources
/// (`taxes`, `discount`, `transport-fee`, `notes`) are read back separately
/// after the bill itself, because the server recomputes them and the form must
/// show what it will actually save rather than what was typed years ago.
class ShopBillFormPage extends StatefulWidget {
  const ShopBillFormPage({super.key, this.billId});

  /// `null` creates a new bill; an id loads and patches the existing one.
  final String? billId;

  @override
  State<ShopBillFormPage> createState() => _ShopBillFormPageState();
}

class _ShopBillFormPageState extends State<ShopBillFormPage> {
  final _billNumber = TextEditingController();
  final _client = TextEditingController();
  final _notes = TextEditingController();
  final _discounts = TextEditingController();
  final _transportFee = TextEditingController();
  final _taxes = TextEditingController();

  List<ShopBillLine> _lines = const [];

  DateTime? _deliveryDate = DateTime.now();
  DateTime? _recurringEndDate;
  String _recurringInterval = 'MONTHLY';
  bool _isRecurring = false;
  bool _locked = false;

  bool _loading = false;
  bool _saving = false;
  bool _loaded = false;
  String? _loadError;
  String? _clientError;
  String? _itemsError;

  bool get _isEdit => widget.billId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _billNumber.dispose();
    _client.dispose();
    _notes.dispose();
    _discounts.dispose();
    _transportFee.dispose();
    _taxes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final services = AppScope.read(context);
    final id = widget.billId!;
    try {
      final payload =
          await services.api.get(ServiceNames.bills, ShopBillApi.one(id));
      final bill = asMap(payload);
      _billNumber.text = billNumber(bill);
      _client.text = billClient(bill);
      _notes.text = billNotes(bill);
      _deliveryDate = pick(bill, const ['delivery_date']) == null
          ? null
          : Fmt.parseDate(pick(bill, const ['delivery_date']));
      _isRecurring = boolOf(bill, const ['is_recurring']);
      _recurringInterval =
          str(bill, const ['recurring_interval'], 'MONTHLY').toUpperCase();
      final end = Fmt.parseDate(pick(bill, const ['recurring_end_date']));
      _recurringEndDate = end;
      _locked = boolOf(bill, const ['locked']);

      _lines = billLines(bill);

      // The bill row already carries these, but the server owns the scalar
      // sub-resources; read them back so an edit starts from the server's view.
      await _readBackScalars(id, bill);

      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  /// Each sub-resource is fetched independently and a 404 on any of them is not
  /// fatal: the bill row's own value is already correct.
  Future<void> _readBackScalars(String id, Map<String, dynamic> bill) async {
    final api = AppScope.read(context).api;
    double? taxes;
    double? discount;
    double? transport;
    String? notes;

    try {
      taxes = numOf(
          asMap(await api.get(
            ServiceNames.bills,
            ShopBillApi.taxes(id),
          )),
          const ['taxes', 'tax', 'amount', 'value']);
    } catch (_) {}
    try {
      discount = numOf(
          asMap(await api.get(
            ServiceNames.bills,
            ShopBillApi.discount(id),
          )),
          const ['discount', 'discounts', 'amount', 'value']);
    } catch (_) {}
    try {
      transport = numOf(
          asMap(await api.get(
            ServiceNames.bills,
            ShopBillApi.transportFee(id),
          )),
          const ['transport_fee', 'fee', 'amount', 'value']);
    } catch (_) {}
    try {
      notes = str(
          asMap(await api.get(
            ServiceNames.bills,
            ShopBillApi.notes(id),
          )),
          const ['notes', 'note']);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _taxes.text = _number(taxes ?? billTaxes(bill));
      _discounts.text = _number(discount ?? billDiscounts(bill));
      _transportFee.text = _number(transport ?? billTransportFee(bill));
      if (notes != null) _notes.text = notes;
    });
  }

  static String _number(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  double _read(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  List<ShopBillLine> get _usableLines =>
      _lines.where((l) => l.isUsable).toList();

  double get _subtotal => linesSubtotal(_usableLines);

  double get _discountValue => _read(_discounts);

  double get _transportValue => _read(_transportFee);

  double get _taxValue => _read(_taxes);

  double get _grandTotal => billGrandTotal(
        subtotal: _subtotal,
        discounts: _discountValue,
        transportFee: _transportValue,
        taxes: _taxValue,
      );

  bool get _canSave =>
      _client.text.trim().isNotEmpty && _usableLines.isNotEmpty && !_saving;

  Future<void> _save() async {
    final client = _client.text.trim();
    final usable = _usableLines;
    if (client.isEmpty || usable.isEmpty) {
      setState(() {
        _clientError = client.isEmpty ? 'Client name is required' : null;
        _itemsError = usable.isEmpty
            ? 'Add at least one item with a name, rate and qty'
            : null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _clientError = null;
      _itemsError = null;
    });

    final services = AppScope.read(context);
    final body = <String, dynamic>{
      if (_billNumber.text.trim().isNotEmpty)
        'bill_number': _billNumber.text.trim(),
      'client_name': client,
      'items': usable.map((l) => l.toJson()).toList(),
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      if (_deliveryDate != null) 'delivery_date': Fmt.isoDate(_deliveryDate),
      'discounts': _discountValue,
      'transport_fee': _transportValue,
      'taxes': _taxValue,
      'locked': _locked,
      if (_isRecurring) ...{
        'is_recurring': true,
        'recurring_interval': _recurringInterval,
        if (_recurringEndDate != null)
          'recurring_end_date': Fmt.isoDate(_recurringEndDate),
      },
    };

    try {
      final Object? result = _isEdit
          ? await services.api.patch(
              ServiceNames.bills, ShopBillApi.one(widget.billId!), body: body)
          : await services.api
              .post(ServiceNames.bills, ShopBillApi.list(), body: body);
      services.cache.invalidateResource('bills');
      if (!mounted) return;
      if (result is QueuedResponse) {
        AppToast.info(context, 'Queued — will sync when you are back online');
      } else {
        AppToast.success(
            context, _isEdit ? 'Shop bill updated' : 'Shop bill created');
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!services.auth.hasPermission(shopBillsPermission)) {
      return Scaffold(
        appBar:
            AppBar(title: Text(_isEdit ? 'Edit shop bill' : 'New shop bill')),
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
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shop bill')),
        body: AppErrorState(message: _loadError, onRetry: _load),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit shop bill' : 'New shop bill'),
        actions: [
          AppButton.icon(
            icon: Icons.save_outlined,
            tooltip: 'Save',
            variant: AppButtonVariant.primary,
            loading: _saving,
            onPressed: _canSave ? _save : null,
          ),
        ],
      ),
      body: _loaded || !_isEdit
          ? Column(
              children: [
                AppOfflineSyncBar(engine: services.sync),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
                      _BillInfoCard(
                        billNumber: _billNumber,
                        client: _client,
                        clientError: _clientError,
                        deliveryDate: _deliveryDate,
                        notes: _notes,
                        onDeliveryDate: (d) =>
                            setState(() => _deliveryDate = d),
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      _ItemsCard(
                        lines: _lines,
                        itemsError: _itemsError,
                        onChanged: (lines) => setState(() => _lines = lines),
                      ),
                      const SizedBox(height: 14),
                      _TotalsCard(
                        discounts: _discounts,
                        transportFee: _transportFee,
                        taxes: _taxes,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      _OptionsCard(
                        isRecurring: _isRecurring,
                        interval: _recurringInterval,
                        endDate: _recurringEndDate,
                        locked: _locked,
                        onRecurring: (v) => setState(() => _isRecurring = v),
                        onInterval: (v) =>
                            setState(() => _recurringInterval = v),
                        onEndDate: (v) => setState(() => _recurringEndDate = v),
                        onLocked: (v) => setState(() => _locked = v),
                      ),
                      const SizedBox(height: 18),
                      AppButton(
                        label: _isEdit ? 'Save changes' : 'Create shop bill',
                        variant: AppButtonVariant.primary,
                        size: AppButtonSize.lg,
                        expand: true,
                        icon: Icons.check,
                        loading: _saving,
                        onPressed: _canSave ? _save : null,
                      ),
                    ],
                  ),
                ),
              ],
            )
          : const AppLoader(),
    );
  }
}

class _BillInfoCard extends StatelessWidget {
  const _BillInfoCard({
    required this.billNumber,
    required this.client,
    required this.notes,
    required this.deliveryDate,
    required this.onDeliveryDate,
    required this.onChanged,
    this.clientError,
  });

  final TextEditingController billNumber;
  final TextEditingController client;
  final TextEditingController notes;
  final DateTime? deliveryDate;
  final ValueChanged<DateTime?> onDeliveryDate;
  final VoidCallback onChanged;
  final String? clientError;

  @override
  Widget build(BuildContext context) => AppCard(
        title: 'Bill information',
        child: Column(
          children: [
            AppField(
              label: 'Bill number',
              hint: 'Auto-generated if left empty',
              optional: true,
              child: AppTextInput(
                controller: billNumber,
                hint: 'e.g. SB-12345678',
                icon: Icons.tag,
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(height: 12),
            AppField(
              label: 'Client name',
              required: true,
              error: clientError,
              child: AppTextInput(
                controller: client,
                hint: 'Shop / client name',
                icon: Icons.storefront_outlined,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(height: 12),
            AppField(
              label: 'Delivery date',
              optional: true,
              child:
                  AppDateField(value: deliveryDate, onChanged: onDeliveryDate),
            ),
            const SizedBox(height: 12),
            AppField(
              label: 'Notes',
              optional: true,
              child: AppTextInput(
                controller: notes,
                hint: 'Optional notes…',
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
          ],
        ),
      );
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({
    required this.lines,
    required this.onChanged,
    this.itemsError,
  });

  final List<ShopBillLine> lines;
  final ValueChanged<List<ShopBillLine>> onChanged;
  final String? itemsError;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return AppCard(
      title: 'Items',
      subtitle: '${lines.length} line${lines.length == 1 ? '' : 's'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShopBillItemsEditor(
            initial: lines,
            error: itemsError,
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Subtotal',
                  style: t.labelMedium?.copyWith(color: c.fgMuted)),
              const Spacer(),
              Text(Fmt.money(linesSubtotal(lines)), style: t.titleSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.discounts,
    required this.transportFee,
    required this.taxes,
    required this.onChanged,
  });

  final TextEditingController discounts;
  final TextEditingController transportFee;
  final TextEditingController taxes;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_ShopBillFormPageState>()!;
    return AppCard(
      title: 'Totals',
      child: Column(
        children: [
          AppField(
            label: 'Bill discount',
            hint: '0.00',
            child: AppMoneyInput(
              controller: discounts,
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: 12),
          AppField(
            label: 'Transport fee',
            hint: '0.00',
            child: AppMoneyInput(
              controller: transportFee,
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: 12),
          AppField(
            label: 'Taxes',
            hint: '0.00',
            child: AppMoneyInput(
              controller: taxes,
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: 14),
          TotalRow(
            'Subtotal',
            Fmt.money(state._subtotal),
          ),
          if (state._discountValue > 0)
            TotalRow('Discounts', '- ${Fmt.money(state._discountValue)}'),
          if (state._transportValue > 0)
            TotalRow('Transport', '+ ${Fmt.money(state._transportValue)}'),
          if (state._taxValue > 0)
            TotalRow('Taxes', '+ ${Fmt.money(state._taxValue)}'),
          TotalRow(
            'Grand total',
            Fmt.money(state._grandTotal),
            strong: true,
            accent: true,
          ),
          const SizedBox(height: 4),
          Text(
            '${Fmt.qty(linesQuantity(state._usableLines))} units',
            style: context.texts.labelSmall?.copyWith(color: context.c.fgFaint),
          ),
        ],
      ),
    );
  }
}

class _OptionsCard extends StatelessWidget {
  const _OptionsCard({
    required this.isRecurring,
    required this.interval,
    required this.endDate,
    required this.locked,
    required this.onRecurring,
    required this.onInterval,
    required this.onEndDate,
    required this.onLocked,
  });

  final bool isRecurring;
  final String interval;
  final DateTime? endDate;
  final bool locked;
  final ValueChanged<bool> onRecurring;
  final ValueChanged<String> onInterval;
  final ValueChanged<DateTime?> onEndDate;
  final ValueChanged<bool> onLocked;

  @override
  Widget build(BuildContext context) => AppCard(
        title: 'Options',
        child: Column(
          children: [
            SwitchListTile(
              value: isRecurring,
              onChanged: onRecurring,
              contentPadding: EdgeInsets.zero,
              title: const Text('Make this a recurring bill'),
              subtitle: const Text('Copies are generated on a schedule'),
            ),
            if (isRecurring) ...[
              const SizedBox(height: 6),
              AppField(
                label: 'Interval',
                child: AppSearchableSelect<String>(
                  value: interval,
                  searchable: false,
                  options: [
                    for (final i in recurringIntervalOptions)
                      AppSelectOption<String>(
                        value: i,
                        label: Fmt.humanise(i),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) onInterval(v);
                  },
                ),
              ),
              const SizedBox(height: 12),
              AppField(
                label: 'End date',
                optional: true,
                child: AppDateField(value: endDate, onChanged: onEndDate),
              ),
            ],
            SwitchListTile(
              value: locked,
              onChanged: onLocked,
              contentPadding: EdgeInsets.zero,
              title: const Text('Lock this bill'),
              subtitle: const Text('Prevents edits after creation'),
            ),
          ],
        ),
      );
}
