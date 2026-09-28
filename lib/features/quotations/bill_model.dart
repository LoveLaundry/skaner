import '../../core/models/json.dart' hide asInt, asString;
import '../../data/resource_controller.dart';
import 'quotation_model.dart';

/// A field the server may legitimately leave empty, so "absent" stays
/// distinguishable from "blank".
String? strOrNull(Map<String, dynamic> row, List<String> keys) {
  final v = asStringOrNull(pick(row, keys));
  return v;
}

int? intOrNull(Map<String, dynamic> row, List<String> keys) {
  final v = pick(row, keys);
  if (v == null) return null;
  if (v is num) return v.round();
  if (v is String && v.trim().isEmpty) return null;
  return asInt(v);
}

List<String> asStrings(Object? v) {
  if (v is! List) return const [];
  return v.map((e) => asString(e).trim()).where((e) => e.isNotEmpty).toList();
}

/// Mirrors the web client's `toISODatetime`: a bare `yyyy-MM-dd` becomes
/// `yyyy-MM-ddT00:00:00`, and a value that already carries a time is sent
/// through untouched.
String isoDateOf(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return isoDateTime(DateTime.now());
  if (value.contains('T')) return value;
  return '${value.split(' ').first}T00:00:00';
}

class BillApi {
  BillApi._();

  static const String list = '/bills';
  static const String unbilledGatePasses = '/bills/unbilled-gatepasses';
  static String one(String id) => '/bills/$id';
  static String payments(String id) => '/bills/$id/payments';
}

/// One line of a hotel bill. The server recomputes `line_total`; it is only
/// ever read here, never sent.
class BillLine {
  const BillLine({
    this.itemName = '',
    this.category = '',
    this.unitPrice = 0,
    this.quantity = 0,
    this.lineTotal = 0,
  });

  final String itemName;
  final String category;
  final double unitPrice;
  final double quantity;
  final double lineTotal;

  factory BillLine.fromJson(Map<String, dynamic> j) => BillLine(
        itemName: str(j, const ['item_name', 'name']),
        category: str(j, const ['category']),
        unitPrice: numOf(j, const ['unit_price', 'rate', 'price']),
        quantity: numOf(j, const ['quantity', 'qty']),
        lineTotal: numOf(j, const ['line_total', 'total', 'amount']),
      );

  Map<String, dynamic> toJson() => {
        'item_name': itemName.trim(),
        if (category.trim().isNotEmpty) 'category': category.trim(),
        'unit_price': unitPrice,
        'quantity': quantity,
      };

  BillLine copyWith({double? quantity, double? unitPrice}) => BillLine(
        itemName: itemName,
        category: category,
        unitPrice: unitPrice ?? this.unitPrice,
        quantity: quantity ?? this.quantity,
        lineTotal: (unitPrice ?? this.unitPrice) * (quantity ?? this.quantity),
      );
}

class BillRecord {
  const BillRecord({
    required this.id,
    required this.clientName,
    required this.items,
    this.quotationId = '',
    this.title,
    this.totalQuantity = 0,
    this.totalAmount = 0,
    this.grandTotal,
    this.discounts = 0,
    this.transportFee = 0,
    this.taxes = 0,
    this.additionalCharges = 0,
    this.paidAmount = 0,
    this.outstandingAmount,
    this.paymentStatus = 'DRAFT',
    this.gatePassId,
    this.notes,
    this.createdAt,
    this.verificationStatus,
  });

  final String id;
  final String quotationId;
  final String clientName;
  final String? title;
  final List<BillLine> items;
  final double totalQuantity;
  final double totalAmount;
  final double? grandTotal;
  final double discounts;
  final double transportFee;
  final double taxes;
  final double additionalCharges;
  final double paidAmount;
  final double? outstandingAmount;
  final String paymentStatus;
  final String? gatePassId;
  final String? notes;
  final String? createdAt;
  final String? verificationStatus;

  double get grand => grandTotal ?? totalAmount;
  double get owed {
    if (isCancelled) return 0;
    final raw = outstandingAmount ?? (grand - paidAmount);
    return raw < 0 ? 0 : raw;
  }

  bool get isPaid =>
      paymentStatus.toUpperCase() == 'PAID' || (outstandingAmount ?? 0) <= 0;
  bool get isCancelled => paymentStatus.toUpperCase() == 'CANCELLED';
  bool get hasPayments => paidAmount > 0;
  String get displayTitle =>
      (title ?? '').trim().isEmpty ? 'Price List' : title!.trim();
  int get itemCount => items.length;

  /// The POST/PATCH body, exactly `BillPayload` in `types/bill.ts`. `line_total`
  /// and every money total the server owns are deliberately absent.
  Map<String, dynamic> toJson({
    String? quotationId,
    bool? instant,
    List<String>? deliveryIds,
    String? gatePassId,
  }) =>
      {
        if (quotationId != null || this.quotationId.isNotEmpty)
          'quotation_id': quotationId ?? this.quotationId,
        'client_name': clientName.trim(),
        'quotation_title': displayTitle,
        'items': [for (final line in items) line.toJson()],
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
        if (instant != null) 'instant': instant,
        if (discounts != 0) 'discounts': discounts,
        if (transportFee != 0) 'transport_fee': transportFee,
        if (taxes != 0) 'taxes': taxes,
        if (additionalCharges != 0) 'additional_charges': additionalCharges,
        if (deliveryIds != null && deliveryIds.isNotEmpty)
          'delivery_ids': deliveryIds,
        if (gatePassId != null && gatePassId.isNotEmpty)
          'gate_pass_id': gatePassId,
      };

