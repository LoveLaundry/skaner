import 'json.dart';

enum DiscountType { fixed, percent }

DiscountType discountTypeFrom(String? raw) =>
    (raw ?? '').toUpperCase() == 'PERCENT' ? DiscountType.percent : DiscountType.fixed;

const Map<DiscountType, String> discountTypeLabels = {
  DiscountType.fixed: 'Fixed',
  DiscountType.percent: 'Percent',
};

class ShopBillItem {
  ShopBillItem({
    required this.itemName,
    required this.unitPrice,
    required this.quantity,
    this.specification,
    this.category,
    double discount = 0,
    this.discountType = DiscountType.fixed,
  }) : _discount = discount;

  final String itemName;
  final String? specification;
  final String? category;
  final double unitPrice;
  final double quantity;
  double _discount;
  DiscountType discountType;

  double get discount => _discount;

  set discount(double v) => _discount = v < 0 ? 0 : v;

  double get gross => unitPrice * quantity;

  /// The discount after applying whichever type the line carries.
  double get discountAmount =>
      discountType == DiscountType.percent ? gross * discount / 100 : discount;

  double get lineTotal => gross - discountAmount;

  String get displayName =>
      (specification == null || specification!.isEmpty) ? itemName : '$itemName · $specification';

  factory ShopBillItem.fromJson(Map<String, dynamic> j) => ShopBillItem(
        itemName: asString(j['item_name']),
        specification: asStringOrNull(j['specification']),
        category: asStringOrNull(j['category']),
        unitPrice: asDouble(j['unit_price']),
        quantity: asDouble(j['quantity']),
        discount: asDouble(j['discount']),
        discountType: discountTypeFrom(asStringOrNull(j['discount_type'])),
      );

  Map<String, dynamic> toJson() => {
        'item_name': itemName,
        if (specification != null) 'specification': specification,
        if (category != null) 'category': category,
        'unit_price': unitPrice,
        'quantity': quantity,
        'discount': discount,
        'discount_type': discountType.name == 'percent' ? 'PERCENT' : 'FIXED',
        'line_total': lineTotal,
      };

  ShopBillItem copy() => ShopBillItem(
        itemName: itemName,
        specification: specification,
        category: category,
        unitPrice: unitPrice,
        quantity: quantity,
        discount: discount,
        discountType: discountType,
      );
}

enum ShopBillStatus { pending, processing, delivered, completed, cancelled }

ShopBillStatus shopBillStatusFrom(String? raw) {
  switch ((raw ?? '').toUpperCase()) {
    case 'PROCESSING':
      return ShopBillStatus.processing;
    case 'DELIVERED':
      return ShopBillStatus.delivered;
    case 'COMPLETED':
      return ShopBillStatus.completed;
    case 'CANCELLED':
      return ShopBillStatus.cancelled;
    default:
      return ShopBillStatus.pending;
  }
}

const Map<ShopBillStatus, String> shopBillStatusLabels = {
  ShopBillStatus.pending: 'Pending',
  ShopBillStatus.processing: 'Processing',
  ShopBillStatus.delivered: 'Delivered',
  ShopBillStatus.completed: 'Completed',
  ShopBillStatus.cancelled: 'Cancelled',
};

/// The happy path through the shop-bill lifecycle.
const List<ShopBillStatus> shopBillTransitions = [
  ShopBillStatus.pending,
  ShopBillStatus.processing,
  ShopBillStatus.delivered,
  ShopBillStatus.completed,
];

class ShopBillNotesChange {
  const ShopBillNotesChange({
    required this.oldNotes,
    required this.newNotes,
    required this.changedBy,
    required this.changedAt,
  });

  final String oldNotes;
  final String newNotes;
  final String changedBy;
  final String changedAt;

  factory ShopBillNotesChange.fromJson(Map<String, dynamic> j) =>
      ShopBillNotesChange(
        oldNotes: asString(j['old_notes']),
        newNotes: asString(j['new_notes']),
        changedBy: asString(j['changed_by']),
        changedAt: asString(j['changed_at']),
      );
}

