import 'dart:convert';

import 'json.dart';

/// Cross-database verification marker attached to bills, gate passes,
/// deliveries, returns and payments.
class Verification {
  const Verification({
    required this.status,
    required this.verified,
    this.lastVerifiedAt,
    this.mainVersion,
    this.secondaryVersion,
    this.error,
  });

  final String status;
  final bool verified;
  final String? lastVerifiedAt;
  final int? mainVersion;
  final int? secondaryVersion;
  final String? error;

  static const String statusVerified = 'VERIFIED';
  static const String statusSyncing = 'SYNCING';
  static const String statusPending = 'PENDING';
  static const String statusFailed = 'FAILED';

  bool get isFailed => status == statusFailed;
  bool get isPending => status == statusPending || status == statusSyncing;

  factory Verification.fromJson(Map<String, dynamic> j) => Verification(
        status: asString(j['status'], statusPending),
        verified: asBool(j['verified']),
        lastVerifiedAt: asStringOrNull(j['last_verified_at']),
        mainVersion: j['main_version'] == null ? null : asInt(j['main_version']),
        secondaryVersion: j['secondary_version'] == null
            ? null
            : asInt(j['secondary_version']),
        error: asStringOrNull(j['error']),
      );

  static Verification? tryParse(Object? v) =>
      v is Map ? Verification.fromJson(asMap(v)) : null;
}

/// The signed-in user.
class AppUser {
  const AppUser({
    required this.id,
    required this.userName,
    required this.authId,
    required this.roleId,
    required this.status,
    this.email,
    this.mobileNumber,
    this.bioData,
    this.userDp,
    this.employeeId,
    this.permissions,
  });

  final String id;
  final String userName;
  final String authId;
  final String roleId;
  final String status;
  final String? email;
  final String? mobileNumber;
  final String? bioData;
  final String? userDp;
  final String? employeeId;

  /// Stored as a JSON array string, sometimes as a bare comma-separated list.
  final String? permissions;

  bool get isAdmin => roleId.toUpperCase() == 'ADMIN';
  bool get isManager => roleId.toUpperCase() == 'MANAGER';
  bool get isStaff => roleId.toUpperCase() == 'STAFF';
  bool get isActive => status.toLowerCase() == 'active';

  List<String> get permissionList {
    final raw = permissions;
    if (raw == null || raw.trim().isEmpty) return const [];
    final trimmed = raw.trim();
    if (trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        // Fall through to the comma-separated reading.
      }
    }
    return trimmed
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// ADMIN holds every permission implicitly; everyone else needs it listed.
  bool hasPermission(String permission) {
    if (isAdmin) return true;
    final list = permissionList;
    if (list.isEmpty) return false;
    if (list.contains('*') || list.contains('all')) return true;
    return list.contains(permission);
  }

  String? get displayEmail => email;
  String? get displayPhone => mobileNumber;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: asString(j['id'] ?? j['_id']),
        userName: asString(j['user_name'] ?? j['username'], 'User'),
        authId: asString(j['auth_id']),
        roleId: asString(j['role_id'], 'STAFF').toUpperCase(),
        status: asString(j['status'], 'active'),
        email: asStringOrNull(j['email']),
        mobileNumber: asStringOrNull(j['mobile_number']),
        bioData: asStringOrNull(j['bio_data']),
        userDp: asStringOrNull(j['user_dp']),
        employeeId: asStringOrNull(j['employee_id']),
        permissions: asStringOrNull(j['permissions']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_name': userName,
        'auth_id': authId,
        'role_id': roleId,
        'status': status,
        if (email != null) 'email': email,
        if (mobileNumber != null) 'mobile_number': mobileNumber,
        if (bioData != null) 'bio_data': bioData,
        if (userDp != null) 'user_dp': userDp,
        if (employeeId != null) 'employee_id': employeeId,
        if (permissions != null) 'permissions': permissions,
      };

  /// The JWT payload, so an expired session is caught before the first request.
  static bool isTokenExpired(String token, {Duration leeway = Duration.zero}) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return false;
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload['exp'];
      if (exp is! num) return false;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
          (exp * 1000).round());
      return DateTime.now().isAfter(expiresAt.subtract(leeway));
    } catch (_) {
      // A malformed token is left alone; the 401 handler deals with it.
      return false;
    }
  }
}

/// Quotation lifecycle. Terminal states have no onward transitions.
enum OrderStatus {
  draft,
  received,
  washing,
  pressing,
  folding,
  packing,
  ready,
  outForDelivery,
  delivered,
  cancelled,
}