  factory BillRecord.fromJson(Map<String, dynamic> j) {
    final verification = j['verification'];
    return BillRecord(
      id: str(j, const ['id', '_id']),
      quotationId: str(j, const ['quotation_id']),
      clientName: str(j, const ['client_name', 'client', 'hotel']),
      title: str(j, const ['quotation_title', 'title']),
      items: asMapList(pick(j, const ['items', 'line_items', 'lines']))
          .map(BillLine.fromJson)
          .toList(),
      totalQuantity: numOf(j, const ['total_quantity', 'total_qty']),
      totalAmount: numOf(j, const ['total_amount', 'subtotal', 'amount']),
      grandTotal:
          j['grand_total'] == null ? null : numOf(j, const ['grand_total']),
      discounts: numOf(j, const ['discounts', 'discount']),
      transportFee: numOf(j, const ['transport_fee']),
      taxes: numOf(j, const ['taxes', 'tax']),
      additionalCharges:
          numOf(j, const ['additional_charges', 'other_charges']),
      paidAmount: numOf(j, const ['paid_amount', 'paid']),
      outstandingAmount: j['outstanding_amount'] == null
          ? null
          : numOf(j, const ['outstanding_amount']),
      paymentStatus: str(j, const ['payment_status', 'status'], 'DRAFT'),
      gatePassId: str(j, const ['gate_pass_id']),
      notes: str(j, const ['notes']),
      createdAt: str(j, const ['created_at']),
      verificationStatus: verification is Map
          ? str(Map<String, dynamic>.from(verification), const ['status'])
          : null,
    );
  }
}

List<BillRecord> billsFrom(dynamic payload) =>
    asRows(payload).map(BillRecord.fromJson).toList();

class UnbilledItem {
  const UnbilledItem({
    required this.itemName,
    this.category = '',
    this.receivedQty = 0,
    this.deliveredQty = 0,
    this.billedQty = 0,
    this.unbilledQty = 0,
  });

  final String itemName;
  final String category;
  final double receivedQty;
  final double deliveredQty;
  final double billedQty;
  final double unbilledQty;

  factory UnbilledItem.fromJson(Map<String, dynamic> j) => UnbilledItem(
        itemName: str(j, const ['item_name', 'name']),
        category: str(j, const ['category']),
        receivedQty: numOf(j, const ['received_qty']),
        deliveredQty: numOf(j, const ['delivered_qty']),
        billedQty: numOf(j, const ['billed_qty']),
        unbilledQty: numOf(j, const ['unbilled_qty']),
      );
}

class RewashedItem {
  const RewashedItem({
    required this.itemName,
    this.specification = '',
    this.receivedQty = 0,
  });

  final String itemName;
  final String specification;
  final double receivedQty;

  factory RewashedItem.fromJson(Map<String, dynamic> j) => RewashedItem(
        itemName: str(j, const ['item_name', 'name']),
        specification: str(j, const ['specification', 'spec']),
        receivedQty: numOf(j, const ['received_qty']),
      );
}

/// A gate pass with pieces that have gone back out but were never billed. This
/// is the pool a bill can be raised from without touching a quotation.
class UnbilledGatePass {
  const UnbilledGatePass({
    required this.id,
    required this.gatePassNumber,
    required this.clientName,
    required this.receivingDate,
    required this.unbilledItems,
    this.totalUnbilledQty = 0,
    this.deliveryIds = const [],
    this.quotationId,
    this.rewashedItems = const [],
    this.totalRewashedQty = 0,
  });

  final String id;
  final String gatePassNumber;
  final String clientName;
  final String receivingDate;
  final List<UnbilledItem> unbilledItems;
  final double totalUnbilledQty;
  final List<String> deliveryIds;
  final String? quotationId;
  final List<RewashedItem> rewashedItems;
  final double totalRewashedQty;