class ShopBill {
  const ShopBill({
    required this.id,
    required this.billNumber,
    required this.clientName,
    required this.items,
    required this.totalQuantity,
    required this.totalAmount,
    required this.discounts,
    required this.transportFee,
    required this.taxes,
    required this.grandTotal,
    required this.status,
    required this.paymentStatus,
    required this.paidAmount,
    required this.outstandingAmount,
    required this.locked,
    required this.isRecurring,
    this.quotationId,
    this.notes,
    this.notesHistory = const [],
    this.deliveryDate,
    this.tags = const [],
    this.recurringInterval,
    this.recurringEndDate,
    this.parentBillId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String billNumber;
  final String clientName;
  final String? quotationId;
  final List<ShopBillItem> items;
  final double totalQuantity;
  final double totalAmount;
  final double discounts;
  final double transportFee;
  final double taxes;
  final double grandTotal;
  final ShopBillStatus status;
  final String paymentStatus;
  final double paidAmount;
  final double outstandingAmount;
  final String? notes;
  final List<ShopBillNotesChange> notesHistory;
  final String? deliveryDate;
  final List<String> tags;

  /// A locked bill can no longer be edited — used once work is on the floor.
  final bool locked;
  final bool isRecurring;
  final String? recurringInterval;
  final String? recurringEndDate;

  /// Set when this bill was split out of another.
  final String? parentBillId;
  final String? createdAt;
  final String? updatedAt;

  String get statusLabel => shopBillStatusLabels[status] ?? 'Pending';
  bool get isCancelled => status == ShopBillStatus.cancelled;
  bool get isCompleted => status == ShopBillStatus.completed;
  bool get isClosed => status == ShopBillStatus.completed || isCancelled;
  bool get isSplit => parentBillId != null;

  /// The next status in the lifecycle, or null when the bill is closed.
  ShopBillStatus? get nextStatus {
    final i = shopBillTransitions.indexOf(status);
    if (i < 0 || i >= shopBillTransitions.length - 1) return null;
    return shopBillTransitions[i + 1];
  }

  String get paymentStatusLabel => commonPaymentStatusLabel(paymentStatus);
  bool get isPaid => paymentStatus.toUpperCase() == 'PAID';
  bool get isPartlyPaid => paymentStatus.toUpperCase() == 'PARTIALLY_PAID';

  factory ShopBill.fromJson(Map<String, dynamic> j) => ShopBill(
        id: asString(j['id'] ?? j['_id']),
        billNumber: asString(j['bill_number']),
        clientName: asString(j['client_name']),
        quotationId: asStringOrNull(j['quotation_id']),
        items: asMapList(j['items']).map(ShopBillItem.fromJson).toList(),
        totalQuantity: asDouble(j['total_quantity']),
        totalAmount: asDouble(j['total_amount']),
        discounts: asDouble(j['discounts']),
        transportFee: asDouble(j['transport_fee']),
        taxes: asDouble(j['taxes']),
        grandTotal: asDouble(j['grand_total']),
        status: shopBillStatusFrom(asStringOrNull(j['status'])),
        paymentStatus: asString(j['payment_status'], 'PENDING'),
        paidAmount: asDouble(j['paid_amount']),
        outstandingAmount: asDouble(j['outstanding_amount']),
        notes: asStringOrNull(j['notes']),
        notesHistory:
            asMapList(j['notes_history']).map(ShopBillNotesChange.fromJson).toList(),
        deliveryDate: asStringOrNull(j['delivery_date']),
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        locked: asBool(j['locked']),
        isRecurring: asBool(j['is_recurring']),
        recurringInterval: asStringOrNull(j['recurring_interval']),
        recurringEndDate: asStringOrNull(j['recurring_end_date']),
        parentBillId: asStringOrNull(j['parent_bill_id']),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
      );
}

String commonPaymentStatusLabel(String? raw) {
  switch ((raw ?? '').toUpperCase()) {
    case 'DRAFT':
      return 'Draft';
    case 'PENDING':
      return 'Pending';
    case 'ISSUED':
      return 'Issued';
    case 'PARTIALLY_PAID':
      return 'Partly Paid';
    case 'PAID':
      return 'Paid';
    case 'CANCELLED':
      return 'Cancelled';
    default:
      return raw == null || raw.isEmpty ? 'Pending' : raw;
  }
}

class BillTemplate {
  const BillTemplate({
    required this.id,
    required this.name,
    required this.items,
    required this.discounts,
    required this.transportFee,
    required this.taxes,
    required this.useCount,
    this.clientName,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? clientName;
  final List<ShopBillItem> items;
  final double discounts;
  final double transportFee;
  final double taxes;
  final String? notes;
  final int useCount;
  final String? createdAt;
  final String? updatedAt;

  factory BillTemplate.fromJson(Map<String, dynamic> j) => BillTemplate(
        id: asString(j['id'] ?? j['_id']),
        name: asString(j['name']),
        clientName: asStringOrNull(j['client_name']),
        items: asMapList(j['items']).map(ShopBillItem.fromJson).toList(),
        discounts: asDouble(j['discounts']),
        transportFee: asDouble(j['transport_fee']),
        taxes: asDouble(j['taxes']),
        notes: asStringOrNull(j['notes']),
        useCount: asInt(j['use_count']),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
      );
}

class LegacyInvoiceEntry {
  const LegacyInvoiceEntry({required this.amount, this.date, this.billNumber});

  final String? date;
  final String? billNumber;
  final double amount;

  factory LegacyInvoiceEntry.fromJson(Map<String, dynamic> j) => LegacyInvoiceEntry(
        date: asStringOrNull(j['date']),
        billNumber: asStringOrNull(j['bill_number']),
        amount: asDouble(j['amount']),
      );

  Map<String, dynamic> toJson() => {
        if (date != null) 'date': date,
        if (billNumber != null) 'bill_number': billNumber,
        'amount': amount,
      };
}

class LegacyInvoice {
  const LegacyInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.shopName,
    required this.entries,
    required this.totalEntries,
    required this.grandTotal,
    this.description,
    this.createdAt,
  });

  final String id;
  final String invoiceNumber;
  final String shopName;
  final String? description;
  final List<LegacyInvoiceEntry> entries;
  final int totalEntries;
  final double grandTotal;
  final String? createdAt;

  factory LegacyInvoice.fromJson(Map<String, dynamic> j) => LegacyInvoice(
        id: asString(j['id'] ?? j['_id']),
        invoiceNumber: asString(j['invoice_number']),
        shopName: asString(j['shop_name']),
        description: asStringOrNull(j['description']),
        entries: asMapList(j['entries']).map(LegacyInvoiceEntry.fromJson).toList(),
        totalEntries: asInt(j['total_entries'], asMapList(j['entries']).length),
        grandTotal: asDouble(j['grand_total']),
        createdAt: asStringOrNull(j['created_at']),
      );
}