OrderStatus orderStatusFrom(String? raw) {
  switch ((raw ?? '').toLowerCase().replaceAll('-', '_')) {
    case 'received':
      return OrderStatus.received;
    case 'washing':
      return OrderStatus.washing;
    case 'pressing':
      return OrderStatus.pressing;
    case 'folding':
      return OrderStatus.folding;
    case 'packing':
      return OrderStatus.packing;
    case 'ready':
      return OrderStatus.ready;
    case 'out_for_delivery':
      return OrderStatus.outForDelivery;
    case 'delivered':
      return OrderStatus.delivered;
    case 'cancelled':
      return OrderStatus.cancelled;
    default:
      return OrderStatus.draft;
  }
}

const Map<OrderStatus, String> orderStatusLabels = {
  OrderStatus.draft: 'Draft',
  OrderStatus.received: 'Received',
  OrderStatus.washing: 'Washing',
  OrderStatus.pressing: 'Pressing',
  OrderStatus.folding: 'Folding',
  OrderStatus.packing: 'Packing',
  OrderStatus.ready: 'Ready',
  OrderStatus.outForDelivery: 'Out for Delivery',
  OrderStatus.delivered: 'Delivered',
  OrderStatus.cancelled: 'Cancelled',
};

/// The legal next states, mirroring `ORDER_STATUS_TRANSITIONS`.
const Map<OrderStatus, List<OrderStatus>> orderStatusTransitions = {
  OrderStatus.draft: [OrderStatus.received, OrderStatus.cancelled],
  OrderStatus.received: [OrderStatus.washing, OrderStatus.cancelled],
  OrderStatus.washing: [OrderStatus.pressing, OrderStatus.cancelled],
  OrderStatus.pressing: [OrderStatus.folding, OrderStatus.cancelled],
  OrderStatus.folding: [OrderStatus.packing, OrderStatus.cancelled],
  OrderStatus.packing: [OrderStatus.ready, OrderStatus.cancelled],
  OrderStatus.ready: [OrderStatus.outForDelivery, OrderStatus.cancelled],
  OrderStatus.outForDelivery: [OrderStatus.delivered, OrderStatus.cancelled],
  OrderStatus.delivered: [],
  OrderStatus.cancelled: [],
};

class QuotationSpec {
  const QuotationSpec({
    required this.specification,
    required this.unitPrice,
  });

  final String specification;
  final double unitPrice;

  factory QuotationSpec.fromJson(Map<String, dynamic> j) => QuotationSpec(
        specification: asString(j['specification']),
        unitPrice: asDouble(j['unit_price']),
      );

  Map<String, dynamic> toJson() =>
      {'specification': specification, 'unit_price': unitPrice};
}

class QuotationLineItem {
  const QuotationLineItem({
    required this.id,
    required this.itemName,
    required this.unitPrice,
    this.category,
    this.notes,
    this.specifications = const [],
  });

  final String id;
  final String itemName;
  final String? category;
  final double unitPrice;
  final String? notes;
  final List<QuotationSpec> specifications;

  double get total => unitPrice * specifications.fold(0.0, (a, s) => a + 1);
  int get specCount => specifications.length;

  factory QuotationLineItem.fromJson(Map<String, dynamic> j) =>
      QuotationLineItem(
        id: asString(j['id']),
        itemName: asString(j['item_name']),
        category: asStringOrNull(j['category']),
        unitPrice: asDouble(j['unit_price']),
        notes: asStringOrNull(j['notes']),
        specifications: asMapList(j['specifications'])
            .map(QuotationSpec.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'item_name': itemName,
        if (category != null) 'category': category,
        'unit_price': unitPrice,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (specifications.isNotEmpty)
          'specifications': specifications.map((s) => s.toJson()).toList(),
      };
}

class StatusHistoryEntry {
  const StatusHistoryEntry({
    required this.status,
    required this.changedAt,
    this.changedBy,
    this.note,
  });

  final String status;
  final String changedAt;
  final String? changedBy;
  final String? note;

  factory StatusHistoryEntry.fromJson(Map<String, dynamic> j) =>
      StatusHistoryEntry(
        status: asString(j['status']),
        changedAt: asString(j['changed_at'] ?? j['timestamp']),
        changedBy: asStringOrNull(j['changed_by']),
        note: asStringOrNull(j['note']),
      );
}

class GarmentTag {
  const GarmentTag({
    required this.id,
    required this.code,
    required this.quotationId,
    this.lineItemId,
    this.label,
    this.createdAt,
    this.trackingUrl = '',
  });

  final String id;
  final String code;
  final String quotationId;
  final String? lineItemId;
  final String? label;
  final String? createdAt;
  final String trackingUrl;

