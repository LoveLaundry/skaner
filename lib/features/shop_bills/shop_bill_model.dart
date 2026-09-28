import 'package:flutter/material.dart';

import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';

/// The web app gates every shop-bill surface behind this one string; it has no
/// finer read/write split, so the whole screen hides without it.
const String shopBillsPermission = 'view_bills';

/// One line of a bill. The web app calls the money field `unit_price` and the
/// row total `line_total`; the server recomputes the total, we only mirror it.
class ShopBillLine {
  const ShopBillLine({
    this.itemName = '',
    this.specification = '',
    this.category = '',
    this.unitPrice = 0,
    this.quantity = 0,
    this.discount = 0,
    this.discountType = 'FIXED',
    this.lineTotal = 0,
  });

  final String itemName;
  final String specification;
  final String category;
  final double unitPrice;
  final double quantity;
  final double discount;
  final String discountType;
  final double lineTotal;

  bool get isPercent => discountType.toUpperCase() == 'PERCENT';
  bool get isUsable =>
      itemName.trim().isNotEmpty && unitPrice > 0 && quantity > 0;

  /// Mirrors `calcItemTotal` on the create page, which does not clamp — the
  /// clamp happens when the lines are summed.
  double get rawTotal {
    final base = unitPrice * quantity;
    return isPercent ? base * (1 - discount / 100) : base - discount;
  }

  double get total => rawTotal <= 0 ? 0 : rawTotal;

  ShopBillLine copyWith({
    String? itemName,
    String? specification,
    String? category,
    double? unitPrice,
    double? quantity,
    double? discount,
    String? discountType,
  }) =>
      ShopBillLine(
        itemName: itemName ?? this.itemName,
        specification: specification ?? this.specification,
        category: category ?? this.category,
        unitPrice: unitPrice ?? this.unitPrice,
        quantity: quantity ?? this.quantity,
        discount: discount ?? this.discount,
        discountType: discountType ?? this.discountType,
        lineTotal: total,
      );

  factory ShopBillLine.fromJson(Map<String, dynamic> json) => ShopBillLine(
        itemName: str(json, const ['item_name', 'name', 'description']),
        specification: str(json, const ['specification', 'spec']),
        category: str(json, const ['category']),
        unitPrice: numOf(json, const ['unit_price', 'rate', 'price']),
        quantity: numOf(json, const ['quantity', 'qty']),
        discount: numOf(json, const ['discount']),
        discountType: str(json, const ['discount_type'], 'FIXED'),
        lineTotal: numOf(json, const ['line_total', 'total', 'amount']),
      );

  Map<String, dynamic> toJson() => {
        'item_name': itemName.trim(),
        if (specification.trim().isNotEmpty)
          'specification': specification.trim(),
        if (category.trim().isNotEmpty) 'category': category.trim(),
        'unit_price': unitPrice,
        'quantity': quantity,
        'discount': discount,
        'discount_type': discountType,
      };
}