  factory UnbilledGatePass.fromJson(Map<String, dynamic> j) => UnbilledGatePass(
        id: str(j, const ['id', '_id']),
        gatePassNumber: str(j, const ['gate_pass_number']),
        clientName: str(j, const ['client_name', 'client']),
        receivingDate: str(j, const ['receiving_date']),
        unbilledItems:
            asMapList(j['unbilled_items']).map(UnbilledItem.fromJson).toList(),
        totalUnbilledQty: numOf(j, const ['total_unbilled_qty']),
        deliveryIds:
            (j['delivery_ids'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        quotationId: str(j, const ['quotation_id']),
        rewashedItems:
            asMapList(j['rewashed_items']).map(RewashedItem.fromJson).toList(),
        totalRewashedQty: numOf(j, const ['total_rewashed_qty']),
      );
}

List<UnbilledGatePass> unbilledGatePassesFrom(dynamic payload) =>
    asRows(payload).map(UnbilledGatePass.fromJson).toList();

/// One payment against a bill. `POST /bills/{id}/payments` is how a hotel
/// settles an invoice, and it is the only way the outstanding amount moves.
class BillPayment {
  const BillPayment({
    this.id = '',
    this.amount = 0,
    this.method = '',
    this.notes = '',
    this.reference = '',
    this.paidAt,
  });

  final String id;
  final double amount;
  final String method;
  final String notes;
  final String reference;
  final String? paidAt;

  /// The four methods the web payment dialog offers.
  static const List<String> methods = [
    'Cash',
    'Bank Transfer',
    'Cheque',
    'Card',
  ];

  factory BillPayment.fromJson(Map<String, dynamic> j) => BillPayment(
        id: str(j, const ['id', '_id']),
        amount: numOf(j, const ['amount', 'paid_amount']),
        method: str(j, const ['payment_method', 'method', 'method_name']),
        notes: str(j, const ['notes', 'note']),
        reference: str(j, const ['reference']),
        paidAt: str(
          j,
          const ['payment_date', 'paid_at', 'created_at', 'timestamp'],
        ),
      );

  Map<String, dynamic> toJson(DateTime paidOn) => {
        'amount': amount,
        'payment_method': method,
        'payment_date': paidOn.toIso8601String().split('T').first,
        if (reference.trim().isNotEmpty) 'reference': reference.trim(),
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      };
}

List<BillPayment> billPaymentsFrom(dynamic payload) =>
    asRows(payload).map(BillPayment.fromJson).toList();

// ── Gate pass ────────────────────────────────────────────────────────────────

class GatePassApi {
  GatePassApi._();

  static const String list = '/gatepasses';
  static String one(String id) => '/gatepasses/$id';
  static String status(String id) => '/gatepasses/$id/status';
  static String adjust(String id) => '/gatepasses/$id/adjust';
  static String date(String id) => '/gatepasses/$id/date';
  static String markDelivered(String id) => '/gatepasses/$id/mark-delivered';
  static String reopen(String id) => '/gatepasses/$id/reopen';
  static String balance(String id) => '/gatepasses/$id/balance';
  static String deliveries(String id) => '/gatepasses/$id/deliveries';
}

/// The status flow a gate pass walks through, in the order the web app allows.
const List<String> gatePassStatuses = [
  'RECEIVED',
  'PROCESSING',
  'READY_FOR_DELIVERY',
  'PARTIALLY_DELIVERED',
  'DELIVERED',
  'CANCELLED',
];

/// The six status a gate pass can be created in. Everything else is reached by
/// walking the flow on the detail screen.
const List<String> gatePassCreateStatuses = [
  'RECEIVED',
  'PROCESSING',
  'READY_FOR_DELIVERY',
  'PARTIALLY_DELIVERED',
  'DELIVERED',
  'CANCELLED',
];

/// A count line as the hotel hands it over. `difference` is the server's own
/// arithmetic (received minus client) — the app never recomputes it.
class GatePassItem {
  const GatePassItem({
    this.itemName = '',
    this.category = '',
    this.specification = '',
    this.clientQty = 0,
    this.receivedQty = 0,
    this.difference = 0,
    this.mismatchReason = '',
    this.mismatchNotes = '',
    this.rewashed = false,
  });

  final String itemName;
  final String category;
  final String specification;
  final int clientQty;
  final int receivedQty;
  final int difference;
  final String mismatchReason;
  final String mismatchNotes;
  final bool rewashed;

  bool get hasMismatch => difference != 0;

  factory GatePassItem.fromJson(Map<String, dynamic> j) => GatePassItem(
        itemName: str(j, const ['item_name', 'name']),
        category: str(j, const ['category']),
        specification: str(j, const ['specification', 'specifications']),
        clientQty: intOf(j, const ['client_qty', 'client_counted_qty']),
        receivedQty: intOf(j, const ['received_qty', 'quantity']),
        difference: intOf(j, const ['difference', 'discrepancy']),
        mismatchReason: str(j, const ['mismatch_reason']),
        mismatchNotes: str(j, const ['mismatch_notes']),
        rewashed: j['rewashed'] == true,
      );

  Map<String, dynamic> toJson() => {
        'item_name': itemName.trim(),
        if (category.trim().isNotEmpty) 'category': category.trim(),
        if (specification.trim().isNotEmpty)
          'specification': specification.trim(),
        'client_qty': clientQty,
        'received_qty': receivedQty,
        if (mismatchReason.trim().isNotEmpty)
          'mismatch_reason': mismatchReason.trim(),
        if (mismatchNotes.trim().isNotEmpty)
          'mismatch_notes': mismatchNotes.trim(),
        'rewashed': rewashed,
      };
}

class MarkedDelivered {
  const MarkedDelivered({
    this.note = '',
    this.deliveredDate,
    this.userId = '',
    this.at,
  });

  final String note;
  final String? deliveredDate;
  final String userId;
  final String? at;

  factory MarkedDelivered.fromJson(Map<String, dynamic>? j) => j == null
      ? const MarkedDelivered()
      : MarkedDelivered(
          note: str(j, const ['note', 'notes']),
          deliveredDate: strOrNull(j, const ['delivered_date']),
          userId: str(j, const ['user_id', 'user_name']),
          at: strOrNull(j, const ['at', 'created_at']),
        );
}

class GatePass {
  const GatePass({
    this.id = '',
    this.gatePassNumber = '',
    this.clientName = '',
    this.receivingDate,
    this.receivedBy = '',
    this.items = const [],
    this.status = 'RECEIVED',
    this.notes = '',
    this.quotationId = '',
    this.markedDelivered,
    this.createdAt,
  });

  final String id;
  final String gatePassNumber;
  final String clientName;
  final String? receivingDate;
  final String receivedBy;
  final List<GatePassItem> items;
  final String status;
  final String? notes;
  final String? quotationId;
  final MarkedDelivered? markedDelivered;
  final String? createdAt;

  int get totalReceived => items.fold(0, (sum, i) => sum + i.receivedQty);
  int get totalClient => items.fold(0, (sum, i) => sum + i.clientQty);
  int get mismatchCount => items.where((i) => i.hasMismatch).length;
  int get rewashedQty =>
      items.where((i) => i.rewashed).fold(0, (sum, i) => sum + i.receivedQty);

  /// The web list buckets a pass by its own shape: cancelled and delivered are
  /// finished, any count mismatch is "partially received", and a pass that has
  /// not been marked received yet is still pending.
  String get sectionKey {
    if (status == 'CANCELLED') return 'historical';
    if (status == 'DELIVERED') return 'completed';
    if (mismatchCount > 0) return 'partial';
    if (status == 'RECEIVED') return 'received';
    return 'pending';
  }

  bool get isClosed => status == 'DELIVERED' || status == 'CANCELLED';

  factory GatePass.fromJson(Map<String, dynamic> j) => GatePass(
        id: str(j, const ['id', '_id']),
        gatePassNumber: str(j, const ['gate_pass_number', 'gate_pass_no']),
        clientName: str(j, const ['client_name', 'client']),
        receivingDate: strOrNull(j, const ['receiving_date', 'received_date']),
        receivedBy: str(j, const ['received_by']),
        items: asMapList(j['items']).map(GatePassItem.fromJson).toList(),
        status: str(j, const ['status'], 'RECEIVED'),
        notes: strOrNull(j, const ['notes']),
        quotationId: strOrNull(j, const ['quotation_id']),
        markedDelivered: j['marked_delivered'] == null
            ? null
            : MarkedDelivered.fromJson(
                Map<String, dynamic>.from(
                  j['marked_delivered'] as Map? ?? const {},
                ),
              ),
        createdAt: strOrNull(j, const ['created_at']),
      );

  Map<String, dynamic> createJson() => {
        'client_name': clientName.trim(),
        'receiving_date': isoDateOf(receivingDate),
        'received_by': receivedBy.trim(),
        'status': status,
        'items': [for (final i in items) i.toJson()],
        if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
        if ((quotationId ?? '').trim().isNotEmpty)
          'quotation_id': quotationId!.trim(),
      };

  /// `PATCH /gatepasses/{id}` never accepts the number, the date or the status —
  /// each of those has its own endpoint so the server can audit the change.
  Map<String, dynamic> updateJson() => {
        'client_name': clientName.trim(),
        'received_by': receivedBy.trim(),
        'items': [for (final i in items) i.toJson()],
        if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
      };
}

List<GatePass> gatePassesFrom(dynamic payload) =>
    asRows(payload).map(GatePass.fromJson).toList();

/// One line of the server-computed balance. The web app renders every
/// pending/remaining number straight from this and refuses to subtract locally,
/// because a delivery can span two passes and would otherwise make one look
/// short.
class GatePassBalanceItem {
  const GatePassBalanceItem({
    this.itemKey = '',
    this.itemName = '',
    this.specification = '',
    this.category = '',
    this.rewashed = false,
    this.expectedQty = 0,
    this.receivedQty = 0,
    this.deliveredQty = 0,
    this.effectiveDeliveredQty = 0,
    this.returnedBackQty = 0,
    this.outstandingDeliveryQty = 0,
    this.notReceivedQty = 0,
    this.extraReceivedQty = 0,
    this.clientCountedQty,
    this.discrepancyQty = 0,
    this.hasCount = false,
    this.flags = const [],
  });

  final String itemKey;
  final String itemName;
  final String specification;
  final String category;
  final bool rewashed;
  final int expectedQty;
  final int receivedQty;
  final int deliveredQty;
  final int effectiveDeliveredQty;
  final int returnedBackQty;
  final int outstandingDeliveryQty;
  final int notReceivedQty;
  final int extraReceivedQty;
  final int? clientCountedQty;
  final int discrepancyQty;
  final bool hasCount;
  final List<String> flags;

  factory GatePassBalanceItem.fromJson(Map<String, dynamic> j) =>
      GatePassBalanceItem(
        itemKey: str(j, const ['item_key']),
        itemName: str(j, const ['item_name']),
        specification: str(j, const ['specification']),
        category: str(j, const ['category']),
        rewashed: j['rewashed'] == true,
        expectedQty: intOf(j, const ['expected_qty']),
        receivedQty: intOf(j, const ['received_qty']),
        deliveredQty: intOf(j, const ['delivered_qty']),
        effectiveDeliveredQty: intOf(j, const ['effective_delivered_qty']),
        returnedBackQty: intOf(j, const ['returned_back_qty']),
        outstandingDeliveryQty: intOf(j, const ['outstanding_delivery_qty']),
        notReceivedQty: intOf(j, const ['not_received_qty']),
        extraReceivedQty: intOf(j, const ['extra_received_qty']),
        clientCountedQty: intOrNull(j, const ['client_counted_qty']),
        discrepancyQty: intOf(j, const ['discrepancy_qty']),
        hasCount: j['has_count'] == true,
        flags: asStrings(j['flags']),
      );
}

class GatePassBalanceTotals {
  const GatePassBalanceTotals({
    this.expectedQty = 0,
    this.receivedQty = 0,
    this.deliveredQty = 0,
    this.effectiveDeliveredQty = 0,
    this.returnedBackQty = 0,
    this.outstandingDeliveryQty = 0,
    this.notReceivedQty = 0,
    this.clientCountedQty = 0,
    this.discrepancyQty = 0,
  });

  final int expectedQty;
  final int receivedQty;
  final int deliveredQty;
  final int effectiveDeliveredQty;
  final int returnedBackQty;
  final int outstandingDeliveryQty;
  final int notReceivedQty;
  final int clientCountedQty;
  final int discrepancyQty;

  factory GatePassBalanceTotals.fromJson(Map<String, dynamic> j) =>
      GatePassBalanceTotals(
        expectedQty: intOf(j, const ['expected_qty']),
        receivedQty: intOf(j, const ['received_qty']),
        deliveredQty: intOf(j, const ['delivered_qty']),
        effectiveDeliveredQty: intOf(j, const ['effective_delivered_qty']),
        returnedBackQty: intOf(j, const ['returned_back_qty']),
        outstandingDeliveryQty: intOf(j, const ['outstanding_delivery_qty']),
        notReceivedQty: intOf(j, const ['not_received_qty']),
        clientCountedQty: intOf(j, const ['client_counted_qty']),
        discrepancyQty: intOf(j, const ['discrepancy_qty']),
      );
}

class GatePassBalance {
  const GatePassBalance({
    this.gatePassId = '',
    this.gatePassNumber = '',
    this.clientName = '',
    this.receivingDate,
    this.status = '',
    this.derivedStatus = '',
    this.statusStale = false,
    this.markedDelivered = false,
    this.items = const [],
    this.totals = const GatePassBalanceTotals(),
    this.flags = const [],
  });

  final String gatePassId;
  final String gatePassNumber;
  final String clientName;
  final String? receivingDate;
  final String status;
  final String derivedStatus;
  final bool statusStale;
  final bool markedDelivered;
  final List<GatePassBalanceItem> items;
  final GatePassBalanceTotals totals;
  final List<String> flags;

  /// The stored status can lag behind what the numbers say; the server tells us
  /// to prefer the derived one whenever it does.
  String get effectiveStatus =>
      statusStale && derivedStatus.isNotEmpty ? derivedStatus : status;

  factory GatePassBalance.fromJson(Map<String, dynamic> j) => GatePassBalance(
        gatePassId: str(j, const ['gate_pass_id']),
        gatePassNumber: str(j, const ['gate_pass_number']),
        clientName: str(j, const ['client_name']),
        receivingDate: strOrNull(j, const ['receiving_date']),
        status: str(j, const ['status']),
        derivedStatus: str(j, const ['derived_status']),
        statusStale: j['status_stale'] == true,
        markedDelivered: j['marked_delivered'] == true,
        items: asMapList(j['items']).map(GatePassBalanceItem.fromJson).toList(),
        totals: GatePassBalanceTotals.fromJson(
          Map<String, dynamic>.from(j['totals'] as Map? ?? const {}),
        ),
        flags: asStrings(j['flags']),
      );
}

// ── Delivery ─────────────────────────────────────────────────────────────────

class DeliveryApi {
  DeliveryApi._();

  static const String list = '/deliveries';
  static const String available = '/deliveries/available';
  static const String pendingGatePasses = '/deliveries/pending-gatepasses';
  static String one(String id) => '/deliveries/$id';
  static String items(String id) => '/deliveries/$id/items';
  static String date(String id) => '/deliveries/$id/date';
  static String cancel(String id) => '/deliveries/$id/cancel';
  static String balance(String id) => '/deliveries/$id/balance';
}

/// One delivered line. `gate_pass_id` is mandatory on a write: a delivery can
/// draw from several passes, so the source of every line has to be explicit.
class DeliveryLine {
  const DeliveryLine({
    this.itemName = '',
    this.specification = '',
    this.quantity = 0,
    this.gatePassId,
    this.clientCountedQty,
    this.discrepancy,
    this.mismatchReason = '',
    this.mismatchNotes = '',
  });

  final String itemName;
  final String specification;
  final int quantity;
  final String? gatePassId;
  final int? clientCountedQty;
  final int? discrepancy;
  final String mismatchReason;
  final String mismatchNotes;

  int get total => quantity;

  factory DeliveryLine.fromJson(Map<String, dynamic> j) => DeliveryLine(
        itemName: str(j, const ['item_name', 'name']),
        specification: str(j, const ['specification', 'specifications']),
        quantity: intOf(j, const ['quantity', 'delivered_qty', 'received_qty']),
        gatePassId: strOrNull(j, const ['gate_pass_id']),
        clientCountedQty: intOrNull(j, const ['client_counted_qty']),
        discrepancy: intOrNull(j, const ['discrepancy']),
        mismatchReason: str(j, const ['mismatch_reason']),
        mismatchNotes: str(j, const ['mismatch_notes']),
      );

  Map<String, dynamic> toJson() => {
        'item_name': itemName.trim(),
        if (specification.trim().isNotEmpty)
          'specification': specification.trim(),
        'quantity': quantity,
        if ((gatePassId ?? '').isNotEmpty) 'gate_pass_id': gatePassId,
        if (clientCountedQty != null) 'client_counted_qty': clientCountedQty,
        if (mismatchReason.trim().isNotEmpty)
          'mismatch_reason': mismatchReason.trim(),
        if (mismatchNotes.trim().isNotEmpty)
          'mismatch_notes': mismatchNotes.trim(),
      };
}

/// One applied correction. The originals are never destroyed, so a delivery
/// carries its full correction history alongside its current quantities.
class DeliveryCorrection {
  const DeliveryCorrection({
    this.correctedAt = '',
    this.correctedBy = '',
    this.reason = '',
    this.changes = const [],
  });

  final String correctedAt;
  final String correctedBy;
  final String reason;
  final List<DeliveryCorrectionChange> changes;

  factory DeliveryCorrection.fromJson(Map<String, dynamic> j) =>
      DeliveryCorrection(
        correctedAt: str(j, const ['corrected_at', 'at']),
        correctedBy: str(j, const ['corrected_by', 'corrected_by_name']),
        reason: str(j, const ['reason']),
        changes: asMapList(j['changes'])
            .map(DeliveryCorrectionChange.fromJson)
            .toList(),
      );
}

class DeliveryCorrectionChange {
  const DeliveryCorrectionChange({
    this.gatePassId = '',
    this.itemName = '',
    this.specification = '',
    this.originalQuantity = 0,
    this.correctedQuantity = 0,
    this.delta = 0,
  });

  final String gatePassId;
  final String itemName;
  final String specification;
  final int originalQuantity;
  final int correctedQuantity;
  final int delta;

  factory DeliveryCorrectionChange.fromJson(Map<String, dynamic> j) =>
      DeliveryCorrectionChange(
        gatePassId: str(j, const ['gate_pass_id']),
        itemName: str(j, const ['item_name']),
        specification: str(j, const ['specification']),
        originalQuantity: intOf(j, const ['original_quantity']),
        correctedQuantity: intOf(j, const ['corrected_quantity']),
        delta: intOf(j, const ['delta']),
      );
}

class Delivery {
  const Delivery({
    this.id = '',
    this.gatePassId = '',
    this.sourceGatePassIds = const [],
    this.clientName = '',
    this.deliveryDate,
    this.deliveredBy = '',
    this.receivedBy = '',
    this.items = const [],
    this.status = '',
    this.notes = '',
    this.corrections = const [],
    this.cancelledAt,
    this.cancelledBy = '',
    this.cancelledReason = '',
    this.sourcePasses = const [],
  });

  final String id;
  final String gatePassId;
  final List<String> sourceGatePassIds;
  final String clientName;
  final String? deliveryDate;
  final String deliveredBy;
  final String receivedBy;
  final List<DeliveryLine> items;
  final String status;
  final String? notes;
  final List<DeliveryCorrection> corrections;
  final String? cancelledAt;
  final String cancelledBy;
  final String cancelledReason;
  final List<SourcePassRef> sourcePasses;

  int get totalPieces => items.fold(0, (sum, i) => sum + i.quantity);
  int get lineCount => items.length;
  bool get isCancelled => status == 'CANCELLED';

  /// A delivery can span several passes; the singular field is only the legacy
  /// fallback, so the list is what any "which passes" question must use.
  List<String> get sources => sourceGatePassIds.isNotEmpty
      ? sourceGatePassIds
      : (gatePassId.isEmpty ? const <String>[] : [gatePassId]);

  factory Delivery.fromJson(Map<String, dynamic> j) => Delivery(
        id: str(j, const ['id', '_id']),
        gatePassId: str(j, const ['gate_pass_id']),
        sourceGatePassIds: asStrings(j['source_gate_pass_ids']),
        clientName: str(j, const ['client_name']),
        deliveryDate: strOrNull(j, const ['delivery_date']),
        deliveredBy: str(j, const ['delivered_by']),
        receivedBy: str(j, const ['received_by']),
        items: asMapList(j['items']).map(DeliveryLine.fromJson).toList(),
        status: str(j, const ['status']),
        notes: strOrNull(j, const ['notes']),
        corrections: asMapList(j['corrections'])
            .map(DeliveryCorrection.fromJson)
            .toList(),
        cancelledAt: strOrNull(j, const ['cancelled_at']),
        cancelledBy: str(j, const ['cancelled_by']),
        cancelledReason: str(j, const ['cancelled_reason']),
        sourcePasses: asMapList(j['source_gate_passes'])
            .map(SourcePassRef.fromJson)
            .toList(),
      );

  Map<String, dynamic> createJson() => {
        if (gatePassId.isNotEmpty) 'gate_pass_id': gatePassId,
        'client_name': clientName.trim(),
        'delivery_date': isoDateOf(deliveryDate),
        'delivered_by': deliveredBy.trim(),
        'received_by': receivedBy.trim(),
        'items': [for (final i in items) i.toJson()],
        if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
      };
}

List<Delivery> deliveriesFrom(dynamic payload) =>
    asRows(payload).map(Delivery.fromJson).toList();

/// One origin pass as the list endpoint echoes it back, so a delivery can be
/// shown as complete only when every pass it drew from is complete.
class SourcePassRef {
  const SourcePassRef({
    this.gatePassId = '',
    this.gatePassNumber = '',
    this.clientName = '',
    this.status = '',
    this.derivedStatus = '',
  });

  final String gatePassId;
  final String gatePassNumber;
  final String clientName;
  final String status;
  final String derivedStatus;

  factory SourcePassRef.fromJson(Map<String, dynamic> j) => SourcePassRef(
        gatePassId: str(j, const ['gate_pass_id']),
        gatePassNumber: str(j, const ['gate_pass_number']),
        clientName: str(j, const ['client_name']),
        status: str(j, const ['status']),
        derivedStatus: str(j, const ['derived_status']),
      );
}

/// How complete a delivery is, from `components/operations-status.tsx`.
///
/// The web app deliberately downgrades a delivery whose own status says
/// DELIVERED when one of its origin passes is still open: a delivery spanning
/// two passes is only as complete as its least-complete pass.
String deriveDeliveryStatus(Delivery d) {
  final raw = d.status.toUpperCase();
  if (raw == 'CANCELLED') return 'CANCELLED';
  if (d.sourcePasses.isEmpty) {
    return raw == 'DELIVERED' ? 'DELIVERED' : 'PENDING';
  }
  const rank = {
    'DELIVERED': 0,
    'PARTIALLY_DELIVERED': 1,
    'READY_FOR_DELIVERY': 2,
    'PROCESSING': 3,
    'RECEIVED': 4,
    'CANCELLED': 5,
  };
  var worst = 'DELIVERED';
  for (final p in d.sourcePasses) {
    final status =
        (p.derivedStatus.isNotEmpty ? p.derivedStatus : p.status).toUpperCase();
    if (status == 'CANCELLED') continue;
    if (!rank.containsKey(status)) continue;
    if (rank[status]! > rank[worst]!) worst = status;
  }
  if (worst == 'CANCELLED') return 'DELIVERED';
  return worst;
}

/// One line of `/deliveries/available`. The server decides what is deliverable,
/// so the delivery form never filters a pass by its own arithmetic.
class AvailableItem {
  const AvailableItem({
    this.itemName = '',
    this.specification = '',
    this.category = '',
    this.expectedQty = 0,
    this.receivedQty = 0,
    this.deliveredQty = 0,
    this.returnedQty = 0,
    this.availableQty = 0,
    this.rewashed = false,
    this.flags = const [],
  });

  final String itemName;
  final String specification;
  final String category;
  final int expectedQty;
  final int receivedQty;
  final int deliveredQty;
  final int returnedQty;
  final int availableQty;
  final bool rewashed;
  final List<String> flags;

  bool get isDeliverable => availableQty > 0;

  factory AvailableItem.fromJson(Map<String, dynamic> j) => AvailableItem(
        itemName: str(j, const ['item_name']),
        specification: str(j, const ['specification']),
        category: str(j, const ['category']),
        expectedQty: intOf(j, const ['expected_qty']),
        receivedQty: intOf(j, const ['received_qty']),
        deliveredQty: intOf(j, const ['delivered_qty']),
        returnedQty: intOf(j, const ['returned_qty']),
        availableQty: intOf(j, const ['available_qty']),
        rewashed: j['rewashed'] == true,
        flags: asStrings(j['flags']),
      );
}

class AvailableGatePass {
  const AvailableGatePass({
    this.gatePassId = '',
    this.gatePassNumber = '',
    this.clientName = '',
    this.receivingDate,
    this.status = '',
    this.derivedStatus = '',
    this.totalReceivedQty = 0,
    this.totalDeliveredQty = 0,
    this.totalAvailableQty = 0,
    this.items = const [],
  });

  final String gatePassId;
  final String gatePassNumber;
  final String clientName;
  final String? receivingDate;
  final String status;
  final String derivedStatus;
  final int totalReceivedQty;
  final int totalDeliveredQty;
  final int totalAvailableQty;
  final List<AvailableItem> items;

  factory AvailableGatePass.fromJson(Map<String, dynamic> j) =>
      AvailableGatePass(
        gatePassId: str(j, const ['gate_pass_id']),
        gatePassNumber: str(j, const ['gate_pass_number']),
        clientName: str(j, const ['client_name']),
        receivingDate: strOrNull(j, const ['receiving_date']),
        status: str(j, const ['status']),
        derivedStatus: str(j, const ['derived_status']),
        totalReceivedQty: intOf(j, const ['total_received_qty']),
        totalDeliveredQty: intOf(j, const ['total_delivered_qty']),
        totalAvailableQty: intOf(j, const ['total_available_qty']),
        items: asMapList(j['items']).map(AvailableItem.fromJson).toList(),
      );
}

class Availability {
  const Availability({
    this.clientName = '',
    this.gatePasses = const [],
    this.totalAvailableQty = 0,
  });

  final String clientName;
  final List<AvailableGatePass> gatePasses;
  final int totalAvailableQty;

  factory Availability.fromJson(Map<String, dynamic> j) => Availability(
        clientName: str(j, const ['client_name']),
        gatePasses: asMapList(j['gate_passes'])
            .map(AvailableGatePass.fromJson)
            .toList(),
        totalAvailableQty: intOf(j, const ['total_available_qty']),
      );
}

// ── Returns ──────────────────────────────────────────────────────────────────

class ReturnApi {
  ReturnApi._();

  static const String list = '/returns';
  static const String pendingResent = '/returns/pending-resent';
  static const String summary = '/returns/stats/summary';
  static String one(String id) => '/returns/$id';
  static String resent(String id) => '/returns/$id/resent';
}

const List<String> returnReasons = [
  'WRONG_ITEM',
  'DAMAGED',
  'MISSING',
  'OTHER',
];

const List<String> returnConditions = [
  'GOOD',
  'DAMAGED',
  'STAINED',
  'LOST',
];

const List<String> returnActions = [
  'RECEIVE_BACK',
  'RE_WASH',
  'DISCARD',
  'COMPENSATE',
];

/// The only two actions that put an item back on the road, so they are the only
/// lines that can be marked as resent.
const List<String> returnResendActions = [
  'RECEIVE_BACK',
  'RE_WASH',
];

class ReturnLine {
  const ReturnLine({
    this.itemName = '',
    this.specification = '',
    this.returnedQty = 0,
    this.reason = 'OTHER',
    this.condition = 'GOOD',
    this.action = 'RE_WASH',
    this.notes = '',
    this.resendStatus,
    this.resentAt,
  });

  final String itemName;
  final String specification;
  final int returnedQty;
  final String reason;
  final String condition;
  final String action;
  final String notes;
  final String? resendStatus;
  final String? resentAt;

  bool get isPendingResend => resendStatus != 'SENT';

  factory ReturnLine.fromJson(Map<String, dynamic> j) => ReturnLine(
        itemName: str(j, const ['item_name', 'name']),
        specification: str(j, const ['specification', 'specifications']),
        returnedQty: intOf(j, const ['returned_qty', 'quantity']),
        reason: str(j, const ['reason'], 'OTHER'),
        condition: str(j, const ['condition'], 'GOOD'),
        action: str(j, const ['action'], 'RE_WASH'),
        notes: str(j, const ['notes']),
        resendStatus: strOrNull(j, const ['resend_status']),
        resentAt: strOrNull(j, const ['resent_at']),
      );

  Map<String, dynamic> toJson() => {
        'item_name': itemName.trim(),
        if (specification.trim().isNotEmpty)
          'specification': specification.trim(),
        'returned_qty': returnedQty,
        'reason': reason,
        'condition': condition,
        'action': action,
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      };
}

/// How a return changes the bill the linen was billed on. The server applies
/// the money side, so the app only has to state the intent.
class BillAdjustment {
  const BillAdjustment({
    this.adjustmentType = 'NONE',
    this.amount = 0,
    this.notes = '',
  });

  final String adjustmentType;
  final double amount;
  final String notes;

  bool get applies => adjustmentType != 'NONE' && amount > 0;

  factory BillAdjustment.fromJson(Map<String, dynamic> j) => BillAdjustment(
        adjustmentType: str(j, const ['adjustment_type'], 'NONE'),
        amount: numOf(j, const ['amount']),
        notes: str(j, const ['notes']),
      );

  Map<String, dynamic> toJson() => {
        'adjustment_type': adjustmentType,
        'amount': amount,
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      };
}

class ReturnRecord {
  const ReturnRecord({
    this.id = '',
    this.returnId = '',
    this.gatePassId = '',
    this.deliveryId = '',
    this.clientName = '',
    this.items = const [],
    this.billAdjustment = const BillAdjustment(),
    this.status = 'PENDING',
    this.recordedBy = '',
    this.notes = '',
    this.createdAt,
  });

  final String id;
  final String returnId;
  final String gatePassId;
  final String deliveryId;
  final String clientName;
  final List<ReturnLine> items;
  final BillAdjustment billAdjustment;
  final String status;
  final String recordedBy;
  final String? notes;
  final String? createdAt;

  /// The id every endpoint takes. Older records only carry `_id`.
  String get key => id.isNotEmpty ? id : returnId;

  int get totalPieces => items.fold(0, (sum, i) => sum + i.returnedQty);
  int get pendingResendCount => items.where((i) => i.isPendingResend).length;

  factory ReturnRecord.fromJson(Map<String, dynamic> j) => ReturnRecord(
        id: str(j, const ['id', '_id']),
        returnId: str(j, const ['return_id']),
        gatePassId: str(j, const ['gate_pass_id']),
        deliveryId: str(j, const ['delivery_id']),
        clientName: str(j, const ['client_name']),
        items: asMapList(j['items']).map(ReturnLine.fromJson).toList(),
        billAdjustment: BillAdjustment.fromJson(
          Map<String, dynamic>.from(j['bill_adjustment'] as Map? ?? const {}),
        ),
        status: str(j, const ['status'], 'PENDING'),
        recordedBy: str(j, const ['recorded_by']),
        notes: strOrNull(j, const ['notes']),
        createdAt: strOrNull(j, const ['created_at']),
      );

  Map<String, dynamic> createJson() => {
        'gate_pass_id': gatePassId,
        if (deliveryId.isNotEmpty) 'delivery_id': deliveryId,
        'client_name': clientName.trim(),
        'items': [for (final i in items) i.toJson()],
        'bill_adjustment': billAdjustment.toJson(),
        if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
      };
}

List<ReturnRecord> returnsFrom(dynamic payload) =>
    asRows(payload).map(ReturnRecord.fromJson).toList();

// ── Dispatch ─────────────────────────────────────────────────────────────────

class DispatchApi {
  DispatchApi._();

  static const String list = '/dispatch';
  static const String optimize = '/dispatch/optimize';
  static String one(String id) => '/dispatch/$id';
}

const List<String> dispatchStatuses = [
  'SCHEDULED',
  'ASSIGNED',
  'EN_ROUTE',
  'COMPLETED',
  'CANCELLED',
];

const List<String> dispatchJobTypes = ['pickup', 'delivery'];

class DispatchJob {
  const DispatchJob({
    this.id = '',
    this.jobType = 'delivery',
    this.orderId,
    this.clientName = '',
    this.address,
    this.contactName,
    this.contactPhone,
    this.scheduledAt,
    this.status = 'SCHEDULED',
    this.assignedTo,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String jobType;
  final String? orderId;
  final String clientName;
  final String? address;
  final String? contactName;
  final String? contactPhone;
  final String? scheduledAt;
  final String status;
  final String? assignedTo;
  final String? notes;
  final String? createdAt;

  bool get isOpen => status != 'COMPLETED' && status != 'CANCELLED';

  factory DispatchJob.fromJson(Map<String, dynamic> j) => DispatchJob(
        id: str(j, const ['id', '_id']),
        jobType: str(j, const ['job_type'], 'delivery'),
        orderId: strOrNull(j, const ['order_id']),
        clientName: str(j, const ['client_name']),
        address: strOrNull(j, const ['address']),
        contactName: strOrNull(j, const ['contact_name']),
        contactPhone: strOrNull(j, const ['contact_phone']),
        scheduledAt: strOrNull(j, const ['scheduled_at']),
        status: str(j, const ['status'], 'SCHEDULED'),
        assignedTo: strOrNull(j, const ['assigned_to']),
        notes: strOrNull(j, const ['notes']),
        createdAt: strOrNull(j, const ['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'job_type': jobType,
        if ((orderId ?? '').isNotEmpty) 'order_id': orderId,
        'client_name': clientName.trim(),
        if ((address ?? '').isNotEmpty) 'address': address!.trim(),
        if ((contactName ?? '').isNotEmpty) 'contact_name': contactName!.trim(),
        if ((contactPhone ?? '').isNotEmpty)
          'contact_phone': contactPhone!.trim(),
        if ((scheduledAt ?? '').isNotEmpty)
          'scheduled_at': isoDateOf(scheduledAt),
        'status': status,
        if ((assignedTo ?? '').isNotEmpty) 'assigned_to': assignedTo!.trim(),
        if ((notes ?? '').isNotEmpty) 'notes': notes!.trim(),
      };
}

List<DispatchJob> dispatchJobsFrom(dynamic payload) =>
    asRows(payload).map(DispatchJob.fromJson).toList();

/// `POST /dispatch/optimize` returns the driver's stop order plus the jobs
/// themselves, so the caller never has to re-join against the list.
class RoutePlan {
  const RoutePlan({this.order = const [], this.stops = const []});

  final List<String> order;
  final List<DispatchJob> stops;

  factory RoutePlan.fromJson(Map<String, dynamic> j) => RoutePlan(
        order: asStrings(j['order']),
        stops: asMapList(j['stops']).map(DispatchJob.fromJson).toList(),
      );
}

/// A pass with linen still to go out, as `/deliveries/pending-gatepasses`
/// reports it. `total_pending` and every line quantity are server-computed.
class PendingGatePassItem {
  const PendingGatePassItem({
    this.itemName = '',
    this.specification = '',
    this.category = '',
    this.receivedQty = 0,
    this.deliveredQty = 0,
    this.returnedQty = 0,
    this.pendingQty = 0,
  });

  final String itemName;
  final String specification;
  final String category;
  final int receivedQty;
  final int deliveredQty;
  final int returnedQty;
  final int pendingQty;

  factory PendingGatePassItem.fromJson(Map<String, dynamic> j) =>
      PendingGatePassItem(
        itemName: str(j, const ['item_name', 'name']),
        specification: str(j, const ['specification', 'specifications']),
        category: str(j, const ['category']),
        receivedQty: intOf(j, const ['received_qty', 'quantity']),
        deliveredQty: intOf(j, const ['delivered_qty']),
        returnedQty: intOf(j, const ['returned_qty']),
        pendingQty: intOf(j, const ['pending_qty']),
      );
}

class PendingGatePass {
  const PendingGatePass({
    this.gatePassId = '',
    this.gatePassNumber = '',
    this.clientName = '',
    this.receivingDate = '',
    this.status = '',
    this.totalPending = 0,
    this.items = const [],
  });

  final String gatePassId;
  final String gatePassNumber;
  final String clientName;
  final String receivingDate;
  final String status;
  final int totalPending;
  final List<PendingGatePassItem> items;

  factory PendingGatePass.fromJson(Map<String, dynamic> j) => PendingGatePass(
        gatePassId: str(j, const ['gate_pass_id', 'id', '_id']),
        gatePassNumber: str(j, const ['gate_pass_number']),
        clientName: str(j, const ['client_name', 'client']),
        receivingDate: str(j, const ['receiving_date']),
        status: str(j, const ['status']),
        totalPending: intOf(j, const ['total_pending']),
        items: asMapList(j['items']).map(PendingGatePassItem.fromJson).toList(),
      );
}

List<PendingGatePass> pendingGatePassesFrom(dynamic payload) =>
    asRows(payload).map(PendingGatePass.fromJson).toList();