  factory GarmentTag.fromJson(Map<String, dynamic> j) => GarmentTag(
        id: asString(j['id'] ?? j['_id']),
        code: asString(j['code']),
        quotationId: asString(j['quotation_id']),
        lineItemId: asStringOrNull(j['line_item_id']),
        label: asStringOrNull(j['label']),
        createdAt: asStringOrNull(j['created_at']),
        trackingUrl: asString(j['tracking_url']),
      );
}

class Quotation {
  const Quotation({
    required this.id,
    required this.clientName,
    required this.lineItems,
    this.quotationTitle,
    this.createdAt,
    this.updatedAt,
    this.status = OrderStatus.draft,
    this.statusHistory = const [],
    this.tag,
  });

  final String id;
  final String clientName;
  final String? quotationTitle;
  final List<QuotationLineItem> lineItems;
  final String? createdAt;
  final String? updatedAt;
  final OrderStatus status;
  final List<StatusHistoryEntry> statusHistory;

  /// `shop` or `hotel` — drives which operation flow the quotation feeds.
  final String? tag;

  String get statusLabel => orderStatusLabels[status] ?? 'Draft';
  bool get isShop => tag == 'shop';
  bool get isHotel => tag == 'hotel';
  bool get isTerminal =>
      status == OrderStatus.delivered || status == OrderStatus.cancelled;

  List<OrderStatus> get nextStatuses => orderStatusTransitions[status] ?? const [];

  factory Quotation.fromJson(Map<String, dynamic> j) => Quotation(
        id: asString(j['id'] ?? j['_id']),
        clientName: asString(j['client_name']),
        quotationTitle: asStringOrNull(j['quotation_title']),
        lineItems: asMapList(j['line_items']).map(QuotationLineItem.fromJson).toList(),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
        status: orderStatusFrom(asStringOrNull(j['status'])),
        statusHistory:
            asMapList(j['status_history']).map(StatusHistoryEntry.fromJson).toList(),
        tag: asStringOrNull(j['tag']),
      );
}

class BillItem {
  const BillItem({
    required this.itemName,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    this.category,
  });

  final String itemName;
  final String? category;
  final double unitPrice;
  final double quantity;
  final double lineTotal;

  factory BillItem.fromJson(Map<String, dynamic> j) => BillItem(
        itemName: asString(j['item_name']),
        category: asStringOrNull(j['category']),
        unitPrice: asDouble(j['unit_price']),
        quantity: asDouble(j['quantity']),
        lineTotal: asDouble(j['line_total'],
            asDouble(j['unit_price']) * asDouble(j['quantity'])),
      );

  Map<String, dynamic> toJson() => {
        'item_name': itemName,
        if (category != null) 'category': category,
        'unit_price': unitPrice,
        'quantity': quantity,
      };
}

enum BillPaymentStatus {
  draft,
  pending,
  issued,
  partiallyPaid,
  paid,
  cancelled,
}

BillPaymentStatus billPaymentStatusFrom(String? raw) {
  switch ((raw ?? '').toUpperCase()) {
    case 'PENDING':
      return BillPaymentStatus.pending;
    case 'ISSUED':
      return BillPaymentStatus.issued;
    case 'PARTIALLY_PAID':
      return BillPaymentStatus.partiallyPaid;
    case 'PAID':
      return BillPaymentStatus.paid;
    case 'CANCELLED':
      return BillPaymentStatus.cancelled;
    default:
      return BillPaymentStatus.draft;
  }
}

const Map<BillPaymentStatus, String> billPaymentStatusLabels = {
  BillPaymentStatus.draft: 'Draft',
  BillPaymentStatus.pending: 'Pending',
  BillPaymentStatus.issued: 'Issued',
  BillPaymentStatus.partiallyPaid: 'Partly Paid',
  BillPaymentStatus.paid: 'Paid',
  BillPaymentStatus.cancelled: 'Cancelled',
};

class Bill {
  const Bill({
    required this.id,
    required this.quotationId,
    required this.clientName,
    required this.items,
    required this.totalQuantity,
    required this.totalAmount,
    this.quotationTitle,
    this.grandTotal,
    this.discounts,
    this.transportFee,
    this.taxes,
    this.additionalCharges,
    this.paidAmount,
    this.outstandingAmount,
    this.status,
    required this.paymentStatus,
    this.gatePassId,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.verification,
  });

  final String id;
  final String quotationId;
  final String clientName;
  final String? quotationTitle;
  final List<BillItem> items;
  final double totalQuantity;
  final double totalAmount;
  final double? grandTotal;
  final double? discounts;
  final double? transportFee;
  final double? taxes;
  final double? additionalCharges;
  final double? paidAmount;
  final double? outstandingAmount;
  final String? status;
  final BillPaymentStatus paymentStatus;
  final String? gatePassId;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;
  final Verification? verification;