List<ShopBillLine> billLines(Map<String, dynamic> row) {
  final raw = pick(row, const ['items', 'lines', 'line_items', 'entries']);
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => ShopBillLine.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

double linesSubtotal(List<ShopBillLine> lines) =>
    lines.fold<double>(0, (sum, line) => sum + line.total);

double linesQuantity(List<ShopBillLine> lines) =>
    lines.fold<double>(0, (sum, line) => sum + line.quantity);

/// The web app's arithmetic: `total - discounts + transport + taxes`, floored
/// at zero so an over-discounted bill never shows a negative grand total.
double billGrandTotal({
  required double subtotal,
  required double discounts,
  required double transportFee,
  required double taxes,
}) {
  final total = subtotal - discounts + transportFee + taxes;
  return total <= 0 ? 0 : total;
}

// ── Field readers ────────────────────────────────────────────────────────────
String billNumber(Map<String, dynamic> r) =>
    str(r, const ['bill_number', 'bill_no', 'number', 'invoice_number']);

String billClient(Map<String, dynamic> r) =>
    str(r, const ['client_name', 'client', 'shop_name', 'name']);

String billStatus(Map<String, dynamic> r) =>
    str(r, const ['status'], 'PENDING').toUpperCase();

String billPaymentStatus(Map<String, dynamic> r) =>
    str(r, const ['payment_status', 'paymentState'], 'DRAFT').toUpperCase();

double billTotalAmount(Map<String, dynamic> r) =>
    numOf(r, const ['total_amount', 'subtotal', 'sub_total']);

double billGrandTotalOf(Map<String, dynamic> r) =>
    numOf(r, const ['grand_total', 'total', 'net_total']);

double billDiscounts(Map<String, dynamic> r) =>
    numOf(r, const ['discounts', 'discount']);

double billTransportFee(Map<String, dynamic> r) =>
    numOf(r, const ['transport_fee', 'transport']);

double billTaxes(Map<String, dynamic> r) => numOf(r, const ['taxes', 'tax']);

double billPaid(Map<String, dynamic> r) =>
    numOf(r, const ['paid_amount', 'amount_paid', 'paid']);

double billOutstanding(Map<String, dynamic> r) => numOf(
      r,
      const ['outstanding_amount', 'outstanding', 'balance_due', 'due'],
      (billGrandTotalOf(r) - billPaid(r)) < 0
          ? 0
          : billGrandTotalOf(r) - billPaid(r),
    );

String billNotes(Map<String, dynamic> r) => str(r, const ['notes', 'note']);

List<String> billTags(Map<String, dynamic> r) {
  final raw = pick(r, const ['tags', 'labels']);
  if (raw is List) {
    return raw.map((e) => '$e').where((e) => e.isNotEmpty).toList();
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const [];
}

Map<String, dynamic> asMap(dynamic payload) =>
    payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};

/// The `PENDING → PROCESSING → DELIVERED → COMPLETED` ladder the web app's
/// "advance status" button walks.
const List<String> shopBillStatusFlow = [
  'PENDING',
  'PROCESSING',
  'DELIVERED',
  'COMPLETED',
];

const List<String> paymentMethodOptions = [
  'Cash',
  'Bank Transfer',
  'Cheque',
  'Card',
];

const List<String> recurringIntervalOptions = [
  'DAILY',
  'WEEKLY',
  'BIWEEKLY',
  'MONTHLY',
];

/// Operational status is a different axis from payment status, so it gets its
/// own badge rather than borrowing [BillStatusBadge]'s payment mapping.
AppTone shopBillStatusTone(String? status) => switch (status?.toUpperCase()) {
      'PENDING' => AppTone.warning,
      'PROCESSING' => AppTone.info,
      'DELIVERED' => AppTone.brand,
      'COMPLETED' => AppTone.success,
      'CANCELLED' => AppTone.neutral,
      _ => AppTone.neutral,
    };

/// Every `/shop-bills` path the React service declares, in one place so no
/// screen can invent a route. Segments that carry user input are encoded.
class ShopBillApi {
  const ShopBillApi._();

  static String list() => '/shop-bills';

  static String one(String id) => '/shop-bills/$id';

  static String item(String id) => '/shop-bills/$id/item';

  static String itemIndex(String id, int index) =>
      '/shop-bills/$id/items/$index';

  static String bulkItems(String id) => '/shop-bills/$id/items/bulk-update';

  static String reorder(String id) => '/shop-bills/$id/items/reorder';

  static String taxes(String id) => '/shop-bills/$id/taxes';

  static String discount(String id) => '/shop-bills/$id/discount';

  static String transportFee(String id) => '/shop-bills/$id/transport-fee';

  static String notes(String id) => '/shop-bills/$id/notes';

  static String notesCategory(String id) => '/shop-bills/$id/notes-category';

  static String notesHistory(String id) => '/shop-bills/$id/notes-history';

  static String recordPayment(String id) => '/shop-bills/$id/record-payment';

  static String paymentHistory(String id) => '/shop-bills/$id/payment-history';

  static String timeline(String id) => '/shop-bills/$id/timeline';

  static String versions(String id) => '/shop-bills/$id/versions';

  static String attachments(String id) => '/shop-bills/$id/attachments';

  static String refund(String id) => '/shop-bills/$id/refund';

  static String creditNote(String id) => '/shop-bills/$id/credit-note';

  static String voidBill(String id) => '/shop-bills/$id/void';

  static String archive(String id) => '/shop-bills/$id/archive';

  static String restore(String id) => '/shop-bills/$id/restore';

  static String duplicate(String id) => '/shop-bills/$id/duplicate';

  static String duplicateOptions(String id) =>
      '/shop-bills/$id/duplicate-options';

  static String mergeBills(String id) => '/shop-bills/$id/merge-bills';

  static String splitBill(String id) => '/shop-bills/$id/split-bill';

  static String linkQuotation(String id) => '/shop-bills/$id/link-quotation';

  static String transferClient(String id) => '/shop-bills/$id/transfer-client';

  static String markDelivered(String id) => '/shop-bills/$id/mark-delivered';

  static String deliveryDate(String id) => '/shop-bills/$id/delivery-date';

  static String makeRecurring(String id) => '/shop-bills/$id/make-recurring';

  static String printData(String id) => '/shop-bills/$id/print-data';

  static String tag(String id) => '/shop-bills/$id/tag';

  static String tagOne(String id, String tag) =>
      '/shop-bills/$id/tag/${Uri.encodeComponent(tag)}';

  static String byNumber(String number) =>
      '/shop-bills/by-number/${Uri.encodeComponent(number)}';

  static String byTag(String tag) =>
      '/shop-bills/by-tag/${Uri.encodeComponent(tag)}';

  static String clientCount(String name) =>
      '/shop-bills/client-count/${Uri.encodeComponent(name)}';

  static String clientLoyalty(String name) =>
      '/shop-bills/client-loyalty/${Uri.encodeComponent(name)}';

  static String clientStatement(String name) =>
      '/shop-bills/clients/${Uri.encodeComponent(name)}/statement';

  static String fromQuotation(String id) => '/shop-bills/from-quotation/$id';

  static String legacy() => '/shop-bills/legacy';

  static String legacyOne(String id) => '/shop-bills/legacy/$id';

  static String auditTrail(String id) => '/shop-bills/audit-trail/$id';

  static String templates() => '/shop-bills/templates';

  static String templateOne(String id) => '/shop-bills/templates/$id';

  static String templateDuplicate(String id) =>
      '/shop-bills/templates/$id/duplicate';

  static String templateUsage(String id) => '/shop-bills/templates/$id/usage';
}

/// A label/value line, used by the detail, print and statement documents so all
/// three read the same way.
class FieldRow extends StatelessWidget {
  const FieldRow(
    this.label,
    this.value, {
    super.key,
    this.emphasis = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasis;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: t.labelSmall?.copyWith(color: c.fgFaint),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: (emphasis ? t.titleSmall : t.bodyMedium)?.copyWith(
                color: valueColor ?? (emphasis ? c.fg : c.fg2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hairline-separated money line for a totals block.
class TotalRow extends StatelessWidget {
  const TotalRow(
    this.label,
    this.value, {
    super.key,
    this.strong = false,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool strong;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final style = (strong ? t.titleSmall : t.bodyMedium)
        ?.copyWith(color: accent ? c.brandText : c.fg);
    return Padding(
      padding: EdgeInsets.only(top: strong ? 8 : 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: strong
              ? Border(top: BorderSide(color: c.line, width: 1.5))
              : const Border(),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: strong ? 8 : 0),
          child: Row(
            children: [
              Expanded(child: Text(label, style: style)),
              Text(value, style: style),
            ],
          ),
        ),
      ),
    );
  }
}

/// One editable line, owning its own controllers.
///
/// The form and the template editor both need the same row: name, spec,
/// category, qty, rate, discount and discount type, with the line total derived
/// rather than typed. Keeping the controllers here means typing in one row never
/// rebuilds the text in another, and a caller only ever sees finished
/// [ShopBillLine] values.
class ShopBillLineDraft {
  ShopBillLineDraft({ShopBillLine? seed}) {
    if (seed == null) {
      qty.text = '1';
      return;
    }
    name.text = seed.itemName;
    spec.text = seed.specification;
    category.text = seed.category;
    price.text = _plain(seed.unitPrice);
    qty.text = _plain(seed.quantity);
    discount.text = _plain(seed.discount);
    discountType = seed.discountType;
  }

  final name = TextEditingController();
  final spec = TextEditingController();
  final category = TextEditingController();
  final price = TextEditingController();
  final qty = TextEditingController();
  final discount = TextEditingController();
  String discountType = 'FIXED';

  ShopBillLine toLine() => ShopBillLine(
        itemName: name.text,
        specification: spec.text,
        category: category.text,
        unitPrice: _read(price.text),
        quantity: _read(qty.text),
        discount: _read(discount.text),
        discountType: discountType,
      );

  void dispose() {
    name.dispose();
    spec.dispose();
    category.dispose();
    price.dispose();
    qty.dispose();
    discount.dispose();
  }

  static double _read(String raw) =>
      double.tryParse(raw.replaceAll(',', '').trim()) ?? 0;

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

/// A multi-line item editor.
///
/// Reports only the rows that carry a name, so a half-typed scratch row at the
/// bottom never reaches the wire, and keeps at least [minimumLines] row so the
/// operator always has somewhere to type.
class ShopBillItemsEditor extends StatefulWidget {
  const ShopBillItemsEditor({
    super.key,
    required this.onChanged,
    this.initial = const [],
    this.minimumLines = 1,
    this.error,
  });

  final ValueChanged<List<ShopBillLine>> onChanged;
  final List<ShopBillLine> initial;
  final int minimumLines;
  final String? error;

  @override
  State<ShopBillItemsEditor> createState() => _ShopBillItemsEditorState();
}

class _ShopBillItemsEditorState extends State<ShopBillItemsEditor> {
  late final List<ShopBillLineDraft> _drafts = [
    for (final line in widget.initial) ShopBillLineDraft(seed: line),
  ];

  @override
  void initState() {
    super.initState();
    if (_drafts.length < widget.minimumLines) {
      while (_drafts.length < widget.minimumLines) {
        _drafts.add(ShopBillLineDraft());
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged(namedLines);

  List<ShopBillLine> get namedLines => _drafts
      .map((d) => d.toLine())
      .where((l) => l.itemName.trim().isNotEmpty)
      .toList();

  void _add() {
    setState(() => _drafts.add(ShopBillLineDraft()));
    _emit();
  }

  void _remove(int index) {
    if (_drafts.length <= widget.minimumLines) return;
    final removed = _drafts.removeAt(index);
    removed.dispose();
    setState(_emit);
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _drafts.length) return;
    setState(() {
      final draft = _drafts.removeAt(index);
      _drafts.insert(target, draft);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _drafts.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _DraftRow(
              index: i,
              draft: _drafts[i],
              canRemove: _drafts.length > widget.minimumLines,
              canMoveUp: i > 0,
              canMoveDown: i < _drafts.length - 1,
              onRemove: () => _remove(i),
              onMoveUp: () => _move(i, -1),
              onMoveDown: () => _move(i, 1),
              onChanged: _emit,
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Add item',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.outline,
              icon: Icons.add,
              onPressed: _add,
            ),
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 10),
            AppNotice(message: widget.error!, tone: AppTone.danger),
          ],
        ],
      );
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onChanged,
  });

  final int index;
  final ShopBillLineDraft draft;
  final bool canRemove;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface3,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text('${index + 1}',
                    style: t.labelSmall?.copyWith(color: c.fg3)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child:
                    Text(Fmt.money(draft.toLine().total), style: t.titleSmall),
              ),
              _DraftIcon(
                icon: Icons.keyboard_arrow_up,
                tooltip: 'Move up',
                onTap: canMoveUp ? onMoveUp : null,
              ),
              _DraftIcon(
                icon: Icons.keyboard_arrow_down,
                tooltip: 'Move down',
                onTap: canMoveDown ? onMoveDown : null,
              ),
              _DraftIcon(
                icon: Icons.close,
                tooltip: 'Remove line',
                danger: true,
                onTap: canRemove ? onRemove : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppField(
            label: 'Item name',
            required: true,
            child: AppTextInput(
              controller: draft.name,
              hint: 'e.g. Bed sheet',
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppField(
                  label: 'Qty',
                  required: true,
                  child: AppNumberInput(
                    controller: draft.qty,
                    allowDecimal: true,
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppField(
                  label: 'Rate',
                  required: true,
                  child: AppMoneyInput(
                    controller: draft.price,
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppField(
                  label: 'Discount',
                  child: AppMoneyInput(
                    controller: draft.discount,
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppField(
                  label: 'Discount type',
                  child: AppSearchableSelect<String>(
                    value: draft.discountType,
                    searchable: false,
                    options: const [
                      AppSelectOption<String>(value: 'FIXED', label: 'Fixed'),
                      AppSelectOption<String>(
                          value: 'PERCENT', label: 'Percent'),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      draft.discountType = v;
                      onChanged();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppField(
                  label: 'Specification',
                  optional: true,
                  child: AppTextInput(
                    controller: draft.spec,
                    hint: 'Size / colour',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppField(
                  label: 'Category',
                  optional: true,
                  child: AppTextInput(
                    controller: draft.category,
                    hint: 'Category',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DraftIcon extends StatelessWidget {
  const _DraftIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null
                ? c.fgFaint.withValues(alpha: 0.4)
                : (danger ? c.danger : c.fg3),
          ),
        ),
      ),
    );
  }
}