  String get paymentStatusLabel =>
      billPaymentStatusLabels[paymentStatus] ?? 'Draft';
  bool get isPaid => paymentStatus == BillPaymentStatus.paid;
  bool get isCancelled => paymentStatus == BillPaymentStatus.cancelled;

  double get effectiveTotal => grandTotal ?? totalAmount;
  double get paid => paidAmount ?? 0;
  double get outstanding => outstandingAmount ?? (effectiveTotal - paid);

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
        id: asString(j['id'] ?? j['_id']),
        quotationId: asString(j['quotation_id']),
        clientName: asString(j['client_name']),
        quotationTitle: asStringOrNull(j['quotation_title']),
        items: asMapList(j['items']).map(BillItem.fromJson).toList(),
        totalQuantity: asDouble(j['total_quantity']),
        totalAmount: asDouble(j['total_amount']),
        grandTotal: j['grand_total'] == null ? null : asDouble(j['grand_total']),
        discounts: j['discounts'] == null ? null : asDouble(j['discounts']),
        transportFee:
            j['transport_fee'] == null ? null : asDouble(j['transport_fee']),
        taxes: j['taxes'] == null ? null : asDouble(j['taxes']),
        additionalCharges: j['additional_charges'] == null
            ? null
            : asDouble(j['additional_charges']),
        paidAmount:
            j['paid_amount'] == null ? null : asDouble(j['paid_amount']),
        outstandingAmount: j['outstanding_amount'] == null
            ? null
            : asDouble(j['outstanding_amount']),
        status: asStringOrNull(j['status']),
        paymentStatus: billPaymentStatusFrom(asStringOrNull(j['payment_status'])),
        gatePassId: asStringOrNull(j['gate_pass_id']),
        notes: asStringOrNull(j['notes']),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
        verification: Verification.tryParse(j['verification']),
      );
}

class UnbilledGatePassItem {
  const UnbilledGatePassItem({
    required this.itemName,
    required this.receivedQty,
    required this.deliveredQty,
    required this.billedQty,
    required this.unbilledQty,
    this.category,
    this.specification,
  });

  final String itemName;
  final String? category;
  final String? specification;
  final double receivedQty;
  final double deliveredQty;
  final double billedQty;
  final double unbilledQty;

  factory UnbilledGatePassItem.fromJson(Map<String, dynamic> j) =>
      UnbilledGatePassItem(
        itemName: asString(j['item_name']),
        category: asStringOrNull(j['category']),
        specification: asStringOrNull(j['specification']),
        receivedQty: asDouble(j['received_qty']),
        deliveredQty: asDouble(j['delivered_qty']),
        billedQty: asDouble(j['billed_qty']),
        unbilledQty: asDouble(j['unbilled_qty']),
      );
}

class UnbilledGatePass {
  const UnbilledGatePass({
    required this.id,
    required this.gatePassNumber,
    required this.clientName,
    required this.receivingDate,
    required this.unbilledItems,
    required this.totalUnbilledQty,
    this.quotationId,
    this.deliveryIds = const [],
    this.rewashedItems = const [],
    this.totalRewashedQty = 0,
  });

  final String id;
  final String gatePassNumber;
  final String clientName;
  final String receivingDate;
  final String? quotationId;
  final List<String> deliveryIds;
  final List<UnbilledGatePassItem> unbilledItems;
  final double totalUnbilledQty;
  final List<UnbilledGatePassItem> rewashedItems;
  final double totalRewashedQty;

  factory UnbilledGatePass.fromJson(Map<String, dynamic> j) {
    final rewashed = asMapList(j['rewashed_items']);
    return UnbilledGatePass(
      id: asString(j['id'] ?? j['_id']),
      gatePassNumber: asString(j['gate_pass_number']),
      clientName: asString(j['client_name']),
      receivingDate: asString(j['receiving_date']),
      quotationId: asStringOrNull(j['quotation_id']),
      deliveryIds: (j['delivery_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      unbilledItems:
          asMapList(j['unbilled_items']).map(UnbilledGatePassItem.fromJson).toList(),
      totalUnbilledQty: asDouble(j['total_unbilled_qty']),
      rewashedItems: rewashed
          .map((e) => UnbilledGatePassItem(
                itemName: asString(e['item_name']),
                specification: asStringOrNull(e['specification']),
                receivedQty: asDouble(e['received_qty']),
                deliveredQty: 0,
                billedQty: 0,
                unbilledQty: 0,
              ))
          .toList(),
      totalRewashedQty: asDouble(j['total_rewashed_qty']),
    );
  }
}
